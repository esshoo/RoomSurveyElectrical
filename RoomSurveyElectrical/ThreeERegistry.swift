import Foundation

enum ThreeERegistryError: LocalizedError {
    case invalidRootObject
    case invalidAppsCollection

    var errorDescription: String? {
        switch self {
        case .invalidRootObject:
            "ملف registry.json الموجود لا يحتوي على كائن JSON صالح، لذلك لم يتم تعديله."
        case .invalidAppsCollection:
            "الحقل apps داخل registry.json ليس قائمة صالحة، لذلك لم يتم تعديله."
        }
    }
}

enum ThreeERegistry {
    static func registerRoomElectricalApp(
        in threeERootURL: URL
    ) throws {
        let fileManager = FileManager.default
        let systemURL = threeERootURL.appendingPathComponent(
            "System",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: systemURL,
            withIntermediateDirectories: true
        )

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?

        coordinator.coordinate(
            writingItemAt: systemURL,
            options: [],
            error: &coordinationError
        ) { coordinatedSystemURL in
            do {
                let registryURL = coordinatedSystemURL
                    .appendingPathComponent(
                        "registry.json",
                        isDirectory: false
                    )
                var rootObject: [String: Any]

                if fileManager.fileExists(atPath: registryURL.path) {
                    let existingData = try Data(contentsOf: registryURL)
                    let json = try JSONSerialization.jsonObject(
                        with: existingData
                    )
                    guard let dictionary = json as? [String: Any] else {
                        throw ThreeERegistryError.invalidRootObject
                    }
                    rootObject = dictionary
                } else {
                    rootObject = [
                        "schemaVersion":
                            ThreeEStorageConstants.registrySchemaVersion,
                        "apps": []
                    ]
                }

                if rootObject["schemaVersion"] == nil {
                    rootObject["schemaVersion"] =
                        ThreeEStorageConstants.registrySchemaVersion
                }

                var apps: [[String: Any]]
                if let existingApps = rootObject["apps"] {
                    guard let appArray = existingApps as? [[String: Any]] else {
                        throw ThreeERegistryError.invalidAppsCollection
                    }
                    apps = appArray
                } else {
                    apps = []
                }

                let newValues = ThreeEStorageConstants.registryEntry
                if let index = apps.firstIndex(where: {
                    ($0["appKey"] as? String)
                        == ThreeEStorageConstants.appKey
                }) {
                    var updatedEntry = apps[index]
                    for (key, value) in newValues {
                        updatedEntry[key] = value
                    }
                    apps[index] = updatedEntry
                } else {
                    apps.append(newValues)
                }

                rootObject["apps"] = apps
                let data = try JSONSerialization.data(
                    withJSONObject: rootObject,
                    options: [.prettyPrinted, .sortedKeys]
                )
                try data.write(to: registryURL, options: .atomic)
            } catch {
                operationError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let operationError {
            throw operationError
        }
    }
}
