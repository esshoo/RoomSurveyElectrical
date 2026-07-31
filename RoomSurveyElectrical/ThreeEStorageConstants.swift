import Foundation

enum ThreeEStorageConstants {
    static let displayName = "3ERoomElectrical"
    static let bundleIdentifier = "com.essam.3E.roomelectrical"
    static let appKey = "roomElectrical"
    static let urlScheme = "electrical"
    static let legacyURLScheme = "3eroomelectrical"
    static let appRelativePath = "Apps/RoomElectrical"
    static let futureAppGroupIdentifier = "group.com.essam.3e"

    static let bookmarkDefaultsKey =
        "com.essam.3E.roomelectrical.threeEFolderBookmark"
    static let registryRelativePath = "System/registry.json"
    static let registrySchemaVersion = 1

    static let appSubdirectories = [
        "Projects/Workspaces",
        "Projects/Scans",
        "Exports",
        "Opened Files",
        "Previews",
        "Index"
    ]

    static let sharedSubdirectories = [
        "Apps",
        appRelativePath,
        "Shared/Inbox",
        "Shared/Outbox",
        "Shared/Projects",
        "Shared/Media",
        "System"
    ]

    static let registryEntry: [String: String] = [
        "appKey": appKey,
        "displayName": displayName,
        "bundleIdentifier": bundleIdentifier,
        "urlScheme": urlScheme,
        "folder": appRelativePath
    ]
}
