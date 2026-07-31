import Combine
import Foundation

enum ThreeEStorageSource: String {
    case appGroup
    case filesFolder
    case privateSandbox

    var title: String {
        switch self {
        case .appGroup:
            "App Group"
        case .filesFolder:
            "مجلد 3E في Files"
        case .privateSandbox:
            "مساحة التطبيق المؤقتة"
        }
    }

    var isShared: Bool {
        self != .privateSandbox
    }
}

enum ThreeEStorageError: LocalizedError {
    case documentsDirectoryUnavailable
    case selectedFolderIsNotThreeE
    case selectedItemIsNotDirectory
    case securityScopeUnavailable
    case bookmarkUnavailable
    case sharedFolderNotConnected
    case invalidRelativePath
    case pathOutsideRoot

    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable:
            "تعذر الوصول إلى مجلد مستندات التطبيق."
        case .selectedFolderIsNotThreeE:
            "اختر مجلد 3E نفسه المستخدم في التطبيقات الأخرى، وليس مجلدًا داخله أو مجلدًا آخر."
        case .selectedItemIsNotDirectory:
            "العنصر المحدد ليس مجلدًا صالحًا."
        case .securityScopeUnavailable:
            "تعذر الحصول على صلاحية مجلد 3E. اختر المجلد نفسه من Files مرة أخرى."
        case .bookmarkUnavailable:
            "تعذر حفظ صلاحية مجلد 3E للاستعادة التلقائية."
        case .sharedFolderNotConnected:
            "اربط مجلد 3E من Files أولًا لفتح هذا المسار المشترك."
        case .invalidRelativePath:
            "المسار المطلوب غير صالح."
        case .pathOutsideRoot:
            "تم رفض المسار لأنه يخرج خارج مجلد 3E."
        }
    }
}

final class ThreeEStorageManager: ObservableObject {
    static let shared = ThreeEStorageManager()

    @Published private(set) var source: ThreeEStorageSource = .privateSandbox
    @Published private(set) var needsFolderReselection = false
    @Published private(set) var statusMessage =
        "يعمل التطبيق حاليًا داخل مساحته الخاصة."
    @Published private(set) var lastErrorMessage: String?

    private struct StorageContext {
        let source: ThreeEStorageSource
        let threeERootURL: URL?
        let appRootURL: URL
    }

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private let contextLock = NSLock()
    private var context: StorageContext
    private var securityScopedURL: URL?
    private var securityScopeActive = false

    private init() {
        let privateRoot: URL
        if let documents = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {
            privateRoot = documents
                .appendingPathComponent("3Essam", isDirectory: true)
                .appendingPathComponent(
                    "3ERoomElectrical",
                    isDirectory: true
                )
        } else {
            privateRoot = fileManager.temporaryDirectory
                .appendingPathComponent(
                    "3ERoomElectrical-Fallback",
                    isDirectory: true
                )
        }

        context = StorageContext(
            source: .privateSandbox,
            threeERootURL: nil,
            appRootURL: privateRoot
        )
        bootstrapStorage()
    }

    deinit {
        releaseSecurityScope()
    }

    var appRootURL: URL {
        currentContext().appRootURL
    }

    var threeERootURL: URL? {
        currentContext().threeERootURL
    }

    var isSharedFolderConnected: Bool {
        source.isShared && threeERootURL != nil
    }

    var selectedFolderName: String {
        threeERootURL?.lastPathComponent ?? "غير مرتبط"
    }

    func connectToSelectedThreeEFolder(_ selectedURL: URL) throws {
        guard selectedURL.lastPathComponent.caseInsensitiveCompare("3E")
                == .orderedSame else {
            throw ThreeEStorageError.selectedFolderIsNotThreeE
        }

        let values = try selectedURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw ThreeEStorageError.selectedItemIsNotDirectory
        }

        guard selectedURL.startAccessingSecurityScopedResource() else {
            throw ThreeEStorageError.securityScopeUnavailable
        }

        do {
            let bookmark = try selectedURL.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: [.isDirectoryKey, .nameKey],
                relativeTo: nil
            )
            guard !bookmark.isEmpty else {
                throw ThreeEStorageError.bookmarkUnavailable
            }

            let newContext = StorageContext(
                source: .filesFolder,
                threeERootURL: selectedURL,
                appRootURL: Self.appRootURL(under: selectedURL)
            )
            try prepare(context: newContext)
            try migratePrivateDataIfNeeded(to: newContext.appRootURL)

            let previousURL = securityScopedURL
            let previousAccessWasActive = securityScopeActive

            setContext(newContext)
            securityScopedURL = selectedURL
            securityScopeActive = true
            defaults.set(
                bookmark,
                forKey: ThreeEStorageConstants.bookmarkDefaultsKey
            )

            if previousAccessWasActive, let previousURL {
                previousURL.stopAccessingSecurityScopedResource()
            }

            needsFolderReselection = false
            lastErrorMessage = nil
            statusMessage =
                "تم ربط مجلد 3E وتسجيل تطبيق 3ERoomElectrical بنجاح."
            notifyStorageChanged()
        } catch {
            selectedURL.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    func ensureDirectories() throws {
        try prepare(context: currentContext())
    }

    func clearLastError() {
        lastErrorMessage = nil
    }

    func clearFolderReselectionRequest() {
        needsFolderReselection = false
    }

    func urlForValidatedRelativePath(_ relativePath: String) throws -> URL {
        guard let sharedRoot = threeERootURL else {
            throw ThreeEStorageError.sharedFolderNotConnected
        }
        return try Self.safeURL(
            relativePath: relativePath,
            under: sharedRoot
        )
    }

    func relativePath(for url: URL) -> String? {
        if let sharedRoot = threeERootURL,
           let relative = Self.relativePath(of: url, under: sharedRoot) {
            return relative
        }
        return Self.relativePath(of: url, under: appRootURL)
    }

    private func bootstrapStorage() {
        if let groupRoot = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier:
                ThreeEStorageConstants.futureAppGroupIdentifier
        ) {
            let groupContext = StorageContext(
                source: .appGroup,
                threeERootURL: groupRoot,
                appRootURL: Self.appRootURL(under: groupRoot)
            )
            do {
                try prepare(context: groupContext)
                try migratePrivateDataIfNeeded(to: groupContext.appRootURL)
                setContext(groupContext)
                source = .appGroup
                statusMessage = "يستخدم التطبيق App Group المشترك."
                return
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }

        if restoreFilesBookmark() {
            return
        }

        let restoreFailed = needsFolderReselection
        do {
            try prepare(context: currentContext())
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        source = .privateSandbox
        if !restoreFailed {
            statusMessage =
                "يعمل التطبيق داخل مساحته الخاصة مؤقتًا حتى تختار مجلد 3E."
        }
    }

    private func restoreFilesBookmark() -> Bool {
        guard let bookmark = defaults.data(
            forKey: ThreeEStorageConstants.bookmarkDefaultsKey
        ) else {
            return false
        }

        do {
            var isStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            guard resolvedURL.lastPathComponent.caseInsensitiveCompare("3E")
                    == .orderedSame else {
                throw ThreeEStorageError.selectedFolderIsNotThreeE
            }
            guard resolvedURL.startAccessingSecurityScopedResource() else {
                throw ThreeEStorageError.securityScopeUnavailable
            }

            do {
                let restoredContext = StorageContext(
                    source: .filesFolder,
                    threeERootURL: resolvedURL,
                    appRootURL: Self.appRootURL(under: resolvedURL)
                )
                try prepare(context: restoredContext)
                try migratePrivateDataIfNeeded(
                    to: restoredContext.appRootURL
                )
                setContext(restoredContext)
                securityScopedURL = resolvedURL
                securityScopeActive = true
                source = .filesFolder
                statusMessage =
                    "تمت استعادة صلاحية مجلد 3E تلقائيًا."
                needsFolderReselection = false
                lastErrorMessage = nil

                if isStale {
                    let refreshedBookmark = try resolvedURL.bookmarkData(
                        options: [.minimalBookmark],
                        includingResourceValuesForKeys: [
                            .isDirectoryKey,
                            .nameKey
                        ],
                        relativeTo: nil
                    )
                    defaults.set(
                        refreshedBookmark,
                        forKey: ThreeEStorageConstants.bookmarkDefaultsKey
                    )
                }
                return true
            } catch {
                resolvedURL.stopAccessingSecurityScopedResource()
                throw error
            }
        } catch {
            defaults.removeObject(
                forKey: ThreeEStorageConstants.bookmarkDefaultsKey
            )
            needsFolderReselection = true
            lastErrorMessage = error.localizedDescription
            statusMessage =
                "تعذر استعادة مجلد 3E. اختر المجلد نفسه من Files مرة أخرى."
            return false
        }
    }

    private func prepare(context: StorageContext) throws {
        if let sharedRoot = context.threeERootURL {
            try fileManager.createDirectory(
                at: sharedRoot,
                withIntermediateDirectories: true
            )
            for relativePath in ThreeEStorageConstants.sharedSubdirectories {
                try fileManager.createDirectory(
                    at: Self.url(
                        forRelativePath: relativePath,
                        under: sharedRoot
                    ),
                    withIntermediateDirectories: true
                )
            }
        }

        try fileManager.createDirectory(
            at: context.appRootURL,
            withIntermediateDirectories: true
        )
        for relativePath in ThreeEStorageConstants.appSubdirectories {
            try fileManager.createDirectory(
                at: Self.url(
                    forRelativePath: relativePath,
                    under: context.appRootURL
                ),
                withIntermediateDirectories: true
            )
        }

        if let sharedRoot = context.threeERootURL {
            try ThreeERegistry.registerRoomElectricalApp(in: sharedRoot)
        }
    }

    private func migratePrivateDataIfNeeded(to destinationRoot: URL) throws {
        guard let documents = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw ThreeEStorageError.documentsDirectoryUnavailable
        }
        let privateRoot = documents
            .appendingPathComponent("3Essam", isDirectory: true)
            .appendingPathComponent("3ERoomElectrical", isDirectory: true)

        guard privateRoot.standardizedFileURL
                != destinationRoot.standardizedFileURL,
              fileManager.fileExists(atPath: privateRoot.path) else {
            return
        }

        try mergeMissingContents(
            from: privateRoot,
            to: destinationRoot
        )
    }

    private func mergeMissingContents(
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

            let destination = destinationDirectory.appendingPathComponent(
                source.lastPathComponent,
                isDirectory: values.isDirectory == true
            )

            if values.isDirectory == true {
                try mergeMissingContents(
                    from: source,
                    to: destination
                )
            } else if values.isRegularFile == true,
                      !fileManager.fileExists(atPath: destination.path) {
                try fileManager.copyItem(at: source, to: destination)
            }
        }
    }

    private func currentContext() -> StorageContext {
        contextLock.lock()
        defer { contextLock.unlock() }
        return context
    }

    private func setContext(_ newContext: StorageContext) {
        contextLock.lock()
        context = newContext
        contextLock.unlock()
        source = newContext.source
    }

    private func releaseSecurityScope() {
        if securityScopeActive, let securityScopedURL {
            securityScopedURL.stopAccessingSecurityScopedResource()
        }
        securityScopeActive = false
        securityScopedURL = nil
    }

    private func notifyStorageChanged() {
        NotificationCenter.default.post(
            name: .threeEStorageDidChange,
            object: self
        )
    }

    private static func appRootURL(under threeERootURL: URL) -> URL {
        url(
            forRelativePath: ThreeEStorageConstants.appRelativePath,
            under: threeERootURL
        )
    }

    private static func url(
        forRelativePath relativePath: String,
        under rootURL: URL
    ) -> URL {
        relativePath.split(separator: "/").reduce(rootURL) {
            $0.appendingPathComponent(String($1), isDirectory: true)
        }
    }

    private static func safeURL(
        relativePath: String,
        under rootURL: URL
    ) throws -> URL {
        let trimmed = relativePath.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("\\"),
              !trimmed.hasPrefix("~"),
              !trimmed.contains("\\"),
              !trimmed.contains(":"),
              !trimmed.contains("\0") else {
            throw ThreeEStorageError.invalidRelativePath
        }

        let components = trimmed.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
              }) else {
            throw ThreeEStorageError.invalidRelativePath
        }

        let candidate = components.reduce(rootURL.standardizedFileURL) {
            $0.appendingPathComponent($1)
        }.standardizedFileURL

        let canonicalRoot = rootURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let canonicalCandidate = candidate
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let rootPath = canonicalRoot.path.hasSuffix("/")
            ? canonicalRoot.path
            : canonicalRoot.path + "/"
        guard canonicalCandidate == canonicalRoot
                || canonicalCandidate.path.hasPrefix(rootPath) else {
            throw ThreeEStorageError.pathOutsideRoot
        }
        return candidate
    }

    private static func relativePath(
        of url: URL,
        under rootURL: URL
    ) -> String? {
        let root = rootURL.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        guard candidate == root || candidate.hasPrefix(root + "/") else {
            return nil
        }
        if candidate == root { return "" }
        return String(candidate.dropFirst(root.count + 1))
    }
}

extension Notification.Name {
    static let threeEStorageDidChange = Notification.Name(
        "3ERoomElectrical.threeEStorageDidChange"
    )
}
