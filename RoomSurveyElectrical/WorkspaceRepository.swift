import Combine
import Foundation

enum GlobalSettingsRepository {
    private static let key = "3ERoomElectrical.globalElectricalSettings.v1"

    static func load() -> ElectricalPlacementSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(ElectricalPlacementSettings.self, from: data) else {
            return .standard
        }
        return settings
    }

    static func save(_ settings: ElectricalPlacementSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum WorkspaceRepository {
    enum RepositoryError: LocalizedError {
        case documentsDirectoryUnavailable
        case projectNotFound
        case invalidName
        case invalidDestination
        case operationNotAllowed

        var errorDescription: String? {
            switch self {
            case .documentsDirectoryUnavailable:
                "تعذر الوصول إلى مجلد المستندات."
            case .projectNotFound:
                "لم يتم العثور على المشروع المطلوب."
            case .invalidName:
                "اكتب اسمًا صحيحًا قبل الحفظ."
            case .invalidDestination:
                "لا يمكن النقل إلى المكان المحدد."
            case .operationNotAllowed:
                "يجب أرشفة العنصر قبل حذفه نهائيًا."
            }
        }
    }

    private static let fileManager = FileManager.default

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var projectsDirectory: URL {
        get throws {
            guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw RepositoryError.documentsDirectoryUnavailable
            }
            let directory = documents.appendingPathComponent("3ERoomElectricalProjects", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    static func createProject(
        name: String,
        kind: SurveyProjectKind,
        settings: ElectricalPlacementSettings
    ) throws -> SurveyProject {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw RepositoryError.invalidName }

        let project = SurveyProject(name: cleanName, kind: kind, settings: settings)
        try save(project)
        return project
    }

    static func loadAll() -> [SurveyProject] {
        var projects = loadStoredProjects()
        projects = importUnlinkedLegacyScans(into: projects)
        return projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func load(projectID: UUID) -> SurveyProject? {
        loadAll().first { $0.id == projectID }
    }

    static func save(_ project: SurveyProject) throws {
        let directory = try directory(for: project.id, create: true)
        let data = try encoder.encode(project)
        try data.write(to: directory.appendingPathComponent("workspace.json"), options: .atomic)
    }

    static func addItem(
        projectID: UUID,
        parentID: UUID?,
        name: String,
        kind: WorkspaceItemKind
    ) throws -> SurveyProject {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw RepositoryError.invalidName }
        guard var project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }

        project.items.append(
            WorkspaceItem(parentID: parentID, name: cleanName, kind: kind)
        )
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func attachScan(
        _ roomProject: RoomProject,
        to destination: ScanDestination
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: destination.surveyProjectID) else {
            throw RepositoryError.projectNotFound
        }

        if let index = project.scans.firstIndex(where: { $0.id == roomProject.id }) {
            project.scans[index].parentID = destination.parentItemID
            project.scans[index].name = roomProject.name
        } else {
            project.scans.append(
                ScanReference(roomProject: roomProject, parentID: destination.parentItemID)
            )
        }
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func updateSettings(
        projectID: UUID,
        settings: ElectricalPlacementSettings
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        project.settings = settings
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func renameProject(projectID: UUID, name: String) throws -> SurveyProject {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw RepositoryError.invalidName }
        guard var project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        project.name = cleanName
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func duplicateProject(projectID: UUID) throws -> SurveyProject {
        guard let source = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }

        var itemIDMap: [UUID: UUID] = [:]
        for item in source.items {
            itemIDMap[item.id] = UUID()
        }

        let copiedItems = source.items.map { item in
            WorkspaceItem(
                id: itemIDMap[item.id] ?? UUID(),
                parentID: item.parentID.flatMap { itemIDMap[$0] },
                name: item.name,
                kind: item.kind,
                createdAt: Date(),
                isArchived: item.isArchived
            )
        }

        var copiedScanIDs: [UUID] = []
        var copiedScans: [ScanReference] = []
        do {
            for scan in source.scans {
                let copiedRoom = try ProjectRepository.duplicate(
                    projectID: scan.id,
                    name: scan.name
                )
                copiedScanIDs.append(copiedRoom.id)
                copiedScans.append(
                    ScanReference(
                        roomProject: copiedRoom,
                        parentID: scan.parentID.flatMap { itemIDMap[$0] },
                        isArchived: scan.isArchived,
                        isIncludedInTakeoff: scan.isIncludedInTakeoff
                    )
                )
            }
        } catch {
            for scanID in copiedScanIDs {
                try? ProjectRepository.delete(projectID: scanID)
            }
            throw error
        }

        let copy = SurveyProject(
            name: "نسخة من \(source.name)",
            kind: source.kind,
            settings: source.settings,
            items: copiedItems,
            scans: copiedScans
        )
        try save(copy)
        return copy
    }

    static func setProjectArchived(projectID: UUID, archived: Bool) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        project.isArchived = archived
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func deleteProject(projectID: UUID) throws {
        guard let project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        guard project.archived else { throw RepositoryError.operationNotAllowed }

        for scan in project.scans {
            if ProjectRepository.load(projectID: scan.id) != nil {
                try ProjectRepository.delete(projectID: scan.id)
            }
        }
        let projectDirectory = try directory(for: projectID, create: false)
        try fileManager.removeItem(at: projectDirectory)
    }

    static func renameItem(
        projectID: UUID,
        itemID: UUID,
        name: String
    ) throws -> SurveyProject {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw RepositoryError.invalidName }
        guard var project = loadStoredProject(projectID: projectID),
              let index = project.items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.projectNotFound
        }
        project.items[index].name = cleanName
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func duplicateItem(projectID: UUID, itemID: UUID) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let source = project.items.first(where: { $0.id == itemID }) else {
            throw RepositoryError.projectNotFound
        }

        let sourceIDs = project.descendantIDs(of: itemID).union([itemID])
        let sourceItems = project.items.filter { sourceIDs.contains($0.id) }
        var itemIDMap: [UUID: UUID] = [:]
        for item in sourceItems {
            itemIDMap[item.id] = UUID()
        }

        let copiedItems = sourceItems.map { item in
            let isRoot = item.id == itemID
            return WorkspaceItem(
                id: itemIDMap[item.id] ?? UUID(),
                parentID: isRoot ? source.parentID : item.parentID.flatMap { itemIDMap[$0] },
                name: isRoot ? "نسخة من \(item.name)" : item.name,
                kind: item.kind,
                createdAt: Date()
            )
        }

        var copiedScanIDs: [UUID] = []
        var copiedScans: [ScanReference] = []
        do {
            for scan in project.scans where scan.parentID.map(sourceIDs.contains) == true {
                let copiedRoom = try ProjectRepository.duplicate(projectID: scan.id, name: scan.name)
                copiedScanIDs.append(copiedRoom.id)
                copiedScans.append(
                    ScanReference(
                        roomProject: copiedRoom,
                        parentID: scan.parentID.flatMap { itemIDMap[$0] },
                        isIncludedInTakeoff: scan.isIncludedInTakeoff
                    )
                )
            }
        } catch {
            for scanID in copiedScanIDs {
                try? ProjectRepository.delete(projectID: scanID)
            }
            throw error
        }

        project.items.append(contentsOf: copiedItems)
        project.scans.append(contentsOf: copiedScans)
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func moveItem(
        projectID: UUID,
        itemID: UUID,
        destinationParentID: UUID?
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let index = project.items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.projectNotFound
        }
        let blockedIDs = project.descendantIDs(of: itemID).union([itemID])
        if let destinationParentID {
            guard project.items.contains(where: { $0.id == destinationParentID }),
                  !blockedIDs.contains(destinationParentID) else {
                throw RepositoryError.invalidDestination
            }
        }
        project.items[index].parentID = destinationParentID
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func setItemArchived(
        projectID: UUID,
        itemID: UUID,
        archived: Bool
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let index = project.items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.projectNotFound
        }
        project.items[index].isArchived = archived
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func deleteItem(projectID: UUID, itemID: UUID) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let item = project.items.first(where: { $0.id == itemID }) else {
            throw RepositoryError.projectNotFound
        }
        guard item.archived else { throw RepositoryError.operationNotAllowed }

        let deletedItemIDs = project.descendantIDs(of: itemID).union([itemID])
        let deletedScans = project.scans.filter {
            $0.parentID.map(deletedItemIDs.contains) == true
        }
        for scan in deletedScans {
            if ProjectRepository.load(projectID: scan.id) != nil {
                try ProjectRepository.delete(projectID: scan.id)
            }
        }
        let deletedScanIDs = Set(deletedScans.map(\.id))
        project.items.removeAll { deletedItemIDs.contains($0.id) }
        project.scans.removeAll { deletedScanIDs.contains($0.id) }
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func renameScan(
        projectID: UUID,
        scanID: UUID,
        name: String
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let index = project.scans.firstIndex(where: { $0.id == scanID }) else {
            throw RepositoryError.projectNotFound
        }
        let roomProject = try ProjectRepository.rename(projectID: scanID, name: name)
        project.scans[index].name = roomProject.name
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func duplicateScan(projectID: UUID, scanID: UUID) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let source = project.scans.first(where: { $0.id == scanID }) else {
            throw RepositoryError.projectNotFound
        }
        let copy = try ProjectRepository.duplicate(projectID: scanID)
        project.scans.append(
            ScanReference(
                roomProject: copy,
                parentID: source.parentID,
                isIncludedInTakeoff: false
            )
        )
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func moveScan(
        projectID: UUID,
        scanID: UUID,
        destinationParentID: UUID?
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let index = project.scans.firstIndex(where: { $0.id == scanID }) else {
            throw RepositoryError.projectNotFound
        }
        if let destinationParentID,
           !project.items.contains(where: { $0.id == destinationParentID }) {
            throw RepositoryError.invalidDestination
        }
        project.scans[index].parentID = destinationParentID
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func setScanArchived(
        projectID: UUID,
        scanID: UUID,
        archived: Bool
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let index = project.scans.firstIndex(where: { $0.id == scanID }) else {
            throw RepositoryError.projectNotFound
        }
        project.scans[index].isArchived = archived
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func setScanIncludedInTakeoff(
        projectID: UUID,
        scanID: UUID,
        included: Bool
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let index = project.scans.firstIndex(where: {
                  $0.id == scanID
              }) else {
            throw RepositoryError.projectNotFound
        }
        project.scans[index].isIncludedInTakeoff = included
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func deleteScan(projectID: UUID, scanID: UUID) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let scan = project.scans.first(where: { $0.id == scanID }) else {
            throw RepositoryError.projectNotFound
        }
        guard scan.archived else { throw RepositoryError.operationNotAllowed }
        try ProjectRepository.delete(projectID: scanID)
        project.scans.removeAll { $0.id == scanID }
        project.updatedAt = Date()
        try save(project)
        return project
    }

    private static func loadStoredProjects() -> [SurveyProject] {
        guard let root = try? projectsDirectory,
              let directories = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return directories.compactMap { directory in
            let url = directory.appendingPathComponent("workspace.json")
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(SurveyProject.self, from: data)
        }
    }

    private static func loadStoredProject(projectID: UUID) -> SurveyProject? {
        guard let directory = try? directory(for: projectID, create: false),
              let data = try? Data(contentsOf: directory.appendingPathComponent("workspace.json")) else {
            return nil
        }
        return try? decoder.decode(SurveyProject.self, from: data)
    }

    private static func importUnlinkedLegacyScans(
        into storedProjects: [SurveyProject]
    ) -> [SurveyProject] {
        var projects = storedProjects
        let linkedScanIDs = Set(projects.flatMap(\.scans).map(\.id))
        let unlinkedScans = ProjectRepository.loadAll().filter { !linkedScanIDs.contains($0.id) }
        guard !unlinkedScans.isEmpty else { return projects }

        var archive: SurveyProject
        if let index = projects.firstIndex(where: \.isImportedArchive) {
            archive = projects.remove(at: index)
        } else {
            archive = SurveyProject(
                name: "المسحات السابقة",
                kind: .other,
                settings: GlobalSettingsRepository.load(),
                isImportedArchive: true
            )
        }

        for scan in unlinkedScans {
            let roomItem = WorkspaceItem(
                parentID: nil,
                name: scan.name,
                kind: .room,
                createdAt: scan.createdAt
            )
            archive.items.append(roomItem)
            archive.scans.append(
                ScanReference(roomProject: scan, parentID: roomItem.id)
            )
        }
        archive.updatedAt = Date()
        try? save(archive)
        projects.append(archive)
        return projects
    }

    private static func directory(for projectID: UUID, create: Bool) throws -> URL {
        let url = try projectsDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
        if create {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } else if !fileManager.fileExists(atPath: url.path) {
            throw RepositoryError.projectNotFound
        }
        return url
    }
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [SurveyProject] = []

    init() {
        reload()
    }

    func reload() {
        projects = WorkspaceRepository.loadAll()
    }

    func project(id: UUID) -> SurveyProject? {
        projects.first { $0.id == id }
    }

    var activeProjects: [SurveyProject] {
        projects.filter { !$0.archived }
    }

    var archivedProjects: [SurveyProject] {
        projects.filter(\.archived)
    }

    @discardableResult
    func createProject(
        name: String,
        kind: SurveyProjectKind,
        settings: ElectricalPlacementSettings
    ) throws -> SurveyProject {
        let project = try WorkspaceRepository.createProject(
            name: name,
            kind: kind,
            settings: settings
        )
        reload()
        return project
    }

    func addItem(
        projectID: UUID,
        parentID: UUID?,
        name: String,
        kind: WorkspaceItemKind
    ) throws {
        _ = try WorkspaceRepository.addItem(
            projectID: projectID,
            parentID: parentID,
            name: name,
            kind: kind
        )
        reload()
    }

    func updateSettings(
        projectID: UUID,
        settings: ElectricalPlacementSettings
    ) throws {
        _ = try WorkspaceRepository.updateSettings(
            projectID: projectID,
            settings: settings
        )
        reload()
    }

    func renameProject(projectID: UUID, name: String) throws {
        _ = try WorkspaceRepository.renameProject(projectID: projectID, name: name)
        reload()
    }

    func duplicateProject(projectID: UUID) throws {
        _ = try WorkspaceRepository.duplicateProject(projectID: projectID)
        reload()
    }

    func setProjectArchived(projectID: UUID, archived: Bool) throws {
        _ = try WorkspaceRepository.setProjectArchived(projectID: projectID, archived: archived)
        reload()
    }

    func deleteProject(projectID: UUID) throws {
        try WorkspaceRepository.deleteProject(projectID: projectID)
        reload()
    }

    func renameItem(projectID: UUID, itemID: UUID, name: String) throws {
        _ = try WorkspaceRepository.renameItem(projectID: projectID, itemID: itemID, name: name)
        reload()
    }

    func duplicateItem(projectID: UUID, itemID: UUID) throws {
        _ = try WorkspaceRepository.duplicateItem(projectID: projectID, itemID: itemID)
        reload()
    }

    func moveItem(projectID: UUID, itemID: UUID, destinationParentID: UUID?) throws {
        _ = try WorkspaceRepository.moveItem(
            projectID: projectID,
            itemID: itemID,
            destinationParentID: destinationParentID
        )
        reload()
    }

    func setItemArchived(projectID: UUID, itemID: UUID, archived: Bool) throws {
        _ = try WorkspaceRepository.setItemArchived(
            projectID: projectID,
            itemID: itemID,
            archived: archived
        )
        reload()
    }

    func deleteItem(projectID: UUID, itemID: UUID) throws {
        _ = try WorkspaceRepository.deleteItem(projectID: projectID, itemID: itemID)
        reload()
    }

    func renameScan(projectID: UUID, scanID: UUID, name: String) throws {
        _ = try WorkspaceRepository.renameScan(projectID: projectID, scanID: scanID, name: name)
        reload()
    }

    func duplicateScan(projectID: UUID, scanID: UUID) throws {
        _ = try WorkspaceRepository.duplicateScan(projectID: projectID, scanID: scanID)
        reload()
    }

    func moveScan(projectID: UUID, scanID: UUID, destinationParentID: UUID?) throws {
        _ = try WorkspaceRepository.moveScan(
            projectID: projectID,
            scanID: scanID,
            destinationParentID: destinationParentID
        )
        reload()
    }

    func setScanArchived(projectID: UUID, scanID: UUID, archived: Bool) throws {
        _ = try WorkspaceRepository.setScanArchived(
            projectID: projectID,
            scanID: scanID,
            archived: archived
        )
        reload()
    }

    func setScanIncludedInTakeoff(
        projectID: UUID,
        scanID: UUID,
        included: Bool
    ) throws {
        _ = try WorkspaceRepository.setScanIncludedInTakeoff(
            projectID: projectID,
            scanID: scanID,
            included: included
        )
        reload()
    }

    func deleteScan(projectID: UUID, scanID: UUID) throws {
        _ = try WorkspaceRepository.deleteScan(projectID: projectID, scanID: scanID)
        reload()
    }
}
