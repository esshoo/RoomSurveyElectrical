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
    case wallLight
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
        case .wallLight: "إضاءة جدارية"
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
        case .wallLight: "light.beacon.max.fill"
        case .dataOutlet: "network"
        case .televisionOutlet: "tv.fill"
        }
    }

    var usesSwitchRules: Bool {
        switch self {
        case .singleSwitch, .doubleSwitch, .tripleSwitch, .airConditionerSwitch:
            true
        default:
            false
        }
    }

    var usesSocketRules: Bool {
        self == .socket || self == .heaterSocket
    }

    var usesDoorSuggestion: Bool {
        usesSwitchRules || usesSocketRules
    }

    func recommendedHeight(using settings: ElectricalPlacementSettings) -> Float {
        if usesSwitchRules {
            return Float(settings.switchHeightMeters)
        }
        if self == .wallLight {
            return Float(settings.wallLightHeightMeters)
        }
        return Float(settings.socketHeightMeters)
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
    let standardHeightAtCreation: Float?
    let standardDoorOffsetAtCreation: Float?
    let measuredDoorOffset: Float?
    let wasAutomaticallyAdjusted: Bool?

    init(
        id: UUID = UUID(),
        wallID: UUID,
        type: ElectricalDeviceType,
        status: PlacementStatus,
        localX: Float,
        localY: Float,
        wallHeight: Float,
        worldPosition: [Float],
        standardHeightAtCreation: Float? = nil,
        standardDoorOffsetAtCreation: Float? = nil,
        measuredDoorOffset: Float? = nil,
        wasAutomaticallyAdjusted: Bool? = nil,
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
        self.standardHeightAtCreation = standardHeightAtCreation
        self.standardDoorOffsetAtCreation = standardDoorOffsetAtCreation
        self.measuredDoorOffset = measuredDoorOffset
        self.wasAutomaticallyAdjusted = wasAutomaticallyAdjusted
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

    init(
        id: UUID = UUID(),
        kind: Kind,
        width: Float,
        height: Float,
        matrix: simd_float4x4
    ) {
        self.id = id
        self.kind = kind
        self.width = width
        self.height = height
        transform = matrix.columnMajorValues
    }

    var matrix: simd_float4x4 {
        simd_float4x4(columnMajorValues: transform)
    }
}

struct FloorSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    let width: Float
    let depth: Float
    let transform: [Float]

    init(surface: CapturedRoom.Surface) {
        id = surface.identifier
        width = surface.dimensions.x
        depth = surface.dimensions.y
        transform = surface.transform.columnMajorValues
    }

    var matrix: simd_float4x4 {
        simd_float4x4(columnMajorValues: transform)
    }
}

struct RoomObjectSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    let category: String
    let width: Float
    let height: Float
    let depth: Float
    let transform: [Float]

    init(object: CapturedRoom.Object) {
        id = object.identifier
        category = String(describing: object.category)
        width = object.dimensions.x
        height = object.dimensions.y
        depth = object.dimensions.z
        transform = object.transform.columnMajorValues
    }

    var matrix: simd_float4x4 {
        simd_float4x4(columnMajorValues: transform)
    }

    var title: String {
        let normalized = category.lowercased()
        if normalized.contains("bed") { return "سرير" }
        if normalized.contains("bathtub") { return "بانيو" }
        if normalized.contains("chair") { return "كرسي" }
        if normalized.contains("dishwasher") { return "غسالة أطباق" }
        if normalized.contains("fireplace") { return "مدفأة" }
        if normalized.contains("oven") { return "فرن" }
        if normalized.contains("refrigerator") { return "ثلاجة" }
        if normalized.contains("sink") { return "حوض" }
        if normalized.contains("sofa") { return "كنبة" }
        if normalized.contains("stairs") { return "سلم" }
        if normalized.contains("storage") { return "تخزين" }
        if normalized.contains("stove") { return "موقد" }
        if normalized.contains("table") { return "طاولة" }
        if normalized.contains("television") { return "تلفزيون" }
        if normalized.contains("toilet") { return "مرحاض" }
        if normalized.contains("washer") { return "غسالة" }
        return "أثاث"
    }
}

struct RoomProject: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
    let walls: [WallSnapshot]
    var surfaces: [SurfaceSnapshot]
    var floors: [FloorSnapshot]?
    var objects: [RoomObjectSnapshot]?
    var points: [ElectricalPoint]
    let processedJSONFile: String
    let rawJSONFile: String?
    let usdzFile: String
    var electricalSettings: ElectricalPlacementSettings?

    var wallCount: Int { walls.count }
    var doorCount: Int { surfaces.filter { $0.kind == .door }.count }
    var windowCount: Int { surfaces.filter { $0.kind == .window }.count }
    var furnitureCount: Int { objects?.count ?? 0 }

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
