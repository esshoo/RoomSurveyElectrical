import Foundation

enum SettingsInheritanceLevel: String, Codable, CaseIterable, Identifiable {
    case appDefaults
    case project
    case roomOrScan
    case element

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appDefaults: "إعدادات التطبيق"
        case .project: "إعدادات المشروع"
        case .roomOrScan: "إعدادات الغرفة أو المسح"
        case .element: "إعداد العنصر"
        }
    }
}

struct RecoveryPolicy: Codable, Equatable {
    var automaticSnapshotBeforeRiskyOperations: Bool
    var maximumSnapshotCount: Int

    static let standard = RecoveryPolicy(
        automaticSnapshotBeforeRiskyOperations: true,
        maximumSnapshotCount: 12
    )
}

struct RecoveryPolicyOverrides: Codable, Equatable {
    var automaticSnapshotBeforeRiskyOperations: Bool?
    var maximumSnapshotCount: Int?

    var isEmpty: Bool {
        automaticSnapshotBeforeRiskyOperations == nil
            && maximumSnapshotCount == nil
    }

    func applying(to base: RecoveryPolicy) -> RecoveryPolicy {
        RecoveryPolicy(
            automaticSnapshotBeforeRiskyOperations:
                automaticSnapshotBeforeRiskyOperations
                    ?? base.automaticSnapshotBeforeRiskyOperations,
            maximumSnapshotCount: max(
                3,
                min(maximumSnapshotCount ?? base.maximumSnapshotCount, 50)
            )
        )
    }
}

struct ElectricalPlacementOverrides: Codable, Equatable {
    var switchHeightMeters: Double?
    var socketHeightMeters: Double?
    var wallLightHeightMeters: Double?
    var switchDoorOffsetMeters: Double?
    var designMode: ElectricalDesignMode?
    var avoidOpenings: Bool?
    var doorSuggestionMinimumMeters: Double?
    var doorSuggestionMaximumMeters: Double?
    var switchAlignmentMinimumMeters: Double?
    var switchAlignmentMaximumMeters: Double?
    var squareBoxWidthMeters: Double?
    var squareBoxHeightMeters: Double?
    var rectangularBoxWidthMeters: Double?
    var rectangularBoxHeightMeters: Double?
    var electricalMergeDistanceMeters: Double?
    var lowCurrentLowHeightMeters: Double?
    var lowCurrentHighHeightMeters: Double?
    var splitAirConditionerCeilingOffsetMeters: Double?
    var windowAirConditionerHeightMeters: Double?
    var keepScreenAwakeDuringSpatialScan: Bool?
    var spatialScanPerformanceProfile: SpatialScanPerformanceProfile?
    var spatialScanContentMode: SpatialScanContentMode?
    var spatialScanThermalProtectionMode: SpatialScanThermalProtectionMode?
    var thermalResumeStabilityDuration: ThermalResumeStabilityDuration?
    var showThermalStateDuringSpatialScan: Bool?
    var spatialRelocalizationStrictness: SpatialRelocalizationStrictness?
    var useOptionalLocationAssistForResume: Bool?

    var isEmpty: Bool {
        switchHeightMeters == nil
            && socketHeightMeters == nil
            && wallLightHeightMeters == nil
            && switchDoorOffsetMeters == nil
            && designMode == nil
            && avoidOpenings == nil
            && doorSuggestionMinimumMeters == nil
            && doorSuggestionMaximumMeters == nil
            && switchAlignmentMinimumMeters == nil
            && switchAlignmentMaximumMeters == nil
            && squareBoxWidthMeters == nil
            && squareBoxHeightMeters == nil
            && rectangularBoxWidthMeters == nil
            && rectangularBoxHeightMeters == nil
            && electricalMergeDistanceMeters == nil
            && lowCurrentLowHeightMeters == nil
            && lowCurrentHighHeightMeters == nil
            && splitAirConditionerCeilingOffsetMeters == nil
            && windowAirConditionerHeightMeters == nil
            && keepScreenAwakeDuringSpatialScan == nil
            && spatialScanPerformanceProfile == nil
            && spatialScanContentMode == nil
            && spatialScanThermalProtectionMode == nil
            && thermalResumeStabilityDuration == nil
            && showThermalStateDuringSpatialScan == nil
            && spatialRelocalizationStrictness == nil
            && useOptionalLocationAssistForResume == nil
    }

    func applying(to base: ElectricalPlacementSettings) -> ElectricalPlacementSettings {
        var result = base
        if let switchHeightMeters { result.switchHeightMeters = max(0, switchHeightMeters) }
        if let socketHeightMeters { result.socketHeightMeters = max(0, socketHeightMeters) }
        if let wallLightHeightMeters { result.wallLightHeightMeters = max(0, wallLightHeightMeters) }
        if let switchDoorOffsetMeters { result.switchDoorOffsetMeters = max(0, switchDoorOffsetMeters) }
        if let designMode { result.designMode = designMode }
        if let avoidOpenings { result.avoidOpenings = avoidOpenings }
        if let doorSuggestionMinimumMeters { result.doorSuggestionMinimumMeters = doorSuggestionMinimumMeters }
        if let doorSuggestionMaximumMeters { result.doorSuggestionMaximumMeters = doorSuggestionMaximumMeters }
        if let switchAlignmentMinimumMeters { result.switchAlignmentMinimumMeters = switchAlignmentMinimumMeters }
        if let switchAlignmentMaximumMeters { result.switchAlignmentMaximumMeters = switchAlignmentMaximumMeters }
        if let squareBoxWidthMeters { result.squareBoxWidthMeters = squareBoxWidthMeters }
        if let squareBoxHeightMeters { result.squareBoxHeightMeters = squareBoxHeightMeters }
        if let rectangularBoxWidthMeters { result.rectangularBoxWidthMeters = rectangularBoxWidthMeters }
        if let rectangularBoxHeightMeters { result.rectangularBoxHeightMeters = rectangularBoxHeightMeters }
        if let electricalMergeDistanceMeters { result.electricalMergeDistanceMeters = electricalMergeDistanceMeters }
        if let lowCurrentLowHeightMeters { result.lowCurrentLowHeightMeters = lowCurrentLowHeightMeters }
        if let lowCurrentHighHeightMeters { result.lowCurrentHighHeightMeters = lowCurrentHighHeightMeters }
        if let splitAirConditionerCeilingOffsetMeters {
            result.splitAirConditionerCeilingOffsetMeters = splitAirConditionerCeilingOffsetMeters
        }
        if let windowAirConditionerHeightMeters {
            result.windowAirConditionerHeightMeters = windowAirConditionerHeightMeters
        }
        if let keepScreenAwakeDuringSpatialScan {
            result.keepScreenAwakeDuringSpatialScan = keepScreenAwakeDuringSpatialScan
        }
        if let spatialScanPerformanceProfile {
            result.spatialScanPerformanceProfile = spatialScanPerformanceProfile
        }
        if let spatialScanContentMode {
            result.spatialScanContentMode = spatialScanContentMode
        }
        if let spatialScanThermalProtectionMode {
            result.spatialScanThermalProtectionMode = spatialScanThermalProtectionMode
        }
        if let thermalResumeStabilityDuration {
            result.thermalResumeStabilityDuration = thermalResumeStabilityDuration
        }
        if let showThermalStateDuringSpatialScan {
            result.showThermalStateDuringSpatialScan = showThermalStateDuringSpatialScan
        }
        if let spatialRelocalizationStrictness {
            result.spatialRelocalizationStrictness = spatialRelocalizationStrictness
        }
        if let useOptionalLocationAssistForResume {
            result.useOptionalLocationAssistForResume = useOptionalLocationAssistForResume
        }
        return result
    }

    static func difference(
        from base: ElectricalPlacementSettings,
        to value: ElectricalPlacementSettings
    ) -> ElectricalPlacementOverrides {
        ElectricalPlacementOverrides(
            switchHeightMeters: changed(base.switchHeightMeters, value.switchHeightMeters),
            socketHeightMeters: changed(base.socketHeightMeters, value.socketHeightMeters),
            wallLightHeightMeters: changed(base.wallLightHeightMeters, value.wallLightHeightMeters),
            switchDoorOffsetMeters: changed(base.switchDoorOffsetMeters, value.switchDoorOffsetMeters),
            designMode: changed(base.designMode, value.designMode),
            avoidOpenings: changed(base.avoidOpenings, value.avoidOpenings),
            doorSuggestionMinimumMeters: changed(base.doorSuggestionMinimumMeters, value.doorSuggestionMinimumMeters),
            doorSuggestionMaximumMeters: changed(base.doorSuggestionMaximumMeters, value.doorSuggestionMaximumMeters),
            switchAlignmentMinimumMeters: changed(base.switchAlignmentMinimumMeters, value.switchAlignmentMinimumMeters),
            switchAlignmentMaximumMeters: changed(base.switchAlignmentMaximumMeters, value.switchAlignmentMaximumMeters),
            squareBoxWidthMeters: changed(base.squareBoxWidthMeters, value.squareBoxWidthMeters),
            squareBoxHeightMeters: changed(base.squareBoxHeightMeters, value.squareBoxHeightMeters),
            rectangularBoxWidthMeters: changed(base.rectangularBoxWidthMeters, value.rectangularBoxWidthMeters),
            rectangularBoxHeightMeters: changed(base.rectangularBoxHeightMeters, value.rectangularBoxHeightMeters),
            electricalMergeDistanceMeters: changed(base.electricalMergeDistanceMeters, value.electricalMergeDistanceMeters),
            lowCurrentLowHeightMeters: changed(base.lowCurrentLowHeightMeters, value.lowCurrentLowHeightMeters),
            lowCurrentHighHeightMeters: changed(base.lowCurrentHighHeightMeters, value.lowCurrentHighHeightMeters),
            splitAirConditionerCeilingOffsetMeters: changed(
                base.splitAirConditionerCeilingOffsetMeters,
                value.splitAirConditionerCeilingOffsetMeters
            ),
            windowAirConditionerHeightMeters: changed(
                base.windowAirConditionerHeightMeters,
                value.windowAirConditionerHeightMeters
            ),
            keepScreenAwakeDuringSpatialScan: changed(
                base.keepScreenAwakeDuringSpatialScan,
                value.keepScreenAwakeDuringSpatialScan
            ),
            spatialScanPerformanceProfile: changed(
                base.spatialScanPerformanceProfile,
                value.spatialScanPerformanceProfile
            ),
            spatialScanContentMode: changed(
                base.spatialScanContentMode,
                value.spatialScanContentMode
            ),
            spatialScanThermalProtectionMode: changed(
                base.spatialScanThermalProtectionMode,
                value.spatialScanThermalProtectionMode
            ),
            thermalResumeStabilityDuration: changed(
                base.thermalResumeStabilityDuration,
                value.thermalResumeStabilityDuration
            ),
            showThermalStateDuringSpatialScan: changed(
                base.showThermalStateDuringSpatialScan,
                value.showThermalStateDuringSpatialScan
            ),
            spatialRelocalizationStrictness: changed(
                base.spatialRelocalizationStrictness,
                value.spatialRelocalizationStrictness
            ),
            useOptionalLocationAssistForResume: changed(
                base.useOptionalLocationAssistForResume,
                value.useOptionalLocationAssistForResume
            )
        )
    }

    private static func changed<T: Equatable>(_ base: T, _ value: T) -> T? {
        base == value ? nil : value
    }
}

struct ProjectAppDefaults: Codable, Equatable {
    var schemaVersion: Int
    var electrical: ElectricalPlacementSettings
    var recoveryPolicy: RecoveryPolicy
    var layerStates: [ProjectLayerState]

    init(
        electrical: ElectricalPlacementSettings,
        recoveryPolicy: RecoveryPolicy = .standard,
        layerStates: [ProjectLayerState] = ProjectLayerState.standardStates
    ) {
        schemaVersion = 1
        self.electrical = electrical
        self.recoveryPolicy = recoveryPolicy
        self.layerStates = ProjectLayerState.normalized(layerStates)
    }

    static let standard = ProjectAppDefaults(electrical: .standard)
}

struct ProjectSettings: Codable, Equatable {
    var electrical: ElectricalPlacementOverrides?
    var recoveryPolicy: RecoveryPolicyOverrides?

    var usesInheritedElectricalSettings: Bool {
        electrical?.isEmpty != false
    }
}

struct RoomSettings: Codable, Identifiable, Equatable {
    let id: UUID
    var displayName: String?
    var electrical: ElectricalPlacementOverrides?
    var ceilingHeightMeters: Double?
    var wallThicknessMeters: Double?

    init(
        id: UUID,
        displayName: String? = nil,
        electrical: ElectricalPlacementOverrides? = nil,
        ceilingHeightMeters: Double? = nil,
        wallThicknessMeters: Double? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.electrical = electrical
        self.ceilingHeightMeters = ceilingHeightMeters
        self.wallThicknessMeters = wallThicknessMeters
    }
}

struct ElementSettingsOverride: Codable, Identifiable, Equatable {
    let id: UUID
    var scanID: UUID?
    var elementID: UUID
    var electrical: ElectricalPlacementOverrides?
    var isVisible: Bool?
    var isLocked: Bool?

    init(
        id: UUID = UUID(),
        scanID: UUID? = nil,
        elementID: UUID,
        electrical: ElectricalPlacementOverrides? = nil,
        isVisible: Bool? = nil,
        isLocked: Bool? = nil
    ) {
        self.id = id
        self.scanID = scanID
        self.elementID = elementID
        self.electrical = electrical
        self.isVisible = isVisible
        self.isLocked = isLocked
    }
}

enum SettingsInheritanceEngine {
    static func electrical(
        appDefaults: ProjectAppDefaults,
        project: ProjectSettings?,
        room: RoomSettings? = nil,
        element: ElementSettingsOverride? = nil
    ) -> ElectricalPlacementSettings {
        var result = appDefaults.electrical
        if let override = project?.electrical {
            result = override.applying(to: result)
        }
        if let override = room?.electrical {
            result = override.applying(to: result)
        }
        if let override = element?.electrical {
            result = override.applying(to: result)
        }
        return result
    }

    static func recoveryPolicy(
        appDefaults: ProjectAppDefaults,
        project: ProjectSettings?
    ) -> RecoveryPolicy {
        project?.recoveryPolicy?.applying(to: appDefaults.recoveryPolicy)
            ?? appDefaults.recoveryPolicy
    }
}

enum ProjectLayerKind: String, Codable, CaseIterable, Identifiable {
    case originalScan
    case architecturalCorrections
    case existingElectrical
    case proposedElectrical
    case ceilingLighting
    case photosAndMaterials
    case furnitureAndDesign
    case dimensionsAndAnnotations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .originalScan: "المسح الأصلي"
        case .architecturalCorrections: "التصحيحات المعمارية"
        case .existingElectrical: "الكهرباء الموجودة"
        case .proposedElectrical: "الكهرباء المقترحة"
        case .ceilingLighting: "إضاءة السقف"
        case .photosAndMaterials: "الصور والخامات"
        case .furnitureAndDesign: "الفرش والتصميم"
        case .dimensionsAndAnnotations: "الأبعاد والملاحظات"
        }
    }

    var systemImage: String {
        switch self {
        case .originalScan: "viewfinder"
        case .architecturalCorrections: "building.2.crop.circle"
        case .existingElectrical: "bolt.circle.fill"
        case .proposedElectrical: "bolt.badge.clock.fill"
        case .ceilingLighting: "light.recessed"
        case .photosAndMaterials: "photo.on.rectangle.angled"
        case .furnitureAndDesign: "chair.lounge.fill"
        case .dimensionsAndAnnotations: "ruler.fill"
        }
    }
}

struct ProjectLayerState: Codable, Identifiable, Equatable {
    var id: ProjectLayerKind { kind }
    var kind: ProjectLayerKind
    var isVisible: Bool
    var isLocked: Bool
    var opacity: Double

    init(
        kind: ProjectLayerKind,
        isVisible: Bool = true,
        isLocked: Bool = false,
        opacity: Double = 1
    ) {
        self.kind = kind
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.opacity = min(max(opacity, 0), 1)
    }

    static let standardStates: [ProjectLayerState] =
        ProjectLayerKind.allCases.map { kind in
            ProjectLayerState(
                kind: kind,
                isVisible: true,
                isLocked: kind == .originalScan,
                opacity: 1
            )
        }

    static func normalized(_ states: [ProjectLayerState]) -> [ProjectLayerState] {
        let stateByKind = Dictionary(
            states.map { ($0.kind, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        return ProjectLayerKind.allCases.map { kind in
            var state = stateByKind[kind]
                ?? standardStates.first { $0.kind == kind }
                ?? ProjectLayerState(kind: kind)
            state.opacity = min(max(state.opacity, 0), 1)
            return state
        }
    }
}

enum ProjectChangeAction: String, Codable, CaseIterable, Identifiable {
    case add
    case modify
    case delete
    case replace
    case confirmExisting
    case markMissing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .add: "إضافة"
        case .modify: "تعديل"
        case .delete: "حذف"
        case .replace: "استبدال"
        case .confirmExisting: "تأكيد الوجود"
        case .markMissing: "غير موجود أثناء المراجعة"
        }
    }
}

enum ProjectEntityKind: String, Codable, CaseIterable, Identifiable {
    case electricalElement
    case architecturalElement
    case wallPhoto
    case material
    case furniture
    case scan
    case projectSetting
    case layer
    case other

    var id: String { rawValue }
}

struct ProjectChangeRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var action: ProjectChangeAction
    var entityKind: ProjectEntityKind
    var entityID: UUID?
    var scanID: UUID?
    var previousState: Data?
    var newState: Data?
    var note: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        action: ProjectChangeAction,
        entityKind: ProjectEntityKind,
        entityID: UUID? = nil,
        scanID: UUID? = nil,
        previousState: Data? = nil,
        newState: Data? = nil,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.action = action
        self.entityKind = entityKind
        self.entityID = entityID
        self.scanID = scanID
        self.previousState = previousState
        self.newState = newState
        self.note = note
        self.createdAt = createdAt
    }
}

enum ProjectChangeSetStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case applied
    case reverted
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: "قيد العمل"
        case .applied: "تم الاعتماد"
        case .reverted: "تم التراجع"
        case .cancelled: "ملغاة"
        }
    }
}

enum ProjectWorkspaceMode: String, Codable, CaseIterable, Identifiable {
    case presentation
    case elementUpdate
    case architecturalUpdate
    case continueScan
    case floorEditor
    case furnitureDesign
    case photosAndMaterials
    case history
    case sharing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .presentation: "العرض"
        case .elementUpdate: "تحديث العناصر"
        case .architecturalUpdate: "التحديث المعماري"
        case .continueScan: "استكمال المسح"
        case .floorEditor: "محرر الدور"
        case .furnitureDesign: "الفرش والتصميم"
        case .photosAndMaterials: "الصور والخامات"
        case .history: "سجل التعديلات"
        case .sharing: "المشاركة وQR"
        }
    }

    var systemImage: String {
        switch self {
        case .presentation: "eye.fill"
        case .elementUpdate: "square.and.pencil"
        case .architecturalUpdate: "building.2.fill"
        case .continueScan: "camera.viewfinder"
        case .floorEditor: "square.grid.3x3.topleft.filled"
        case .furnitureDesign: "chair.lounge.fill"
        case .photosAndMaterials: "photo.on.rectangle.angled"
        case .history: "clock.arrow.circlepath"
        case .sharing: "qrcode"
        }
    }

    var implementationBuild: Int {
        switch self {
        case .presentation: 50
        case .elementUpdate: 47
        case .architecturalUpdate: 48
        case .continueScan: 46
        case .floorEditor: 49
        case .furnitureDesign: 51
        case .photosAndMaterials: 45
        case .history: 45
        case .sharing: 52
        }
    }
}

struct ProjectChangeSet: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var mode: ProjectWorkspaceMode
    var notes: String?
    let createdAt: Date
    var updatedAt: Date
    var status: ProjectChangeSetStatus
    var changes: [ProjectChangeRecord]
    var recoverySnapshotID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        mode: ProjectWorkspaceMode,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        status: ProjectChangeSetStatus = .draft,
        changes: [ProjectChangeRecord] = [],
        recoverySnapshotID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.changes = changes
        self.recoverySnapshotID = recoverySnapshotID
    }
}

struct RecoverySnapshotMetadata: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var reason: String
    var fileName: String
    var linkedChangeSetID: UUID?
    var byteCount: Int
    var scanCount: Int?

    init(
        id: UUID,
        createdAt: Date,
        reason: String,
        fileName: String,
        linkedChangeSetID: UUID?,
        byteCount: Int,
        scanCount: Int? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.reason = reason
        self.fileName = fileName
        self.linkedChangeSetID = linkedChangeSetID
        self.byteCount = byteCount
        self.scanCount = scanCount
    }
}

struct ProjectWorldMapScanStatus: Identifiable, Equatable {
    let id: UUID
    var scanName: String
    var isAvailable: Bool
    var savedAt: Date?
}

struct ProjectWorldMapSummary: Equatable {
    var scans: [ProjectWorldMapScanStatus]

    var availableCount: Int { scans.filter(\.isAvailable).count }
    var totalCount: Int { scans.count }
    var latestSavedAt: Date? { scans.compactMap(\.savedAt).max() }
}

extension SurveyProject {
    mutating func normalizeFoundation(appDefaults: ProjectAppDefaults) {
        foundationSchemaVersion = max(foundationSchemaVersion ?? 0, 1)

        if projectSettings == nil {
            let legacyOverride = ElectricalPlacementOverrides.difference(
                from: appDefaults.electrical,
                to: settings
            )
            projectSettings = ProjectSettings(
                electrical: legacyOverride.isEmpty ? nil : legacyOverride,
                recoveryPolicy: nil
            )
        }

        roomSettings = roomSettings ?? []
        elementOverrides = elementOverrides ?? []
        layerStates = ProjectLayerState.normalized(
            layerStates ?? appDefaults.layerStates
        )
        changeSets = changeSets ?? []
        recoverySnapshots = recoverySnapshots ?? []
        preferredWorkspaceMode = preferredWorkspaceMode ?? .presentation

        settings = SettingsInheritanceEngine.electrical(
            appDefaults: appDefaults,
            project: projectSettings
        )
    }

    func effectiveElectricalSettings(
        appDefaults: ProjectAppDefaults,
        scanID: UUID? = nil,
        elementID: UUID? = nil
    ) -> ElectricalPlacementSettings {
        let room = scanID.flatMap { id in
            roomSettings?.first { $0.id == id }
        }
        let element = elementID.flatMap { id in
            elementOverrides?.first {
                $0.elementID == id
                    && (scanID == nil || $0.scanID == scanID)
            }
        }
        return SettingsInheritanceEngine.electrical(
            appDefaults: appDefaults,
            project: projectSettings,
            room: room,
            element: element
        )
    }

    func layerState(_ kind: ProjectLayerKind) -> ProjectLayerState {
        layerStates?.first { $0.kind == kind }
            ?? ProjectLayerState.standardStates.first { $0.kind == kind }
            ?? ProjectLayerState(kind: kind)
    }
}
