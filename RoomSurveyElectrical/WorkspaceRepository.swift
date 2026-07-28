import Combine
import Foundation

enum GlobalSettingsRepository {
    private static let legacyElectricalKey =
        "3ERoomElectrical.globalElectricalSettings.v1"
    private static let appDefaultsKey =
        "3ERoomElectrical.projectAppDefaults.v1"

    static func loadAppDefaults() -> ProjectAppDefaults {
        if let data = UserDefaults.standard.data(forKey: appDefaultsKey),
           let defaults = try? JSONDecoder().decode(
               ProjectAppDefaults.self,
               from: data
           ) {
            return ProjectAppDefaults(
                electrical: defaults.electrical,
                recoveryPolicy: defaults.recoveryPolicy,
                layerStates: defaults.layerStates
            )
        }

        if let data = UserDefaults.standard.data(forKey: legacyElectricalKey),
           let settings = try? JSONDecoder().decode(
               ElectricalPlacementSettings.self,
               from: data
           ) {
            return ProjectAppDefaults(electrical: settings)
        }

        return .standard
    }

    static func saveAppDefaults(_ defaults: ProjectAppDefaults) {
        let normalized = ProjectAppDefaults(
            electrical: defaults.electrical,
            recoveryPolicy: defaults.recoveryPolicy,
            layerStates: defaults.layerStates
        )
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        UserDefaults.standard.set(data, forKey: appDefaultsKey)
        saveLegacyElectrical(normalized.electrical)
    }

    static func load() -> ElectricalPlacementSettings {
        loadAppDefaults().electrical
    }

    static func save(_ settings: ElectricalPlacementSettings) {
        var defaults = loadAppDefaults()
        defaults.electrical = settings
        saveAppDefaults(defaults)
    }

    private static func saveLegacyElectrical(
        _ settings: ElectricalPlacementSettings
    ) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: legacyElectricalKey)
    }
}

enum WorkspaceRepository {
    enum RepositoryError: LocalizedError {
        case documentsDirectoryUnavailable
        case projectNotFound
        case invalidName
        case invalidDestination
        case operationNotAllowed
        case recoverySnapshotNotFound
        case changeSetNotFound

        var errorDescription: String? {
            switch self {
            case .documentsDirectoryUnavailable:
                "تعذر الوصول إلى مجلد المستندات."
            case .projectNotFound:
                "لم يتم العثور على المشروع المطلوب."
            case .invalidName:
                "اكتب اسمًا صحيحًا قبل الحفظ."
            case .invalidDestination:
                "لا يمكن النقل إلى المكان المحدد."
            case .operationNotAllowed:
                "لا يمكن تنفيذ العملية في الحالة الحالية."
            case .recoverySnapshotNotFound:
                "نقطة الاستعادة المطلوبة غير موجودة أو لم تعد متاحة."
            case .changeSetNotFound:
                "جلسة التعديل المطلوبة غير موجودة."
            }
        }
    }

    private static let fileManager = FileManager.default

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var recoveryRoomEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return encoder
    }

    private static var recoveryRoomDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return decoder
    }

    private struct RecoveryPayload {
        let project: SurveyProject
        let rooms: [RoomProject]
    }

    private static var projectsDirectory: URL {
        get throws {
            do {
                try ApplicationFileLayout.prepare()
                return try ApplicationFileLayout.workspaceProjectsDirectory
            } catch {
                throw RepositoryError.documentsDirectoryUnavailable
            }
        }
    }

    static func createProject(
        name: String,
        kind: SurveyProjectKind,
        settings: ElectricalPlacementSettings
    ) throws -> SurveyProject {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw RepositoryError.invalidName }

        var project = SurveyProject(
            name: cleanName,
            kind: kind,
            settings: settings
        )
        project.normalizeFoundation(
            appDefaults: GlobalSettingsRepository.loadAppDefaults()
        )
        try save(project)
        return project
    }

    static func loadAll() -> [SurveyProject] {
        var projects = loadStoredProjects()
        projects = importUnlinkedLegacyScans(into: projects)
        return projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func load(projectID: UUID) -> SurveyProject? {
        loadAll().first { $0.id == projectID }
    }

    static func save(_ project: SurveyProject) throws {
        var normalizedProject = project
        normalizedProject.normalizeFoundation(
            appDefaults: GlobalSettingsRepository.loadAppDefaults()
        )
        let directory = try directory(
            for: normalizedProject.id,
            create: true
        )
        let data = try encoder.encode(normalizedProject)
        try data.write(
            to: directory.appendingPathComponent("workspace.json"),
            options: .atomic
        )
    }

    static func addItem(
        projectID: UUID,
        parentID: UUID?,
        name: String,
        kind: WorkspaceItemKind
    ) throws -> SurveyProject {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw RepositoryError.invalidName }
        guard var project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }

        project.items.append(
            WorkspaceItem(parentID: parentID, name: cleanName, kind: kind)
        )
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func attachScan(
        _ roomProject: RoomProject,
        to destination: ScanDestination
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: destination.surveyProjectID) else {
            throw RepositoryError.projectNotFound
        }

        if let index = project.scans.firstIndex(where: { $0.id == roomProject.id }) {
            project.scans[index].parentID = destination.parentItemID
            project.scans[index].name = roomProject.name
        } else {
            project.scans.append(
                ScanReference(roomProject: roomProject, parentID: destination.parentItemID)
            )
        }
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func updateSettings(
        projectID: UUID,
        settings: ElectricalPlacementSettings
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        let appDefaults = GlobalSettingsRepository.loadAppDefaults()
        let override = ElectricalPlacementOverrides.difference(
            from: appDefaults.electrical,
            to: settings
        )
        var projectSettings = project.projectSettings ?? ProjectSettings()
        projectSettings.electrical = override.isEmpty ? nil : override
        project.projectSettings = projectSettings
        project.settings = SettingsInheritanceEngine.electrical(
            appDefaults: appDefaults,
            project: projectSettings
        )
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func resetProjectElectricalSettings(
        projectID: UUID
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        let appDefaults = GlobalSettingsRepository.loadAppDefaults()
        var projectSettings = project.projectSettings ?? ProjectSettings()
        projectSettings.electrical = nil
        project.projectSettings = projectSettings
        project.settings = appDefaults.electrical
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func updateLayerState(
        projectID: UUID,
        kind: ProjectLayerKind,
        isVisible: Bool? = nil,
        isLocked: Bool? = nil,
        opacity: Double? = nil
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        var states = ProjectLayerState.normalized(
            project.layerStates ?? ProjectLayerState.standardStates
        )
        guard let index = states.firstIndex(where: { $0.kind == kind }) else {
            throw RepositoryError.projectNotFound
        }
        if let isVisible { states[index].isVisible = isVisible }
        if let isLocked { states[index].isLocked = isLocked }
        if let opacity {
            states[index].opacity = min(max(opacity, 0), 1)
        }
        project.layerStates = states
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func updateRoomSettings(
        projectID: UUID,
        settings: RoomSettings
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              project.scans.contains(where: { $0.id == settings.id }) else {
            throw RepositoryError.projectNotFound
        }
        var roomSettings = project.roomSettings ?? []
        if let index = roomSettings.firstIndex(where: {
            $0.id == settings.id
        }) {
            roomSettings[index] = settings
        } else {
            roomSettings.append(settings)
        }
        project.roomSettings = roomSettings
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func removeRoomSettings(
        projectID: UUID,
        scanID: UUID
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        project.roomSettings?.removeAll { $0.id == scanID }
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func updateElementOverride(
        projectID: UUID,
        override: ElementSettingsOverride
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        if let scanID = override.scanID,
           !project.scans.contains(where: { $0.id == scanID }) {
            throw RepositoryError.projectNotFound
        }
        var overrides = project.elementOverrides ?? []
        if let index = overrides.firstIndex(where: {
            $0.id == override.id
        }) {
            overrides[index] = override
        } else {
            overrides.append(override)
        }
        project.elementOverrides = overrides
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func removeElementOverride(
        projectID: UUID,
        overrideID: UUID
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        project.elementOverrides?.removeAll { $0.id == overrideID }
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func effectiveElectricalSettings(
        projectID: UUID,
        scanID: UUID? = nil,
        elementID: UUID? = nil
    ) throws -> ElectricalPlacementSettings {
        guard let project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        return project.effectiveElectricalSettings(
            appDefaults: GlobalSettingsRepository.loadAppDefaults(),
            scanID: scanID,
            elementID: elementID
        )
    }

    static func setPreferredWorkspaceMode(
        projectID: UUID,
        mode: ProjectWorkspaceMode
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        project.preferredWorkspaceMode = mode
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func beginChangeSet(
        projectID: UUID,
        name: String,
        mode: ProjectWorkspaceMode,
        notes: String?
    ) throws -> SurveyProject {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw RepositoryError.invalidName }
        guard var project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }

        let changeSetID = UUID()
        let snapshot = try writeRecoverySnapshot(
            project,
            reason: "قبل جلسة: \(cleanName)",
            linkedChangeSetID: changeSetID
        )
        var snapshots = project.recoverySnapshots ?? []
        snapshots.append(snapshot)
        project.recoverySnapshots = snapshots

        var changeSets = project.changeSets ?? []
        changeSets.append(
            ProjectChangeSet(
                id: changeSetID,
                name: cleanName,
                mode: mode,
                notes: notes?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                recoverySnapshotID: snapshot.id
            )
        )
        project.changeSets = changeSets
        project.preferredWorkspaceMode = mode
        project.updatedAt = Date()
        try pruneRecoverySnapshots(in: &project)
        try save(project)
        return project
    }

    static func completeChangeSet(
        projectID: UUID,
        changeSetID: UUID
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              var changeSets = project.changeSets,
              let index = changeSets.firstIndex(where: {
                  $0.id == changeSetID
              }) else {
            throw RepositoryError.changeSetNotFound
        }
        guard changeSets[index].status == .draft else {
            throw RepositoryError.operationNotAllowed
        }
        changeSets[index].status = .applied
        changeSets[index].updatedAt = Date()
        project.changeSets = changeSets
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func appendChangeRecord(
        projectID: UUID,
        changeSetID: UUID,
        record: ProjectChangeRecord
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              var changeSets = project.changeSets,
              let index = changeSets.firstIndex(where: {
                  $0.id == changeSetID
              }) else {
            throw RepositoryError.changeSetNotFound
        }
        guard changeSets[index].status == .draft else {
            throw RepositoryError.operationNotAllowed
        }
        changeSets[index].changes.append(record)
        changeSets[index].updatedAt = Date()
        project.changeSets = changeSets
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func revertChangeSet(
        projectID: UUID,
        changeSetID: UUID
    ) throws -> SurveyProject {
        guard let current = loadStoredProject(projectID: projectID),
              let target = current.changeSets?.first(where: {
                  $0.id == changeSetID
              }) else {
            throw RepositoryError.changeSetNotFound
        }
        guard target.status == .applied || target.status == .draft,
              let snapshotID = target.recoverySnapshotID else {
            throw RepositoryError.operationNotAllowed
        }

        let laterActiveChangeExists = (current.changeSets ?? []).contains {
            $0.createdAt > target.createdAt
                && ($0.status == .draft || $0.status == .applied)
        }
        guard !laterActiveChangeExists else {
            throw RepositoryError.operationNotAllowed
        }

        let recoveryPayload = try loadRecoveryPayload(
            projectID: projectID,
            snapshotID: snapshotID,
            metadata: current.recoverySnapshots ?? []
        )
        var restored = recoveryPayload.project
        let safetySnapshot = try writeRecoverySnapshot(
            current,
            reason: "قبل التراجع عن: \(target.name)",
            linkedChangeSetID: changeSetID
        )

        var history = current.changeSets ?? []
        guard let targetIndex = history.firstIndex(where: {
            $0.id == changeSetID
        }) else {
            throw RepositoryError.changeSetNotFound
        }
        history[targetIndex].status = .reverted
        history[targetIndex].updatedAt = Date()

        restored.changeSets = history
        restored.recoverySnapshots = mergeSnapshots(
            current.recoverySnapshots ?? [],
            [safetySnapshot]
        )
        restored.preferredWorkspaceMode = .history
        restored.updatedAt = Date()
        restored.normalizeFoundation(
            appDefaults: GlobalSettingsRepository.loadAppDefaults()
        )
        try pruneRecoverySnapshots(in: &restored)
        try restoreRooms(recoveryPayload.rooms)
        try save(restored)
        return restored
    }

    static func createRecoverySnapshot(
        projectID: UUID,
        reason: String
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        let cleanReason = reason.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let snapshot = try writeRecoverySnapshot(
            project,
            reason: cleanReason.isEmpty ? "نقطة استعادة يدوية" : cleanReason,
            linkedChangeSetID: nil
        )
        var snapshots = project.recoverySnapshots ?? []
        snapshots.append(snapshot)
        project.recoverySnapshots = snapshots
        project.updatedAt = Date()
        try pruneRecoverySnapshots(in: &project)
        try save(project)
        return project
    }

    static func restoreRecoverySnapshot(
        projectID: UUID,
        snapshotID: UUID
    ) throws -> SurveyProject {
        guard let current = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        guard let targetMetadata = current.recoverySnapshots?.first(where: {
            $0.id == snapshotID
        }) else {
            throw RepositoryError.recoverySnapshotNotFound
        }

        let recoveryPayload = try loadRecoveryPayload(
            projectID: projectID,
            snapshotID: snapshotID,
            metadata: current.recoverySnapshots ?? []
        )
        var restored = recoveryPayload.project
        let safetySnapshot = try writeRecoverySnapshot(
            current,
            reason: "قبل استعادة: \(targetMetadata.reason)",
            linkedChangeSetID: nil
        )
        var history = current.changeSets ?? []
        history.append(
            ProjectChangeSet(
                name: "استعادة: \(targetMetadata.reason)",
                mode: .history,
                notes: "تمت استعادة نقطة محفوظة بتاريخ \(targetMetadata.createdAt.formatted()).",
                status: .applied,
                recoverySnapshotID: safetySnapshot.id
            )
        )
        restored.changeSets = history
        restored.recoverySnapshots = mergeSnapshots(
            current.recoverySnapshots ?? [],
            [safetySnapshot]
        )
        restored.preferredWorkspaceMode = .history
        restored.updatedAt = Date()
        restored.normalizeFoundation(
            appDefaults: GlobalSettingsRepository.loadAppDefaults()
        )
        try pruneRecoverySnapshots(in: &restored)
        try restoreRooms(recoveryPayload.rooms)
        try save(restored)
        return restored
    }

    static func worldMapSummary(
        for project: SurveyProject
    ) -> ProjectWorldMapSummary {
        let scans = project.scans.map { scan in
            guard let roomProject = ProjectRepository.load(
                projectID: scan.id
            ),
            ProjectRepository.hasWorldMap(roomProject),
            let fileName = roomProject.worldMapFile,
            let fileURL = try? ProjectRepository.fileURL(
                projectID: roomProject.id,
                fileName: fileName
            ) else {
                return ProjectWorldMapScanStatus(
                    id: scan.id,
                    scanName: scan.name,
                    isAvailable: false,
                    savedAt: nil
                )
            }
            let savedAt = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            return ProjectWorldMapScanStatus(
                id: scan.id,
                scanName: scan.name,
                isAvailable: true,
                savedAt: savedAt
            )
        }
        return ProjectWorldMapSummary(scans: scans)
    }

    static func renameProject(projectID: UUID, name: String) throws -> SurveyProject {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw RepositoryError.invalidName }
        guard var project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        project.name = cleanName
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func duplicateProject(projectID: UUID) throws -> SurveyProject {
        guard let source = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }

        var itemIDMap: [UUID: UUID] = [:]
        for item in source.items {
            itemIDMap[item.id] = UUID()
        }

        let copiedItems = source.items.map { item in
            WorkspaceItem(
                id: itemIDMap[item.id] ?? UUID(),
                parentID: item.parentID.flatMap { itemIDMap[$0] },
                name: item.name,
                kind: item.kind,
                createdAt: Date(),
                isArchived: item.isArchived
            )
        }

        var copiedScanIDs: [UUID] = []
        var scanIDMap: [UUID: UUID] = [:]
        var copiedScans: [ScanReference] = []
        do {
            for scan in source.scans {
                let copiedRoom = try ProjectRepository.duplicate(
                    projectID: scan.id,
                    name: scan.name
                )
                copiedScanIDs.append(copiedRoom.id)
                scanIDMap[scan.id] = copiedRoom.id
                copiedScans.append(
                    ScanReference(
                        roomProject: copiedRoom,
                        parentID: scan.parentID.flatMap { itemIDMap[$0] },
                        isArchived: scan.isArchived,
                        isIncludedInTakeoff: scan.isIncludedInTakeoff
                    )
                )
            }
        } catch {
            for scanID in copiedScanIDs {
                try? ProjectRepository.delete(projectID: scanID)
            }
            throw error
        }

        var copy = SurveyProject(
            name: "نسخة من \(source.name)",
            kind: source.kind,
            settings: source.settings,
            items: copiedItems,
            scans: copiedScans,
            projectSettings: source.projectSettings,
            layerStates: source.layerStates,
            preferredWorkspaceMode: source.preferredWorkspaceMode
        )
        copy.roomSettings = source.roomSettings?.compactMap { setting in
            guard let copiedID = scanIDMap[setting.id] else { return nil }
            return RoomSettings(
                id: copiedID,
                displayName: setting.displayName,
                electrical: setting.electrical,
                ceilingHeightMeters: setting.ceilingHeightMeters,
                wallThicknessMeters: setting.wallThicknessMeters
            )
        }
        copy.elementOverrides = source.elementOverrides?.map { override in
            ElementSettingsOverride(
                id: override.id,
                scanID: override.scanID.flatMap { scanIDMap[$0] },
                elementID: override.elementID,
                electrical: override.electrical,
                isVisible: override.isVisible,
                isLocked: override.isLocked
            )
        }
        copy.changeSets = []
        copy.recoverySnapshots = []
        copy.normalizeFoundation(
            appDefaults: GlobalSettingsRepository.loadAppDefaults()
        )
        try save(copy)
        return copy
    }

    static func setProjectArchived(projectID: UUID, archived: Bool) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        project.isArchived = archived
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func deleteProject(projectID: UUID) throws {
        guard let project = loadStoredProject(projectID: projectID) else {
            throw RepositoryError.projectNotFound
        }
        guard project.archived else { throw RepositoryError.operationNotAllowed }

        for scan in project.scans {
            if ProjectRepository.load(projectID: scan.id) != nil {
                try ProjectRepository.delete(projectID: scan.id)
            }
        }
        let projectDirectory = try directory(for: projectID, create: false)
        try fileManager.removeItem(at: projectDirectory)
    }

    static func renameItem(
        projectID: UUID,
        itemID: UUID,
        name: String
    ) throws -> SurveyProject {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw RepositoryError.invalidName }
        guard var project = loadStoredProject(projectID: projectID),
              let index = project.items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.projectNotFound
        }
        project.items[index].name = cleanName
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func duplicateItem(projectID: UUID, itemID: UUID) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let source = project.items.first(where: { $0.id == itemID }) else {
            throw RepositoryError.projectNotFound
        }

        let sourceIDs = project.descendantIDs(of: itemID).union([itemID])
        let sourceItems = project.items.filter { sourceIDs.contains($0.id) }
        var itemIDMap: [UUID: UUID] = [:]
        for item in sourceItems {
            itemIDMap[item.id] = UUID()
        }

        let copiedItems = sourceItems.map { item in
            let isRoot = item.id == itemID
            return WorkspaceItem(
                id: itemIDMap[item.id] ?? UUID(),
                parentID: isRoot ? source.parentID : item.parentID.flatMap { itemIDMap[$0] },
                name: isRoot ? "نسخة من \(item.name)" : item.name,
                kind: item.kind,
                createdAt: Date()
            )
        }

        var copiedScanIDs: [UUID] = []
        var copiedScans: [ScanReference] = []
        do {
            for scan in project.scans where scan.parentID.map(sourceIDs.contains) == true {
                let copiedRoom = try ProjectRepository.duplicate(projectID: scan.id, name: scan.name)
                copiedScanIDs.append(copiedRoom.id)
                copiedScans.append(
                    ScanReference(
                        roomProject: copiedRoom,
                        parentID: scan.parentID.flatMap { itemIDMap[$0] },
                        isIncludedInTakeoff: scan.isIncludedInTakeoff
                    )
                )
            }
        } catch {
            for scanID in copiedScanIDs {
                try? ProjectRepository.delete(projectID: scanID)
            }
            throw error
        }

        project.items.append(contentsOf: copiedItems)
        project.scans.append(contentsOf: copiedScans)
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func moveItem(
        projectID: UUID,
        itemID: UUID,
        destinationParentID: UUID?
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let index = project.items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.projectNotFound
        }
        let blockedIDs = project.descendantIDs(of: itemID).union([itemID])
        if let destinationParentID {
            guard project.items.contains(where: { $0.id == destinationParentID }),
                  !blockedIDs.contains(destinationParentID) else {
                throw RepositoryError.invalidDestination
            }
        }
        project.items[index].parentID = destinationParentID
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func setItemArchived(
        projectID: UUID,
        itemID: UUID,
        archived: Bool
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let index = project.items.firstIndex(where: { $0.id == itemID }) else {
            throw RepositoryError.projectNotFound
        }
        project.items[index].isArchived = archived
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func deleteItem(projectID: UUID, itemID: UUID) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let item = project.items.first(where: { $0.id == itemID }) else {
            throw RepositoryError.projectNotFound
        }
        guard item.archived else { throw RepositoryError.operationNotAllowed }

        let deletedItemIDs = project.descendantIDs(of: itemID).union([itemID])
        let deletedScans = project.scans.filter {
            $0.parentID.map(deletedItemIDs.contains) == true
        }
        for scan in deletedScans {
            if ProjectRepository.load(projectID: scan.id) != nil {
                try ProjectRepository.delete(projectID: scan.id)
            }
        }
        let deletedScanIDs = Set(deletedScans.map(\.id))
        project.items.removeAll { deletedItemIDs.contains($0.id) }
        project.scans.removeAll { deletedScanIDs.contains($0.id) }
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func renameScan(
        projectID: UUID,
        scanID: UUID,
        name: String
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let index = project.scans.firstIndex(where: { $0.id == scanID }) else {
            throw RepositoryError.projectNotFound
        }
        let roomProject = try ProjectRepository.rename(projectID: scanID, name: name)
        project.scans[index].name = roomProject.name
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func duplicateScan(projectID: UUID, scanID: UUID) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let source = project.scans.first(where: { $0.id == scanID }) else {
            throw RepositoryError.projectNotFound
        }
        let copy = try ProjectRepository.duplicate(projectID: scanID)
        project.scans.append(
            ScanReference(
                roomProject: copy,
                parentID: source.parentID,
                isIncludedInTakeoff: false
            )
        )
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func moveScan(
        projectID: UUID,
        scanID: UUID,
        destinationParentID: UUID?
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let index = project.scans.firstIndex(where: { $0.id == scanID }) else {
            throw RepositoryError.projectNotFound
        }
        if let destinationParentID,
           !project.items.contains(where: { $0.id == destinationParentID }) {
            throw RepositoryError.invalidDestination
        }
        project.scans[index].parentID = destinationParentID
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func setScanArchived(
        projectID: UUID,
        scanID: UUID,
        archived: Bool
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let index = project.scans.firstIndex(where: { $0.id == scanID }) else {
            throw RepositoryError.projectNotFound
        }
        project.scans[index].isArchived = archived
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func setScanIncludedInTakeoff(
        projectID: UUID,
        scanID: UUID,
        included: Bool
    ) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let index = project.scans.firstIndex(where: {
                  $0.id == scanID
              }) else {
            throw RepositoryError.projectNotFound
        }
        project.scans[index].isIncludedInTakeoff = included
        project.updatedAt = Date()
        try save(project)
        return project
    }

    static func deleteScan(projectID: UUID, scanID: UUID) throws -> SurveyProject {
        guard var project = loadStoredProject(projectID: projectID),
              let scan = project.scans.first(where: { $0.id == scanID }) else {
            throw RepositoryError.projectNotFound
        }
        guard scan.archived else { throw RepositoryError.operationNotAllowed }
        try ProjectRepository.delete(projectID: scanID)
        project.scans.removeAll { $0.id == scanID }
        project.updatedAt = Date()
        try save(project)
        return project
    }

    private static func recoveryDirectory(
        for projectID: UUID,
        create: Bool
    ) throws -> URL {
        let url = try directory(
            for: projectID,
            create: create
        ).appendingPathComponent("recovery", isDirectory: true)
        if create {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        } else if !fileManager.fileExists(atPath: url.path) {
            throw RepositoryError.recoverySnapshotNotFound
        }
        return url
    }

    private static func writeRecoverySnapshot(
        _ project: SurveyProject,
        reason: String,
        linkedChangeSetID: UUID?
    ) throws -> RecoverySnapshotMetadata {
        let snapshotID = UUID()
        let folderName = "snapshot-\(snapshotID.uuidString)"
        let root = try recoveryDirectory(
            for: project.id,
            create: true
        )
        let snapshotDirectory = root.appendingPathComponent(
            folderName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: snapshotDirectory,
            withIntermediateDirectories: true
        )

        do {
            let workspaceData = try encoder.encode(project)
            try workspaceData.write(
                to: snapshotDirectory.appendingPathComponent("workspace.json"),
                options: .atomic
            )

            let scansDirectory = snapshotDirectory.appendingPathComponent(
                "scans",
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: scansDirectory,
                withIntermediateDirectories: true
            )

            var byteCount = workspaceData.count
            var scanCount = 0
            for scan in project.scans {
                guard let room = ProjectRepository.load(projectID: scan.id) else {
                    throw RepositoryError.projectNotFound
                }
                let roomData = try recoveryRoomEncoder.encode(room)
                try roomData.write(
                    to: scansDirectory.appendingPathComponent(
                        "\(scan.id.uuidString).json"
                    ),
                    options: .atomic
                )
                byteCount += roomData.count
                scanCount += 1
            }

            return RecoverySnapshotMetadata(
                id: snapshotID,
                createdAt: Date(),
                reason: reason,
                fileName: folderName,
                linkedChangeSetID: linkedChangeSetID,
                byteCount: byteCount,
                scanCount: scanCount
            )
        } catch {
            try? fileManager.removeItem(at: snapshotDirectory)
            throw error
        }
    }

    private static func loadRecoveryPayload(
        projectID: UUID,
        snapshotID: UUID,
        metadata: [RecoverySnapshotMetadata]
    ) throws -> RecoveryPayload {
        guard let record = metadata.first(where: { $0.id == snapshotID }) else {
            throw RepositoryError.recoverySnapshotNotFound
        }
        let root = try recoveryDirectory(
            for: projectID,
            create: false
        )
        let snapshotDirectory = root.appendingPathComponent(
            record.fileName,
            isDirectory: true
        )
        let workspaceURL = snapshotDirectory.appendingPathComponent(
            "workspace.json"
        )
        guard fileManager.fileExists(atPath: workspaceURL.path),
              let workspaceData = try? Data(contentsOf: workspaceURL),
              let project = try? decoder.decode(
                  SurveyProject.self,
                  from: workspaceData
              ),
              project.id == projectID else {
            throw RepositoryError.recoverySnapshotNotFound
        }

        let scansDirectory = snapshotDirectory.appendingPathComponent(
            "scans",
            isDirectory: true
        )
        var rooms: [RoomProject] = []
        if let files = try? fileManager.contentsOfDirectory(
            at: scansDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for file in files where file.pathExtension.lowercased() == "json" {
                guard let data = try? Data(contentsOf: file),
                      let room = try? recoveryRoomDecoder.decode(
                          RoomProject.self,
                          from: data
                      ),
                      project.scans.contains(where: { $0.id == room.id }) else {
                    throw RepositoryError.recoverySnapshotNotFound
                }
                rooms.append(room)
            }
        }
        guard Set(rooms.map(\.id)) == Set(project.scans.map(\.id)) else {
            throw RepositoryError.recoverySnapshotNotFound
        }
        return RecoveryPayload(project: project, rooms: rooms)
    }

    private static func restoreRooms(_ rooms: [RoomProject]) throws {
        for room in rooms {
            try ProjectRepository.save(room)
        }
    }

    private static func mergeSnapshots(
        _ first: [RecoverySnapshotMetadata],
        _ second: [RecoverySnapshotMetadata]
    ) -> [RecoverySnapshotMetadata] {
        var byID: [UUID: RecoverySnapshotMetadata] = [:]
        for snapshot in first + second {
            byID[snapshot.id] = snapshot
        }
        return byID.values.sorted { $0.createdAt > $1.createdAt }
    }

    private static func pruneRecoverySnapshots(
        in project: inout SurveyProject
    ) throws {
        let appDefaults = GlobalSettingsRepository.loadAppDefaults()
        let policy = SettingsInheritanceEngine.recoveryPolicy(
            appDefaults: appDefaults,
            project: project.projectSettings
        )
        let maximumCount = max(3, min(policy.maximumSnapshotCount, 50))
        let snapshots = (project.recoverySnapshots ?? [])
            .sorted { $0.createdAt > $1.createdAt }
        guard snapshots.count > maximumCount else {
            project.recoverySnapshots = snapshots
            return
        }

        var protectedSnapshotIDs: Set<UUID> = []
        for changeSet in project.changeSets ?? []
            where changeSet.status == .draft
                || changeSet.status == .applied {
            if let snapshotID = changeSet.recoverySnapshotID {
                protectedSnapshotIDs.insert(snapshotID)
            }
        }
        var kept: [RecoverySnapshotMetadata] = []
        var removed: [RecoverySnapshotMetadata] = []
        for snapshot in snapshots {
            if protectedSnapshotIDs.contains(snapshot.id)
                || kept.count < maximumCount {
                kept.append(snapshot)
            } else {
                removed.append(snapshot)
            }
        }
        project.recoverySnapshots = kept

        if let directory = try? recoveryDirectory(
            for: project.id,
            create: false
        ) {
            for snapshot in removed {
                try? fileManager.removeItem(
                    at: directory.appendingPathComponent(snapshot.fileName)
                )
            }
        }
    }

    private static func loadStoredProjects() -> [SurveyProject] {
        guard let root = try? projectsDirectory,
              let directories = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let appDefaults = GlobalSettingsRepository.loadAppDefaults()
        return directories.compactMap { directory in
            let url = directory.appendingPathComponent("workspace.json")
            guard let data = try? Data(contentsOf: url),
                  var project = try? decoder.decode(
                      SurveyProject.self,
                      from: data
                  ) else {
                return nil
            }
            let original = project
            project.normalizeFoundation(appDefaults: appDefaults)
            if project != original {
                try? save(project)
            }
            return project
        }
    }

    private static func loadStoredProject(projectID: UUID) -> SurveyProject? {
        guard let directory = try? directory(
            for: projectID,
            create: false
        ),
        let data = try? Data(
            contentsOf: directory.appendingPathComponent("workspace.json")
        ),
        var project = try? decoder.decode(
            SurveyProject.self,
            from: data
        ) else {
            return nil
        }
        let original = project
        project.normalizeFoundation(
            appDefaults: GlobalSettingsRepository.loadAppDefaults()
        )
        if project != original {
            try? save(project)
        }
        return project
    }

    private static func importUnlinkedLegacyScans(
        into storedProjects: [SurveyProject]
    ) -> [SurveyProject] {
        var projects = storedProjects
        let linkedScanIDs = Set(projects.flatMap(\.scans).map(\.id))
        let unlinkedScans = ProjectRepository.loadAll().filter { !linkedScanIDs.contains($0.id) }
        guard !unlinkedScans.isEmpty else { return projects }

        var archive: SurveyProject
        if let index = projects.firstIndex(where: \.isImportedArchive) {
            archive = projects.remove(at: index)
        } else {
            archive = SurveyProject(
                name: "المسحات السابقة",
                kind: .other,
                settings: GlobalSettingsRepository.load(),
                isImportedArchive: true
            )
        }

        for scan in unlinkedScans {
            let roomItem = WorkspaceItem(
                parentID: nil,
                name: scan.name,
                kind: .room,
                createdAt: scan.createdAt
            )
            archive.items.append(roomItem)
            archive.scans.append(
                ScanReference(roomProject: scan, parentID: roomItem.id)
            )
        }
        archive.updatedAt = Date()
        try? save(archive)
        projects.append(archive)
        return projects
    }

    private static func directory(for projectID: UUID, create: Bool) throws -> URL {
        let url = try projectsDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
        if create {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } else if !fileManager.fileExists(atPath: url.path) {
            throw RepositoryError.projectNotFound
        }
        return url
    }
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [SurveyProject] = []

    init() {
        reload()
    }

    func reload() {
        projects = WorkspaceRepository.loadAll()
        HomeWidgetSnapshotStore.update(projects: projects)
    }

    func project(id: UUID) -> SurveyProject? {
        projects.first { $0.id == id }
    }

    var activeProjects: [SurveyProject] {
        projects.filter { !$0.archived }
    }

    var archivedProjects: [SurveyProject] {
        projects.filter(\.archived)
    }

    @discardableResult
    func createProject(
        name: String,
        kind: SurveyProjectKind,
        settings: ElectricalPlacementSettings
    ) throws -> SurveyProject {
        let project = try WorkspaceRepository.createProject(
            name: name,
            kind: kind,
            settings: settings
        )
        reload()
        return project
    }

    func addItem(
        projectID: UUID,
        parentID: UUID?,
        name: String,
        kind: WorkspaceItemKind
    ) throws {
        _ = try WorkspaceRepository.addItem(
            projectID: projectID,
            parentID: parentID,
            name: name,
            kind: kind
        )
        reload()
    }

    func updateSettings(
        projectID: UUID,
        settings: ElectricalPlacementSettings
    ) throws {
        _ = try WorkspaceRepository.updateSettings(
            projectID: projectID,
            settings: settings
        )
        reload()
    }

    func resetProjectElectricalSettings(projectID: UUID) throws {
        _ = try WorkspaceRepository.resetProjectElectricalSettings(
            projectID: projectID
        )
        reload()
    }

    func updateLayerState(
        projectID: UUID,
        kind: ProjectLayerKind,
        isVisible: Bool? = nil,
        isLocked: Bool? = nil,
        opacity: Double? = nil
    ) throws {
        _ = try WorkspaceRepository.updateLayerState(
            projectID: projectID,
            kind: kind,
            isVisible: isVisible,
            isLocked: isLocked,
            opacity: opacity
        )
        reload()
    }

    func setPreferredWorkspaceMode(
        projectID: UUID,
        mode: ProjectWorkspaceMode
    ) throws {
        _ = try WorkspaceRepository.setPreferredWorkspaceMode(
            projectID: projectID,
            mode: mode
        )
        reload()
    }

    func beginChangeSet(
        projectID: UUID,
        name: String,
        mode: ProjectWorkspaceMode,
        notes: String?
    ) throws {
        _ = try WorkspaceRepository.beginChangeSet(
            projectID: projectID,
            name: name,
            mode: mode,
            notes: notes
        )
        reload()
    }

    func completeChangeSet(
        projectID: UUID,
        changeSetID: UUID
    ) throws {
        _ = try WorkspaceRepository.completeChangeSet(
            projectID: projectID,
            changeSetID: changeSetID
        )
        reload()
    }

    func revertChangeSet(
        projectID: UUID,
        changeSetID: UUID
    ) throws {
        _ = try WorkspaceRepository.revertChangeSet(
            projectID: projectID,
            changeSetID: changeSetID
        )
        reload()
    }

    func createRecoverySnapshot(
        projectID: UUID,
        reason: String
    ) throws {
        _ = try WorkspaceRepository.createRecoverySnapshot(
            projectID: projectID,
            reason: reason
        )
        reload()
    }

    func restoreRecoverySnapshot(
        projectID: UUID,
        snapshotID: UUID
    ) throws {
        _ = try WorkspaceRepository.restoreRecoverySnapshot(
            projectID: projectID,
            snapshotID: snapshotID
        )
        reload()
    }

    func renameProject(projectID: UUID, name: String) throws {
        _ = try WorkspaceRepository.renameProject(projectID: projectID, name: name)
        reload()
    }

    func duplicateProject(projectID: UUID) throws {
        _ = try WorkspaceRepository.duplicateProject(projectID: projectID)
        reload()
    }

    func setProjectArchived(projectID: UUID, archived: Bool) throws {
        _ = try WorkspaceRepository.setProjectArchived(projectID: projectID, archived: archived)
        reload()
    }

    func deleteProject(projectID: UUID) throws {
        try WorkspaceRepository.deleteProject(projectID: projectID)
        reload()
    }

    func renameItem(projectID: UUID, itemID: UUID, name: String) throws {
        _ = try WorkspaceRepository.renameItem(projectID: projectID, itemID: itemID, name: name)
        reload()
    }

    func duplicateItem(projectID: UUID, itemID: UUID) throws {
        _ = try WorkspaceRepository.duplicateItem(projectID: projectID, itemID: itemID)
        reload()
    }

    func moveItem(projectID: UUID, itemID: UUID, destinationParentID: UUID?) throws {
        _ = try WorkspaceRepository.moveItem(
            projectID: projectID,
            itemID: itemID,
            destinationParentID: destinationParentID
        )
        reload()
    }

    func setItemArchived(projectID: UUID, itemID: UUID, archived: Bool) throws {
        _ = try WorkspaceRepository.setItemArchived(
            projectID: projectID,
            itemID: itemID,
            archived: archived
        )
        reload()
    }

    func deleteItem(projectID: UUID, itemID: UUID) throws {
        _ = try WorkspaceRepository.deleteItem(projectID: projectID, itemID: itemID)
        reload()
    }

    func renameScan(projectID: UUID, scanID: UUID, name: String) throws {
        _ = try WorkspaceRepository.renameScan(projectID: projectID, scanID: scanID, name: name)
        reload()
    }

    func duplicateScan(projectID: UUID, scanID: UUID) throws {
        _ = try WorkspaceRepository.duplicateScan(projectID: projectID, scanID: scanID)
        reload()
    }

    func moveScan(projectID: UUID, scanID: UUID, destinationParentID: UUID?) throws {
        _ = try WorkspaceRepository.moveScan(
            projectID: projectID,
            scanID: scanID,
            destinationParentID: destinationParentID
        )
        reload()
    }

    func setScanArchived(projectID: UUID, scanID: UUID, archived: Bool) throws {
        _ = try WorkspaceRepository.setScanArchived(
            projectID: projectID,
            scanID: scanID,
            archived: archived
        )
        reload()
    }

    func setScanIncludedInTakeoff(
        projectID: UUID,
        scanID: UUID,
        included: Bool
    ) throws {
        _ = try WorkspaceRepository.setScanIncludedInTakeoff(
            projectID: projectID,
            scanID: scanID,
            included: included
        )
        reload()
    }

    func deleteScan(projectID: UUID, scanID: UUID) throws {
        _ = try WorkspaceRepository.deleteScan(projectID: projectID, scanID: scanID)
        reload()
    }

    @discardableResult
    func importProjectPackage(
        _ package: PreparedProjectPackage,
        strategy: ProjectPackageImportStrategy
    ) throws -> SurveyProject {
        let project = try ProjectPackageService.importPackage(
            package,
            strategy: strategy
        )
        reload()
        return project
    }
}
