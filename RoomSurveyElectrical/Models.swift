import Foundation
import RoomPlan
import simd

enum ElectricalDeviceType: String, Codable, CaseIterable, Hashable, Identifiable {
    case socket
    case singleSwitch
    case doubleSwitch
    case tripleSwitch
    case airConditionerSwitch
    case heaterSocket
    case dataOutlet
    case televisionOutlet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .socket: "فيش كهرباء"
        case .singleSwitch: "مفتاح مفرد"
        case .doubleSwitch: "مفتاح ثنائي"
        case .tripleSwitch: "مفتاح ثلاثي"
        case .airConditionerSwitch: "مفتاح تكييف"
        case .heaterSocket: "فيش سخان"
        case .dataOutlet: "نقطة بيانات"
        case .televisionOutlet: "نقطة تلفزيون"
        }
    }

    var systemImage: String {
        switch self {
        case .socket: "powerplug.fill"
        case .singleSwitch: "lightswitch.on.fill"
        case .doubleSwitch: "switch.2"
        case .tripleSwitch: "slider.horizontal.3"
        case .airConditionerSwitch: "snowflake"
        case .heaterSocket: "flame.fill"
        case .dataOutlet: "network"
        case .televisionOutlet: "tv.fill"
        }
    }
}

enum PlacementStatus: String, Codable, CaseIterable, Hashable, Identifiable {
    case existing
    case proposed

    var id: String { rawValue }
    var title: String { self == .existing ? "موجود" : "مقترح" }
}

struct ElectricalPoint: Codable, Identifiable, Equatable {
    let id: UUID
    let wallID: UUID
    let type: ElectricalDeviceType
    let status: PlacementStatus
    let localX: Float
    let localY: Float
    let heightFromFloor: Float
    let worldPosition: [Float]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        wallID: UUID,
        type: ElectricalDeviceType,
        status: PlacementStatus,
        localX: Float,
        localY: Float,
        wallHeight: Float,
        worldPosition: [Float],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.wallID = wallID
        self.type = type
        self.status = status
        self.localX = localX
        self.localY = localY
        self.heightFromFloor = max(0, localY + wallHeight / 2)
        self.worldPosition = worldPosition
        self.createdAt = createdAt
    }
}

struct WallSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    let width: Float
    let height: Float
    let transform: [Float]

    init(surface: CapturedRoom.Surface) {
        id = surface.identifier
        width = surface.dimensions.x
        height = surface.dimensions.y
        transform = surface.transform.columnMajorValues
    }

    var matrix: simd_float4x4 {
        simd_float4x4(columnMajorValues: transform)
    }
}

struct SurfaceSnapshot: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case door
        case window
        case opening
    }

    let id: UUID
    let kind: Kind
    let width: Float
    let height: Float
    let transform: [Float]

    init(surface: CapturedRoom.Surface, kind: Kind) {
        id = surface.identifier
        self.kind = kind
        width = surface.dimensions.x
        height = surface.dimensions.y
        transform = surface.transform.columnMajorValues
    }
}

struct RoomProject: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
    let walls: [WallSnapshot]
    let surfaces: [SurfaceSnapshot]
    var points: [ElectricalPoint]
    let processedJSONFile: String
    let rawJSONFile: String?
    let usdzFile: String

    var wallCount: Int { walls.count }
    var doorCount: Int { surfaces.filter { $0.kind == .door }.count }
    var windowCount: Int { surfaces.filter { $0.kind == .window }.count }

    var boq: [BOQLine] {
        ElectricalDeviceType.allCases.flatMap { type in
            PlacementStatus.allCases.compactMap { status in
                let count = points.filter { $0.type == type && $0.status == status }.count
                return count == 0 ? nil : BOQLine(type: type, status: status, count: count)
            }
        }
    }
}

struct BOQLine: Identifiable {
    let type: ElectricalDeviceType
    let status: PlacementStatus
    let count: Int
    var id: String { "\(type.rawValue)-\(status.rawValue)" }
}

struct WallTap: Identifiable {
    let id = UUID()
    let wallID: UUID
    let localX: Float
    let localY: Float
    let worldPosition: [Float]
}

extension simd_float4x4 {
    var columnMajorValues: [Float] {
        [
            columns.0.x, columns.0.y, columns.0.z, columns.0.w,
            columns.1.x, columns.1.y, columns.1.z, columns.1.w,
            columns.2.x, columns.2.y, columns.2.z, columns.2.w,
            columns.3.x, columns.3.y, columns.3.z, columns.3.w
        ]
    }

    init(columnMajorValues values: [Float]) {
        guard values.count == 16 else {
            self = matrix_identity_float4x4
            return
        }

        self.init(columns: (
            SIMD4(values[0], values[1], values[2], values[3]),
            SIMD4(values[4], values[5], values[6], values[7]),
            SIMD4(values[8], values[9], values[10], values[11]),
            SIMD4(values[12], values[13], values[14], values[15])
        ))
    }
}
