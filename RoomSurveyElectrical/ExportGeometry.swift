import CoreGraphics
import Foundation
import simd

enum ExportGeometry {
    static func center(_ matrix: simd_float4x4) -> SIMD2<Float> {
        SIMD2(matrix.columns.3.x, matrix.columns.3.z)
    }

    static func axis(_ value: SIMD2<Float>) -> SIMD2<Float> {
        let length = simd_length(value)
        return length > 0.0001 ? value / length : SIMD2(1, 0)
    }

    static func lineEndpoints(
        matrix: simd_float4x4,
        width: Float
    ) -> (SIMD2<Float>, SIMD2<Float>) {
        let center = center(matrix)
        let xAxis = axis(
            SIMD2(matrix.columns.0.x, matrix.columns.0.z)
        )
        let half = xAxis * (width / 2)
        return (center - half, center + half)
    }

    static func objectCorners(
        matrix: simd_float4x4,
        width: Float,
        depth: Float
    ) -> [SIMD2<Float>] {
        rectangleCorners(
            matrix: matrix,
            width: width,
            depth: depth,
            depthColumn: matrix.columns.2
        )
    }

    static func floorCorners(
        matrix: simd_float4x4,
        width: Float,
        depth: Float
    ) -> [SIMD2<Float>] {
        rectangleCorners(
            matrix: matrix,
            width: width,
            depth: depth,
            depthColumn: matrix.columns.1
        )
    }

    static func electricalPosition(
        _ point: ElectricalPoint,
        project: RoomProject
    ) -> SIMD2<Float>? {
        if point.worldPosition.count >= 3 {
            return SIMD2(
                point.worldPosition[0],
                point.worldPosition[2]
            )
        }
        guard let wall = project.walls.first(
            where: { $0.id == point.wallID }
        ) else {
            return nil
        }
        let world = simd_mul(
            wall.matrix,
            SIMD4(point.localX, point.localY, 0, 1)
        )
        return SIMD2(world.x, world.z)
    }

    static func allPlanPoints(
        in project: RoomProject
    ) -> [SIMD2<Float>] {
        var points: [SIMD2<Float>] = []
        for wall in project.walls {
            let ends = lineEndpoints(
                matrix: wall.matrix,
                width: wall.width
            )
            points.append(contentsOf: [ends.0, ends.1])
        }
        for surface in project.surfaces {
            let ends = lineEndpoints(
                matrix: surface.matrix,
                width: surface.width
            )
            points.append(contentsOf: [ends.0, ends.1])
        }
        for floor in project.floors ?? [] {
            points.append(
                contentsOf: floorCorners(
                    matrix: floor.matrix,
                    width: floor.width,
                    depth: floor.depth
                )
            )
        }
        for object in project.objects ?? [] {
            points.append(
                contentsOf: objectCorners(
                    matrix: object.matrix,
                    width: object.width,
                    depth: object.depth
                )
            )
        }
        points.append(
            contentsOf: project.points.compactMap {
                electricalPosition($0, project: project)
            }
        )
        points.append(
            contentsOf: (project.ceilingLights ?? []).compactMap {
                guard $0.worldPosition.count >= 3 else { return nil }
                return SIMD2(
                    $0.worldPosition[0],
                    $0.worldPosition[2]
                )
            }
        )
        return points
    }

    static func shortElectricalTitle(
        _ type: ElectricalDeviceType
    ) -> String {
        switch type {
        case .socket: "فيش"
        case .singleSwitch: "مفتاح"
        case .doubleSwitch: "مفتاح ثنائي"
        case .tripleSwitch: "مفتاح ثلاثي"
        case .airConditionerSwitch: "مفتاح تكييف"
        case .heaterSwitch: "مفتاح سخان"
        case .shutterSwitch: "مفتاح شتر"
        case .heaterSocket: "فيش سخان"
        case .wallLight: "إضاءة جدارية"
        case .dataOutlet: "إنترنت"
        case .mountedDataOutlet: "إنترنت علوي"
        case .telephoneOutlet: "تليفون"
        case .mountedTelephoneOutlet: "تليفون علوي"
        case .televisionOutlet: "تلفزيون"
        case .mountedTelevisionOutlet: "تلفزيون علوي"
        case .splitAirConditioner: "مكيف سبليت"
        case .windowAirConditioner: "مكيف شباك"
        }
    }

    static func surfaceTitle(_ kind: SurfaceSnapshot.Kind) -> String {
        switch kind {
        case .door: "باب"
        case .window: "شباك"
        case .opening: "فتحة"
        }
    }

    private static func rectangleCorners(
        matrix: simd_float4x4,
        width: Float,
        depth: Float,
        depthColumn: SIMD4<Float>
    ) -> [SIMD2<Float>] {
        let center = center(matrix)
        let xAxis = axis(
            SIMD2(matrix.columns.0.x, matrix.columns.0.z)
        )
        var depthAxis = axis(
            SIMD2(depthColumn.x, depthColumn.z)
        )
        if abs(simd_dot(xAxis, depthAxis)) > 0.95 {
            depthAxis = SIMD2(-xAxis.y, xAxis.x)
        }
        let x = xAxis * (width / 2)
        let z = depthAxis * (depth / 2)
        return [
            center - x - z,
            center + x - z,
            center + x + z,
            center - x + z
        ]
    }
}

struct ExportPlanProjection {
    let minimumX: Float
    let maximumZ: Float
    let scale: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat

    init?(project: RoomProject, targetRect: CGRect) {
        let points = ExportGeometry.allPlanPoints(in: project)
        guard let first = points.first else { return nil }

        let minimumX = points.reduce(first.x) { min($0, $1.x) }
        let maximumX = points.reduce(first.x) { max($0, $1.x) }
        let minimumZ = points.reduce(first.y) { min($0, $1.y) }
        let maximumZ = points.reduce(first.y) { max($0, $1.y) }
        let width = max(maximumX - minimumX, 0.5)
        let depth = max(maximumZ - minimumZ, 0.5)
        let scale = min(
            targetRect.width / CGFloat(width),
            targetRect.height / CGFloat(depth)
        )
        let drawingWidth = CGFloat(width) * scale
        let drawingHeight = CGFloat(depth) * scale

        self.minimumX = minimumX
        self.maximumZ = maximumZ
        self.scale = scale
        offsetX = targetRect.minX
            + (targetRect.width - drawingWidth) / 2
        offsetY = targetRect.minY
            + (targetRect.height - drawingHeight) / 2
    }

    func map(_ point: SIMD2<Float>) -> CGPoint {
        CGPoint(
            x: offsetX + CGFloat(point.x - minimumX) * scale,
            y: offsetY + CGFloat(maximumZ - point.y) * scale
        )
    }
}
