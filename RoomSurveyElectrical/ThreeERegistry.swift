import Foundation

enum ThreeERegistryError: LocalizedError {
    case invalidRootObject
    case invalidAppsCollection

    var errorDescription: String? {
        switch self {
        case .invalidRootObject:
            "ملف registry.json الموجود لا يحتوي على كائن JSON صالح، لذلك لم يتم تعديله."
        case .invalidAppsCollection:
            "الحقل apps داخل registry.json ليس قائمة أو كائنًا صالحًا، لذلك لم يتم تعديله."
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
                        "apps": [String: Any]()
                    ]
                }

                if rootObject["schemaVersion"] == nil {
                    rootObject["schemaVersion"] =
                        ThreeEStorageConstants.registrySchemaVersion
                }

                var apps = try normalizedApps(
                    from: rootObject["apps"]
                )
                let appKey = ThreeEStorageConstants.appKey
                var updatedEntry = apps[appKey] ?? [:]

                for (key, value) in ThreeEStorageConstants.registryEntry {
                    updatedEntry[key] = value
                }

                apps[appKey] = updatedEntry
                rootObject["apps"] = apps

                let data = try JSONSerialization.data(
                    withJSONObject: rootObject,
                    options: [
                        .prettyPrinted,
                        .sortedKeys,
                        .withoutEscapingSlashes
                    ]
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

    /// Accepts both historical formats and returns the canonical
    /// dictionary keyed by appKey.
    private static func normalizedApps(
        from rawValue: Any?
    ) throws -> [String: [String: Any]] {
        guard let rawValue else {
            return [:]
        }

        if let dictionary = rawValue as? [String: Any] {
            var result: [String: [String: Any]] = [:]

            for (dictionaryKey, rawEntry) in dictionary {
                guard var entry = rawEntry as? [String: Any] else {
                    throw ThreeERegistryError.invalidAppsCollection
                }

                let storedKey = (entry["appKey"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let appKey = (storedKey?.isEmpty == false)
                    ? storedKey!
                    : dictionaryKey
                entry["appKey"] = appKey
                result[appKey] = entry
            }

            return result
        }

        if let array = rawValue as? [[String: Any]] {
            var result: [String: [String: Any]] = [:]

            for entry in array {
                guard let appKey = (entry["appKey"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !appKey.isEmpty else {
                    throw ThreeERegistryError.invalidAppsCollection
                }
                result[appKey] = entry
            }

            return result
        }

        throw ThreeERegistryError.invalidAppsCollection
    }
}
