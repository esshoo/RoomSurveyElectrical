import CryptoKit
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let threeERoomProject = UTType(
        exportedAs: "com.3essam.3eroomelectrical.project",
        conformingTo: .archive
    )
}

struct ProjectPackagePreview {
    let projectID: UUID
    let name: String
    let kind: SurveyProjectKind
    let createdAt: Date
    let exportedAt: Date
    let appVersion: String
    let folderCount: Int
    let scanCount: Int
    let totalBytes: Int
    let missingAssetCount: Int
}

struct PreparedProjectPackage: Identifiable {
    let id = UUID()
    let preview: ProjectPackagePreview
    fileprivate let manifest: ProjectPackageManifest
    fileprivate let workspace: SurveyProject
    fileprivate let scans: [UUID: PreparedPackagedScan]
}

enum ProjectPackageImportStrategy {
    case add
    case copy
    case rename(String)
    case replace(UUID)
}

enum ProjectPackageError: LocalizedError {
    case projectNotFound
    case missingScan(String)
    case cannotReadFile
    case fileTooLarge
    case invalidArchive
    case unsupportedCompression
    case invalidManifest
    case unsupportedVersion(Int)
    case damagedFile(String)
    case duplicateProject
    case invalidName
    case replacementProjectNotFound

    var errorDescription: String? {
        switch self {
        case .projectNotFound:
            "لم يتم العثور على المشروع المطلوب."
        case .missingScan(let name):
            "تعذر العثور على بيانات المسح: \(name)."
        case .cannotReadFile:
            "تعذر قراءة ملف المشروع."
        case .fileTooLarge:
            "ملف المشروع أكبر من الحد الآمن للاستيراد."
        case .invalidArchive:
            "هذا الملف ليس حزمة 3ERoomElectrical صالحة."
        case .unsupportedCompression:
            "طريقة ضغط هذا الملف غير مدعومة. أعد تصديره من التطبيق."
        case .invalidManifest:
            "بيانات تعريف حزمة المشروع غير مكتملة أو غير صالحة."
        case .unsupportedVersion(let version):
            "إصدار ملف المشروع (\(version)) أحدث من الإصدار الذي يدعمه التطبيق."
        case .damagedFile(let path):
            "فشل التحقق من سلامة الملف داخل الحزمة: \(path)."
        case .duplicateProject:
            "يوجد مشروع بنفس الاسم أو المعرّف. اختر نسخة جديدة أو إعادة تسمية أو استبدال."
        case .invalidName:
            "اكتب اسمًا جديدًا صحيحًا للمشروع."
        case .replacementProjectNotFound:
            "المشروع المطلوب استبداله لم يعد موجودًا."
        }
    }
}

enum ProjectPackageService {
    static let formatVersion = 2
    static let maximumPackageBytes = 1_500_000_000

    static func makePackage(projectID: UUID) throws -> URL {
        guard let project = WorkspaceRepository.load(
            projectID: projectID
        ) else {
            throw ProjectPackageError.projectNotFound
        }

        var packageProject = project
        // Recovery payloads are local, potentially large, and are not part of
        // the portable .3eroom contract in Build 45. Keep the audit history,
        // but clear links that would point to files unavailable after import.
        packageProject.recoverySnapshots = []
        packageProject.changeSets = packageProject.changeSets?.map { changeSet in
            var portable = changeSet
            portable.recoverySnapshotID = nil
            return portable
        }

        let workspaceData = try packageEncoder.encode(packageProject)
        let workspaceRecord = fileRecord(
            path: "project/workspace.json",
            fileName: "workspace.json",
            data: workspaceData
        )
        var payloads: [(path: String, data: Data)] = [
            (workspaceRecord.path, workspaceData)
        ]
        var packagedScans: [ProjectPackageScanRecord] = []
        var requiresWallPhotoReader = false

        for scanReference in project.scans {
            guard var room = ProjectRepository.load(
                projectID: scanReference.id
            ) else {
                throw ProjectPackageError.missingScan(
                    scanReference.name
                )
            }
            // Geographic evidence and the camera reference image are private,
            // device-local resume aids. Never place them in a portable package.
            if var continuation = room.scanContinuationState {
                continuation.geographicReference = nil
                continuation.referenceImageFile = nil
                room.scanContinuationState = continuation
            }
            let folder = "scans/\(scanReference.id.uuidString)"
            let projectData = try roomEncoder.encode(room)
            let projectRecord = fileRecord(
                path: "\(folder)/project.json",
                fileName: "project.json",
                data: projectData
            )
            payloads.append((projectRecord.path, projectData))

            var assetRecords: [ProjectPackageFileRecord] = []
            var missingFiles: [String] = []
            var assetNames = [
                room.processedJSONFile,
                room.usdzFile
            ]
            if let rawJSONFile = room.rawJSONFile {
                assetNames.append(rawJSONFile)
            }
            if let worldMapFile = room.worldMapFile {
                assetNames.append(worldMapFile)
            }
            if !(room.wallPhotos ?? []).isEmpty {
                requiresWallPhotoReader = true
            }
            for photo in room.wallPhotos ?? [] {
                assetNames.append(photo.fileName)
                if let thumbnailFileName = photo.thumbnailFileName {
                    assetNames.append(thumbnailFileName)
                }
            }

            var seenNames: Set<String> = []
            for fileName in assetNames where
                seenNames.insert(fileName).inserted {
                do {
                    let url = try ProjectRepository.fileURL(
                        projectID: room.id,
                        fileName: fileName
                    )
                    let data = try Data(
                        contentsOf: url,
                        options: .mappedIfSafe
                    )
                    let record = fileRecord(
                        path: "\(folder)/\(fileName)",
                        fileName: fileName,
                        data: data
                    )
                    assetRecords.append(record)
                    payloads.append((record.path, data))
                } catch {
                    missingFiles.append(fileName)
                }
            }

            packagedScans.append(
                ProjectPackageScanRecord(
                    id: room.id,
                    name: scanReference.name,
                    projectFile: projectRecord,
                    assets: assetRecords,
                    missingFiles: missingFiles
                )
            )
        }

        let manifest = ProjectPackageManifest(
            formatIdentifier:
                "com.3essam.3eroomelectrical.project",
            formatVersion: requiresWallPhotoReader ? 2 : 1,
            minimumReaderVersion: requiresWallPhotoReader ? 2 : 1,
            appVersion: appVersion,
            exportedAt: Date(),
            projectID: project.id,
            projectName: project.name,
            projectCreatedAt: project.createdAt,
            workspace: workspaceRecord,
            scans: packagedScans
        )
        let manifestData = try packageEncoder.encode(manifest)

        var archive = StoredZIPArchive()
        archive.add(name: "manifest.json", data: manifestData)
        for payload in payloads {
            archive.add(name: payload.path, data: payload.data)
        }
        return try ProjectExportService.writeTemporaryFile(
            archive.data(),
            name: ProjectExportService.sanitized(project.name),
            extension: "3eroom"
        )
    }

    static func prepareImport(
        from url: URL
    ) throws -> PreparedProjectPackage {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if let fileSize = try? url.resourceValues(
            forKeys: [.fileSizeKey]
        ).fileSize,
        fileSize > maximumPackageBytes {
            throw ProjectPackageError.fileTooLarge
        }

        let packageData: Data
        do {
            packageData = try Data(
                contentsOf: url,
                options: .mappedIfSafe
            )
        } catch {
            throw ProjectPackageError.cannotReadFile
        }
        guard packageData.count <= maximumPackageBytes else {
            throw ProjectPackageError.fileTooLarge
        }

        let entries = try StoredZIPReader(
            data: packageData
        ).readEntries()
        guard let manifestData = entries["manifest.json"],
              let manifest = try? packageDecoder.decode(
                ProjectPackageManifest.self,
                from: manifestData
              ),
              manifest.formatIdentifier
                == "com.3essam.3eroomelectrical.project",
              manifest.minimumReaderVersion <= formatVersion else {
            throw ProjectPackageError.invalidManifest
        }
        guard manifest.formatVersion <= formatVersion else {
            throw ProjectPackageError.unsupportedVersion(
                manifest.formatVersion
            )
        }

        let workspaceData = try verifiedData(
            for: manifest.workspace,
            in: entries
        )
        let workspace: SurveyProject
        do {
            workspace = try packageDecoder.decode(
                SurveyProject.self,
                from: workspaceData
            )
        } catch {
            throw ProjectPackageError.invalidManifest
        }
        guard workspace.id == manifest.projectID,
              workspace.name == manifest.projectName,
              workspace.formatVersion <= 1 else {
            throw ProjectPackageError.invalidManifest
        }

        let manifestScanIDs = Set(manifest.scans.map(\.id))
        let workspaceScanIDs = Set(workspace.scans.map(\.id))
        guard manifestScanIDs == workspaceScanIDs,
              manifestScanIDs.count == manifest.scans.count else {
            throw ProjectPackageError.invalidManifest
        }

        var preparedScans: [UUID: PreparedPackagedScan] = [:]
        var verifiedBytes = manifest.workspace.byteCount
        var missingAssetCount = 0
        for scanRecord in manifest.scans {
            let projectData = try verifiedData(
                for: scanRecord.projectFile,
                in: entries
            )
            let room: RoomProject
            do {
                room = try roomDecoder.decode(
                    RoomProject.self,
                    from: projectData
                )
            } catch {
                throw ProjectPackageError.damagedFile(
                    scanRecord.projectFile.path
                )
            }
            guard room.id == scanRecord.id,
                  scanRecord.projectFile.fileName
                    == "project.json" else {
                throw ProjectPackageError.invalidManifest
            }

            var assets: [String: Data] = [:]
            for asset in scanRecord.assets {
                guard isSafeFileName(asset.fileName),
                      asset.fileName != "project.json" else {
                    throw ProjectPackageError.invalidManifest
                }
                let data = try verifiedData(
                    for: asset,
                    in: entries
                )
                guard assets.updateValue(
                    data,
                    forKey: asset.fileName
                ) == nil else {
                    throw ProjectPackageError.invalidManifest
                }
                verifiedBytes += asset.byteCount
            }
            let wallPhotoAssets = (room.wallPhotos ?? []).flatMap { photo in
                [photo.fileName] + (photo.thumbnailFileName.map { [$0] } ?? [])
            }
            let declaredAssets = Set(
                [
                    room.processedJSONFile,
                    room.usdzFile
                ] + (room.rawJSONFile.map { [$0] } ?? [])
                    + (room.worldMapFile.map { [$0] } ?? [])
                    + wallPhotoAssets
            )
            let availableAssets = Set(assets.keys)
            let missingAssets = Set(scanRecord.missingFiles)
            guard scanRecord.missingFiles.allSatisfy({
                isSafeFileName($0)
            }),
            missingAssets.count == scanRecord.missingFiles.count,
            declaredAssets == availableAssets.union(missingAssets),
            availableAssets.isDisjoint(with: missingAssets) else {
                throw ProjectPackageError.invalidManifest
            }
            missingAssetCount += scanRecord.missingFiles.count
            verifiedBytes += scanRecord.projectFile.byteCount
            preparedScans[scanRecord.id] = PreparedPackagedScan(
                project: room,
                assets: assets
            )
        }

        return PreparedProjectPackage(
            preview: ProjectPackagePreview(
                projectID: workspace.id,
                name: workspace.name,
                kind: workspace.kind,
                createdAt: workspace.createdAt,
                exportedAt: manifest.exportedAt,
                appVersion: manifest.appVersion,
                folderCount: workspace.items.count,
                scanCount: workspace.scans.count,
                totalBytes: verifiedBytes,
                missingAssetCount: missingAssetCount
            ),
            manifest: manifest,
            workspace: workspace,
            scans: preparedScans
        )
    }

    @discardableResult
    static func importPackage(
        _ package: PreparedProjectPackage,
        strategy: ProjectPackageImportStrategy
    ) throws -> SurveyProject {
        let existingProjects = WorkspaceRepository.loadAll()
        let source = package.workspace
        let targetID: UUID
        let targetName: String
        let remapAllIDs: Bool
        var replacedProject: SurveyProject?

        switch strategy {
        case .add:
            guard !existingProjects.contains(where: {
                $0.id == source.id
                    || namesMatch($0.name, source.name)
            }) else {
                throw ProjectPackageError.duplicateProject
            }
            targetID = source.id
            targetName = source.name
            remapAllIDs = false
        case .copy:
            targetID = UUID()
            targetName = uniqueProjectName(
                base: "نسخة من \(source.name)",
                among: existingProjects
            )
            remapAllIDs = true
        case .rename(let requestedName):
            let cleaned = requestedName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !cleaned.isEmpty else {
                throw ProjectPackageError.invalidName
            }
            guard !existingProjects.contains(where: {
                namesMatch($0.name, cleaned)
            }) else {
                throw ProjectPackageError.duplicateProject
            }
            targetID = UUID()
            targetName = cleaned
            remapAllIDs = true
        case .replace(let projectID):
            guard let existing = existingProjects.first(
                where: { $0.id == projectID }
            ) else {
                throw ProjectPackageError
                    .replacementProjectNotFound
            }
            replacedProject = existing
            targetID = existing.id
            targetName = source.name
            remapAllIDs = true
        }

        var itemIDMap: [UUID: UUID] = [:]
        for item in source.items {
            itemIDMap[item.id] = remapAllIDs ? UUID() : item.id
        }

        var scanIDMap: [UUID: UUID] = [:]
        for scan in source.scans {
            let collision = ProjectRepository.load(
                projectID: scan.id
            ) != nil
            scanIDMap[scan.id] = remapAllIDs || collision
                ? UUID()
                : scan.id
        }

        var importedRooms: [UUID: RoomProject] = [:]
        var installedScanIDs: [UUID] = []
        do {
            for sourceScan in source.scans {
                guard let packagedScan = package.scans[
                    sourceScan.id
                ],
                let newScanID = scanIDMap[sourceScan.id] else {
                    throw ProjectPackageError.invalidManifest
                }
                let importedRoom = roomCopy(
                    packagedScan.project,
                    id: newScanID,
                    name: sourceScan.name
                )
                try ProjectRepository.installImported(
                    importedRoom,
                    files: packagedScan.assets
                )
                installedScanIDs.append(newScanID)
                importedRooms[sourceScan.id] = importedRoom
            }

            let importedItems = source.items.map { item in
                WorkspaceItem(
                    id: itemIDMap[item.id] ?? item.id,
                    parentID: item.parentID.flatMap {
                        itemIDMap[$0]
                    },
                    name: item.name,
                    kind: item.kind,
                    createdAt: item.createdAt,
                    isArchived: item.isArchived
                )
            }
            let importedScans = try source.scans.map {
                sourceScan -> ScanReference in
                guard let importedRoom = importedRooms[
                    sourceScan.id
                ] else {
                    throw ProjectPackageError.invalidManifest
                }
                var reference = ScanReference(
                    roomProject: importedRoom,
                    parentID: sourceScan.parentID.flatMap {
                        itemIDMap[$0]
                    },
                    isArchived: sourceScan.isArchived,
                    isIncludedInTakeoff:
                        sourceScan.isIncludedInTakeoff
                )
                reference.name = sourceScan.name
                return reference
            }
            var importedProject = SurveyProject(
                id: targetID,
                name: targetName,
                kind: source.kind,
                settings: source.settings,
                createdAt: source.createdAt,
                updatedAt: Date(),
                items: importedItems,
                scans: importedScans,
                isImportedArchive: source.isImportedArchive,
                isArchived: source.isArchived,
                foundationSchemaVersion: source.foundationSchemaVersion,
                projectSettings: source.projectSettings,
                layerStates: source.layerStates,
                preferredWorkspaceMode: source.preferredWorkspaceMode
            )
            importedProject.roomSettings = source.roomSettings?.compactMap {
                setting in
                guard let mappedScanID = scanIDMap[setting.id] else {
                    return nil
                }
                return RoomSettings(
                    id: mappedScanID,
                    displayName: setting.displayName,
                    electrical: setting.electrical,
                    ceilingHeightMeters: setting.ceilingHeightMeters,
                    wallThicknessMeters: setting.wallThicknessMeters
                )
            }
            importedProject.elementOverrides = source.elementOverrides?.map {
                override in
                ElementSettingsOverride(
                    id: override.id,
                    scanID: override.scanID.flatMap { scanIDMap[$0] },
                    elementID: override.elementID,
                    electrical: override.electrical,
                    isVisible: override.isVisible,
                    isLocked: override.isLocked
                )
            }
            importedProject.changeSets = source.changeSets?.map { changeSet in
                var copied = changeSet
                copied.recoverySnapshotID = nil
                copied.changes = copied.changes.map { change in
                    var remappedChange = change
                    remappedChange.scanID = change.scanID.flatMap {
                        scanIDMap[$0]
                    }
                    return remappedChange
                }
                return copied
            }
            importedProject.recoverySnapshots = []
            importedProject.normalizeFoundation(
                appDefaults: GlobalSettingsRepository.loadAppDefaults()
            )
            try WorkspaceRepository.save(importedProject)

            if let replacedProject {
                let importedIDs = Set(importedScans.map(\.id))
                for oldScan in replacedProject.scans where
                    !importedIDs.contains(oldScan.id) {
                    try? ProjectRepository.delete(
                        projectID: oldScan.id
                    )
                }
            }
            return importedProject
        } catch {
            for scanID in installedScanIDs {
                try? ProjectRepository.delete(projectID: scanID)
            }
            throw error
        }
    }

    private static func roomCopy(
        _ source: RoomProject,
        id: UUID,
        name: String
    ) -> RoomProject {
        RoomProject(
            id: id,
            name: name,
            createdAt: source.createdAt,
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
    }

    private static func verifiedData(
        for record: ProjectPackageFileRecord,
        in entries: [String: Data]
    ) throws -> Data {
        guard isSafeArchivePath(record.path),
              record.byteCount >= 0,
              let data = entries[record.path],
              data.count == record.byteCount,
              sha256(data) == record.sha256 else {
            throw ProjectPackageError.damagedFile(record.path)
        }
        return data
    }

    private static func fileRecord(
        path: String,
        fileName: String,
        data: Data
    ) -> ProjectPackageFileRecord {
        ProjectPackageFileRecord(
            path: path,
            fileName: fileName,
            byteCount: data.count,
            sha256: sha256(data)
        )
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static func namesMatch(
        _ first: String,
        _ second: String
    ) -> Bool {
        first.compare(
            second,
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "ar")
        ) == .orderedSame
    }

    private static func uniqueProjectName(
        base: String,
        among projects: [SurveyProject]
    ) -> String {
        var candidate = base
        var suffix = 2
        while projects.contains(where: {
            namesMatch($0.name, candidate)
        }) {
            candidate = "\(base) (\(suffix))"
            suffix += 1
        }
        return candidate
    }

    private static func isSafeArchivePath(
        _ path: String
    ) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("\0") else {
            return false
        }
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        return components.allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }

    private static func isSafeFileName(
        _ fileName: String
    ) -> Bool {
        isSafeArchivePath(fileName) && !fileName.contains("/")
    }

    private static var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey:
                "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
    }

    private static var packageEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var packageDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var roomEncoder: JSONEncoder {
        let encoder = packageEncoder
        encoder.nonConformingFloatEncodingStrategy =
            .convertToString(
                positiveInfinity: "Infinity",
                negativeInfinity: "-Infinity",
                nan: "NaN"
            )
        return encoder
    }

    private static var roomDecoder: JSONDecoder {
        let decoder = packageDecoder
        decoder.nonConformingFloatDecodingStrategy =
            .convertFromString(
                positiveInfinity: "Infinity",
                negativeInfinity: "-Infinity",
                nan: "NaN"
            )
        return decoder
    }
}

fileprivate struct ProjectPackageManifest: Codable {
    let formatIdentifier: String
    let formatVersion: Int
    let minimumReaderVersion: Int
    let appVersion: String
    let exportedAt: Date
    let projectID: UUID
    let projectName: String
    let projectCreatedAt: Date
    let workspace: ProjectPackageFileRecord
    let scans: [ProjectPackageScanRecord]
}

fileprivate struct ProjectPackageScanRecord: Codable {
    let id: UUID
    let name: String
    let projectFile: ProjectPackageFileRecord
    let assets: [ProjectPackageFileRecord]
    let missingFiles: [String]
}

fileprivate struct ProjectPackageFileRecord: Codable {
    let path: String
    let fileName: String
    let byteCount: Int
    let sha256: String
}

fileprivate struct PreparedPackagedScan {
    let project: RoomProject
    let assets: [String: Data]
}

private struct StoredZIPReader {
    private let data: Data
    private let maximumEntries = 10_000

    init(data: Data) {
        self.data = data
    }

    func readEntries() throws -> [String: Data] {
        var result: [String: Data] = [:]
        var cursor = 0
        var totalUncompressedBytes = 0

        while cursor + 4 <= data.count {
            let signature = try data.littleEndianUInt32(
                at: cursor
            )
            if signature == 0x02014B50
                || signature == 0x06054B50 {
                break
            }
            guard signature == 0x04034B50,
                  result.count < maximumEntries,
                  cursor + 30 <= data.count else {
                throw ProjectPackageError.invalidArchive
            }

            let flags = try data.littleEndianUInt16(
                at: cursor + 6
            )
            let compression = try data.littleEndianUInt16(
                at: cursor + 8
            )
            let expectedCRC = try data.littleEndianUInt32(
                at: cursor + 14
            )
            let compressedSize = Int(
                try data.littleEndianUInt32(at: cursor + 18)
            )
            let uncompressedSize = Int(
                try data.littleEndianUInt32(at: cursor + 22)
            )
            let nameLength = Int(
                try data.littleEndianUInt16(at: cursor + 26)
            )
            let extraLength = Int(
                try data.littleEndianUInt16(at: cursor + 28)
            )

            guard flags & 0x0001 == 0,
                  flags & 0x0008 == 0,
                  compression == 0 else {
                throw ProjectPackageError
                    .unsupportedCompression
            }
            guard compressedSize == uncompressedSize else {
                throw ProjectPackageError.invalidArchive
            }

            let nameStart = cursor + 30
            let nameEnd = nameStart + nameLength
            let contentStart = nameEnd + extraLength
            let contentEnd = contentStart + compressedSize
            guard nameLength > 0,
                  nameEnd >= nameStart,
                  contentStart >= nameEnd,
                  contentEnd >= contentStart,
                  contentEnd <= data.count,
                  let name = String(
                    data: data[nameStart..<nameEnd],
                    encoding: .utf8
                  ),
                  isSafePath(name),
                  result[name] == nil else {
                throw ProjectPackageError.invalidArchive
            }

            totalUncompressedBytes += uncompressedSize
            guard totalUncompressedBytes
                <= ProjectPackageService.maximumPackageBytes else {
                throw ProjectPackageError.fileTooLarge
            }
            let content = Data(data[contentStart..<contentEnd])
            guard ProjectPackageCRC32.checksum(content)
                == expectedCRC else {
                throw ProjectPackageError.damagedFile(name)
            }
            result[name] = content
            cursor = contentEnd
        }

        guard !result.isEmpty,
              result["manifest.json"] != nil else {
            throw ProjectPackageError.invalidArchive
        }
        return result
    }

    private func isSafePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("\0") else {
            return false
        }
        return path.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }
}

private enum ProjectPackageCRC32 {
    private static let table: [UInt32] = (0..<256).map {
        value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1
                ? 0xEDB88320 ^ (crc >> 1)
                : crc >> 1
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int(
                (crc ^ UInt32(byte)) & 0xFF
            )
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    func littleEndianUInt16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else {
            throw ProjectPackageError.invalidArchive
        }
        return UInt16(self[offset])
            | (UInt16(self[offset + 1]) << 8)
    }

    func littleEndianUInt32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else {
            throw ProjectPackageError.invalidArchive
        }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
