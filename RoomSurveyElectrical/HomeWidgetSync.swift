import Foundation
import WidgetKit

enum HomeWidgetSharedConfiguration {
    static let appGroupIdentifier = "group.com.essam.threeroomelectrical"
    static let widgetKind = "3ERoomElectricalRecentProjects"
    static let dataFolderName = "3ERoomElectricalWidgetData"
    static let snapshotFileName = "recent-projects.json"
    static let maximumProjects = 6
}

private struct HomeWidgetProjectSnapshot: Codable {
    let projectID: UUID
    let name: String
    let kindTitle: String
    let systemImage: String
    let scanCount: Int
    let roomCount: Int
    let updatedAt: Date
    let previewFileName: String
}

enum HomeWidgetSnapshotStore {
    private static let fileManager = FileManager.default

    static func update(projects: [SurveyProject]) {
        guard let directory = sharedDirectory(create: true) else { return }

        let activeProjects = projects
            .filter { !$0.archived }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(HomeWidgetSharedConfiguration.maximumProjects)

        let snapshots = activeProjects.map { project in
            let previewName = previewFileName(projectID: project.id)
            copyCachedPreviewIfAvailable(
                projectID: project.id,
                destination: directory.appendingPathComponent(previewName)
            )
            return HomeWidgetProjectSnapshot(
                projectID: project.id,
                name: project.name,
                kindTitle: project.kind.title,
                systemImage: project.kind.systemImage,
                scanCount: project.scanCount,
                roomCount: project.roomCount,
                updatedAt: project.updatedAt,
                previewFileName: previewName
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshots) else { return }

        let snapshotURL = directory.appendingPathComponent(
            HomeWidgetSharedConfiguration.snapshotFileName
        )
        do {
            try data.write(to: snapshotURL, options: .atomic)
            removeUnusedPreviews(
                in: directory,
                keeping: Set(snapshots.map(\.previewFileName))
            )
            WidgetCenter.shared.reloadTimelines(
                ofKind: HomeWidgetSharedConfiguration.widgetKind
            )
        } catch {
            return
        }
    }

    static func publishPreview(projectID: UUID, data: Data) {
        guard let directory = sharedDirectory(create: true) else { return }
        let destination = directory.appendingPathComponent(
            previewFileName(projectID: projectID)
        )
        do {
            try data.write(to: destination, options: .atomic)
            WidgetCenter.shared.reloadTimelines(
                ofKind: HomeWidgetSharedConfiguration.widgetKind
            )
        } catch {
            return
        }
    }

    static var isSharedContainerAvailable: Bool {
        sharedDirectory(create: false) != nil
    }

    private static func sharedDirectory(create: Bool) -> URL? {
        guard let root = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier:
                HomeWidgetSharedConfiguration.appGroupIdentifier
        ) else {
            return nil
        }
        let directory = root.appendingPathComponent(
            HomeWidgetSharedConfiguration.dataFolderName,
            isDirectory: true
        )
        if create {
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                return nil
            }
        }
        return directory
    }

    private static func previewFileName(projectID: UUID) -> String {
        "project-\(projectID.uuidString.lowercased()).png"
    }

    private static func copyCachedPreviewIfAvailable(
        projectID: UUID,
        destination: URL
    ) {
        guard !fileManager.fileExists(atPath: destination.path),
              let previewsDirectory = try? ApplicationFileLayout.previewsDirectory
        else {
            return
        }
        let source = previewsDirectory.appendingPathComponent(
            "\(projectID.uuidString).png"
        )
        guard let data = try? Data(contentsOf: source) else { return }
        try? data.write(to: destination, options: .atomic)
    }

    private static func removeUnusedPreviews(
        in directory: URL,
        keeping names: Set<String>
    ) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for file in files where file.pathExtension.lowercased() == "png" {
            if !names.contains(file.lastPathComponent) {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}

enum HomeWidgetInstallationStatus: Equatable {
    case ready
    case extensionMissing
    case invalidExtensionPoint
    case identityMismatch

    var message: String {
        switch self {
        case .ready:
            "امتداد WidgetKit موجود وهويته متطابقة داخل التطبيق."
        case .extensionMissing:
            "نسخة التثبيت لا تحتوي Widget Extension داخل PlugIns."
        case .invalidExtensionPoint:
            "الامتداد موجود، لكن NSExtensionPointIdentifier ليس WidgetKit."
        case .identityMismatch:
            "الامتداد موجود، لكن Bundle ID الخاص به لا يتبع Bundle ID التطبيق بعد التوقيع."
        }
    }

    var systemImage: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .extensionMissing: "puzzlepiece.extension.fill"
        case .invalidExtensionPoint: "exclamationmark.triangle.fill"
        case .identityMismatch: "link.badge.plus"
        }
    }
}

struct ProvisioningProfileSummary: Equatable {
    let exists: Bool
    let applicationIdentifier: String
    let teamIdentifier: String
    let expirationDate: Date?

    static let missing = ProvisioningProfileSummary(
        exists: false,
        applicationIdentifier: "غير موجود",
        teamIdentifier: "غير موجود",
        expirationDate: nil
    )
}

struct HomeWidgetDiagnosticReport: Equatable {
    let status: HomeWidgetInstallationStatus
    let hostBundleIdentifier: String
    let widgetBundleIdentifier: String
    let extensionPointIdentifier: String
    let hostProfile: ProvisioningProfileSummary
    let widgetProfile: ProvisioningProfileSummary

    var expectedWidgetBundleIdentifier: String {
        hostBundleIdentifier + ".widget"
    }

    var provisioningIsValid: Bool {
        guard hostProfile.exists, widgetProfile.exists else { return false }
        guard hostProfile.applicationIdentifier.hasSuffix(hostBundleIdentifier),
              widgetProfile.applicationIdentifier.hasSuffix(widgetBundleIdentifier)
        else {
            return false
        }
        guard !hostProfile.teamIdentifier.isEmpty,
              hostProfile.teamIdentifier == widgetProfile.teamIdentifier
        else {
            return false
        }
        return true
    }

    var provisioningMessage: String {
        if !hostProfile.exists {
            return "التطبيق الرئيسي لا يحتوي embedded.mobileprovision بعد التوقيع."
        }
        if !widgetProfile.exists {
            return "الويدجت موجودة داخل PlugIns لكنها لا تحتوي Provisioning Profile مستقلًا؛ لن يسجلها iOS كويدجت."
        }
        if !hostProfile.applicationIdentifier.hasSuffix(hostBundleIdentifier) {
            return "Provisioning Profile التطبيق لا يطابق Bundle ID المثبت."
        }
        if !widgetProfile.applicationIdentifier.hasSuffix(widgetBundleIdentifier) {
            return "Provisioning Profile الويدجت لا يطابق Bundle ID الويدجت."
        }
        if hostProfile.teamIdentifier != widgetProfile.teamIdentifier {
            return "التطبيق والويدجت موقّعان بفريقين مختلفين."
        }
        return "Provisioning Profile التطبيق والويدجت متطابقان."
    }
}

enum HomeWidgetDiagnostics {
    private static let fileManager = FileManager.default

    static var report: HomeWidgetDiagnosticReport {
        let hostID = Bundle.main.bundleIdentifier ?? "غير معروف"
        let hostProfile = provisioningProfile(in: Bundle.main)
        guard let bundle = embeddedWidgetBundle else {
            return HomeWidgetDiagnosticReport(
                status: .extensionMissing,
                hostBundleIdentifier: hostID,
                widgetBundleIdentifier: "غير موجود",
                extensionPointIdentifier: "غير موجود",
                hostProfile: hostProfile,
                widgetProfile: .missing
            )
        }

        let widgetID = bundle.bundleIdentifier ?? "غير معروف"
        let extensionPoint = ((bundle.infoDictionary?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String) ?? "غير معروف"
        let expectedID = hostID + ".widget"
        let status: HomeWidgetInstallationStatus
        if extensionPoint != "com.apple.widgetkit-extension" {
            status = .invalidExtensionPoint
        } else if widgetID != expectedID {
            status = .identityMismatch
        } else {
            status = .ready
        }
        return HomeWidgetDiagnosticReport(
            status: status,
            hostBundleIdentifier: hostID,
            widgetBundleIdentifier: widgetID,
            extensionPointIdentifier: extensionPoint,
            hostProfile: hostProfile,
            widgetProfile: provisioningProfile(in: bundle)
        )
    }

    static var status: HomeWidgetInstallationStatus { report.status }

    private static var embeddedWidgetBundle: Bundle? {
        guard let plugInsURL = Bundle.main.builtInPlugInsURL,
              let children = try? fileManager.contentsOfDirectory(
                  at: plugInsURL,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              ),
              let widgetURL = children.first(where: {
                  $0.pathExtension.caseInsensitiveCompare("appex") == .orderedSame
                      && $0.lastPathComponent.caseInsensitiveCompare(
                          "3ERoomElectricalWidgetExtension.appex"
                      ) == .orderedSame
              }) else {
            return nil
        }
        return Bundle(url: widgetURL)
    }

    private static func provisioningProfile(
        in bundle: Bundle
    ) -> ProvisioningProfileSummary {
        guard let profileURL = bundle.url(
            forResource: "embedded",
            withExtension: "mobileprovision"
        ), let data = try? Data(contentsOf: profileURL),
           let containerText = String(data: data, encoding: .isoLatin1),
           let plistStart = containerText.range(of: "<plist"),
           let plistEnd = containerText.range(
               of: "</plist>",
               range: plistStart.lowerBound..<containerText.endIndex
           ) else {
            return .missing
        }

        let plistText = String(
            containerText[plistStart.lowerBound..<plistEnd.upperBound]
        )
        guard let plistData = plistText.data(using: .utf8),
              let object = try? PropertyListSerialization.propertyList(
                  from: plistData,
                  options: [],
                  format: nil
              ),
              let dictionary = object as? [String: Any],
              let entitlements = dictionary["Entitlements"] as? [String: Any]
        else {
            return ProvisioningProfileSummary(
                exists: true,
                applicationIdentifier: "غير قابل للقراءة",
                teamIdentifier: "غير قابل للقراءة",
                expirationDate: nil
            )
        }

        let appIdentifier = entitlements["application-identifier"] as? String
            ?? entitlements["com.apple.application-identifier"] as? String
            ?? "غير موجود"
        let entitlementTeam = entitlements[
            "com.apple.developer.team-identifier"
        ] as? String
        let profileTeams = dictionary["TeamIdentifier"] as? [String]
        let teamIdentifier = entitlementTeam
            ?? profileTeams?.first
            ?? appIdentifier.split(separator: ".").first.map(String.init)
            ?? "غير موجود"

        return ProvisioningProfileSummary(
            exists: true,
            applicationIdentifier: appIdentifier,
            teamIdentifier: teamIdentifier,
            expirationDate: dictionary["ExpirationDate"] as? Date
        )
    }
}
