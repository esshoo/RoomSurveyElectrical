import ARKit
import Foundation
import RoomPlan

enum ProjectRepository {
    enum RepositoryError: LocalizedError {
        case documentsDirectoryUnavailable
        case projectNotFound
        case invalidName
        case projectAlreadyExists
        case invalidImportedFiles

        var errorDescription: String? {
            switch self {
            case .documentsDirectoryUnavailable:
                "تعذر الوصول إلى مجلد المستندات."
            case .projectNotFound:
                "ملفات المشروع غير موجودة."
            case .invalidName:
                "اكتب اسمًا صحيحًا قبل الحفظ."
            case .projectAlreadyExists:
                "يوجد مسح آخر بنفس المعرّف ولا يمكن استبداله مباشرة."
            case .invalidImportedFiles:
                "ملفات المسح داخل حزمة المشروع غير مكتملة أو غير صالحة."
            }
        }
    }

    private static let fileManager = FileManager.default

    private static var storageEncoder: JSONEncoder {
        configuredEncoder(outputFormatting: [])
    }

    private static var diagnosticEncoder: JSONEncoder {
        configuredEncoder(outputFormatting: [.prettyPrinted, .sortedKeys])
    }

    private static func configuredEncoder(
        outputFormatting: JSONEncoder.OutputFormatting
    ) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = outputFormatting
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
            do {
                try ApplicationFileLayout.prepare()
                return try ApplicationFileLayout.roomScansDirectory
            } catch {
                throw RepositoryError.documentsDirectoryUnavailable
            }
        }
    }

    static func createProject(
        room: CapturedRoom,
        rawData: CapturedRoomData?,
        name requestedName: String? = nil,
        includeFurniture: Bool = true
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
        if includeFurniture {
            do {
                processedData = try diagnosticEncoder.encode(room)
            } catch {
                processedData = try diagnosticEncoder.encode(RoomSummaryExport(room: room))
            }
        } else {
            // Architecture-only mode intentionally avoids persisting RoomPlan
            // object classifications. The stable summary contains the room
            // envelope and openings required by the electrical workflow.
            processedData = try diagnosticEncoder.encode(RoomSummaryExport(room: room))
        }
        try processedData.write(
            to: projectDirectory.appendingPathComponent(processedFile),
            options: .atomic
        )

        var savedRawFile: String?
        if includeFurniture, let rawData {
            // Raw CapturedRoomData is useful for diagnostics, but it is not
            // required by the electrical editor. Some scans contain values
            // that JSONEncoder cannot represent, so do not fail the project.
            do {
                let encodedRawData = try diagnosticEncoder.encode(rawData)
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

        var project = RoomProject(
            id: id,
            name: scanName,
            createdAt: Date(),
            walls: room.walls.map { WallSnapshot(surface: $0) },
            surfaces: surfaces,
            floors: room.floors.map { FloorSnapshot(surface: $0) },
            objects: includeFurniture
                ? room.objects.map { RoomObjectSnapshot(object: $0) }
                : [],
            points: [],
            processedJSONFile: processedFile,
            rawJSONFile: savedRawFile,
            usdzFile: usdzFile,
            electricalSettings: nil
        )

        project.normalizeWallPhotoMetadata()
        try save(project)
        return project
    }

    static func save(_ project: RoomProject) throws {
        var normalizedProject = project
        normalizedProject.normalizeWallPhotoMetadata()
        let projectDirectory = try directory(for: normalizedProject.id, create: true)
        let data = try storageEncoder.encode(normalizedProject)
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

        project.normalizeWallPhotoMetadata()

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

    static func assetURL(
        projectID: UUID,
        fileName: String,
        createProjectDirectory: Bool = false
    ) throws -> URL {
        guard isSafeImportedFileName(fileName) else {
            throw RepositoryError.invalidImportedFiles
        }
        return try directory(
            for: projectID,
            create: createProjectDirectory
        ).appendingPathComponent(fileName)
    }


    static func saveWorldMap(
        _ worldMap: ARWorldMap,
        projectID: UUID
    ) throws -> String {
        let fileName = "spatial-world-map.arexperience"
        let url = try assetURL(
            projectID: projectID,
            fileName: fileName,
            createProjectDirectory: true
        )
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: worldMap,
            requiringSecureCoding: true
        )
        try data.write(to: url, options: .atomic)
        return fileName
    }

    static func loadWorldMap(
        projectID: UUID,
        fileName: String
    ) throws -> ARWorldMap {
        let url = try assetURL(projectID: projectID, fileName: fileName)
        let data = try Data(contentsOf: url)
        guard let map = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: ARWorldMap.self,
            from: data
        ) else {
            throw RepositoryError.invalidImportedFiles
        }
        return map
    }

    static func hasWorldMap(_ project: RoomProject) -> Bool {
        guard let fileName = project.worldMapFile,
              let url = try? assetURL(projectID: project.id, fileName: fileName) else {
            return false
        }
        return fileManager.fileExists(atPath: url.path)
    }

    static func removeAsset(projectID: UUID, fileName: String?) {
        guard let fileName,
              let url = try? assetURL(
                projectID: projectID,
                fileName: fileName
              ) else { return }
        try? fileManager.removeItem(at: url)
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
            worldMapFile: source.worldMapFile,
            electricalSettings: source.electricalSettings,
            ceilingLights: source.ceilingLights,
            ceilingLightLayouts: source.ceilingLightLayouts,
            wallAppearances: source.wallAppearances,
            wallPhotos: source.wallPhotos,
            wallPhotoSegments: source.wallPhotoSegments,
            photographicScanProgress: source.photographicScanProgress,
            scanContinuationState: source.scanContinuationState
        )
        try save(copy)
        return copy
    }

    static func installImported(
        _ project: RoomProject,
        files: [String: Data]
    ) throws {
        let requiredFiles = [
            project.processedJSONFile,
            project.usdzFile
        ] + (project.rawJSONFile.map { [$0] } ?? [])
        guard requiredFiles.allSatisfy({
            isSafeImportedFileName($0)
        }),
        files.keys.allSatisfy({
            isSafeImportedFileName($0)
        }) else {
            throw RepositoryError.invalidImportedFiles
        }

        let root = try projectsDirectory
        let destination = root.appendingPathComponent(
            project.id.uuidString,
            isDirectory: true
        )
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw RepositoryError.projectAlreadyExists
        }

        let staging = root.appendingPathComponent(
            ".import-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: staging,
            withIntermediateDirectories: false
        )
        defer {
            if fileManager.fileExists(atPath: staging.path) {
                try? fileManager.removeItem(at: staging)
            }
        }

        for (fileName, data) in files {
            try data.write(
                to: staging.appendingPathComponent(fileName),
                options: .atomic
            )
        }
        let projectData = try storageEncoder.encode(project)
        try projectData.write(
            to: staging.appendingPathComponent("project.json"),
            options: .atomic
        )
        try fileManager.moveItem(at: staging, to: destination)
    }

    static func delete(projectID: UUID) throws {
        let projectDirectory = try directory(for: projectID, create: false)
        try fileManager.removeItem(at: projectDirectory)
    }

    private static func isSafeImportedFileName(
        _ fileName: String
    ) -> Bool {
        guard !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              fileName.utf8.count <= 255,
              !fileName.contains("/"),
              !fileName.contains("\\"),
              !fileName.contains("\0") else {
            return false
        }
        return true
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
