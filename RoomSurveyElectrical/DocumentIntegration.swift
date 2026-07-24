import CryptoKit
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let threeEDXF = UTType(
        importedAs: "com.3essam.dxf",
        conformingTo: .data
    )
}

enum ExportArtifactKind: String, Codable, CaseIterable {
    case takeoffXLSX
    case takeoffPDF
    case layeredPlanPDF
    case layoutDXF
    case combinedDXF
    case dxfPackage
    case singleDXF
    case planPNG
    case planPNGPackage
    case singleGLB
    case glbPackage
    case projectPackage
    case unknown

    var title: String {
        switch self {
        case .takeoffXLSX: "حصر XLSX"
        case .takeoffPDF: "تقرير حصر PDF"
        case .layeredPlanPDF: "مخطط PDF بطبقات"
        case .layoutDXF: "DXF Layouts"
        case .combinedDXF: "DXF موحد"
        case .dxfPackage: "حزمة DXF"
        case .singleDXF: "DXF منفرد"
        case .planPNG: "مخطط PNG"
        case .planPNGPackage: "حزمة PNG"
        case .singleGLB: "مجسم GLB"
        case .glbPackage: "حزمة GLB"
        case .projectPackage: "مشروع 3ERoomElectrical"
        case .unknown: "تصدير غير محدد"
        }
    }

    var folderName: String {
        switch self {
        case .takeoffXLSX: "XLSX"
        case .takeoffPDF, .layeredPlanPDF: "PDF"
        case .layoutDXF, .combinedDXF, .singleDXF: "DXF"
        case .dxfPackage: "DXF Packages"
        case .planPNG: "PNG"
        case .planPNGPackage: "PNG Packages"
        case .singleGLB: "GLB"
        case .glbPackage: "GLB Packages"
        case .projectPackage: "Projects"
        case .unknown: "Other"
        }
    }
}

struct ExportRegistryRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let sha256: String
    let fileName: String
    let relativePath: String
    let byteCount: Int64
    let kind: ExportArtifactKind
    let projectID: UUID
    let projectName: String
    let scopeItemID: UUID?
    let roomIDs: [UUID]
    let exportedAt: Date
}

enum ExportRegistry {
    private static let fileManager = FileManager.default
    private static let maximumRecords = 1_000

    static func register(
        sourceURL: URL,
        kind: ExportArtifactKind,
        project: SurveyProject,
        scopeItemID: UUID?,
        roomIDs: [UUID]
    ) throws -> URL {
        try ApplicationFileLayout.prepare()

        let kindDirectory = try ApplicationFileLayout.exportsDirectory
            .appendingPathComponent(kind.folderName, isDirectory: true)
        try fileManager.createDirectory(
            at: kindDirectory,
            withIntermediateDirectories: true
        )

        let destination = ApplicationFileLayout.uniqueDestination(
            in: kindDirectory,
            preferredName: sourceURL.lastPathComponent
        )
        try fileManager.copyItem(at: sourceURL, to: destination)

        let hash = try SHA256FileHasher.hash(url: destination)
        let resourceValues = try destination.resourceValues(
            forKeys: [.fileSizeKey]
        )
        let relativePath = destination.path.replacingOccurrences(
            of: try ApplicationFileLayout.appDirectory.path + "/",
            with: ""
        )
        let record = ExportRegistryRecord(
            id: UUID(),
            sha256: hash,
            fileName: destination.lastPathComponent,
            relativePath: relativePath,
            byteCount: Int64(resourceValues.fileSize ?? 0),
            kind: kind,
            projectID: project.id,
            projectName: project.name,
            scopeItemID: scopeItemID,
            roomIDs: roomIDs,
            exportedAt: Date()
        )
        var records = loadRecords()
        records.removeAll { $0.sha256 == record.sha256 }
        records.insert(record, at: 0)
        if records.count > maximumRecords {
            records.removeLast(records.count - maximumRecords)
        }
        try saveRecords(records)
        return destination
    }

    static func record(forSHA256 sha256: String) -> ExportRegistryRecord? {
        loadRecords().first { $0.sha256 == sha256 }
    }

    static func recentRecords(limit: Int = 20) -> [ExportRegistryRecord] {
        Array(loadRecords().prefix(max(0, limit)))
    }

    private static var registryURL: URL {
        get throws {
            try ApplicationFileLayout.indexDirectory
                .appendingPathComponent("exports.json")
        }
    }

    private static func loadRecords() -> [ExportRegistryRecord] {
        guard let url = try? registryURL,
              let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(
            [ExportRegistryRecord].self,
            from: data
        )) ?? []
    }

    private static func saveRecords(
        _ records: [ExportRegistryRecord]
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records)
        try data.write(to: registryURL, options: .atomic)
    }
}

struct DXFDocumentCounts: Equatable {
    var floors = 0
    var walls = 0
    var doors = 0
    var windows = 0
    var openings = 0
    var furniture = 0
    var existingElectrical = 0
    var proposedElectrical = 0
    var ceilingLights = 0

    var totalElectrical: Int {
        existingElectrical + proposedElectrical
    }

    var hasValues: Bool {
        floors + walls + doors + windows + openings + furniture
            + existingElectrical + proposedElectrical + ceilingLights > 0
    }
}

enum ExternalDocumentFormat: String {
    case projectPackage
    case pdf
    case dxf
    case unsupported

    var title: String {
        switch self {
        case .projectPackage: "مشروع 3ERoomElectrical"
        case .pdf: "PDF"
        case .dxf: "DXF"
        case .unsupported: "ملف غير مدعوم"
        }
    }
}

enum DocumentOriginConfidence: String {
    case exactRegistryMatch
    case brandedFile
    case unknown

    var title: String {
        switch self {
        case .exactRegistryMatch: "تطابق مؤكد مع سجل التصدير"
        case .brandedFile: "تم اكتشاف وسم 3ERoomElectrical"
        case .unknown: "لم يتم العثور على وسم التطبيق"
        }
    }
}

struct ExternalDocumentInspection: Identifiable {
    let id = UUID()
    let localURL: URL
    let format: ExternalDocumentFormat
    let confidence: DocumentOriginConfidence
    let registryRecord: ExportRegistryRecord?
    let detectedKind: ExportArtifactKind
    let dxfCounts: DXFDocumentCounts?
    let sha256: String

    var isBranded: Bool {
        confidence != .unknown
    }
}

enum ExternalDocumentInspector {
    private static let fileManager = FileManager.default

    static func inspect(_ sourceURL: URL) throws -> ExternalDocumentInspection {
        try ApplicationFileLayout.prepare()
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let localURL = try cacheOpenedFile(sourceURL)
        let hash = try SHA256FileHasher.hash(url: localURL)
        let record = ExportRegistry.record(forSHA256: hash)
        let fileExtension = localURL.pathExtension.lowercased()

        switch fileExtension {
        case "3eroom":
            return ExternalDocumentInspection(
                localURL: localURL,
                format: .projectPackage,
                confidence: record == nil ? .brandedFile : .exactRegistryMatch,
                registryRecord: record,
                detectedKind: .projectPackage,
                dxfCounts: nil,
                sha256: hash
            )
        case "pdf":
            let markers = try FileMarkerScanner.scan(
                url: localURL,
                markers: [
                    "3ERoomElectrical Layered PDF Engine",
                    "3ERoomElectrical",
                    "3Essam"
                ]
            )
            let kind: ExportArtifactKind
            if let record {
                kind = record.kind
            } else if markers.contains(
                "3ERoomElectrical Layered PDF Engine"
            ) {
                kind = .layeredPlanPDF
            } else {
                kind = .unknown
            }
            return ExternalDocumentInspection(
                localURL: localURL,
                format: .pdf,
                confidence: confidence(record: record, markers: markers),
                registryRecord: record,
                detectedKind: kind,
                dxfCounts: nil,
                sha256: hash
            )
        case "dxf":
            let analysis = try DXFSignatureAnalyzer.analyse(url: localURL)
            return ExternalDocumentInspection(
                localURL: localURL,
                format: .dxf,
                confidence: record != nil
                    ? .exactRegistryMatch
                    : (analysis.isBranded ? .brandedFile : .unknown),
                registryRecord: record,
                detectedKind: record?.kind ?? analysis.detectedKind,
                dxfCounts: analysis.counts,
                sha256: hash
            )
        default:
            return ExternalDocumentInspection(
                localURL: localURL,
                format: .unsupported,
                confidence: record == nil ? .unknown : .exactRegistryMatch,
                registryRecord: record,
                detectedKind: record?.kind ?? .unknown,
                dxfCounts: nil,
                sha256: hash
            )
        }
    }

    private static func confidence(
        record: ExportRegistryRecord?,
        markers: Set<String>
    ) -> DocumentOriginConfidence {
        if record != nil {
            return .exactRegistryMatch
        }
        return markers.isEmpty ? .unknown : .brandedFile
    }

    private static func cacheOpenedFile(_ sourceURL: URL) throws -> URL {
        let appRoot = try ApplicationFileLayout.appDirectory
            .standardizedFileURL.path
        let sourcePath = sourceURL.standardizedFileURL.path
        if sourcePath == appRoot || sourcePath.hasPrefix(appRoot + "/") {
            return sourceURL
        }

        let destination = ApplicationFileLayout.uniqueDestination(
            in: try ApplicationFileLayout.importsDirectory,
            preferredName: sourceURL.lastPathComponent
        )
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }
}

private enum SHA256FileHasher {
    static func hash(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576),
              !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
    }
}

private enum FileMarkerScanner {
    static func scan(
        url: URL,
        markers: [String]
    ) throws -> Set<String> {
        let markerData = markers.map { ($0, Data($0.utf8)) }
        let maximumMarkerLength = markerData.map { $0.1.count }.max() ?? 0
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var found: Set<String> = []
        var overlap = Data()
        while let chunk = try handle.read(upToCount: 1_048_576),
              !chunk.isEmpty {
            var searchable = overlap
            searchable.append(chunk)
            for (name, data) in markerData where !found.contains(name) {
                if searchable.range(of: data) != nil {
                    found.insert(name)
                }
            }
            if found.count == markers.count {
                break
            }
            let overlapCount = min(
                max(0, maximumMarkerLength - 1),
                searchable.count
            )
            overlap = searchable.suffix(overlapCount)
        }
        return found
    }
}

private struct DXFSignatureAnalysis {
    let isBranded: Bool
    let detectedKind: ExportArtifactKind
    let counts: DXFDocumentCounts
}

private enum DXFSignatureAnalyzer {
    static func analyse(url: URL) throws -> DXFSignatureAnalysis {
        var reader = try DXFLineReader(url: url)
        var counts = DXFDocumentCounts()
        var currentType: String?
        var currentLayer: String?
        var currentSection: String?
        var waitingForSectionName = false
        var brandTextCount = 0
        var layoutObjectCount = 0
        var knownLayers: Set<String> = []

        let expectedLayers: Set<String> = [
            "FLOOR", "WALLS", "DOORS", "WINDOWS", "OPENINGS",
            "FURNITURE", "ELECTRICAL_EXISTING",
            "ELECTRICAL_PROPOSED", "CEILING_LIGHTING",
            "DIM_WALLS", "DIM_ELECTRICAL", "ANNOTATIONS"
        ]

        func finishEntity() {
            guard currentSection == "ENTITIES",
                  let type = currentType,
                  let layer = currentLayer else {
                currentType = nil
                currentLayer = nil
                return
            }
            switch (layer.uppercased(), type.uppercased()) {
            case ("FLOOR", "LWPOLYLINE"), ("FLOOR", "POLYLINE"):
                counts.floors += 1
            case ("WALLS", "LINE"):
                counts.walls += 1
            case ("DOORS", "LINE"):
                counts.doors += 1
            case ("WINDOWS", "LINE"):
                counts.windows += 1
            case ("OPENINGS", "LINE"):
                counts.openings += 1
            case ("FURNITURE", "LWPOLYLINE"),
                 ("FURNITURE", "POLYLINE"):
                counts.furniture += 1
            case ("ELECTRICAL_EXISTING", "CIRCLE"):
                counts.existingElectrical += 1
            case ("ELECTRICAL_PROPOSED", "CIRCLE"):
                counts.proposedElectrical += 1
            case ("CEILING_LIGHTING", "CIRCLE"):
                counts.ceilingLights += 1
            default:
                break
            }
            currentType = nil
            currentLayer = nil
        }

        while let codeLine = try reader.nextLine(),
              let valueLine = try reader.nextLine() {
            let codeText = codeLine.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard let code = Int(codeText) else { continue }
            let value = valueLine.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            if waitingForSectionName, code == 2 {
                currentSection = value.uppercased()
                waitingForSectionName = false
                continue
            }

            if code == 0 {
                finishEntity()
                let upperValue = value.uppercased()
                if upperValue == "SECTION" {
                    waitingForSectionName = true
                    continue
                }
                if upperValue == "ENDSEC" {
                    currentSection = nil
                    continue
                }
                if upperValue == "LAYOUT" {
                    layoutObjectCount += 1
                }
                currentType = upperValue
                continue
            }

            if code == 8, currentType != nil {
                currentLayer = value
            }
            if code == 2 {
                let upperValue = value.uppercased()
                if expectedLayers.contains(upperValue) {
                    knownLayers.insert(upperValue)
                }
            }
            if code == 1 || code == 3 || code == 999 {
                if value.localizedCaseInsensitiveContains(
                    "3ERoomElectrical"
                ) || value.localizedCaseInsensitiveContains("3Essam") {
                    brandTextCount += 1
                }
            }
        }
        finishEntity()

        let isBranded = brandTextCount > 0 && knownLayers.count >= 8
        let kind: ExportArtifactKind
        if layoutObjectCount > 1 {
            kind = .layoutDXF
        } else if counts.walls > 0 && brandTextCount > 1 {
            kind = .combinedDXF
        } else if counts.walls > 0 {
            kind = .singleDXF
        } else {
            kind = .unknown
        }
        return DXFSignatureAnalysis(
            isBranded: isBranded,
            detectedKind: kind,
            counts: counts
        )
    }
}

private struct DXFLineReader {
    private let handle: FileHandle
    private var buffer = Data()
    private var reachedEnd = false

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
    }

    mutating func nextLine() throws -> String? {
        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                var line = buffer.prefix(upTo: newlineIndex)
                buffer.removeSubrange(...newlineIndex)
                if line.last == 0x0D {
                    line = line.dropLast()
                }
                return String(decoding: line, as: UTF8.self)
            }

            if reachedEnd {
                guard !buffer.isEmpty else {
                    try? handle.close()
                    return nil
                }
                var line = buffer
                buffer.removeAll(keepingCapacity: false)
                if line.last == 0x0D {
                    line.removeLast()
                }
                return String(decoding: line, as: UTF8.self)
            }

            let chunk = try handle.read(upToCount: 262_144) ?? Data()
            if chunk.isEmpty {
                reachedEnd = true
            } else {
                buffer.append(chunk)
            }
        }
    }
}
