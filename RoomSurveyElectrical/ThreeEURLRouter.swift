import Foundation

struct ThreeEOpenTarget {
    let relativePath: String
    let url: URL
    let isDirectory: Bool
}

enum ThreeEURLCommand {
    case open(relativePath: String?, projectID: UUID?)
}

enum ThreeEURLRouterError: LocalizedError {
    case unsupportedScheme
    case unsupportedAction
    case targetNotFound(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedScheme:
            "تم رفض الرابط لأنه لا يتبع تطبيق 3ERoomElectrical."
        case .unsupportedAction:
            "أمر الرابط غير مدعوم. الأمر المتاح حاليًا هو electrical://open."
        case .targetNotFound(let path):
            "المسار غير موجود داخل مجلد 3E: \(path)"
        }
    }
}

enum ThreeEURLRouter {
    static func command(for incomingURL: URL) throws -> ThreeEURLCommand {
        guard incomingURL.scheme?.lowercased()
                == ThreeEStorageConstants.urlScheme else {
            throw ThreeEURLRouterError.unsupportedScheme
        }

        let action: String
        if let host = incomingURL.host, !host.isEmpty {
            action = host.lowercased()
        } else {
            action = incomingURL.pathComponents
                .first(where: { $0 != "/" })?
                .lowercased() ?? ""
        }
        guard action == "open" else {
            throw ThreeEURLRouterError.unsupportedAction
        }

        let components = URLComponents(
            url: incomingURL,
            resolvingAgainstBaseURL: false
        )
        let relativePath = components?.queryItems?.first(
            where: { $0.name == "path" }
        )?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectValue = components?.queryItems?.first(
            where: { $0.name == "project" }
        )?.value
        let projectID = projectValue.flatMap(UUID.init(uuidString:))

        return .open(
            relativePath: relativePath?.isEmpty == false
                ? relativePath
                : nil,
            projectID: projectID
        )
    }

    static func target(
        for relativePath: String,
        storage: ThreeEStorageManager = .shared
    ) throws -> ThreeEOpenTarget {
        let targetURL = try storage.urlForValidatedRelativePath(relativePath)
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            throw ThreeEURLRouterError.targetNotFound(relativePath)
        }
        let values = try targetURL.resourceValues(forKeys: [.isDirectoryKey])
        return ThreeEOpenTarget(
            relativePath: relativePath,
            url: targetURL,
            isDirectory: values.isDirectory == true
        )
    }
}
