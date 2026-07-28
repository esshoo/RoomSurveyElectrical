import Foundation
import RoomPlan
import simd

enum RoomProjectGeometryMerger {
    static func merge(
        capturedRoom: CapturedRoom,
        into source: RoomProject,
        includeFurniture: Bool,
        incomingWorldTransform: simd_float4x4? = nil
    ) -> RoomProject {
        var result = source
        let transform = incomingWorldTransform ?? matrix_identity_float4x4
        result.walls = mergeWalls(
            existing: source.walls,
            incoming: capturedRoom.walls.map {
                let snapshot = WallSnapshot(surface: $0)
                return WallSnapshot(
                    id: snapshot.id,
                    width: snapshot.width,
                    height: snapshot.height,
                    matrix: transform * snapshot.matrix
                )
            }
        )
        result.surfaces = mergeSurfaces(
            existing: source.surfaces,
            incoming: capturedRoom.doors.map {
                transformedSurface($0, kind: .door, by: transform)
            } + capturedRoom.windows.map {
                transformedSurface($0, kind: .window, by: transform)
            } + capturedRoom.openings.map {
                transformedSurface($0, kind: .opening, by: transform)
            }
        )
        result.floors = mergeFloors(
            existing: source.floors ?? [],
            incoming: capturedRoom.floors.map {
                let snapshot = FloorSnapshot(surface: $0)
                return FloorSnapshot(
                    id: snapshot.id,
                    width: snapshot.width,
                    depth: snapshot.depth,
                    matrix: transform * snapshot.matrix
                )
            }
        )
        if includeFurniture {
            result.objects = mergeObjects(
                existing: source.objects ?? [],
                incoming: capturedRoom.objects.map {
                    let snapshot = RoomObjectSnapshot(object: $0)
                    return RoomObjectSnapshot(
                        id: snapshot.id,
                        category: snapshot.category,
                        width: snapshot.width,
                        height: snapshot.height,
                        depth: snapshot.depth,
                        matrix: transform * snapshot.matrix
                    )
                }
            )
        }
        result.normalizeWallPhotoMetadata()
        return result
    }

    private static func transformedSurface(
        _ surface: CapturedRoom.Surface,
        kind: SurfaceSnapshot.Kind,
        by transform: simd_float4x4
    ) -> SurfaceSnapshot {
        let snapshot = SurfaceSnapshot(surface: surface, kind: kind)
        return SurfaceSnapshot(
            id: snapshot.id,
            kind: snapshot.kind,
            width: snapshot.width,
            height: snapshot.height,
            matrix: transform * snapshot.matrix,
            colorHex: snapshot.colorHex,
            isManuallyAdded: snapshot.isManuallyAdded
        )
    }

    private static func mergeWalls(
        existing: [WallSnapshot],
        incoming: [WallSnapshot]
    ) -> [WallSnapshot] {
        var merged = existing
        var usedExisting: Set<UUID> = []

        for wall in incoming {
            if let index = bestWallMatch(
                for: wall,
                in: merged,
                excluding: usedExisting
            ) {
                let old = merged[index]
                merged[index] = WallSnapshot(
                    id: old.id,
                    width: wall.width,
                    height: wall.height,
                    matrix: wall.matrix
                )
                usedExisting.insert(old.id)
            } else {
                merged.append(wall)
            }
        }
        return merged
    }

    private static func bestWallMatch(
        for incoming: WallSnapshot,
        in existing: [WallSnapshot],
        excluding used: Set<UUID>
    ) -> Int? {
        let incomingCenter = translation(of: incoming.matrix)
        let incomingNormal = normalizedAxisZ(of: incoming.matrix)

        return existing.indices
            .filter { !used.contains(existing[$0].id) }
            .compactMap { index -> (Int, Float)? in
                let candidate = existing[index]
                let candidateCenter = translation(of: candidate.matrix)
                let centerDistance = simd_distance(incomingCenter, candidateCenter)
                let alignment = abs(simd_dot(
                    incomingNormal,
                    normalizedAxisZ(of: candidate.matrix)
                ))
                let widthDifference = abs(incoming.width - candidate.width)
                let heightDifference = abs(incoming.height - candidate.height)
                guard centerDistance <= 0.55,
                      alignment >= 0.92,
                      widthDifference <= max(0.75, candidate.width * 0.35),
                      heightDifference <= max(0.45, candidate.height * 0.25) else {
                    return nil
                }
                let score = centerDistance
                    + (1 - alignment) * 2
                    + widthDifference * 0.25
                    + heightDifference * 0.25
                return (index, score)
            }
            .min(by: { $0.1 < $1.1 })?
            .0
    }

    private static func mergeSurfaces(
        existing: [SurfaceSnapshot],
        incoming: [SurfaceSnapshot]
    ) -> [SurfaceSnapshot] {
        var merged = existing
        var usedExisting: Set<UUID> = []

        for surface in incoming {
            if let index = bestSurfaceMatch(
                for: surface,
                in: merged,
                excluding: usedExisting
            ) {
                let old = merged[index]
                merged[index] = SurfaceSnapshot(
                    id: old.id,
                    kind: surface.kind,
                    width: surface.width,
                    height: surface.height,
                    matrix: surface.matrix,
                    colorHex: old.colorHex,
                    isManuallyAdded: old.isManuallyAdded
                )
                usedExisting.insert(old.id)
            } else {
                merged.append(surface)
            }
        }
        return merged
    }

    private static func bestSurfaceMatch(
        for incoming: SurfaceSnapshot,
        in existing: [SurfaceSnapshot],
        excluding used: Set<UUID>
    ) -> Int? {
        let incomingCenter = translation(of: incoming.matrix)
        let incomingNormal = normalizedAxisZ(of: incoming.matrix)

        return existing.indices
            .filter {
                !used.contains(existing[$0].id)
                    && existing[$0].kind == incoming.kind
                    && existing[$0].isManuallyAdded != true
            }
            .compactMap { index -> (Int, Float)? in
                let candidate = existing[index]
                let distance = simd_distance(
                    incomingCenter,
                    translation(of: candidate.matrix)
                )
                let alignment = abs(simd_dot(
                    incomingNormal,
                    normalizedAxisZ(of: candidate.matrix)
                ))
                let widthDifference = abs(incoming.width - candidate.width)
                let heightDifference = abs(incoming.height - candidate.height)
                guard distance <= 0.40,
                      alignment >= 0.90,
                      widthDifference <= max(0.45, candidate.width * 0.40),
                      heightDifference <= max(0.45, candidate.height * 0.40) else {
                    return nil
                }
                return (
                    index,
                    distance + (1 - alignment) + widthDifference * 0.2 + heightDifference * 0.2
                )
            }
            .min(by: { $0.1 < $1.1 })?
            .0
    }

    private static func mergeFloors(
        existing: [FloorSnapshot],
        incoming: [FloorSnapshot]
    ) -> [FloorSnapshot] {
        var merged = existing
        for floor in incoming {
            if let index = merged.indices.min(by: {
                floorMatchScore(floor, merged[$0]) < floorMatchScore(floor, merged[$1])
            }), floorMatchScore(floor, merged[index]) < 1.15 {
                let old = merged[index]
                merged[index] = FloorSnapshot(
                    id: old.id,
                    width: floor.width,
                    depth: floor.depth,
                    matrix: floor.matrix
                )
            } else {
                merged.append(floor)
            }
        }
        return merged
    }

    private static func floorMatchScore(
        _ first: FloorSnapshot,
        _ second: FloorSnapshot
    ) -> Float {
        simd_distance(translation(of: first.matrix), translation(of: second.matrix))
            + abs(first.width - second.width) * 0.15
            + abs(first.depth - second.depth) * 0.15
    }

    private static func mergeObjects(
        existing: [RoomObjectSnapshot],
        incoming: [RoomObjectSnapshot]
    ) -> [RoomObjectSnapshot] {
        var merged = existing
        var usedExisting: Set<UUID> = []

        for object in incoming {
            let incomingCenter = translation(of: object.matrix)
            let match = merged.indices
                .filter {
                    !usedExisting.contains(merged[$0].id)
                        && merged[$0].category == object.category
                }
                .compactMap { index -> (Int, Float)? in
                    let candidate = merged[index]
                    let distance = simd_distance(
                        incomingCenter,
                        translation(of: candidate.matrix)
                    )
                    guard distance <= 0.65 else { return nil }
                    let sizeDifference = abs(object.width - candidate.width)
                        + abs(object.height - candidate.height)
                        + abs(object.depth - candidate.depth)
                    guard sizeDifference <= 1.20 else { return nil }
                    return (index, distance + sizeDifference * 0.15)
                }
                .min(by: { $0.1 < $1.1 })?
                .0

            if let index = match {
                let old = merged[index]
                merged[index] = RoomObjectSnapshot(
                    id: old.id,
                    category: object.category,
                    width: object.width,
                    height: object.height,
                    depth: object.depth,
                    matrix: object.matrix
                )
                usedExisting.insert(old.id)
            } else {
                merged.append(object)
            }
        }
        return merged
    }

    private static func translation(of matrix: simd_float4x4) -> SIMD3<Float> {
        SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }

    private static func normalizedAxisZ(of matrix: simd_float4x4) -> SIMD3<Float> {
        let axis = SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        let length = simd_length(axis)
        return length > 0.0001 ? axis / length : SIMD3(0, 0, 1)
    }
}
