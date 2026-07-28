import Foundation
import simd

/// The spatial model is independent from the app's Arabic/RTL user interface.
/// ARKit, RoomPlan, SceneKit and the persisted project all use one right-handed,
/// Y-up coordinate contract. UI layout direction must never alter these matrices.
enum SpatialCoordinateContract {
    struct Validation: Equatable {
        let isFinite: Bool
        let determinant: Float
        let upAlignment: Float
        let hasRigidScale: Bool

        var isSafeRigidTransform: Bool {
            isFinite
                && determinant > 0.85
                && determinant < 1.15
                && upAlignment > 0.96
                && hasRigidScale
        }
    }

    static func validateProjectMapping(_ matrix: simd_float4x4) -> Validation {
        let finite = matrix.columnMajorValues.allSatisfy { $0.isFinite }
        let x = SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)
        let y = SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)
        let z = SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        let determinant = simd_dot(x, simd_cross(y, z))
        let up = normalized(y)
        let scaleSafe = abs(simd_length(x) - 1) < 0.08
            && abs(simd_length(y) - 1) < 0.08
            && abs(simd_length(z) - 1) < 0.08
            && abs(simd_dot(normalized(x), normalized(y))) < 0.08
            && abs(simd_dot(normalized(x), normalized(z))) < 0.08
            && abs(simd_dot(normalized(y), normalized(z))) < 0.08
        return Validation(
            isFinite: finite,
            determinant: determinant,
            upAlignment: simd_dot(up, SIMD3<Float>(0, 1, 0)),
            hasRigidScale: scaleSafe
        )
    }

    /// Builds a gravity-aligned mapping from a fresh AR session into the saved
    /// project. Only yaw and translation are allowed. Pitch/roll differences
    /// between the saved screenshot and the current phone pose must not tilt or
    /// mirror the room geometry.
    static func gravityAlignedMapping(
        savedCamera: simd_float4x4,
        currentCamera: simd_float4x4,
        previousWorldToProject: simd_float4x4
    ) -> simd_float4x4? {
        guard savedCamera.columnMajorValues.allSatisfy { $0.isFinite },
              currentCamera.columnMajorValues.allSatisfy { $0.isFinite },
              validateProjectMapping(previousWorldToProject).isSafeRigidTransform else {
            return nil
        }

        let savedForward = horizontalCameraForward(savedCamera)
        let currentForward = horizontalCameraForward(currentCamera)
        guard simd_length(savedForward) > 0.9,
              simd_length(currentForward) > 0.9 else {
            return nil
        }

        let savedHeading = atan2(savedForward.x, savedForward.z)
        let currentHeading = atan2(currentForward.x, currentForward.z)
        let yaw = normalizedAngle(savedHeading - currentHeading)
        let rotation = yawRotation(yaw)

        let savedPosition = translation(savedCamera)
        let currentPosition = translation(currentCamera)
        let rotatedCurrent = transformPoint(currentPosition, by: rotation)
        var sessionToSavedWorld = rotation
        sessionToSavedWorld.columns.3 = SIMD4(
            savedPosition.x - rotatedCurrent.x,
            savedPosition.y - rotatedCurrent.y,
            savedPosition.z - rotatedCurrent.z,
            1
        )

        let resolved = previousWorldToProject * sessionToSavedWorld
        guard validateProjectMapping(resolved).isSafeRigidTransform else {
            return nil
        }
        return resolved
    }

    /// Computes a planar correction that maps one gravity-aligned wall pose to
    /// another. It cannot introduce reflection, scale, pitch or roll.
    static func planarWallCorrection(
        from sourceWall: simd_float4x4,
        to targetWall: simd_float4x4,
        allowHalfTurn: Bool
    ) -> [simd_float4x4] {
        let sourceXAxis = normalizedHorizontalAxis(sourceWall.columns.0)
        let targetXAxis = normalizedHorizontalAxis(targetWall.columns.0)
        guard simd_length(sourceXAxis) > 0.9,
              simd_length(targetXAxis) > 0.9 else { return [] }

        let sourceHeading = atan2(sourceXAxis.x, sourceXAxis.z)
        let targetHeading = atan2(targetXAxis.x, targetXAxis.z)
        var yawCandidates = [normalizedAngle(targetHeading - sourceHeading)]
        if allowHalfTurn {
            yawCandidates.append(normalizedAngle(targetHeading + .pi - sourceHeading))
        }

        let sourceCenter = translation(sourceWall)
        let targetCenter = translation(targetWall)
        return yawCandidates.compactMap { yaw in
            let rotation = yawRotation(yaw)
            let rotatedSource = transformPoint(sourceCenter, by: rotation)
            var correction = rotation
            correction.columns.3 = SIMD4(
                targetCenter.x - rotatedSource.x,
                targetCenter.y - rotatedSource.y,
                targetCenter.z - rotatedSource.z,
                1
            )
            return validateProjectMapping(correction).isSafeRigidTransform
                ? correction
                : nil
        }
    }

    static func wallIsVertical(_ matrix: simd_float4x4) -> Bool {
        let up = normalized(SIMD3(
            matrix.columns.1.x,
            matrix.columns.1.y,
            matrix.columns.1.z
        ))
        return simd_dot(up, SIMD3<Float>(0, 1, 0)) > 0.94
    }

    static func translation(_ matrix: simd_float4x4) -> SIMD3<Float> {
        SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }

    static func horizontalCameraForward(_ matrix: simd_float4x4) -> SIMD3<Float> {
        normalized(SIMD3(-matrix.columns.2.x, 0, -matrix.columns.2.z))
    }

    static func normalizedHorizontalAxis(_ column: SIMD4<Float>) -> SIMD3<Float> {
        normalized(SIMD3(column.x, 0, column.z))
    }

    static func yawRotation(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return simd_float4x4(columns: (
            SIMD4(c, 0, -s, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(s, 0, c, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }

    static func transformPoint(
        _ point: SIMD3<Float>,
        by matrix: simd_float4x4
    ) -> SIMD3<Float> {
        let value = matrix * SIMD4(point.x, point.y, point.z, 1)
        return SIMD3(value.x, value.y, value.z)
    }

    static func normalizedAngle(_ angle: Float) -> Float {
        var value = angle
        while value > .pi { value -= 2 * .pi }
        while value < -.pi { value += 2 * .pi }
        return value
    }

    private static func normalized(_ value: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(value)
        return length > 0.000_1 ? value / length : .zero
    }
}
