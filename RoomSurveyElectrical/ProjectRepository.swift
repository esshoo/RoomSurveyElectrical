import Foundation
import RoomPlan

enum ProjectRepository {
    enum RepositoryError: LocalizedError {
        case documentsDirectoryUnavailable
        case projectNotFound
        case invalidName

        var errorDescription: String? {
            switch self {
            case .documentsDirectoryUnavailable:
                "تعذر الوصول إلى مجلد المستندات."
            case .projectNotFound:
                "ملفات المشروع غير موجودة."
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
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return decoder
    }

    private struct RoomSummaryExport: Codable {
        let formatVersion: Int
        let createdAt: Date
        let walls: [WallSnapshot]
        let doors: [SurfaceSnapshot]
        let windows: [SurfaceSnapshot]
        let openings: [SurfaceSnapshot]

        init(room: CapturedRoom) {
            formatVersion = 1
            createdAt = Date()
            walls = room.walls.map { WallSnapshot(surface: $0) }
            doors = room.doors.map { SurfaceSnapshot(surface: $0, kind: .door) }
            windows = room.windows.map { SurfaceSnapshot(surface: $0, kind: .window) }
            openings = room.openings.map { SurfaceSnapshot(surface: $0, kind: .opening) }
        }
    }

    static var projectsDirectory: URL {
        get throws {
            guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw RepositoryError.documentsDirectoryUnavailable
            }

            let directory = documents.appendingPathComponent("RoomSurveyProjects", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    static func createProject(
        room: CapturedRoom,
        rawData: CapturedRoomData?,
        name requestedName: String? = nil
    ) throws -> RoomProject {
        let id = UUID()
        let projectDirectory = try directory(for: id, create: true)
        let processedFile = "room.json"
        let rawFile = "raw-room.json"
        let usdzFile = "room.usdz"

        // A RoomPlan scan may contain non-finite measurements or a newly
        // introduced value that its Codable implementation cannot serialize.
        // Keep a stable app-owned snapshot as a fallback so a valid scan is
        // never discarded just because Apple's diagnostic JSON failed.
        let processedData: Data
        do {
            processedData = try encoder.encode(room)
        } catch {
            processedData = try encoder.encode(RoomSummaryExport(room: room))
        }
        try processedData.write(
            to: projectDirectory.appendingPathComponent(processedFile),
            options: .atomic
        )

        var savedRawFile: String?
        if let rawData {
            // Raw CapturedRoomData is useful for diagnostics, but it is not
            // required by the electrical editor. Some scans contain values
            // that JSONEncoder cannot represent, so do not fail the project.
            do {
                let encodedRawData = try encoder.encode(rawData)
                try encodedRawData.write(
                    to: projectDirectory.appendingPathComponent(rawFile),
                    options: .atomic
                )
                savedRawFile = rawFile
            } catch {
                savedRawFile = nil
            }
        }

        let usdzURL = projectDirectory.appendingPathComponent(usdzFile)
        try? fileManager.removeItem(at: usdzURL)
        try room.export(to: usdzURL, exportOptions: .parametric)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateFormat = "d MMM yyyy - HH:mm"

        let surfaces = room.doors.map { SurfaceSnapshot(surface: $0, kind: .door) }
            + room.windows.map { SurfaceSnapshot(surface: $0, kind: .window) }
            + room.openings.map { SurfaceSnapshot(surface: $0, kind: .opening) }

        let cleanName = requestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let scanName = cleanName.flatMap { $0.isEmpty ? nil : $0 }
            ?? "غرفة \(formatter.string(from: Date()))"

        let project = RoomProject(
            id: id,
            name: scanName,
            createdAt: Date(),
            walls: room.walls.map { WallSnapshot(surface: $0) },
            surfaces: surfaces,
            floors: room.floors.map { FloorSnapshot(surface: $0) },
            objects: room.objects.map { RoomObjectSnapshot(object: $0) },
            points: [],
            processedJSONFile: processedFile,
            rawJSONFile: savedRawFile,
            usdzFile: usdzFile,
            electricalSettings: nil
        )

        try save(project)
        return project
    }

    static func save(_ project: RoomProject) throws {
        let projectDirectory = try directory(for: project.id, create: true)
        let data = try encoder.encode(project)
        try data.write(
            to: projectDirectory.appendingPathComponent("project.json"),
            options: .atomic
        )
    }

    static func loadAll() -> [RoomProject] {
        guard let root = try? projectsDirectory,
              let directories = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return directories.compactMap { directory in
            guard let id = UUID(uuidString: directory.lastPathComponent) else { return nil }
            return load(projectID: id)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    static func load(projectID: UUID) -> RoomProject? {
        guard let projectDirectory = try? directory(for: projectID, create: false),
              let data = try? Data(
                contentsOf: projectDirectory.appendingPathComponent("project.json")
              ), var project = try? decoder.decode(RoomProject.self, from: data) else {
            return nil
        }

        if project.floors == nil || project.objects == nil,
           let roomData = try? Data(
            contentsOf: projectDirectory.appendingPathComponent(project.processedJSONFile)
           ), let capturedRoom = try? decoder.decode(CapturedRoom.self, from: roomData) {
            project.floors = capturedRoom.floors.map { FloorSnapshot(surface: $0) }
            project.objects = capturedRoom.objects.map { RoomObjectSnapshot(object: $0) }
            try? save(project)
        }

        return project
    }

    static func fileURL(projectID: UUID, fileName: String) throws -> URL {
        let url = try directory(for: projectID, create: false).appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            throw RepositoryError.projectNotFound
        }
        return url
    }

    static func rename(projectID: UUID, name: String) throws -> RoomProject {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw RepositoryError.invalidName }
        guard var project = load(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        project.name = cleanName
        try save(project)
        return project
    }

    static func duplicate(projectID: UUID, name: String? = nil) throws -> RoomProject {
        guard let source = load(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }

        let newID = UUID()
        let sourceDirectory = try directory(for: projectID, create: false)
        let destinationDirectory = try directory(for: newID, create: false, validateExistence: false)
        try fileManager.copyItem(at: sourceDirectory, to: destinationDirectory)

        let requestedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let copyName = requestedName.flatMap { $0.isEmpty ? nil : $0 }
            ?? "نسخة من \(source.name)"
        let copy = RoomProject(
            id: newID,
            name: copyName,
            createdAt: Date(),
            walls: source.walls,
            surfaces: source.surfaces,
            floors: source.floors,
            objects: source.objects,
            points: source.points,
            processedJSONFile: source.processedJSONFile,
            rawJSONFile: source.rawJSONFile,
            usdzFile: source.usdzFile,
            electricalSettings: source.electricalSettings,
            ceilingLights: source.ceilingLights,
            ceilingLightLayouts: source.ceilingLightLayouts
        )
        try save(copy)
        return copy
    }

    static func delete(projectID: UUID) throws {
        let projectDirectory = try directory(for: projectID, create: false)
        try fileManager.removeItem(at: projectDirectory)
    }

    private static func directory(
        for projectID: UUID,
        create: Bool,
        validateExistence: Bool = true
    ) throws -> URL {
        let url = try projectsDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
        if create {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } else if validateExistence && !fileManager.fileExists(atPath: url.path) {
            throw RepositoryError.projectNotFound
        }
        return url
    }
}
