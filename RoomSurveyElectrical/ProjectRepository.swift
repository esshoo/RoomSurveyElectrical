import Foundation
import RoomPlan

enum ProjectRepository {
    enum RepositoryError: LocalizedError {
        case documentsDirectoryUnavailable
        case projectNotFound

        var errorDescription: String? {
            switch self {
            case .documentsDirectoryUnavailable:
                "تعذر الوصول إلى مجلد المستندات."
            case .projectNotFound:
                "ملفات المشروع غير موجودة."
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
            points: [],
            processedJSONFile: processedFile,
            rawJSONFile: savedRawFile,
            usdzFile: usdzFile
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
            let metadataURL = directory.appendingPathComponent("project.json")
            guard let data = try? Data(contentsOf: metadataURL) else { return nil }
            return try? decoder.decode(RoomProject.self, from: data)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    static func load(projectID: UUID) -> RoomProject? {
        guard let projectDirectory = try? directory(for: projectID, create: false),
              let data = try? Data(
                contentsOf: projectDirectory.appendingPathComponent("project.json")
              ) else {
            return nil
        }
        return try? decoder.decode(RoomProject.self, from: data)
    }

    static func fileURL(projectID: UUID, fileName: String) throws -> URL {
        let url = try directory(for: projectID, create: false).appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            throw RepositoryError.projectNotFound
        }
        return url
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
