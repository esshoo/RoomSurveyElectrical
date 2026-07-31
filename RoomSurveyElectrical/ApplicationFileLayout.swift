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

    static var privateAppDirectory: URL {
        get throws {
            try brandDirectory
                .appendingPathComponent(
                    "3ERoomElectrical",
                    isDirectory: true
                )
        }
    }

    static var appDirectory: URL {
        ThreeEStorageManager.shared.appRootURL
    }

    static var workspaceProjectsDirectory: URL {
        appDirectory
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent("Workspaces", isDirectory: true)
    }

    static var roomScansDirectory: URL {
        appDirectory
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent("Scans", isDirectory: true)
    }

    static var exportsDirectory: URL {
        appDirectory.appendingPathComponent(
            "Exports",
            isDirectory: true
        )
    }

    static var importsDirectory: URL {
        appDirectory.appendingPathComponent(
            "Opened Files",
            isDirectory: true
        )
    }

    static var previewsDirectory: URL {
        appDirectory.appendingPathComponent(
            "Previews",
            isDirectory: true
        )
    }

    static var indexDirectory: URL {
        appDirectory.appendingPathComponent(
            "Index",
            isDirectory: true
        )
    }

    static func prepare() throws {
        try ThreeEStorageManager.shared.ensureDirectories()

        let directories = [
            appDirectory,
            workspaceProjectsDirectory,
            roomScansDirectory,
            exportsDirectory,
            importsDirectory,
            previewsDirectory,
            indexDirectory
        ]

        for directory in directories {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        try copyLegacyDirectoryIfNeeded(
            named: "3ERoomElectricalProjects",
            to: workspaceProjectsDirectory
        )
        try copyLegacyDirectoryIfNeeded(
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

    private static func copyLegacyDirectoryIfNeeded(
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

        try copyMissingContents(from: legacy, to: destination)
    }

    private static func copyMissingContents(
        from sourceDirectory: URL,
        to destinationDirectory: URL
    ) throws {
        try fileManager.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        let children = try fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ],
            options: []
        )

        for source in children {
            let values = try source.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ])
            guard values.isSymbolicLink != true else { continue }

            let target = destinationDirectory.appendingPathComponent(
                source.lastPathComponent,
                isDirectory: values.isDirectory == true
            )
            if values.isDirectory == true {
                try copyMissingContents(from: source, to: target)
            } else if values.isRegularFile == true,
                      !fileManager.fileExists(atPath: target.path) {
                try fileManager.copyItem(at: source, to: target)
            }
        }
    }
}
