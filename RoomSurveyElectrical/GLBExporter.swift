import Foundation
import ImageIO
import simd
import UIKit

struct GLBExportOptions: Equatable {
    var includeWallAppearances: Bool
    var includeFurniture: Bool
    var textureMaximumDimension: Int
    var textureJPEGQuality: Double

    init(
        includeWallAppearances: Bool = true,
        includeFurniture: Bool = true,
        textureMaximumDimension: Int = 2048,
        textureJPEGQuality: Double = 0.84
    ) {
        self.includeWallAppearances = includeWallAppearances
        self.includeFurniture = includeFurniture
        self.textureMaximumDimension = min(max(textureMaximumDimension, 512), 4096)
        self.textureJPEGQuality = min(max(textureJPEGQuality, 0.55), 0.95)
    }

    static let standard = GLBExportOptions()
}

extension ProjectExportService {
    static func makeGLB(
        title: String,
        room: ExportRoomRecord,
        metadata: ExportDocumentMetadata,
        options: GLBExportOptions = .standard
    ) throws -> URL {
        let data = try GLBRoomBuilder(
            title: title,
            record: room,
            metadata: metadata,
            options: options
        ).build()
        return try writeTemporaryFile(
            data,
            name: "\(sanitized(title))-model",
            extension: "glb"
        )
    }

    static func makeGLBPackage(
        title: String,
        rooms: [ExportRoomRecord],
        metadata: ExportDocumentMetadata,
        options: GLBExportOptions = .standard
    ) throws -> URL {
        guard !rooms.isEmpty else { throw ProjectExportError.noRooms }
        if rooms.count == 1 {
            return try makeGLB(
                title: title,
                room: rooms[0],
                metadata: metadata,
                options: options
            )
        }

        var archive = StoredZIPArchive()
        for (index, room) in rooms.enumerated() {
            let name = String(
                format: "%02d-%@.glb",
                index + 1,
                sanitized(room.scan.name)
            )
            archive.add(
                name: name,
                data: try GLBRoomBuilder(
                    title: room.scan.name,
                    record: room,
                    metadata: metadata,
                    options: options
                ).build()
            )
        }
        return try writeTemporaryFile(
            archive.data(),
            name: "\(sanitized(title))-GLB",
            extension: "zip"
        )
    }
}

private struct GLBRoomBuilder {
    let title: String
    let record: ExportRoomRecord
    let metadata: ExportDocumentMetadata
    let options: GLBExportOptions

    private enum BaseMaterial: CaseIterable, Hashable {
        case floor
        case wall
        case door
        case window
        case opening
        case furniture
        case electricalExisting
        case electricalProposed
        case ceilingLight
    }

    func build() throws -> Data {
        var resources = GLBResources()
        let cube = resources.appendCubeGeometry()
        let baseMeshes = registerBaseMeshes(
            resources: &resources,
            cube: cube
        )
        var nodes = makeBaseNodes(meshes: baseMeshes)
        var sceneRootNodes = Array(nodes.indices)
        if options.includeWallAppearances {
            let appearanceNodes = makeWallAppearanceNodes(resources: &resources)
            if !appearanceNodes.isEmpty {
                let firstAppearanceIndex = nodes.count
                nodes.append(contentsOf: appearanceNodes)
                let appearanceNodeIndices = Array(
                    firstAppearanceIndex..<nodes.count
                )
                nodes.append([
                    "name": "Wall Photos and Colors",
                    "children": appearanceNodeIndices,
                    "extras": [
                        "layer": "wall-photos"
                    ]
                ])
                sceneRootNodes.append(nodes.count - 1)
            }
        }

        var json: [String: Any] = [
            "asset": [
                "version": "2.0",
                "generator": "3ERoomElectrical",
                "copyright": metadata.brandName
            ],
            "scene": 0,
            "scenes": [
                [
                    "name": title,
                    "nodes": sceneRootNodes
                ]
            ],
            "nodes": nodes,
            "meshes": resources.meshes,
            "materials": resources.materials,
            "buffers": [
                ["byteLength": resources.binary.count]
            ],
            "bufferViews": resources.bufferViews,
            "accessors": resources.accessors,
            "extras": [
                "brand": metadata.brandName,
                "project": metadata.projectName,
                "projectCreatedAt": metadata.projectCreatedISO8601,
                "projectCreatedDisplay": metadata.projectCreatedText,
                "exportedAt": metadata.exportedISO8601,
                "exportedDisplay": metadata.exportedText,
                "drawingTitle": title,
                "location": record.location,
                "source": "RoomPlan + 3ERoomElectrical",
                "wallAppearancesIncluded": options.includeWallAppearances,
                "furnitureIncluded": options.includeFurniture,
                "embeddedWallTextureCount": resources.images.count
            ]
        ]
        if !resources.images.isEmpty {
            json["samplers"] = [[
                "magFilter": 9729,
                "minFilter": 9729,
                "wrapS": 33071,
                "wrapT": 33071
            ]]
            json["images"] = resources.images
            json["textures"] = resources.textures
        }

        guard JSONSerialization.isValidJSONObject(json) else {
            throw ProjectExportError.cannotCreateFile
        }
        var jsonData = try JSONSerialization.data(
            withJSONObject: json,
            options: [.sortedKeys]
        )
        while !jsonData.count.isMultiple(of: 4) {
            jsonData.append(0x20)
        }
        var binaryData = resources.binary
        while !binaryData.count.isMultiple(of: 4) {
            binaryData.append(0)
        }

        let totalLength = 12
            + 8 + jsonData.count
            + 8 + binaryData.count
        var glb = Data()
        glb.appendGLBUInt32(0x46546C67)
        glb.appendGLBUInt32(2)
        glb.appendGLBUInt32(UInt32(totalLength))
        glb.appendGLBUInt32(UInt32(jsonData.count))
        glb.appendGLBUInt32(0x4E4F534A)
        glb.append(jsonData)
        glb.appendGLBUInt32(UInt32(binaryData.count))
        glb.appendGLBUInt32(0x004E4942)
        glb.append(binaryData)
        return glb
    }

    private func registerBaseMeshes(
        resources: inout GLBResources,
        cube: GLBPrimitiveGeometry
    ) -> [BaseMaterial: Int] {
        var result: [BaseMaterial: Int] = [:]
        for material in BaseMaterial.allCases {
            let definition = baseMaterialDefinition(material)
            let materialIndex = resources.appendMaterial(definition)
            result[material] = resources.appendMesh(
                name: definition["name"] as? String ?? "Material",
                geometry: cube,
                materialIndex: materialIndex,
                includesTextureCoordinates: false
            )
        }
        return result
    }

    private func makeBaseNodes(
        meshes: [BaseMaterial: Int]
    ) -> [[String: Any]] {
        var nodes: [[String: Any]] = []

        for (index, floor) in (record.project.floors ?? []).enumerated() {
            guard let mesh = meshes[.floor] else { continue }
            nodes.append(
                node(
                    name: "Floor \(index + 1)",
                    mesh: mesh,
                    matrix: boxMatrix(
                        center: floor.matrix.columns.3,
                        xAxis: SIMD2(
                            floor.matrix.columns.0.x,
                            floor.matrix.columns.0.z
                        ),
                        size: SIMD3(
                            max(floor.width, 0.02),
                            0.035,
                            max(floor.depth, 0.02)
                        )
                    )
                )
            )
        }

        for (index, wall) in record.project.walls.enumerated() {
            guard let mesh = meshes[.wall] else { continue }
            nodes.append(
                node(
                    name: "Wall \(index + 1)",
                    mesh: mesh,
                    matrix: boxMatrix(
                        center: wall.matrix.columns.3,
                        xAxis: SIMD2(
                            wall.matrix.columns.0.x,
                            wall.matrix.columns.0.z
                        ),
                        size: SIMD3(
                            max(wall.width, 0.02),
                            max(wall.height, 0.02),
                            0.06
                        )
                    )
                )
            )
        }

        for (index, surface) in record.project.surfaces.enumerated() {
            let material: BaseMaterial
            switch surface.kind {
            case .door: material = .door
            case .window: material = .window
            case .opening: material = .opening
            }
            guard let mesh = meshes[material] else { continue }
            nodes.append(
                node(
                    name: "\(ExportGeometry.surfaceTitle(surface.kind)) \(index + 1)",
                    mesh: mesh,
                    matrix: boxMatrix(
                        center: surface.matrix.columns.3,
                        xAxis: SIMD2(
                            surface.matrix.columns.0.x,
                            surface.matrix.columns.0.z
                        ),
                        size: SIMD3(
                            max(surface.width, 0.02),
                            max(surface.height, 0.02),
                            0.075
                        )
                    )
                )
            )
        }

        if options.includeFurniture,
           let furnitureMesh = meshes[.furniture] {
            for (index, object) in (record.project.objects ?? []).enumerated() {
                nodes.append(
                    node(
                        name: "\(object.title) \(index + 1)",
                        mesh: furnitureMesh,
                        matrix: boxMatrix(
                            center: object.matrix.columns.3,
                            xAxis: SIMD2(
                                object.matrix.columns.0.x,
                                object.matrix.columns.0.z
                            ),
                            size: SIMD3(
                                max(object.width, 0.02),
                                max(object.height, 0.02),
                                max(object.depth, 0.02)
                            )
                        )
                    )
                )
            }
        }

        for (index, point) in record.project.points.enumerated() {
            guard let center = electricalCenter(
                point,
                project: record.project
            ) else {
                continue
            }
            let size: SIMD3<Float>
            switch point.type {
            case .splitAirConditioner:
                size = SIMD3(0.85, 0.28, 0.16)
            case .windowAirConditioner:
                size = SIMD3(0.60, 0.45, 0.25)
            case .wallLight:
                size = SIMD3(0.16, 0.16, 0.10)
            default:
                size = SIMD3(0.10, 0.10, 0.055)
            }
            let wall = record.project.walls.first {
                $0.id == point.wallID
            }
            let xAxis = wall.map {
                SIMD2(
                    $0.matrix.columns.0.x,
                    $0.matrix.columns.0.z
                )
            } ?? SIMD2(1, 0)
            let material: BaseMaterial = point.status == .existing
                ? .electricalExisting
                : .electricalProposed
            guard let mesh = meshes[material] else { continue }
            nodes.append(
                node(
                    name: "\(ExportGeometry.shortElectricalTitle(point.type)) \(index + 1)",
                    mesh: mesh,
                    matrix: boxMatrix(
                        center: center,
                        xAxis: xAxis,
                        size: size
                    )
                )
            )
        }

        if let lightMesh = meshes[.ceilingLight] {
            for (index, light) in (
                record.project.ceilingLights ?? []
            ).enumerated() {
                guard light.worldPosition.count >= 3 else { continue }
                let diameter = max(light.diameterMeters, 0.02)
                nodes.append(
                    node(
                        name: "Ceiling Light \(index + 1)",
                        mesh: lightMesh,
                        matrix: boxMatrix(
                            center: SIMD4(
                                light.worldPosition[0],
                                light.worldPosition[1],
                                light.worldPosition[2],
                                1
                            ),
                            xAxis: SIMD2(1, 0),
                            size: SIMD3(
                                diameter,
                                0.035,
                                diameter
                            )
                        )
                    )
                )
            }
        }
        return nodes
    }

    private func makeWallAppearanceNodes(
        resources: inout GLBResources
    ) -> [[String: Any]] {
        var nodes: [[String: Any]] = []
        for (wallIndex, wall) in record.project.walls.enumerated() {
            guard let appearance = record.project.wallAppearance(for: wall.id),
                  appearance.visualMode != .defaultMaterial,
                  let geometry = wallOverlayGeometry(
                    for: wall,
                    appearance: appearance
                  ) else {
                continue
            }

            let materialIndex: Int
            switch appearance.visualMode {
            case .solidColor:
                materialIndex = resources.appendMaterial(
                    material(
                        "\(appearance.displayName) Color",
                        wallColor(
                            hex: appearance.solidColorHex,
                            opacity: appearance.opacity
                        )
                    )
                )
            case .capturedPhotos:
                guard let asset = record.project.primaryPhoto(for: wall.id),
                      let jpegData = exportTextureData(asset: asset) else {
                    continue
                }
                let textureIndex = resources.appendJPEGTexture(
                    data: jpegData,
                    name: "\(appearance.displayName) Photo"
                )
                materialIndex = resources.appendMaterial(
                    material(
                        "\(appearance.displayName) Photo",
                        [1, 1, 1, Double(appearance.opacity)],
                        textureIndex: textureIndex
                    )
                )
            case .defaultMaterial:
                continue
            }

            let primitive = resources.appendPrimitiveGeometry(geometry)
            let meshIndex = resources.appendMesh(
                name: "Wall Appearance \(wallIndex + 1)",
                geometry: primitive,
                materialIndex: materialIndex,
                includesTextureCoordinates: true
            )
            nodes.append(
                node(
                    name: "Wall Appearance \(wallIndex + 1) – \(appearance.displayName)",
                    mesh: meshIndex,
                    matrix: matrixArray(wall.matrix)
                )
            )
        }
        return nodes
    }

    private func wallOverlayGeometry(
        for wall: WallSnapshot,
        appearance: WallAppearance
    ) -> GLBRawGeometry? {
        let openings = wallOpeningRectangles(for: wall)
        var xCuts: [Float] = [-wall.width / 2, wall.width / 2]
        var yCuts: [Float] = [-wall.height / 2, wall.height / 2]
        for opening in openings {
            xCuts.append(max(-wall.width / 2, opening.minX))
            xCuts.append(min(wall.width / 2, opening.maxX))
            yCuts.append(max(-wall.height / 2, opening.minY))
            yCuts.append(min(wall.height / 2, opening.maxY))
        }
        xCuts = uniqueSorted(xCuts)
        yCuts = uniqueSorted(yCuts)

        var positions: [Float] = []
        var normals: [Float] = []
        var textureCoordinates: [Float] = []
        var indices: [UInt16] = []
        let depth: Float = 0.031

        guard xCuts.count >= 2, yCuts.count >= 2 else { return nil }
        for xIndex in 0..<(xCuts.count - 1) {
            for yIndex in 0..<(yCuts.count - 1) {
                let minX = xCuts[xIndex]
                let maxX = xCuts[xIndex + 1]
                let minY = yCuts[yIndex]
                let maxY = yCuts[yIndex + 1]
                guard maxX - minX > 0.002,
                      maxY - minY > 0.002 else { continue }
                let center = SIMD2<Float>(
                    (minX + maxX) / 2,
                    (minY + maxY) / 2
                )
                guard !openings.contains(where: { $0.contains(center) }) else {
                    continue
                }
                guard positions.count / 3 <= Int(UInt16.max) - 4 else {
                    return nil
                }
                let base = UInt16(positions.count / 3)
                positions.append(contentsOf: [
                    minX, minY, depth,
                    maxX, minY, depth,
                    maxX, maxY, depth,
                    minX, maxY, depth
                ])
                for _ in 0..<4 {
                    normals.append(contentsOf: [0, 0, 1])
                }
                textureCoordinates.append(
                    contentsOf: [
                        textureU(x: minX, wall: wall, appearance: appearance),
                        textureV(y: minY, wall: wall, appearance: appearance),
                        textureU(x: maxX, wall: wall, appearance: appearance),
                        textureV(y: minY, wall: wall, appearance: appearance),
                        textureU(x: maxX, wall: wall, appearance: appearance),
                        textureV(y: maxY, wall: wall, appearance: appearance),
                        textureU(x: minX, wall: wall, appearance: appearance),
                        textureV(y: maxY, wall: wall, appearance: appearance)
                    ]
                )
                indices.append(contentsOf: [
                    base, base + 1, base + 2,
                    base, base + 2, base + 3
                ])
            }
        }
        guard !indices.isEmpty else { return nil }
        return GLBRawGeometry(
            positions: positions,
            normals: normals,
            textureCoordinates: textureCoordinates,
            indices: indices
        )
    }

    private func wallOpeningRectangles(
        for wall: WallSnapshot
    ) -> [GLBWallLocalRectangle] {
        let inverse = simd_inverse(wall.matrix)
        return record.project.surfaces.compactMap { surface in
            let local = simd_mul(inverse, surface.matrix.columns.3)
            guard abs(local.z) <= 0.30,
                  abs(local.x) <= wall.width / 2 + surface.width / 2 else {
                return nil
            }
            return GLBWallLocalRectangle(
                minX: local.x - surface.width / 2,
                maxX: local.x + surface.width / 2,
                minY: local.y - surface.height / 2,
                maxY: local.y + surface.height / 2
            )
        }
    }

    private func textureU(
        x: Float,
        wall: WallSnapshot,
        appearance: WallAppearance
    ) -> Float {
        let value = min(
            max((x + wall.width / 2) / max(wall.width, 0.001), 0),
            1
        )
        return appearance.flipsPhotoHorizontally ? 1 - value : value
    }

    private func textureV(
        y: Float,
        wall: WallSnapshot,
        appearance: WallAppearance
    ) -> Float {
        let normalized = (y + wall.height / 2) / max(wall.height, 0.001)
        let value = min(max(1 - normalized, 0), 1)
        return appearance.flipsPhotoVertically ? 1 - value : value
    }

    private func uniqueSorted(_ values: [Float]) -> [Float] {
        values.sorted().reduce(into: []) { result, value in
            if let last = result.last, abs(last - value) < 0.0005 {
                return
            }
            result.append(value)
        }
    }

    private func exportTextureData(asset: WallPhotoAsset) -> Data? {
        guard let url = WallPhotoStorage.fileURL(
            projectID: record.project.id,
            asset: asset
        ), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let maximumDimension = options.textureMaximumDimension
        let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let sourceMaximumDimension = max(width, height)
        let targetDimension = sourceMaximumDimension > 0
            ? min(sourceMaximumDimension, maximumDimension)
            : maximumDimension
        let imageOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetDimension,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            imageOptions as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(
            compressionQuality: CGFloat(options.textureJPEGQuality)
        )
    }

    private func electricalCenter(
        _ point: ElectricalPoint,
        project: RoomProject
    ) -> SIMD4<Float>? {
        if point.worldPosition.count >= 3 {
            return SIMD4(
                point.worldPosition[0],
                point.worldPosition[1],
                point.worldPosition[2],
                1
            )
        }
        guard let wall = project.walls.first(
            where: { $0.id == point.wallID }
        ) else {
            return nil
        }
        return simd_mul(
            wall.matrix,
            SIMD4(point.localX, point.localY, 0.04, 1)
        )
    }

    private func node(
        name: String,
        mesh: Int,
        matrix: [Double]
    ) -> [String: Any] {
        [
            "name": name,
            "mesh": mesh,
            "matrix": matrix
        ]
    }

    private func boxMatrix(
        center: SIMD4<Float>,
        xAxis: SIMD2<Float>,
        size: SIMD3<Float>
    ) -> [Double] {
        let axis = ExportGeometry.axis(xAxis)
        let cosine = axis.x
        let sine = axis.y
        return [
            Double(cosine * size.x), 0, Double(sine * size.x), 0,
            0, Double(size.y), 0, 0,
            Double(-sine * size.z), 0, Double(cosine * size.z), 0,
            Double(center.x), Double(center.y), Double(center.z), 1
        ]
    }

    private func matrixArray(_ matrix: simd_float4x4) -> [Double] {
        [
            Double(matrix.columns.0.x),
            Double(matrix.columns.0.y),
            Double(matrix.columns.0.z),
            Double(matrix.columns.0.w),
            Double(matrix.columns.1.x),
            Double(matrix.columns.1.y),
            Double(matrix.columns.1.z),
            Double(matrix.columns.1.w),
            Double(matrix.columns.2.x),
            Double(matrix.columns.2.y),
            Double(matrix.columns.2.z),
            Double(matrix.columns.2.w),
            Double(matrix.columns.3.x),
            Double(matrix.columns.3.y),
            Double(matrix.columns.3.z),
            Double(matrix.columns.3.w)
        ]
    }

    private func baseMaterialDefinition(
        _ materialType: BaseMaterial
    ) -> [String: Any] {
        switch materialType {
        case .floor:
            material("Floor", [0.68, 0.70, 0.73, 1])
        case .wall:
            material("Walls", [0.08, 0.38, 0.64, 1])
        case .door:
            material("Doors", [1.00, 0.48, 0.10, 1])
        case .window:
            material("Windows", [0.20, 0.68, 0.88, 0.72])
        case .opening:
            material("Openings", [0.62, 0.28, 0.78, 0.72])
        case .furniture:
            material("Furniture", [0.50, 0.52, 0.56, 1])
        case .electricalExisting:
            material("Electrical Existing", [0.20, 0.78, 0.35, 1])
        case .electricalProposed:
            material("Electrical Proposed", [1.00, 0.58, 0.10, 1])
        case .ceilingLight:
            material(
                "Ceiling Lighting",
                [1.00, 0.82, 0.10, 1],
                emissive: [0.8, 0.55, 0.05]
            )
        }
    }

    private func wallColor(
        hex: String,
        opacity: Float
    ) -> [Double] {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else {
            return [0.85, 0.85, 0.87, Double(opacity)]
        }
        return [
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255,
            Double(opacity)
        ]
    }

    private func material(
        _ name: String,
        _ color: [Double],
        textureIndex: Int? = nil,
        emissive: [Double]? = nil
    ) -> [String: Any] {
        var pbr: [String: Any] = [
            "baseColorFactor": color,
            "metallicFactor": 0,
            "roughnessFactor": 0.82
        ]
        if let textureIndex {
            pbr["baseColorTexture"] = [
                "index": textureIndex,
                "texCoord": 0
            ]
        }
        var result: [String: Any] = [
            "name": name,
            "doubleSided": true,
            "pbrMetallicRoughness": pbr
        ]
        if color[3] < 1 {
            result["alphaMode"] = "BLEND"
        }
        if let emissive {
            result["emissiveFactor"] = emissive
        }
        return result
    }
}

private struct GLBResources {
    var binary = Data()
    var bufferViews: [[String: Any]] = []
    var accessors: [[String: Any]] = []
    var materials: [[String: Any]] = []
    var meshes: [[String: Any]] = []
    var images: [[String: Any]] = []
    var textures: [[String: Any]] = []

    mutating func appendMaterial(_ definition: [String: Any]) -> Int {
        materials.append(definition)
        return materials.count - 1
    }

    mutating func appendMesh(
        name: String,
        geometry: GLBPrimitiveGeometry,
        materialIndex: Int,
        includesTextureCoordinates: Bool
    ) -> Int {
        var attributes: [String: Any] = [
            "POSITION": geometry.positionAccessor,
            "NORMAL": geometry.normalAccessor
        ]
        if includesTextureCoordinates,
           let textureAccessor = geometry.textureCoordinateAccessor {
            attributes["TEXCOORD_0"] = textureAccessor
        }
        meshes.append([
            "name": name,
            "primitives": [[
                "attributes": attributes,
                "indices": geometry.indexAccessor,
                "material": materialIndex,
                "mode": 4
            ]]
        ])
        return meshes.count - 1
    }

    mutating func appendCubeGeometry() -> GLBPrimitiveGeometry {
        let positions: [Float] = [
            -0.5, -0.5,  0.5,  0.5, -0.5,  0.5,
             0.5,  0.5,  0.5, -0.5,  0.5,  0.5,
             0.5, -0.5, -0.5, -0.5, -0.5, -0.5,
            -0.5,  0.5, -0.5,  0.5,  0.5, -0.5,
            -0.5, -0.5, -0.5, -0.5, -0.5,  0.5,
            -0.5,  0.5,  0.5, -0.5,  0.5, -0.5,
             0.5, -0.5,  0.5,  0.5, -0.5, -0.5,
             0.5,  0.5, -0.5,  0.5,  0.5,  0.5,
            -0.5,  0.5,  0.5,  0.5,  0.5,  0.5,
             0.5,  0.5, -0.5, -0.5,  0.5, -0.5,
            -0.5, -0.5, -0.5,  0.5, -0.5, -0.5,
             0.5, -0.5,  0.5, -0.5, -0.5,  0.5
        ]
        let normals: [Float] = [
             0,  0,  1,  0,  0,  1,  0,  0,  1,  0,  0,  1,
             0,  0, -1,  0,  0, -1,  0,  0, -1,  0,  0, -1,
            -1,  0,  0, -1,  0,  0, -1,  0,  0, -1,  0,  0,
             1,  0,  0,  1,  0,  0,  1,  0,  0,  1,  0,
             0,  1,  0,  0,  1,  0,  0,  1,  0,  0,  1,
             0, -1,  0,  0, -1,  0,  0, -1,  0,  0, -1
        ]
        let indices: [UInt16] = [
             0,  1,  2,  0,  2,  3,
             4,  5,  6,  4,  6,  7,
             8,  9, 10,  8, 10, 11,
            12, 13, 14, 12, 14, 15,
            16, 17, 18, 16, 18, 19,
            20, 21, 22, 20, 22, 23
        ]
        return appendPrimitiveGeometry(
            GLBRawGeometry(
                positions: positions,
                normals: normals,
                textureCoordinates: [],
                indices: indices
            )
        )
    }

    mutating func appendPrimitiveGeometry(
        _ geometry: GLBRawGeometry
    ) -> GLBPrimitiveGeometry {
        let positionView = appendFloatBufferView(
            geometry.positions,
            target: 34962
        )
        let normalView = appendFloatBufferView(
            geometry.normals,
            target: 34962
        )
        let positionAccessor = appendAccessor([
            "bufferView": positionView,
            "byteOffset": 0,
            "componentType": 5126,
            "count": geometry.positions.count / 3,
            "type": "VEC3",
            "min": vectorMinimum(geometry.positions, componentCount: 3),
            "max": vectorMaximum(geometry.positions, componentCount: 3)
        ])
        let normalAccessor = appendAccessor([
            "bufferView": normalView,
            "byteOffset": 0,
            "componentType": 5126,
            "count": geometry.normals.count / 3,
            "type": "VEC3"
        ])

        var textureAccessor: Int?
        if !geometry.textureCoordinates.isEmpty {
            let textureView = appendFloatBufferView(
                geometry.textureCoordinates,
                target: 34962
            )
            textureAccessor = appendAccessor([
                "bufferView": textureView,
                "byteOffset": 0,
                "componentType": 5126,
                "count": geometry.textureCoordinates.count / 2,
                "type": "VEC2",
                "min": vectorMinimum(
                    geometry.textureCoordinates,
                    componentCount: 2
                ),
                "max": vectorMaximum(
                    geometry.textureCoordinates,
                    componentCount: 2
                )
            ])
        }

        let indexView = appendUInt16BufferView(
            geometry.indices,
            target: 34963
        )
        let indexAccessor = appendAccessor([
            "bufferView": indexView,
            "byteOffset": 0,
            "componentType": 5123,
            "count": geometry.indices.count,
            "type": "SCALAR",
            "min": [Int(geometry.indices.min() ?? 0)],
            "max": [Int(geometry.indices.max() ?? 0)]
        ])
        return GLBPrimitiveGeometry(
            positionAccessor: positionAccessor,
            normalAccessor: normalAccessor,
            textureCoordinateAccessor: textureAccessor,
            indexAccessor: indexAccessor
        )
    }

    mutating func appendJPEGTexture(
        data: Data,
        name: String
    ) -> Int {
        alignBinary(to: 4)
        let offset = binary.count
        binary.append(data)
        let bufferViewIndex = bufferViews.count
        bufferViews.append([
            "buffer": 0,
            "byteOffset": offset,
            "byteLength": data.count
        ])
        images.append([
            "name": name,
            "mimeType": "image/jpeg",
            "bufferView": bufferViewIndex
        ])
        textures.append([
            "name": name,
            "sampler": 0,
            "source": images.count - 1
        ])
        return textures.count - 1
    }

    private mutating func appendFloatBufferView(
        _ values: [Float],
        target: Int
    ) -> Int {
        alignBinary(to: 4)
        let offset = binary.count
        for value in values {
            binary.appendGLBFloat(value)
        }
        let index = bufferViews.count
        bufferViews.append([
            "buffer": 0,
            "byteOffset": offset,
            "byteLength": binary.count - offset,
            "target": target
        ])
        return index
    }

    private mutating func appendUInt16BufferView(
        _ values: [UInt16],
        target: Int
    ) -> Int {
        alignBinary(to: 4)
        let offset = binary.count
        for value in values {
            binary.appendGLBUInt16(value)
        }
        let index = bufferViews.count
        bufferViews.append([
            "buffer": 0,
            "byteOffset": offset,
            "byteLength": binary.count - offset,
            "target": target
        ])
        return index
    }

    private mutating func appendAccessor(
        _ definition: [String: Any]
    ) -> Int {
        accessors.append(definition)
        return accessors.count - 1
    }

    private mutating func alignBinary(to alignment: Int) {
        while !binary.count.isMultiple(of: alignment) {
            binary.append(0)
        }
    }

    private func vectorMinimum(
        _ values: [Float],
        componentCount: Int
    ) -> [Double] {
        guard !values.isEmpty else {
            return Array(repeating: 0, count: componentCount)
        }
        var result = Array(
            repeating: Float.greatestFiniteMagnitude,
            count: componentCount
        )
        for index in stride(from: 0, to: values.count, by: componentCount) {
            for component in 0..<componentCount {
                result[component] = min(
                    result[component],
                    values[index + component]
                )
            }
        }
        return result.map(Double.init)
    }

    private func vectorMaximum(
        _ values: [Float],
        componentCount: Int
    ) -> [Double] {
        guard !values.isEmpty else {
            return Array(repeating: 0, count: componentCount)
        }
        var result = Array(
            repeating: -Float.greatestFiniteMagnitude,
            count: componentCount
        )
        for index in stride(from: 0, to: values.count, by: componentCount) {
            for component in 0..<componentCount {
                result[component] = max(
                    result[component],
                    values[index + component]
                )
            }
        }
        return result.map(Double.init)
    }
}

private struct GLBPrimitiveGeometry {
    let positionAccessor: Int
    let normalAccessor: Int
    let textureCoordinateAccessor: Int?
    let indexAccessor: Int
}

private struct GLBRawGeometry {
    let positions: [Float]
    let normals: [Float]
    let textureCoordinates: [Float]
    let indices: [UInt16]
}

private struct GLBWallLocalRectangle {
    let minX: Float
    let maxX: Float
    let minY: Float
    let maxY: Float

    func contains(_ point: SIMD2<Float>) -> Bool {
        point.x > minX && point.x < maxX
            && point.y > minY && point.y < maxY
    }
}

private extension Data {
    mutating func appendGLBUInt16(_ value: UInt16) {
        append(UInt8(value & 0x00FF))
        append(UInt8((value >> 8) & 0x00FF))
    }

    mutating func appendGLBUInt32(_ value: UInt32) {
        append(UInt8(value & 0x000000FF))
        append(UInt8((value >> 8) & 0x000000FF))
        append(UInt8((value >> 16) & 0x000000FF))
        append(UInt8((value >> 24) & 0x000000FF))
    }

    mutating func appendGLBFloat(_ value: Float) {
        appendGLBUInt32(value.bitPattern)
    }
}
