import Foundation
import RoomPlan
import simd

enum ElementColorOption: String, Codable, CaseIterable, Identifiable {
    case automatic
    case orange
    case cyan
    case green
    case red
    case blue
    case yellow
    case white
    case black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "تلقائي"
        case .orange: "برتقالي"
        case .cyan: "سماوي"
        case .green: "أخضر"
        case .red: "أحمر"
        case .blue: "أزرق"
        case .yellow: "أصفر"
        case .white: "أبيض"
        case .black: "أسود"
        }
    }

    var hexValue: String? {
        switch self {
        case .automatic: nil
        case .orange: "#FF9500"
        case .cyan: "#32ADE6"
        case .green: "#34C759"
        case .red: "#FF3B30"
        case .blue: "#007AFF"
        case .yellow: "#FFCC00"
        case .white: "#FFFFFF"
        case .black: "#111111"
        }
    }

    init(hexValue: String?) {
        self = Self.allCases.first { $0.hexValue == hexValue } ?? .automatic
    }
}

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
    var wallID: UUID
    var type: ElectricalDeviceType
    var status: PlacementStatus
    var localX: Float
    var localY: Float
    var heightFromFloor: Float
    var worldPosition: [Float]
    let createdAt: Date
    var standardHeightAtCreation: Float?
    var standardDoorOffsetAtCreation: Float?
    var measuredDoorOffset: Float?
    var wasAutomaticallyAdjusted: Bool?
    var colorHex: String?
    var groupID: UUID?

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
        colorHex: String? = nil,
        groupID: UUID? = nil,
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
        self.colorHex = colorHex
        self.groupID = groupID
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
    var kind: Kind
    var width: Float
    var height: Float
    var transform: [Float]
    var colorHex: String?
    var isManuallyAdded: Bool?

    init(surface: CapturedRoom.Surface, kind: Kind) {
        id = surface.identifier
        self.kind = kind
        width = surface.dimensions.x
        height = surface.dimensions.y
        transform = surface.transform.columnMajorValues
        colorHex = nil
        isManuallyAdded = false
    }

    init(
        id: UUID = UUID(),
        kind: Kind,
        width: Float,
        height: Float,
        matrix: simd_float4x4,
        colorHex: String? = nil,
        isManuallyAdded: Bool? = true
    ) {
        self.id = id
        self.kind = kind
        self.width = width
        self.height = height
        transform = matrix.columnMajorValues
        self.colorHex = colorHex
        self.isManuallyAdded = isManuallyAdded
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

extension RoomProject {
    @discardableResult
    mutating func appendElectricalPointMergingNearby(
        _ point: ElectricalPoint,
        mergeDistance: Float
    ) -> Bool {
        guard mergeDistance > 0,
              let wall = walls.first(where: { $0.id == point.wallID }),
              let candidateIndex = points.indices
                .filter({
                    points[$0].wallID == point.wallID
                        && points[$0].status == point.status
                        && electricalTypesCanMerge(points[$0].type, point.type)
                        && abs(points[$0].localX - point.localX) <= mergeDistance
                })
                .min(by: {
                    abs(points[$0].localX - point.localX)
                        < abs(points[$1].localX - point.localX)
                }) else {
            points.append(point)
            return false
        }

        var mergedPoint = point
        let groupID = points[candidateIndex].groupID ?? UUID()
        let groupedIndices = points.indices.filter {
            $0 == candidateIndex || points[$0].groupID == groupID
        }

        if point.status == .existing {
            for index in groupedIndices {
                points[index].groupID = groupID
            }
            mergedPoint.groupID = groupID
            points.append(mergedPoint)
            return true
        }

        let totalX = groupedIndices.reduce(point.localX) { result, index in
            result + points[index].localX
        }
        let centerX = totalX / Float(groupedIndices.count + 1)

        for index in groupedIndices {
            points[index].localX = centerX
            points[index].groupID = groupID
            let world = simd_mul(
                wall.matrix,
                SIMD4(centerX, points[index].localY, 0.035, 1)
            )
            points[index].worldPosition = [world.x, world.y, world.z]
            if points[index].type.usesSwitchRules {
                points[index].measuredDoorOffset = distanceToNearestDoorEdge(
                    localX: centerX,
                    wall: wall
                )
            }
        }

        mergedPoint.localX = centerX
        mergedPoint.groupID = groupID
        let mergedWorld = simd_mul(
            wall.matrix,
            SIMD4(centerX, mergedPoint.localY, 0.035, 1)
        )
        mergedPoint.worldPosition = [mergedWorld.x, mergedWorld.y, mergedWorld.z]
        if mergedPoint.type.usesSwitchRules {
            mergedPoint.measuredDoorOffset = distanceToNearestDoorEdge(
                localX: centerX,
                wall: wall
            )
        }
        points.append(mergedPoint)
        return true
    }

    mutating func normalizeElectricalGroups() {
        let counts = Dictionary(
            grouping: points.compactMap(\.groupID),
            by: { $0 }
        )
        for index in points.indices {
            if let groupID = points[index].groupID,
               (counts[groupID]?.count ?? 0) < 2 {
                points[index].groupID = nil
            }
        }
    }

    private func electricalTypesCanMerge(
        _ first: ElectricalDeviceType,
        _ second: ElectricalDeviceType
    ) -> Bool {
        (first.usesSwitchRules && second.usesSwitchRules)
            || (first.usesSocketRules && second.usesSocketRules)
    }

    private func distanceToNearestDoorEdge(
        localX: Float,
        wall: WallSnapshot
    ) -> Float? {
        let inverseWall = simd_inverse(wall.matrix)
        return surfaces
            .filter { $0.kind == .door }
            .compactMap { surface -> Float? in
                let localCenter = simd_mul(inverseWall, surface.matrix.columns.3)
                guard abs(localCenter.z) <= 0.30 else { return nil }
                let leftEdge = localCenter.x - surface.width / 2
                let rightEdge = localCenter.x + surface.width / 2
                return min(abs(localX - leftEdge), abs(localX - rightEdge))
            }
            .min()
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
