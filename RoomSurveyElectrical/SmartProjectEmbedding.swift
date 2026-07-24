import CryptoKit
import Foundation

struct SmartEmbeddedProjectEnvelope: Codable {
    let formatIdentifier: String
    let containerVersion: Int
    let projectID: UUID
    let projectName: String
    let exportedAt: Date
    let appVersion: String
    let payloadFileName: String
    let payloadByteCount: Int
    let payloadSHA256: String
    let compression: String
}


struct SmartEmbeddedProjectPayload {
    let envelope: SmartEmbeddedProjectEnvelope
    let packageData: Data
}

enum SmartProjectEmbeddingError: LocalizedError {
    case invalidDXF
    case invalidEnvelope
    case unsupportedContainerVersion(Int)
    case damagedPackage
    case packageTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .invalidDXF:
            "ملف DXF غير صالح أو بنيته غير مدعومة."
        case .invalidEnvelope:
            "بيانات تعريف مشروع 3ERoomElectrical داخل DXF غير صالحة."
        case .unsupportedContainerVersion(let version):
            "إصدار حاوية المشروع داخل DXF (\(version)) غير مدعوم."
        case .damagedPackage:
            "فشل التحقق من سلامة مشروع 3ERoomElectrical المضمن داخل DXF."
        case .packageTooLarge(let bytes):
            "حزمة المشروع كبيرة جدًا لتضمينها داخل DXF (\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))). صدّر ملف .3eroom مستقلًا أو استخدم مشروعًا أخف."
        }
    }
}

enum DXFSmartProjectEmbedder {
    static let formatIdentifier =
        "com.3essam.3eroomelectrical.dxf-package"
    static let packageFormat = "3EROOM_DXF_PACKAGE_V1"
    static let dictionaryKey = "3EROOMELECTRICAL"

    // DXF stores binary XRECORD data as hexadecimal text, so the final
    // document is roughly twice the embedded package size. Keep a guard
    // here to avoid exhausting memory on mobile devices.
    static let maximumEmbeddedPackageBytes = 256_000_000

    private static let rootDictionaryHandle = "F00000"
    private static let smartDictionaryHandle = "F00001"
    private static let packageRecordHandle = "F00002"
    private static let metadataRecordHandle = "F00003"

    static func embed(
        packageData: Data,
        projectID: UUID,
        projectName: String,
        exportedAt: Date,
        in dxf: String
    ) throws -> String {
        guard packageData.count <= maximumEmbeddedPackageBytes else {
            throw SmartProjectEmbeddingError.packageTooLarge(
                packageData.count
            )
        }

        var pairs = try parse(dxf)

        let envelope = SmartEmbeddedProjectEnvelope(
            formatIdentifier: formatIdentifier,
            containerVersion: 1,
            projectID: projectID,
            projectName: projectName,
            exportedAt: exportedAt,
            appVersion: appVersion,
            payloadFileName: "3ERoomElectrical.project.3eroom",
            payloadByteCount: packageData.count,
            payloadSHA256: sha256(packageData),
            compression: "stored-zip"
        )
        let envelopeData = try envelopeEncoder.encode(envelope)
        let envelopeBase64 = envelopeData.base64EncodedString()

        try addObjects(
            envelopeBase64: envelopeBase64,
            packageData: packageData,
            to: &pairs
        )
        try validateSmartDXF(pairs)
        return render(pairs)
    }

    static func extract(
        from dxf: String
    ) throws -> SmartEmbeddedProjectPayload? {
        let pairs = try parse(dxf)
        guard let objects = section(named: "OBJECTS", in: pairs),
              let root = firstObject(
                type: "DICTIONARY",
                in: pairs,
                section: objects
              ),
              let smartDictionaryHandle = dictionaryValueHandle(
                key: dictionaryKey,
                in: pairs,
                range: root.start..<root.end
              ),
              let smartDictionary = object(
                type: "DICTIONARY",
                handle: smartDictionaryHandle,
                in: pairs,
                section: objects
              ),
              let metadataHandle = dictionaryValueHandle(
                key: "PROJECT_METADATA",
                in: pairs,
                range: smartDictionary.start..<smartDictionary.end
              ),
              let packageHandle = dictionaryValueHandle(
                key: "PROJECT_PACKAGE",
                in: pairs,
                range: smartDictionary.start..<smartDictionary.end
              ),
              let metadataRecord = object(
                type: "XRECORD",
                handle: metadataHandle,
                in: pairs,
                section: objects
              ),
              let packageRecord = object(
                type: "XRECORD",
                handle: packageHandle,
                in: pairs,
                section: objects
              ) else {
            return nil
        }

        let metadataBase64 = pairs[
            metadataRecord.start..<metadataRecord.end
        ]
        .filter { $0.code == 1 }
        .map(\.value)
        .joined()
        guard let envelopeData = Data(base64Encoded: metadataBase64),
              let envelope = try? envelopeDecoder.decode(
                SmartEmbeddedProjectEnvelope.self,
                from: envelopeData
              ),
              envelope.formatIdentifier == formatIdentifier else {
            throw SmartProjectEmbeddingError.invalidEnvelope
        }
        guard envelope.containerVersion == 1 else {
            throw SmartProjectEmbeddingError
                .unsupportedContainerVersion(
                    envelope.containerVersion
                )
        }

        let packageRecordPairs = pairs[
            packageRecord.start..<packageRecord.end
        ]
        guard packageRecordPairs.contains(where: {
            $0.code == 300 && $0.value == packageFormat
        }) else {
            throw SmartProjectEmbeddingError.invalidEnvelope
        }
        if let declaredByteCount = packageRecordPairs
            .first(where: { $0.code == 90 })
            .flatMap({ Int($0.value) }),
           declaredByteCount != envelope.payloadByteCount {
            throw SmartProjectEmbeddingError.damagedPackage
        }

        var packageData = Data()
        for pair in packageRecordPairs
        where pair.code == 310 {
            guard let chunk = dataFromHex(pair.value) else {
                throw SmartProjectEmbeddingError.damagedPackage
            }
            packageData.append(chunk)
        }
        guard packageData.count == envelope.payloadByteCount,
              sha256(packageData) == envelope.payloadSHA256 else {
            throw SmartProjectEmbeddingError.damagedPackage
        }
        return SmartEmbeddedProjectPayload(
            envelope: envelope,
            packageData: packageData
        )
    }

    private static func addObjects(
        envelopeBase64: String,
        packageData: Data,
        to pairs: inout [DXFPair]
    ) throws {
        let smartObjects = smartObjectPairs(
            envelopeBase64: envelopeBase64,
            packageData: packageData
        )

        if let objects = section(named: "OBJECTS", in: pairs) {
            guard let root = firstObject(
                type: "DICTIONARY",
                in: pairs,
                section: objects
            ),
            let rootHandle = value(
                code: 5,
                in: pairs,
                range: root.start..<root.end
            ) else {
                throw SmartProjectEmbeddingError.invalidDXF
            }

            let hasSmartEntry = pairs[root.start..<root.end]
                .contains {
                    $0.code == 3 &&
                    $0.value == dictionaryKey
                }
            if !hasSmartEntry {
                pairs.insert(
                    contentsOf: [
                        DXFPair(3, dictionaryKey),
                        DXFPair(350, smartDictionaryHandle)
                    ],
                    at: root.end
                )
            }

            guard let refreshedObjects = section(
                named: "OBJECTS",
                in: pairs
            ) else {
                throw SmartProjectEmbeddingError.invalidDXF
            }
            let ownedObjects = smartObjects.map {
                $0.replacingOwnerPlaceholder(with: rootHandle)
            }
            pairs.insert(
                contentsOf: ownedObjects,
                at: refreshedObjects.end
            )
            return
        }

        guard let eofIndex = pairs.firstIndex(where: {
            $0.code == 0 && $0.value == "EOF"
        }) else {
            throw SmartProjectEmbeddingError.invalidDXF
        }

        var sectionPairs: [DXFPair] = [
            DXFPair(0, "SECTION"),
            DXFPair(2, "OBJECTS"),
            DXFPair(0, "DICTIONARY"),
            DXFPair(5, rootDictionaryHandle),
            DXFPair(330, "0"),
            DXFPair(100, "AcDbDictionary"),
            DXFPair(280, "0"),
            DXFPair(281, "1"),
            DXFPair(3, dictionaryKey),
            DXFPair(350, smartDictionaryHandle)
        ]
        sectionPairs += smartObjects.map {
            $0.replacingOwnerPlaceholder(
                with: rootDictionaryHandle
            )
        }
        sectionPairs.append(DXFPair(0, "ENDSEC"))
        pairs.insert(contentsOf: sectionPairs, at: eofIndex)
    }

    private static func smartObjectPairs(
        envelopeBase64: String,
        packageData: Data
    ) -> [DXFPair] {
        var result: [DXFPair] = [
            DXFPair(0, "DICTIONARY"),
            DXFPair(5, smartDictionaryHandle),
            DXFPair(330, ownerPlaceholder),
            DXFPair(100, "AcDbDictionary"),
            DXFPair(280, "0"),
            DXFPair(281, "1"),
            DXFPair(3, "PROJECT_METADATA"),
            DXFPair(350, metadataRecordHandle),
            DXFPair(3, "PROJECT_PACKAGE"),
            DXFPair(350, packageRecordHandle),

            DXFPair(0, "XRECORD"),
            DXFPair(5, metadataRecordHandle),
            DXFPair(330, smartDictionaryHandle),
            DXFPair(100, "AcDbXrecord"),
            DXFPair(280, "1")
        ]
        result += stringChunks(envelopeBase64, length: 250).map {
            DXFPair(1, $0)
        }

        result += [
            DXFPair(0, "XRECORD"),
            DXFPair(5, packageRecordHandle),
            DXFPair(330, smartDictionaryHandle),
            DXFPair(100, "AcDbXrecord"),
            DXFPair(280, "1"),
            // XRECORD data must use normal DXF group codes below 1000.
            // Do not start an XDATA block (1001+) before binary 310 data.
            DXFPair(300, packageFormat),
            DXFPair(90, String(packageData.count))
        ]
        for chunk in binaryChunks(packageData, length: 127) {
            result.append(DXFPair(310, hex(chunk)))
        }
        return result
    }

    private static func validateSmartDXF(
        _ pairs: [DXFPair]
    ) throws {
        guard let objects = section(named: "OBJECTS", in: pairs),
              let smartDictionary = object(
                type: "DICTIONARY",
                handle: smartDictionaryHandle,
                in: pairs,
                section: objects
              ),
              let packageRecord = object(
                type: "XRECORD",
                handle: packageRecordHandle,
                in: pairs,
                section: objects
              ) else {
            throw SmartProjectEmbeddingError.invalidDXF
        }

        guard value(
            code: 330,
            in: pairs,
            range: smartDictionary.start..<smartDictionary.end
        ) != nil else {
            throw SmartProjectEmbeddingError.invalidDXF
        }

        let recordPairs = pairs[packageRecord.start..<packageRecord.end]
        guard recordPairs.contains(where: {
            $0.code == 300 && $0.value == packageFormat
        }) else {
            throw SmartProjectEmbeddingError.invalidDXF
        }

        // AutoCAD treats 1001 as the beginning of XDATA. Once XDATA
        // begins, normal object data such as group 310 may not follow.
        // Smart project XRECORDs deliberately contain no XDATA.
        guard !recordPairs.contains(where: { $0.code >= 1000 }) else {
            throw SmartProjectEmbeddingError.invalidDXF
        }

        for pair in recordPairs where pair.code == 310 {
            let value = pair.value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !value.isEmpty,
                  value.count <= 254,
                  value.count.isMultiple(of: 2),
                  dataFromHex(value) != nil else {
                throw SmartProjectEmbeddingError.invalidDXF
            }
        }
    }

    private static func parse(_ dxf: String) throws -> [DXFPair] {
        let normalized = dxf
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "\n" }
        ).map(String.init)
        while lines.last == "" {
            lines.removeLast()
        }
        guard lines.count.isMultiple(of: 2) else {
            throw SmartProjectEmbeddingError.invalidDXF
        }

        var result: [DXFPair] = []
        result.reserveCapacity(lines.count / 2)
        var index = 0
        while index < lines.count {
            guard let code = Int(
                lines[index].trimmingCharacters(
                    in: CharacterSet.whitespacesAndNewlines
                )
            ) else {
                throw SmartProjectEmbeddingError.invalidDXF
            }
            result.append(DXFPair(code, lines[index + 1]))
            index += 2
        }
        return result
    }

    private static func render(_ pairs: [DXFPair]) -> String {
        var result = ""
        result.reserveCapacity(pairs.count * 12)
        for pair in pairs {
            result += "\(pair.code)\n\(pair.value)\n"
        }
        return result
    }

    private static func section(
        named name: String,
        in pairs: [DXFPair]
    ) -> DXFRange? {
        var index = 0
        while index + 1 < pairs.count {
            if pairs[index] == DXFPair(0, "SECTION"),
               pairs[index + 1] == DXFPair(2, name) {
                var end = index + 2
                while end < pairs.count {
                    if pairs[end] == DXFPair(0, "ENDSEC") {
                        return DXFRange(start: index, end: end)
                    }
                    end += 1
                }
                return nil
            }
            index += 1
        }
        return nil
    }

    private static func firstObject(
        type: String,
        in pairs: [DXFPair],
        section: DXFRange
    ) -> DXFRange? {
        var index = section.start + 2
        while index < section.end {
            if pairs[index] == DXFPair(0, type) {
                var end = index + 1
                while end < section.end && pairs[end].code != 0 {
                    end += 1
                }
                return DXFRange(start: index, end: end)
            }
            index += 1
        }
        return nil
    }

    private static func value(
        code: Int,
        in pairs: [DXFPair],
        range: Range<Int>
    ) -> String? {
        pairs[range].first(where: { $0.code == code })?.value
    }

    private static func object(
        type: String,
        handle: String,
        in pairs: [DXFPair],
        section: DXFRange
    ) -> DXFRange? {
        var index = section.start + 2
        while index < section.end {
            guard pairs[index].code == 0 else {
                index += 1
                continue
            }
            let objectType = pairs[index].value
            var end = index + 1
            while end < section.end && pairs[end].code != 0 {
                end += 1
            }
            if objectType == type,
               value(
                code: 5,
                in: pairs,
                range: index..<end
               ) == handle {
                return DXFRange(start: index, end: end)
            }
            index = end
        }
        return nil
    }

    private static func dictionaryValueHandle(
        key: String,
        in pairs: [DXFPair],
        range: Range<Int>
    ) -> String? {
        var index = range.lowerBound
        while index < range.upperBound {
            if pairs[index].code == 3,
               pairs[index].value == key {
                var next = index + 1
                while next < range.upperBound &&
                        pairs[next].code != 3 &&
                        pairs[next].code != 0 {
                    if pairs[next].code == 350 ||
                       pairs[next].code == 360 {
                        return pairs[next].value
                    }
                    next += 1
                }
            }
            index += 1
        }
        return nil
    }

    private static func dataFromHex(_ value: String) -> Data? {
        let clean = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard clean.count.isMultiple(of: 2) else { return nil }
        var data = Data()
        data.reserveCapacity(clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let end = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<end], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = end
        }
        return data
    }

    private static func binaryChunks(
        _ data: Data,
        length: Int
    ) -> [Data] {
        guard !data.isEmpty else { return [] }
        var chunks: [Data] = []
        chunks.reserveCapacity((data.count + length - 1) / length)
        var offset = 0
        while offset < data.count {
            let end = min(offset + length, data.count)
            chunks.append(data.subdata(in: offset..<end))
            offset = end
        }
        return chunks
    }

    private static func stringChunks(
        _ string: String,
        length: Int
    ) -> [String] {
        guard !string.isEmpty else { return [] }
        var chunks: [String] = []
        var start = string.startIndex
        while start < string.endIndex {
            let end = string.index(
                start,
                offsetBy: length,
                limitedBy: string.endIndex
            ) ?? string.endIndex
            chunks.append(String(string[start..<end]))
            start = end
        }
        return chunks
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
    }

    private static var envelopeDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var envelopeEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    fileprivate static let ownerPlaceholder = "__ROOT_DICTIONARY__"
}

private struct DXFRange {
    let start: Int
    // Index of ENDSEC / ENDTAB, excluded from inserted content.
    let end: Int
}

private struct DXFPair: Equatable {
    let code: Int
    var value: String

    init(_ code: Int, _ value: String) {
        self.code = code
        self.value = value
    }

    func replacingOwnerPlaceholder(
        with owner: String
    ) -> DXFPair {
        guard value == DXFSmartProjectEmbedder.ownerPlaceholder else {
            return self
        }
        return DXFPair(code, owner)
    }
}
