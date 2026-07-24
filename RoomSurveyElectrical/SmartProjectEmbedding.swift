import CryptoKit
import Foundation

struct SmartProjectEmbeddedPackage {
    let packageFileName: String
    let packageData: Data
    let manifestData: Data
    let manifest: SmartProjectEmbeddingManifest

    var packageBase64: String {
        packageData.base64EncodedString()
    }

    var manifestBase64: String {
        manifestData.base64EncodedString()
    }
}

struct SmartProjectEmbeddingManifest: Codable {
    let formatIdentifier: String
    let formatVersion: Int
    let marker: String
    let application: String
    let readableBy: String
    let packageFileName: String
    let packageByteCount: Int
    let packageSHA256: String
    let packageEncoding: String
    let projectID: UUID
    let projectName: String
    let projectCreatedAt: Date
    let exportedAt: Date
}

enum SmartProjectEmbedding {
    static let applicationID = "3EROOMELECTRICAL"
    static let marker = "3EROOM_PROJECT_PACKAGE_V1"
    static let packageFileName = "3ERoomElectrical.project.3eroom"
    static let dxfDictionaryEntry = "3EROOMELECTRICAL_PACKAGE"
    static let dxfXRecordHandle = "E3E001"

    static func makePackage(
        metadata: ExportDocumentMetadata
    ) -> SmartProjectEmbeddedPackage? {
        guard let projectID = metadata.projectID else {
            return nil
        }
        guard let package = try? ProjectPackageService.makePackageData(
            projectID: projectID
        ) else {
            return nil
        }
        let manifest = SmartProjectEmbeddingManifest(
            formatIdentifier:
                "com.3essam.3eroomelectrical.embedded-project",
            formatVersion: 1,
            marker: marker,
            application: "3E Room Electrical",
            readableBy:
                "Read manifest, verify packageSHA256, then import the embedded .3eroom package.",
            packageFileName: packageFileName,
            packageByteCount: package.data.count,
            packageSHA256: sha256(package.data),
            packageEncoding: "raw-in-pdf-base64-in-dxf",
            projectID: projectID,
            projectName: metadata.projectName,
            projectCreatedAt: metadata.projectCreatedAt,
            exportedAt: metadata.exportedAt
        )
        guard let manifestData = try? encoder.encode(manifest) else {
            return nil
        }
        return SmartProjectEmbeddedPackage(
            packageFileName: packageFileName,
            packageData: package.data,
            manifestData: manifestData,
            manifest: manifest
        )
    }

    static func chunks(
        _ value: String,
        size: Int = 900
    ) -> [String] {
        guard size > 0, !value.isEmpty else { return [] }
        var result: [String] = []
        var start = value.startIndex
        while start < value.endIndex {
            let end = value.index(
                start,
                offsetBy: size,
                limitedBy: value.endIndex
            ) ?? value.endIndex
            result.append(String(value[start..<end]))
            start = end
        }
        return result
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
