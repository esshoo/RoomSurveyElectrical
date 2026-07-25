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

    var message: String? {
        switch self {
        case .ready:
            nil
        case .extensionMissing:
            "نسخة التثبيت لا تحتوي امتداد الويدجت داخل PlugIns. يجب أن يحتفظ برنامج التوقيع بالـWidget Extension."
        }
    }

    var systemImage: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .extensionMissing: "puzzlepiece.extension.fill"
        }
    }
}

enum HomeWidgetDiagnostics {
    private static let fileManager = FileManager.default

    static var status: HomeWidgetInstallationStatus {
        extensionIsEmbedded ? .ready : .extensionMissing
    }

    private static var extensionIsEmbedded: Bool {
        guard let plugInsURL = Bundle.main.builtInPlugInsURL,
              let children = try? fileManager.contentsOfDirectory(
                  at: plugInsURL,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              ) else {
            return false
        }
        return children.contains {
            $0.pathExtension.caseInsensitiveCompare("appex") == .orderedSame
                && $0.lastPathComponent
                    .caseInsensitiveCompare(
                        "3ERoomElectricalWidgetExtension.appex"
                    ) == .orderedSame
        }
    }
}
