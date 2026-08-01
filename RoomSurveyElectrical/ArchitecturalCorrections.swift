import Foundation
import simd

enum ArchitecturalEntitySource: String, Codable, CaseIterable, Identifiable {
    case roomPlan
    case manual
    case merged
    case corrected
    case rescanned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .roomPlan: "RoomPlan"
        case .manual: "يدوي"
        case .merged: "دمج"
        case .corrected: "تصحيح"
        case .rescanned: "إعادة مسح"
        }
    }
}

struct ArchitecturalWallState: Codable, Equatable {
    var wallID: UUID
    var width: Float
    var height: Float
    var transform: [Float]

    init(wall: WallSnapshot) {
        wallID = wall.id
        width = wall.width
        height = wall.height
        transform = wall.transform
    }

    init(
        wallID: UUID,
        width: Float,
        height: Float,
        transform: [Float]
    ) {
        self.wallID = wallID
        self.width = width
        self.height = height
        self.transform = transform
    }

    var wall: WallSnapshot {
        WallSnapshot(
            id: wallID,
            width: width,
            height: height,
            matrix: simd_float4x4(columnMajorValues: transform)
        )
    }

    var isValid: Bool {
        guard width.isFinite,
              height.isFinite,
              width >= 0.05,
              height >= 0.20,
              transform.count == 16,
              transform.allSatisfy({ $0.isFinite }) else {
            return false
        }
        return SpatialCoordinateContract.validateProjectMapping(
            simd_float4x4(columnMajorValues: transform)
        ).isSafeRigidTransform
    }
}

struct ArchitecturalWallCorrection: Codable, Identifiable, Equatable {
    let id: UUID
    let changeSetID: UUID
    let scanID: UUID
    let wallID: UUID
    let source: ArchitecturalEntitySource
    let beforeState: ArchitecturalWallState
    let afterState: ArchitecturalWallState
    let appliedAt: Date
    var note: String?

    init(
        id: UUID = UUID(),
        changeSetID: UUID,
        scanID: UUID,
        wallID: UUID,
        source: ArchitecturalEntitySource = .corrected,
        beforeState: ArchitecturalWallState,
        afterState: ArchitecturalWallState,
        appliedAt: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.changeSetID = changeSetID
        self.scanID = scanID
        self.wallID = wallID
        self.source = source
        self.beforeState = beforeState
        self.afterState = afterState
        self.appliedAt = appliedAt
        self.note = note
    }
}

enum ArchitecturalCorrectionError: LocalizedError {
    case invalidWallState
    case staleWall
    case wallNotFound

    var errorDescription: String? {
        switch self {
        case .invalidWallState:
            "بيانات الحائط المصححة غير صالحة أو تحتوي على تحويل مكاني غير آمن."
        case .staleWall:
            "تغير الحائط منذ بدء الجلسة. ألغِ السجل الحالي وأنشئ تعديلًا جديدًا من أحدث حالة."
        case .wallNotFound:
            "الحائط المرتبط بالتصحيح لم يعد موجودًا داخل المسح."
        }
    }
}

extension RoomProject {
    var preservedOriginalWalls: [WallSnapshot] {
        originalWalls ?? walls
    }

    var hasArchitecturalCorrections: Bool {
        architecturalCorrections?.isEmpty == false
    }

    mutating func normalizeArchitecturalCorrections() {
        guard let storedCorrections = architecturalCorrections,
              !storedCorrections.isEmpty else {
            return
        }

        if originalWalls == nil {
            originalWalls = walls
        }
        guard let originalWalls else { return }

        var wallByID = Dictionary(
            originalWalls.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let validIDs = Set(wallByID.keys)
        let candidates = storedCorrections
            .filter {
                $0.scanID == id
                    && $0.wallID == $0.beforeState.wallID
                    && $0.wallID == $0.afterState.wallID
                    && validIDs.contains($0.wallID)
                    && $0.beforeState.isValid
                    && $0.afterState.isValid
            }
            .sorted { $0.appliedAt < $1.appliedAt }

        var normalizedCorrections: [ArchitecturalWallCorrection] = []
        for correction in candidates {
            guard let current = wallByID[correction.wallID],
                  ArchitecturalWallState(wall: current)
                    == correction.beforeState else {
                continue
            }
            wallByID[correction.wallID] = correction.afterState.wall
            normalizedCorrections.append(correction)
        }

        architecturalCorrections = normalizedCorrections
        walls = originalWalls.compactMap { wallByID[$0.id] }
        refreshElectricalPointsForCorrectedWalls(
            Set(normalizedCorrections.map(\.wallID))
        )
    }

    mutating func applyArchitecturalCorrection(
        _ correction: ArchitecturalWallCorrection
    ) throws {
        guard correction.scanID == id,
              correction.wallID == correction.beforeState.wallID,
              correction.wallID == correction.afterState.wallID,
              correction.beforeState.isValid,
              correction.afterState.isValid else {
            throw ArchitecturalCorrectionError.invalidWallState
        }
        guard let currentWall = walls.first(where: {
            $0.id == correction.wallID
        }) else {
            throw ArchitecturalCorrectionError.wallNotFound
        }
        guard ArchitecturalWallState(wall: currentWall)
            == correction.beforeState else {
            throw ArchitecturalCorrectionError.staleWall
        }

        if originalWalls == nil {
            originalWalls = walls
        }
        var corrections = architecturalCorrections ?? []
        corrections.append(correction)
        architecturalCorrections = corrections
        normalizeArchitecturalCorrections()
    }

    mutating func refreshElectricalPointsForCorrectedWalls(
        _ wallIDs: Set<UUID>
    ) {
        guard !wallIDs.isEmpty else { return }
        let wallByID = Dictionary(
            walls.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        for index in points.indices {
            guard wallIDs.contains(points[index].wallID),
                  let wall = wallByID[points[index].wallID] else {
                continue
            }
            let localY = points[index].heightFromFloor - wall.height / 2
            points[index].localY = localY
            let world = wall.matrix * SIMD4<Float>(
                points[index].localX,
                localY,
                0.01,
                1
            )
            points[index].worldPosition = [world.x, world.y, world.z]
        }
    }
}
