import Foundation
import RoomPlan
import simd

/// Merges a new RoomPlan result only after it proves that the incoming session
/// shares a safe, right-handed, gravity-aligned project coordinate space.
enum RoomProjectGeometryMerger {
    struct MergeReport: Codable, Equatable {
        var accepted: Bool
        var usedReferenceWallRefinement: Bool
        var matchedWallCount: Int
        var appendedWallCount: Int
        var conflictingWallCount: Int
        var maximumWallTiltDegrees: Float
        var message: String
    }

    struct MergeOutcome {
        var project: RoomProject
        var effectiveTransform: simd_float4x4
        var report: MergeReport
    }

    static func mergeValidated(
        capturedRoom: CapturedRoom,
        into source: RoomProject,
        includeFurniture: Bool,
        incomingWorldTransform: simd_float4x4? = nil,
        referenceWall: SpatialWallReference? = nil,
        requiresReferenceWallMatch: Bool = false
    ) -> MergeOutcome {
        let initial = incomingWorldTransform ?? matrix_identity_float4x4
        guard SpatialCoordinateContract.validateProjectMapping(initial).isSafeRigidTransform else {
            return rejected(
                source: source,
                transform: initial,
                message: "تم رفض الدمج لأن تحويل الجلسة يحتوي على انعكاس أو ميل أو مقياس غير صالح."
            )
        }

        let resolution = resolveTransform(
            capturedRoom: capturedRoom,
            source: source,
            initialTransform: initial,
            referenceWall: referenceWall
        )
        let effectiveTransform = resolution.transform
        let incomingWalls = capturedRoom.walls.map {
            let snapshot = WallSnapshot(surface: $0)
            return WallSnapshot(
                id: snapshot.id,
                width: snapshot.width,
                height: snapshot.height,
                matrix: effectiveTransform * snapshot.matrix
            )
        }

        let maximumTilt = incomingWalls.map(wallTiltDegrees).max() ?? 0
        guard incomingWalls.allSatisfy({
            SpatialCoordinateContract.wallIsVertical($0.matrix)
        }) else {
            return rejected(
                source: source,
                transform: effectiveTransform,
                maximumTilt: maximumTilt,
                message: "تم رفض الدمج لأن الجلسة الجديدة مالت عن محور الجاذبية. لن تُضاف حوائط مائلة أو معكوسة للمشروع."
            )
        }

        let analysis = analyzeWalls(
            incoming: incomingWalls,
            existing: source.walls
        )
        if requiresReferenceWallMatch && analysis.matchedCount == 0 {
            return rejected(
                source: source,
                transform: effectiveTransform,
                usedRefinement: resolution.usedReferenceWall,
                conflicts: analysis.conflictCount,
                maximumTilt: maximumTilt,
                message: "لم يتم العثور على حائط مشترك مؤكد بين الجلسة المحفوظة والجلسة الجديدة. تم الاحتفاظ بالمشروع القديم ومنع الدمج لتجنب تكرار الحوائط."
            )
        }
        if analysis.conflictCount > 0 {
            return rejected(
                source: source,
                transform: effectiveTransform,
                usedRefinement: resolution.usedReferenceWall,
                matched: analysis.matchedCount,
                conflicts: analysis.conflictCount,
                maximumTilt: maximumTilt,
                message: "اكتشف التطبيق حوائط متراكبة باتجاهات أو مراكز غير متوافقة. تم إيقاف الدمج بدل إنشاء نسخة ثانية من الحائط نفسه."
            )
        }

        var result = source
        let wallMerge = mergeWalls(existing: source.walls, incoming: incomingWalls)
        result.walls = wallMerge.walls
        result.surfaces = mergeSurfaces(
            existing: source.surfaces,
            incoming: capturedRoom.doors.map {
                transformedSurface($0, kind: .door, by: effectiveTransform)
            } + capturedRoom.windows.map {
                transformedSurface($0, kind: .window, by: effectiveTransform)
            } + capturedRoom.openings.map {
                transformedSurface($0, kind: .opening, by: effectiveTransform)
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
                    matrix: effectiveTransform * snapshot.matrix
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
                        matrix: effectiveTransform * snapshot.matrix
                    )
                }
            )
        }
        result.snapshotGeometryRevision = (source.snapshotGeometryRevision ?? 0) + 1
        result.normalizeWallPhotoMetadata()

        return MergeOutcome(
            project: result,
            effectiveTransform: effectiveTransform,
            report: MergeReport(
                accepted: true,
                usedReferenceWallRefinement: resolution.usedReferenceWall,
                matchedWallCount: wallMerge.matchedCount,
                appendedWallCount: wallMerge.appendedCount,
                conflictingWallCount: 0,
                maximumWallTiltDegrees: maximumTilt,
                message: wallMerge.appendedCount == 0
                    ? "تم تحديث الحوائط المشتركة دون إنشاء نسخ متراكبة."
                    : "تم تثبيت حائط مشترك ثم إضافة الجزء الجديد داخل نفس إحداثيات المشروع."
            )
        )
    }

    static func recoverCheckpoint(
        _ checkpoint: SpatialResumeGeometryCheckpoint,
        into source: RoomProject,
        includeFurniture: Bool
    ) -> MergeOutcome {
        let maximumTilt = checkpoint.walls.map(wallTiltDegrees).max() ?? 0
        guard checkpoint.walls.allSatisfy({
            SpatialCoordinateContract.wallIsVertical($0.matrix)
        }) else {
            return rejected(
                source: source,
                transform: matrix_identity_float4x4,
                maximumTilt: maximumTilt,
                message: "نقطة الاسترداد تحتوي على اتجاهات مائلة وغير آمنة، لذلك لم تُدمج."
            )
        }
        let analysis = analyzeWalls(
            incoming: checkpoint.walls,
            existing: source.walls
        )
        guard analysis.matchedCount > 0, analysis.conflictCount == 0 else {
            return rejected(
                source: source,
                transform: matrix_identity_float4x4,
                matched: analysis.matchedCount,
                conflicts: analysis.conflictCount,
                maximumTilt: maximumTilt,
                message: "تعذر إثبات وجود حائط مشترك آمن داخل نقطة الاسترداد؛ ظل المشروع الأصلي كما هو."
            )
        }

        var result = source
        let wallMerge = mergeWalls(
            existing: source.walls,
            incoming: checkpoint.walls
        )
        result.walls = wallMerge.walls
        result.surfaces = mergeSurfaces(
            existing: source.surfaces,
            incoming: checkpoint.surfaces
        )
        result.floors = mergeFloors(
            existing: source.floors ?? [],
            incoming: checkpoint.floors
        )
        if includeFurniture {
            result.objects = mergeObjects(
                existing: source.objects ?? [],
                incoming: checkpoint.objects
            )
        }
        result.snapshotGeometryRevision = (source.snapshotGeometryRevision ?? 0) + 1
        result.normalizeWallPhotoMetadata()
        return MergeOutcome(
            project: result,
            effectiveTransform: matrix_identity_float4x4,
            report: MergeReport(
                accepted: true,
                usedReferenceWallRefinement: false,
                matchedWallCount: wallMerge.matchedCount,
                appendedWallCount: wallMerge.appendedCount,
                conflictingWallCount: 0,
                maximumWallTiltDegrees: maximumTilt,
                message: "تم استرداد آخر نقطة حفظ بعد التحقق من الحائط المشترك وعدم وجود تراكب متعارض."
            )
        )
    }

    static func transformedCandidate(
        capturedRoom: CapturedRoom,
        by transform: simd_float4x4
    ) -> SpatialResumeGeometryCheckpoint {
        SpatialResumeGeometryCheckpoint(
            createdAt: Date(),
            walls: capturedRoom.walls.map {
                let snapshot = WallSnapshot(surface: $0)
                return WallSnapshot(
                    id: snapshot.id,
                    width: snapshot.width,
                    height: snapshot.height,
                    matrix: transform * snapshot.matrix
                )
            },
            surfaces: capturedRoom.doors.map {
                transformedSurface($0, kind: .door, by: transform)
            } + capturedRoom.windows.map {
                transformedSurface($0, kind: .window, by: transform)
            } + capturedRoom.openings.map {
                transformedSurface($0, kind: .opening, by: transform)
            },
            floors: capturedRoom.floors.map {
                let snapshot = FloorSnapshot(surface: $0)
                return FloorSnapshot(
                    id: snapshot.id,
                    width: snapshot.width,
                    depth: snapshot.depth,
                    matrix: transform * snapshot.matrix
                )
            },
            objects: capturedRoom.objects.map {
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

    private struct TransformResolution {
        var transform: simd_float4x4
        var usedReferenceWall: Bool
    }

    private struct WallAnalysis {
        var matchedCount: Int
        var conflictCount: Int
        var error: Float
    }

    private struct WallMergeResult {
        var walls: [WallSnapshot]
        var matchedCount: Int
        var appendedCount: Int
    }

    private static func resolveTransform(
        capturedRoom: CapturedRoom,
        source: RoomProject,
        initialTransform: simd_float4x4,
        referenceWall: SpatialWallReference?
    ) -> TransformResolution {
        guard let referenceWall,
              let target = source.walls.first(where: { $0.id == referenceWall.wallID }),
              !capturedRoom.walls.isEmpty else {
            return TransformResolution(
                transform: initialTransform,
                usedReferenceWall: false
            )
        }

        let incomingSnapshots = capturedRoom.walls.map { WallSnapshot(surface: $0) }
        let targetCenter = translation(of: target.matrix)
        let candidates = incomingSnapshots.filter {
            abs($0.width - target.width) <= max(0.90, target.width * 0.38)
                && abs($0.height - target.height) <= max(0.55, target.height * 0.30)
        }
        guard !candidates.isEmpty else {
            return TransformResolution(
                transform: initialTransform,
                usedReferenceWall: false
            )
        }

        var possibleTransforms: [(simd_float4x4, Bool)] = [(initialTransform, false)]
        for candidate in candidates {
            let initiallyMapped = initialTransform * candidate.matrix
            for correction in SpatialCoordinateContract.planarWallCorrection(
                from: initiallyMapped,
                to: target.matrix,
                allowHalfTurn: true
            ) {
                possibleTransforms.append((correction * initialTransform, true))
            }
        }

        let best = possibleTransforms
            .filter { SpatialCoordinateContract.validateProjectMapping($0.0).isSafeRigidTransform }
            .map { transform, refined -> (simd_float4x4, Bool, Float) in
                let walls = incomingSnapshots.map {
                    WallSnapshot(
                        id: $0.id,
                        width: $0.width,
                        height: $0.height,
                        matrix: transform * $0.matrix
                    )
                }
                let analysis = analyzeWalls(incoming: walls, existing: source.walls)
                let referenceDistance = walls.map {
                    simd_distance(translation(of: $0.matrix), targetCenter)
                        + abs($0.width - target.width) * 0.3
                        + abs($0.height - target.height) * 0.3
                }.min() ?? 50
                let score = Float(analysis.matchedCount) * 12
                    - Float(analysis.conflictCount) * 15
                    - analysis.error
                    - referenceDistance
                return (transform, refined, score)
            }
            .max(by: { $0.2 < $1.2 })

        guard let best else {
            return TransformResolution(
                transform: initialTransform,
                usedReferenceWall: false
            )
        }
        return TransformResolution(
            transform: best.0,
            usedReferenceWall: best.1
        )
    }

    private static func analyzeWalls(
        incoming: [WallSnapshot],
        existing: [WallSnapshot]
    ) -> WallAnalysis {
        guard !existing.isEmpty else {
            return WallAnalysis(matchedCount: 0, conflictCount: 0, error: 0)
        }
        var matched = 0
        var conflicts = 0
        var totalError: Float = 0
        for wall in incoming {
            let center = translation(of: wall.matrix)
            let normal = normalizedAxisZ(of: wall.matrix)
            let comparisons = existing.map { candidate -> (Float, Float, Float, Float) in
                let distance = simd_distance(center, translation(of: candidate.matrix))
                let alignment = abs(simd_dot(normal, normalizedAxisZ(of: candidate.matrix)))
                return (
                    distance,
                    alignment,
                    abs(wall.width - candidate.width),
                    abs(wall.height - candidate.height)
                )
            }
            if let best = comparisons.min(by: {
                wallComparisonScore($0) < wallComparisonScore($1)
            }) {
                if isWallMatch(best, incoming: wall) {
                    matched += 1
                    totalError += wallComparisonScore(best)
                } else if best.0 <= 1.10,
                          best.1 >= 0.82,
                          best.2 <= max(1.10, wall.width * 0.55) {
                    conflicts += 1
                    totalError += 8
                }
            }
        }
        return WallAnalysis(
            matchedCount: matched,
            conflictCount: conflicts,
            error: totalError
        )
    }

    private static func wallComparisonScore(
        _ value: (Float, Float, Float, Float)
    ) -> Float {
        value.0 + (1 - value.1) * 2 + value.2 * 0.25 + value.3 * 0.25
    }

    private static func isWallMatch(
        _ comparison: (Float, Float, Float, Float),
        incoming: WallSnapshot
    ) -> Bool {
        comparison.0 <= 0.62
            && comparison.1 >= 0.90
            && comparison.2 <= max(0.80, incoming.width * 0.38)
            && comparison.3 <= max(0.50, incoming.height * 0.28)
    }

    private static func rejected(
        source: RoomProject,
        transform: simd_float4x4,
        usedRefinement: Bool = false,
        matched: Int = 0,
        conflicts: Int = 0,
        maximumTilt: Float = 0,
        message: String
    ) -> MergeOutcome {
        MergeOutcome(
            project: source,
            effectiveTransform: transform,
            report: MergeReport(
                accepted: false,
                usedReferenceWallRefinement: usedRefinement,
                matchedWallCount: matched,
                appendedWallCount: 0,
                conflictingWallCount: conflicts,
                maximumWallTiltDegrees: maximumTilt,
                message: message
            )
        )
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
    ) -> WallMergeResult {
        var merged = existing
        var usedExisting: Set<UUID> = []
        var matched = 0
        var appended = 0

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
                matched += 1
            } else {
                merged.append(wall)
                appended += 1
            }
        }
        return WallMergeResult(
            walls: merged,
            matchedCount: matched,
            appendedCount: appended
        )
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
                guard centerDistance <= 0.62,
                      alignment >= 0.90,
                      widthDifference <= max(0.80, candidate.width * 0.38),
                      heightDifference <= max(0.50, candidate.height * 0.28) else {
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
                guard distance <= 0.48,
                      alignment >= 0.88,
                      widthDifference <= max(0.50, candidate.width * 0.42),
                      heightDifference <= max(0.50, candidate.height * 0.42) else {
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

    private static func wallTiltDegrees(_ wall: WallSnapshot) -> Float {
        let up = SIMD3(
            wall.matrix.columns.1.x,
            wall.matrix.columns.1.y,
            wall.matrix.columns.1.z
        )
        let length = simd_length(up)
        guard length > 0.0001 else { return 90 }
        let alignment = min(max(simd_dot(up / length, SIMD3<Float>(0, 1, 0)), -1), 1)
        return acos(alignment) * 180 / .pi
    }

    private static func translation(of matrix: simd_float4x4) -> SIMD3<Float> {
        SpatialCoordinateContract.translation(matrix)
    }

    private static func normalizedAxisZ(of matrix: simd_float4x4) -> SIMD3<Float> {
        let axis = SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        let length = simd_length(axis)
        return length > 0.0001 ? axis / length : SIMD3(0, 0, 1)
    }
}
