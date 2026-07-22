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

        var errorDescription: String? {
            switch self {
            case .documentsDirectoryUnavailable:
                "تعذر الوصول إلى مجلد المستندات."
            case .projectNotFound:
                "لم يتم العثور على المشروع المطلوب."
            case .invalidName:
                "اكتب اسمًا صحيحًا قبل الحفظ."
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
}
