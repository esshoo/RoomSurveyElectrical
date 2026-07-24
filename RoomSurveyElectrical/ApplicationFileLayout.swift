import Foundation

enum ApplicationFileLayout {
    enum LayoutError: LocalizedError {
        case documentsDirectoryUnavailable

        var errorDescription: String? {
            switch self {
            case .documentsDirectoryUnavailable:
                "تعذر الوصول إلى مجلد مستندات التطبيق."
            }
        }
    }

    private static let fileManager = FileManager.default

    static var documentsDirectory: URL {
        get throws {
            guard let url = fileManager.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first else {
                throw LayoutError.documentsDirectoryUnavailable
            }
            return url
        }
    }

    static var brandDirectory: URL {
        get throws {
            try documentsDirectory
                .appendingPathComponent("3Essam", isDirectory: true)
        }
    }

    static var appDirectory: URL {
        get throws {
            try brandDirectory
                .appendingPathComponent(
                    "3ERoomElectrical",
                    isDirectory: true
                )
        }
    }

    static var workspaceProjectsDirectory: URL {
        get throws {
            try appDirectory
                .appendingPathComponent("Projects", isDirectory: true)
                .appendingPathComponent("Workspaces", isDirectory: true)
        }
    }

    static var roomScansDirectory: URL {
        get throws {
            try appDirectory
                .appendingPathComponent("Projects", isDirectory: true)
                .appendingPathComponent("Scans", isDirectory: true)
        }
    }

    static var exportsDirectory: URL {
        get throws {
            try appDirectory.appendingPathComponent(
                "Exports",
                isDirectory: true
            )
        }
    }

    static var importsDirectory: URL {
        get throws {
            try appDirectory.appendingPathComponent(
                "Opened Files",
                isDirectory: true
            )
        }
    }

    static var previewsDirectory: URL {
        get throws {
            try appDirectory.appendingPathComponent(
                "Previews",
                isDirectory: true
            )
        }
    }

    static var indexDirectory: URL {
        get throws {
            try appDirectory.appendingPathComponent(
                "Index",
                isDirectory: true
            )
        }
    }

    static func prepare() throws {
        let directories = [
            try brandDirectory,
            try appDirectory,
            try workspaceProjectsDirectory,
            try roomScansDirectory,
            try exportsDirectory,
            try importsDirectory,
            try previewsDirectory,
            try indexDirectory
        ]

        for directory in directories {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        try migrateLegacyDirectory(
            named: "3ERoomElectricalProjects",
            to: workspaceProjectsDirectory
        )
        try migrateLegacyDirectory(
            named: "RoomSurveyProjects",
            to: roomScansDirectory
        )
    }

    static func uniqueDestination(
        in directory: URL,
        preferredName: String
    ) -> URL {
        let original = directory.appendingPathComponent(preferredName)
        guard fileManager.fileExists(atPath: original.path) else {
            return original
        }

        let extensionName = original.pathExtension
        let stem = original.deletingPathExtension().lastPathComponent
        var suffix = 2
        while true {
            let candidateName = extensionName.isEmpty
                ? "\(stem) (\(suffix))"
                : "\(stem) (\(suffix)).\(extensionName)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private static func migrateLegacyDirectory(
        named legacyName: String,
        to destination: URL
    ) throws {
        let legacy = try documentsDirectory.appendingPathComponent(
            legacyName,
            isDirectory: true
        )
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: legacy.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return
        }

        let legacyContents = try fileManager.contentsOfDirectory(
            at: legacy,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for source in legacyContents {
            let target = destination.appendingPathComponent(
                source.lastPathComponent
            )
            guard !fileManager.fileExists(atPath: target.path) else {
                continue
            }
            do {
                try fileManager.moveItem(at: source, to: target)
            } catch {
                try fileManager.copyItem(at: source, to: target)
            }
        }

        let remaining = try? fileManager.contentsOfDirectory(
            at: legacy,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        if remaining?.isEmpty == true {
            try? fileManager.removeItem(at: legacy)
        }
    }
}
