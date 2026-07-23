import Foundation

enum SurveyProjectKind: String, Codable, CaseIterable, Identifiable {
    case residential
    case villa
    case commercial
    case industrial
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .residential: "سكني"
        case .villa: "فيلا"
        case .commercial: "تجاري"
        case .industrial: "صناعي"
        case .other: "أخرى"
        }
    }

    var systemImage: String {
        switch self {
        case .residential: "building.2.fill"
        case .villa: "house.lodge.fill"
        case .commercial: "storefront.fill"
        case .industrial: "building.columns.fill"
        case .other: "folder.fill"
        }
    }
}

enum WorkspaceItemKind: String, Codable, CaseIterable, Identifiable {
    case building
    case floor
    case apartment
    case zone
    case room

    var id: String { rawValue }

    var title: String {
        switch self {
        case .building: "مبنى"
        case .floor: "دور"
        case .apartment: "شقة"
        case .zone: "منطقة"
        case .room: "غرفة"
        }
    }

    var systemImage: String {
        switch self {
        case .building: "building.2.fill"
        case .floor: "square.3.layers.3d"
        case .apartment: "door.left.hand.closed"
        case .zone: "rectangle.3.group.fill"
        case .room: "square.dashed"
        }
    }
}

enum ElectricalDesignMode: String, Codable, CaseIterable, Identifiable {
    case existing
    case newInstallation
    case shopDrawing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .existing: "موجود – As-Built"
        case .newInstallation: "تأسيس جديد"
        case .shopDrawing: "Shop Drawing"
        }
    }

    var subtitle: String {
        switch self {
        case .existing: "حفظ النقاط في مكانها الحقيقي دون ضبط تلقائي."
        case .newInstallation: "تطبيق الارتفاعات والأبعاد الافتراضية عند الإضافة."
        case .shopDrawing: "عرض الموجود والمقترح في طبقات منفصلة."
        }
    }
}

struct ElectricalPlacementSettings: Codable, Equatable {
    var switchHeightMeters: Double
    var socketHeightMeters: Double
    var wallLightHeightMeters: Double
    var switchDoorOffsetMeters: Double
    var designMode: ElectricalDesignMode
    var avoidOpenings: Bool
    var doorSuggestionMinimumMetersValue: Double?
    var doorSuggestionMaximumMetersValue: Double?
    var switchAlignmentMinimumMetersValue: Double?
    var switchAlignmentMaximumMetersValue: Double?
    var squareBoxWidthMetersValue: Double?
    var squareBoxHeightMetersValue: Double?
    var rectangularBoxWidthMetersValue: Double?
    var rectangularBoxHeightMetersValue: Double?
    var electricalMergeDistanceMetersValue: Double?
    var lowCurrentLowHeightMetersValue: Double?
    var lowCurrentHighHeightMetersValue: Double?
    var splitAirConditionerCeilingOffsetMetersValue: Double?
    var windowAirConditionerHeightMetersValue: Double?

    var doorSuggestionMinimumMeters: Double {
        get { doorSuggestionMinimumMetersValue ?? 0.20 }
        set { doorSuggestionMinimumMetersValue = max(0, newValue) }
    }

    var doorSuggestionMaximumMeters: Double {
        get { doorSuggestionMaximumMetersValue ?? 0.50 }
        set { doorSuggestionMaximumMetersValue = max(0, newValue) }
    }

    var switchAlignmentMinimumMeters: Double {
        get { switchAlignmentMinimumMetersValue ?? 0.20 }
        set { switchAlignmentMinimumMetersValue = max(0, newValue) }
    }

    var switchAlignmentMaximumMeters: Double {
        get { switchAlignmentMaximumMetersValue ?? 0.50 }
        set { switchAlignmentMaximumMetersValue = max(0, newValue) }
    }

    var squareBoxWidthMeters: Double {
        get { squareBoxWidthMetersValue ?? 0.07 }
        set { squareBoxWidthMetersValue = max(0, newValue) }
    }

    var squareBoxHeightMeters: Double {
        get { squareBoxHeightMetersValue ?? 0.07 }
        set { squareBoxHeightMetersValue = max(0, newValue) }
    }

    var rectangularBoxWidthMeters: Double {
        get { rectangularBoxWidthMetersValue ?? 0.05 }
        set { rectangularBoxWidthMetersValue = max(0, newValue) }
    }

    var rectangularBoxHeightMeters: Double {
        get { rectangularBoxHeightMetersValue ?? 0.10 }
        set { rectangularBoxHeightMetersValue = max(0, newValue) }
    }

    var electricalMergeDistanceMeters: Double {
        get { electricalMergeDistanceMetersValue ?? 0.20 }
        set { electricalMergeDistanceMetersValue = max(0, newValue) }
    }

    var lowCurrentLowHeightMeters: Double {
        get { lowCurrentLowHeightMetersValue ?? socketHeightMeters }
        set { lowCurrentLowHeightMetersValue = max(0, newValue) }
    }

    var lowCurrentHighHeightMeters: Double {
        get { lowCurrentHighHeightMetersValue ?? switchHeightMeters }
        set { lowCurrentHighHeightMetersValue = max(0, newValue) }
    }

    var splitAirConditionerCeilingOffsetMeters: Double {
        get { splitAirConditionerCeilingOffsetMetersValue ?? 0.30 }
        set { splitAirConditionerCeilingOffsetMetersValue = max(0, newValue) }
    }

    var windowAirConditionerHeightMeters: Double {
        get { windowAirConditionerHeightMetersValue ?? 1.60 }
        set { windowAirConditionerHeightMetersValue = max(0, newValue) }
    }

    static let standard = ElectricalPlacementSettings(
        switchHeightMeters: 1.20,
        socketHeightMeters: 0.50,
        wallLightHeightMeters: 1.80,
        switchDoorOffsetMeters: 0.20,
        designMode: .existing,
        avoidOpenings: true,
        doorSuggestionMinimumMetersValue: 0.20,
        doorSuggestionMaximumMetersValue: 0.50,
        switchAlignmentMinimumMetersValue: 0.20,
        switchAlignmentMaximumMetersValue: 0.50,
        squareBoxWidthMetersValue: 0.07,
        squareBoxHeightMetersValue: 0.07,
        rectangularBoxWidthMetersValue: 0.05,
        rectangularBoxHeightMetersValue: 0.10,
        electricalMergeDistanceMetersValue: 0.20,
        lowCurrentLowHeightMetersValue: 0.50,
        lowCurrentHighHeightMetersValue: 1.20,
        splitAirConditionerCeilingOffsetMetersValue: 0.30,
        windowAirConditionerHeightMetersValue: 1.60
    )
}

struct WorkspaceItem: Codable, Identifiable, Equatable {
    let id: UUID
    var parentID: UUID?
    var name: String
    let kind: WorkspaceItemKind
    let createdAt: Date
    var isArchived: Bool?

    init(
        id: UUID = UUID(),
        parentID: UUID?,
        name: String,
        kind: WorkspaceItemKind,
        createdAt: Date = Date(),
        isArchived: Bool? = nil
    ) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
        self.isArchived = isArchived
    }

    var archived: Bool { isArchived ?? false }
}

struct ScanReference: Codable, Identifiable, Equatable {
    let id: UUID
    var parentID: UUID?
    var name: String
    let createdAt: Date
    var isArchived: Bool?
    var isIncludedInTakeoff: Bool?

    init(
        roomProject: RoomProject,
        parentID: UUID?,
        isArchived: Bool? = nil,
        isIncludedInTakeoff: Bool? = nil
    ) {
        id = roomProject.id
        self.parentID = parentID
        name = roomProject.name
        createdAt = roomProject.createdAt
        self.isArchived = isArchived
        self.isIncludedInTakeoff = isIncludedInTakeoff
    }

    var archived: Bool { isArchived ?? false }
    var includedInTakeoff: Bool { isIncludedInTakeoff ?? true }
}

struct SurveyProject: Codable, Identifiable, Equatable {
    var formatVersion: Int
    let id: UUID
    var name: String
    var kind: SurveyProjectKind
    let createdAt: Date
    var updatedAt: Date
    var settings: ElectricalPlacementSettings
    var items: [WorkspaceItem]
    var scans: [ScanReference]
    var isImportedArchive: Bool
    var isArchived: Bool?

    init(
        id: UUID = UUID(),
        name: String,
        kind: SurveyProjectKind,
        settings: ElectricalPlacementSettings,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        items: [WorkspaceItem] = [],
        scans: [ScanReference] = [],
        isImportedArchive: Bool = false,
        isArchived: Bool? = nil
    ) {
        formatVersion = 1
        self.id = id
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.settings = settings
        self.items = items
        self.scans = scans
        self.isImportedArchive = isImportedArchive
        self.isArchived = isArchived
    }

    var roomCount: Int {
        items.filter { $0.kind == .room }.count
    }

    var scanCount: Int { scans.count }
    var archived: Bool { isArchived ?? false }
    var archivedItemCount: Int { items.filter(\.archived).count }
    var archivedScanCount: Int { scans.filter(\.archived).count }

    func children(of parentID: UUID?) -> [WorkspaceItem] {
        items
            .filter { $0.parentID == parentID && !$0.archived }
            .sorted {
                if $0.kind.rawValue == $1.kind.rawValue {
                    return $0.createdAt < $1.createdAt
                }
                return $0.kind.sortOrder < $1.kind.sortOrder
            }
    }

    func scans(in parentID: UUID?) -> [ScanReference] {
        scans
            .filter { $0.parentID == parentID && !$0.archived }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func item(id: UUID) -> WorkspaceItem? {
        items.first { $0.id == id }
    }

    func descendantIDs(of itemID: UUID) -> Set<UUID> {
        var result: Set<UUID> = []
        var pending = [itemID]
        while let current = pending.popLast() {
            let childIDs = items.filter { $0.parentID == current }.map(\.id)
            for childID in childIDs where !result.contains(childID) {
                result.insert(childID)
                pending.append(childID)
            }
        }
        return result
    }
}

struct ScanDestination: Identifiable, Equatable {
    let id = UUID()
    let surveyProjectID: UUID
    let parentItemID: UUID?
    let scanName: String
}

private extension WorkspaceItemKind {
    var sortOrder: Int {
        switch self {
        case .building: 0
        case .floor: 1
        case .apartment: 2
        case .zone: 3
        case .room: 4
        }
    }
}
