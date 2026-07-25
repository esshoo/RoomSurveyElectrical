import Foundation

enum HomeWidgetSnapshotStore {
    // Sideloadly compatibility build: the Home Screen widget is intentionally
    // static and does not request App Group entitlements. These methods remain
    // so existing project and preview code keeps compiling without changing
    // the saved project format.
    static func update(projects: [SurveyProject]) {
        _ = projects
    }

    static func publishPreview(projectID: UUID, data: Data) {
        _ = projectID
        _ = data
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
            "الامتداد موجود، لكن Bundle ID الخاص به لا يتبع Bundle ID التطبيق بعد توقيع Sideloadly."
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

struct HomeWidgetDiagnosticReport: Equatable {
    let status: HomeWidgetInstallationStatus
    let hostBundleIdentifier: String
    let widgetBundleIdentifier: String
    let extensionPointIdentifier: String

    var expectedWidgetBundleIdentifier: String {
        hostBundleIdentifier + ".widget"
    }
}

enum HomeWidgetDiagnostics {
    private static let fileManager = FileManager.default

    static var report: HomeWidgetDiagnosticReport {
        let hostID = Bundle.main.bundleIdentifier ?? "غير معروف"
        guard let bundle = embeddedWidgetBundle else {
            return HomeWidgetDiagnosticReport(
                status: .extensionMissing,
                hostBundleIdentifier: hostID,
                widgetBundleIdentifier: "غير موجود",
                extensionPointIdentifier: "غير موجود"
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
            extensionPointIdentifier: extensionPoint
        )
    }

    static var status: HomeWidgetInstallationStatus {
        report.status
    }

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
}
