import Foundation
import simd

extension ProjectExportService {
    static func makeGLB(
        title: String,
        room: ExportRoomRecord,
        metadata: ExportDocumentMetadata
    ) throws -> URL {
        let data = try GLBRoomBuilder(
            title: title,
            record: room,
            metadata: metadata
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
        metadata: ExportDocumentMetadata
    ) throws -> URL {
        guard !rooms.isEmpty else { throw ProjectExportError.noRooms }
        if rooms.count == 1 {
            return try makeGLB(
                title: title,
                room: rooms[0],
                metadata: metadata
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
                    metadata: metadata
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

    private enum Material: Int {
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
        let geometry = cubeGeometry()
        let nodes = makeNodes()
        let materials = materialDefinitions()
        let meshes = materials.indices.map { index in
            [
                "name": materials[index]["name"] ?? "Material",
                "primitives": [
                    [
                        "attributes": [
                            "POSITION": 0,
                            "NORMAL": 1
                        ],
                        "indices": 2,
                        "material": index,
                        "mode": 4
                    ] as [String: Any]
                ]
            ] as [String: Any]
        }

        let json: [String: Any] = [
            "asset": [
                "version": "2.0",
                "generator": "3ERoomElectrical",
                "copyright": metadata.brandName
            ],
            "scene": 0,
            "scenes": [
                [
                    "name": title,
                    "nodes": Array(nodes.indices)
                ]
            ],
            "nodes": nodes,
            "meshes": meshes,
            "materials": materials,
            "buffers": [
                ["byteLength": geometry.data.count]
            ],
            "bufferViews": [
                [
                    "buffer": 0,
                    "byteOffset": geometry.positionOffset,
                    "byteLength": geometry.positionLength,
                    "target": 34962
                ],
                [
                    "buffer": 0,
                    "byteOffset": geometry.normalOffset,
                    "byteLength": geometry.normalLength,
                    "target": 34962
                ],
                [
                    "buffer": 0,
                    "byteOffset": geometry.indexOffset,
                    "byteLength": geometry.indexLength,
                    "target": 34963
                ]
            ],
            "accessors": [
                [
                    "bufferView": 0,
                    "byteOffset": 0,
                    "componentType": 5126,
                    "count": 24,
                    "type": "VEC3",
                    "min": [-0.5, -0.5, -0.5],
                    "max": [0.5, 0.5, 0.5]
                ],
                [
                    "bufferView": 1,
                    "byteOffset": 0,
                    "componentType": 5126,
                    "count": 24,
                    "type": "VEC3"
                ],
                [
                    "bufferView": 2,
                    "byteOffset": 0,
                    "componentType": 5123,
                    "count": 36,
                    "type": "SCALAR",
                    "min": [0],
                    "max": [23]
                ]
            ],
            "extras": [
                "brand": metadata.brandName,
                "project": metadata.projectName,
                "projectCreatedAt": metadata.projectCreatedISO8601,
                "projectCreatedDisplay": metadata.projectCreatedText,
                "exportedAt": metadata.exportedISO8601,
                "exportedDisplay": metadata.exportedText,
                "drawingTitle": title,
                "location": record.location,
                "source": "RoomPlan + 3ERoomElectrical"
            ]
        ]

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
        var binaryData = geometry.data
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

    private func makeNodes() -> [[String: Any]] {
        var nodes: [[String: Any]] = []

        for (index, floor) in (record.project.floors ?? []).enumerated() {
            nodes.append(
                node(
                    name: "Floor \(index + 1)",
                    material: .floor,
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
            nodes.append(
                node(
                    name: "Wall \(index + 1)",
                    material: .wall,
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
            let material: Material
            switch surface.kind {
            case .door: material = .door
            case .window: material = .window
            case .opening: material = .opening
            }
            nodes.append(
                node(
                    name: "\(ExportGeometry.surfaceTitle(surface.kind)) \(index + 1)",
                    material: material,
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

        for (index, object) in (record.project.objects ?? []).enumerated() {
            nodes.append(
                node(
                    name: "\(object.title) \(index + 1)",
                    material: .furniture,
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
            nodes.append(
                node(
                    name: "\(ExportGeometry.shortElectricalTitle(point.type)) \(index + 1)",
                    material: point.status == .existing
                        ? .electricalExisting
                        : .electricalProposed,
                    matrix: boxMatrix(
                        center: center,
                        xAxis: xAxis,
                        size: size
                    )
                )
            )
        }

        for (index, light) in (
            record.project.ceilingLights ?? []
        ).enumerated() {
            guard light.worldPosition.count >= 3 else { continue }
            let diameter = max(light.diameterMeters, 0.02)
            nodes.append(
                node(
                    name: "Ceiling Light \(index + 1)",
                    material: .ceilingLight,
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
        return nodes
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
        material: Material,
        matrix: [Double]
    ) -> [String: Any] {
        [
            "name": name,
            "mesh": material.rawValue,
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

    private func materialDefinitions() -> [[String: Any]] {
        [
            material("Floor", [0.68, 0.70, 0.73, 1]),
            material("Walls", [0.08, 0.38, 0.64, 1]),
            material("Doors", [1.00, 0.48, 0.10, 1]),
            material("Windows", [0.20, 0.68, 0.88, 0.72]),
            material("Openings", [0.62, 0.28, 0.78, 0.72]),
            material("Furniture", [0.50, 0.52, 0.56, 1]),
            material("Electrical Existing", [0.20, 0.78, 0.35, 1]),
            material("Electrical Proposed", [1.00, 0.58, 0.10, 1]),
            material(
                "Ceiling Lighting",
                [1.00, 0.82, 0.10, 1],
                emissive: [0.8, 0.55, 0.05]
            )
        ]
    }

    private func material(
        _ name: String,
        _ color: [Double],
        emissive: [Double]? = nil
    ) -> [String: Any] {
        var result: [String: Any] = [
            "name": name,
            "doubleSided": true,
            "pbrMetallicRoughness": [
                "baseColorFactor": color,
                "metallicFactor": 0,
                "roughnessFactor": 0.82
            ]
        ]
        if color[3] < 1 {
            result["alphaMode"] = "BLEND"
        }
        if let emissive {
            result["emissiveFactor"] = emissive
        }
        return result
    }

    private func cubeGeometry() -> GLBGeometry {
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
             1,  0,  0,  1,  0,  0,  1,  0,  0,  1,  0,  0,
             0,  1,  0,  0,  1,  0,  0,  1,  0,  0,  1,  0,
             0, -1,  0,  0, -1,  0,  0, -1,  0,  0, -1,  0
        ]
        let indices: [UInt16] = [
             0,  1,  2,  0,  2,  3,
             4,  5,  6,  4,  6,  7,
             8,  9, 10,  8, 10, 11,
            12, 13, 14, 12, 14, 15,
            16, 17, 18, 16, 18, 19,
            20, 21, 22, 20, 22, 23
        ]

        var data = Data()
        let positionOffset = data.count
        for value in positions {
            data.appendGLBFloat(value)
        }
        let positionLength = data.count - positionOffset
        let normalOffset = data.count
        for value in normals {
            data.appendGLBFloat(value)
        }
        let normalLength = data.count - normalOffset
        let indexOffset = data.count
        for value in indices {
            data.appendGLBUInt16(value)
        }
        let indexLength = data.count - indexOffset

        return GLBGeometry(
            data: data,
            positionOffset: positionOffset,
            positionLength: positionLength,
            normalOffset: normalOffset,
            normalLength: normalLength,
            indexOffset: indexOffset,
            indexLength: indexLength
        )
    }
}

private struct GLBGeometry {
    let data: Data
    let positionOffset: Int
    let positionLength: Int
    let normalOffset: Int
    let normalLength: Int
    let indexOffset: Int
    let indexLength: Int
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
