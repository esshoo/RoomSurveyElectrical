import Foundation
import SceneKit
import simd
import SwiftUI

enum ScanPresentationMode: String, CaseIterable, Identifiable {
    case plan2D
    case model3D

    var id: String { rawValue }
    var title: String { self == .plan2D ? "2D" : "3D" }
    var systemImage: String { self == .plan2D ? "square.grid.2x2" : "cube.fill" }
}

struct ViewerLayerVisibility: Equatable {
    var floor = true
    var walls = true
    var openings = true
    var furniture = true
    var electrical = true
    var dimensions = true
}

struct RoomViewerView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    let surveyProjectID: UUID
    @State private var project: RoomProject

    @State private var mode: ScanPresentationMode = .plan2D
    @State private var layers = ViewerLayerVisibility()
    @State private var showInformation = false
    @State private var showRename = false
    @State private var showMove = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    init(initialProject: RoomProject, surveyProjectID: UUID) {
        self.surveyProjectID = surveyProjectID
        _project = State(initialValue: initialProject)
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            switch mode {
            case .plan2D:
                Plan2DView(
                    project: $project,
                    layers: layers,
                    onProjectChanged: persistViewerProject
                )
            case .model3D:
                model3D
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                optionsMenu
            }
        }
        .safeAreaInset(edge: .bottom) {
            viewerControls
        }
        .sheet(isPresented: $showInformation) {
            ScanInformationSheet(project: project)
        }
        .sheet(isPresented: $showRename) {
            RenameSheet(title: "إعادة تسمية المسح", initialName: project.name) { name in
                do {
                    try store.renameScan(
                        projectID: surveyProjectID,
                        scanID: project.id,
                        name: name
                    )
                    reloadProject()
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showMove) {
            if let workspaceProject = store.project(id: surveyProjectID) {
                MoveDestinationSheet(
                    project: workspaceProject,
                    excludedItemIDs: [],
                    currentParentID: scanReference?.parentID
                ) { destinationID in
                    do {
                        try store.moveScan(
                            projectID: surveyProjectID,
                            scanID: project.id,
                            destinationParentID: destinationID
                        )
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                }
            }
        }
        .alert("تعذر تنفيذ العملية", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "حذف المسح نهائيًا",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("حذف نهائيًا", role: .destructive) {
                deleteScan()
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("سيتم حذف بيانات المسح وملفات JSON وUSDZ، ولا يمكن التراجع عن ذلك.")
        }
        .onAppear {
            store.reload()
            reloadProject()
        }
    }

    @ViewBuilder
    private var model3D: some View {
        if let url = try? ProjectRepository.fileURL(
            projectID: project.id,
            fileName: project.usdzFile
        ) {
            USDZRoomView(url: url, project: project, layers: layers)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Label(
                        "اسحب للتدوير • قرّب بإصبعين • اضغط مرتين لإعادة العرض",
                        systemImage: "hand.draw.fill"
                    )
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 12)
                }
        } else {
            ContentUnavailableView(
                "نموذج 3D غير موجود",
                systemImage: "cube.transparent",
                description: Text("ملف USDZ الخاص بهذا المسح غير متاح.")
            )
        }
    }

    private var viewerControls: some View {
        HStack(spacing: 12) {
            Picker("طريقة العرض", selection: $mode) {
                ForEach(ScanPresentationMode.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Menu {
                Toggle(isOn: $layers.floor) {
                    Label("الأرضية", systemImage: "square.fill")
                }
                Toggle(isOn: $layers.walls) {
                    Label("الحوائط", systemImage: "rectangle.split.3x1.fill")
                }
                Toggle(isOn: $layers.openings) {
                    Label("الأبواب والشبابيك", systemImage: "door.left.hand.open")
                }
                Toggle(isOn: $layers.furniture) {
                    Label("الأثاث", systemImage: "chair.lounge.fill")
                }
                Toggle(isOn: $layers.electrical) {
                    Label("الكهرباء", systemImage: "bolt.circle.fill")
                }
                if mode == .plan2D {
                    Toggle(isOn: $layers.dimensions) {
                        Label("الأبعاد", systemImage: "ruler.fill")
                    }
                }
            } label: {
                Image(systemName: "square.3.layers.3d")
                    .font(.headline)
                    .frame(width: 42, height: 34)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("طبقات العرض")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var optionsMenu: some View {
        Menu {
            Button {
                showInformation = true
            } label: {
                Label("معلومات المسح والحصر", systemImage: "info.circle")
            }

            Section("إدارة المسح") {
                Button {
                    showRename = true
                } label: {
                    Label("إعادة تسمية", systemImage: "pencil")
                }

                Button {
                    duplicateScan()
                } label: {
                    Label("إنشاء نسخة", systemImage: "plus.square.on.square")
                }

                Button {
                    showMove = true
                } label: {
                    Label("نقل", systemImage: "folder")
                }

                if scanIsArchived {
                    Button {
                        setScanArchived(false)
                    } label: {
                        Label("استعادة من الأرشيف", systemImage: "arrow.uturn.backward.circle")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("حذف نهائي", systemImage: "trash")
                    }
                } else {
                    Button {
                        setScanArchived(true)
                    } label: {
                        Label("أرشفة", systemImage: "archivebox")
                    }
                }
            }

            Section("تصدير الملفات الأصلية") {
                if let url = try? ProjectRepository.fileURL(
                    projectID: project.id,
                    fileName: "project.json"
                ) {
                    ShareLink(item: url) {
                        Label("المشروع والنقاط JSON", systemImage: "list.bullet.rectangle")
                    }
                }

                if let url = try? ProjectRepository.fileURL(
                    projectID: project.id,
                    fileName: project.processedJSONFile
                ) {
                    ShareLink(item: url) {
                        Label("بيانات RoomPlan JSON", systemImage: "doc.text")
                    }
                }

                if let url = try? ProjectRepository.fileURL(
                    projectID: project.id,
                    fileName: project.usdzFile
                ) {
                    ShareLink(item: url) {
                        Label("نموذج USDZ", systemImage: "cube")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var scanReference: ScanReference? {
        store.project(id: surveyProjectID)?.scans.first { $0.id == project.id }
    }

    private var scanIsArchived: Bool {
        scanReference?.archived ?? false
    }

    private func reloadProject() {
        if var updatedProject = ProjectRepository.load(projectID: project.id) {
            if let workspaceSettings = store.project(id: surveyProjectID)?.settings {
                updatedProject.electricalSettings = workspaceSettings
                try? ProjectRepository.save(updatedProject)
            }
            project = updatedProject
        }
    }

    private func persistViewerProject() {
        do {
            try ProjectRepository.save(project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func duplicateScan() {
        do {
            try store.duplicateScan(projectID: surveyProjectID, scanID: project.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setScanArchived(_ archived: Bool) {
        do {
            try store.setScanArchived(
                projectID: surveyProjectID,
                scanID: project.id,
                archived: archived
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteScan() {
        do {
            try store.deleteScan(projectID: surveyProjectID, scanID: project.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum Plan2DEditTool: String, Identifiable {
    case door
    case window
    case singleSwitch
    case socket
    case wallLight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .door: "باب"
        case .window: "شباك"
        case .singleSwitch: "مفتاح مفرد"
        case .socket: "فيش كهرباء"
        case .wallLight: "إضاءة جدارية"
        }
    }

    var systemImage: String {
        switch self {
        case .door: "door.left.hand.open"
        case .window: "rectangle.split.3x1"
        case .singleSwitch: ElectricalDeviceType.singleSwitch.systemImage
        case .socket: ElectricalDeviceType.socket.systemImage
        case .wallLight: ElectricalDeviceType.wallLight.systemImage
        }
    }

    var electricalType: ElectricalDeviceType? {
        switch self {
        case .singleSwitch: .singleSwitch
        case .socket: .socket
        case .wallLight: .wallLight
        case .door, .window: nil
        }
    }
}

private enum Plan2DAddition {
    case surface(UUID)
    case electricalPoint(UUID)
}

private enum Plan2DElementSelection: Identifiable, Equatable {
    case surface(UUID)
    case electricalPoint(UUID)

    var id: String {
        switch self {
        case .surface(let id): "surface-\(id.uuidString)"
        case .electricalPoint(let id): "point-\(id.uuidString)"
        }
    }
}

private struct NearestWallPlacement {
    let wall: WallSnapshot
    let localX: Float
    let distance: Float
}

private struct Plan2DSurfaceProjection {
    let kind: SurfaceSnapshot.Kind
    let centerX: Float
    let centerY: Float
    let width: Float
    let height: Float
}

private struct Plan2DElectricalDraft {
    let type: ElectricalDeviceType
    let placement: NearestWallPlacement
    var resolvedLocalX: Float
}

private enum Plan2DSmartPrompt {
    case nearDoor(distance: Float)
    case alignSocket(switchPointID: UUID, distance: Float)
}

private struct Plan2DView: View {
    @Binding var project: RoomProject
    let layers: ViewerLayerVisibility
    let onProjectChanged: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var rotation: Angle = .zero
    @State private var committedRotation: Angle = .zero
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var activeTool: Plan2DEditTool?
    @State private var lastAddition: Plan2DAddition?
    @State private var feedbackText: String?
    @State private var electricalDraft: Plan2DElectricalDraft?
    @State private var smartPrompt: Plan2DSmartPrompt?
    @State private var selectedElement: Plan2DElementSelection?
    @State private var draggedElement: Plan2DElementSelection?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .secondarySystemGroupedBackground)

                Canvas { context, size in
                    drawPlan(context: &context, size: size)
                }
                .contentShape(Rectangle())
                .scaleEffect(zoom)
                .rotationEffect(rotation)
                .offset(offset)
                .gesture(dragGesture)
                .highPriorityGesture(elementMoveGesture(viewSize: geometry.size))
                .simultaneousGesture(magnificationGesture)
                .simultaneousGesture(rotationGesture)
                .simultaneousGesture(
                    SpatialTapGesture(coordinateSpace: .named("plan2D")).onEnded { value in
                        if activeTool != nil {
                            placeActiveTool(at: value.location, viewSize: geometry.size)
                        } else {
                            selectedElement = element(
                                at: value.location,
                                viewSize: geometry.size
                            )
                        }
                    }
                )

                controlsOverlay
            }
            .coordinateSpace(name: "plan2D")
        }
        .clipped()
        .confirmationDialog(
            smartPromptTitle,
            isPresented: Binding(
                get: { smartPrompt != nil },
                set: {
                    if !$0 {
                        smartPrompt = nil
                        electricalDraft = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            smartPromptButtons
        } message: {
            Text(smartPromptMessage)
        }
        .sheet(item: $selectedElement) { selection in
            elementEditor(for: selection)
        }
    }

    private var controlsOverlay: some View {
        VStack(spacing: 10) {
            HStack {
                PlanLegendView(layers: layers)
                Spacer()

                if lastAddition != nil {
                    Button(action: undoLastAddition) {
                        Image(systemName: "arrow.uturn.backward")
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("التراجع عن آخر إضافة")
                }

                Button(action: resetView) {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("إعادة ضبط المخطط")
            }

            if let tool = activeTool {
                HStack(spacing: 8) {
                    Label(
                        "اضغط قرب الحائط لإضافة \(tool.title)",
                        systemImage: tool.systemImage
                    )
                    .font(.caption.weight(.semibold))
                    Spacer()
                    Button("إلغاء") {
                        activeTool = nil
                        feedbackText = nil
                    }
                    .font(.caption.weight(.semibold))
                }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            if let feedbackText {
                Label(
                    feedbackText,
                    systemImage: activeTool == nil
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(activeTool == nil ? Color.green : Color.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
            } else if activeTool == nil {
                Label(
                    "انقر على العنصر لتعديله • اضغط مطولًا واسحب لنقله",
                    systemImage: "hand.tap.fill"
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
            }

            Spacer()

            HStack {
                Spacer()
                editMenu
            }
        }
        .padding(12)
    }

    private var editMenu: some View {
        Menu {
            Section("فتحات معمارية") {
                editToolButton(.door)
                editToolButton(.window)
            }

            Section("نقاط كهربائية مقترحة") {
                editToolButton(.singleSwitch)
                editToolButton(.socket)
                editToolButton(.wallLight)
            }
        } label: {
            Label("إضافة", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 16)
                .frame(height: 44)
        }
        .buttonStyle(.borderedProminent)
    }

    private func editToolButton(_ tool: Plan2DEditTool) -> some View {
        Button {
            activeTool = tool
            feedbackText = nil
        } label: {
            Label(tool.title, systemImage: tool.systemImage)
        }
    }

    @ViewBuilder
    private var smartPromptButtons: some View {
        switch smartPrompt {
        case .nearDoor:
            Button("نعم، اتركه في المكان الذي حددته") {
                resolveDoorPrompt(keepCurrentPosition: true)
            }
            Button("لا، اضبطه على بُعد \(doorOffsetCentimeters) سم") {
                resolveDoorPrompt(keepCurrentPosition: false)
            }
            Button("إلغاء الإضافة", role: .cancel) {
                cancelSmartPlacement()
            }
        case .alignSocket:
            Button("نعم، اجعله أسفل المفتاح مباشرة") {
                resolveSwitchAlignment(align: true)
            }
            Button("لا، اتركه في مكانه") {
                resolveSwitchAlignment(align: false)
            }
            Button("إلغاء الإضافة", role: .cancel) {
                cancelSmartPlacement()
            }
        case nil:
            EmptyView()
        }
    }

    private var smartPromptTitle: String {
        switch smartPrompt {
        case .nearDoor: "العنصر قريب من الباب"
        case .alignSocket: "الفيش قريب من مفتاح"
        case nil: ""
        }
    }

    private var smartPromptMessage: String {
        switch smartPrompt {
        case .nearDoor(let distance):
            return "المسافة الحالية عن حافة الباب \(centimeters(distance)) سم. هل تريد الاحتفاظ بهذا المكان؟"
        case .alignSocket(let switchPointID, let distance):
            let switchName = project.points.first(where: { $0.id == switchPointID })?.type.title
                ?? "المفتاح"
            return "المسافة الحالية من \(switchName) هي \(centimeters(distance)) سم. هل تريد محاذاة الفيش أسفله؟"
        case nil:
            return ""
        }
    }

    private var doorOffsetCentimeters: String {
        centimeters(Float(electricalSettings.switchDoorOffsetMeters))
    }

    private var electricalSettings: ElectricalPlacementSettings {
        project.electricalSettings ?? .standard
    }

    @ViewBuilder
    private func elementEditor(for selection: Plan2DElementSelection) -> some View {
        switch selection {
        case .surface(let id):
            if let surface = project.surfaces.first(where: { $0.id == id }),
               let placement = wallPlacement(for: surface) {
                Plan2DSurfaceEditor(
                    surface: surface,
                    distanceFromWallStart: placement.localX + placement.wall.width / 2,
                    onSave: { width, height, colorHex in
                        updateSurface(
                            id: id,
                            width: width,
                            height: height,
                            colorHex: colorHex
                        )
                    },
                    onDelete: {
                        deleteElement(selection)
                    }
                )
            } else {
                ContentUnavailableView(
                    "العنصر غير متاح",
                    systemImage: "exclamationmark.triangle"
                )
            }
        case .electricalPoint(let id):
            if let point = project.points.first(where: { $0.id == id }) {
                Plan2DElectricalEditor(
                    point: point,
                    distanceFromWallStart: distanceFromWallStart(for: point),
                    onSave: { type, colorHex in
                        updateElectricalPoint(
                            id: id,
                            type: type,
                            colorHex: colorHex
                        )
                    },
                    onDelete: {
                        deleteElement(selection)
                    }
                )
            } else {
                ContentUnavailableView(
                    "العنصر غير متاح",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
    }

    private func elementMoveGesture(viewSize: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.45, maximumDistance: 14)
            .sequenced(
                before: DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .named("plan2D")
                )
            )
            .onChanged { value in
                switch value {
                case .first(true):
                    break
                case .second(true, let dragValue):
                    guard let dragValue else { return }
                    if draggedElement == nil {
                        draggedElement = element(
                            at: dragValue.startLocation,
                            viewSize: viewSize
                        )
                    }
                    if let draggedElement {
                        moveElement(
                            draggedElement,
                            to: dragValue.location,
                            viewSize: viewSize
                        )
                    }
                default:
                    break
                }
            }
            .onEnded { value in
                if case .second(true, _) = value,
                   draggedElement != nil {
                    feedbackText = "تم نقل العنصر وحفظ موضعه الجديد."
                    onProjectChanged()
                }
                draggedElement = nil
            }
    }

    private func element(
        at screenPoint: CGPoint,
        viewSize: CGSize
    ) -> Plan2DElementSelection? {
        let projection = PlanProjection(project: project, size: viewSize)
        var candidates: [(selection: Plan2DElementSelection, distance: CGFloat)] = []

        for surface in project.surfaces where isEditableSurface(surface) {
            let endpoints = surfacePlanEndpoints(surface)
            let start = transformedCanvasPoint(projection.map(endpoints.0), size: viewSize)
            let end = transformedCanvasPoint(projection.map(endpoints.1), size: viewSize)
            let distance = distanceFromPoint(screenPoint, toSegmentFrom: start, to: end)
            if distance <= 26 {
                candidates.append((.surface(surface.id), distance))
            }
        }

        for point in project.points where point.worldPosition.count >= 3 {
            let planPoint = SIMD2(point.worldPosition[0], point.worldPosition[2])
            let center = transformedCanvasPoint(projection.map(planPoint), size: viewSize)
            let distance = hypot(screenPoint.x - center.x, screenPoint.y - center.y)
            if distance <= 28 {
                candidates.append((.electricalPoint(point.id), distance))
            }
        }

        return candidates.min { $0.distance < $1.distance }?.selection
    }

    private func moveElement(
        _ selection: Plan2DElementSelection,
        to screenPoint: CGPoint,
        viewSize: CGSize
    ) {
        switch selection {
        case .surface(let id):
            guard let index = project.surfaces.firstIndex(where: { $0.id == id }),
                  let current = wallPlacement(for: project.surfaces[index]),
                  let target = wallPlacement(
                      on: current.wall,
                      at: screenPoint,
                      viewSize: viewSize
                  ) else {
                return
            }

            let surface = project.surfaces[index]
            let halfWidth = min(surface.width / 2, current.wall.width / 2)
            let localX = min(
                max(target.localX, -current.wall.width / 2 + halfWidth),
                current.wall.width / 2 - halfWidth
            )
            let matrix = simd_mul(
                current.wall.matrix,
                translationMatrix(
                    x: localX,
                    y: current.localY,
                    z: 0.01
                )
            )
            project.surfaces[index].transform = matrix.columnMajorValues

        case .electricalPoint(let id):
            guard let index = project.points.firstIndex(where: { $0.id == id }),
                  let wall = project.walls.first(where: {
                      $0.id == project.points[index].wallID
                  }),
                  let target = wallPlacement(
                      on: wall,
                      at: screenPoint,
                      viewSize: viewSize
                  ) else {
                return
            }

            let margin: Float = 0.04
            let localX = min(
                max(target.localX, -wall.width / 2 + margin),
                wall.width / 2 - margin
            )
            let groupID = project.points[index].status == .proposed
                ? project.points[index].groupID
                : nil
            let indices = project.points.indices.filter {
                $0 == index || (groupID != nil && project.points[$0].groupID == groupID)
            }
            for pointIndex in indices {
                project.points[pointIndex].localX = localX
                let world = simd_mul(
                    wall.matrix,
                    SIMD4(localX, project.points[pointIndex].localY, 0.035, 1)
                )
                project.points[pointIndex].worldPosition = [world.x, world.y, world.z]
                if project.points[pointIndex].type.usesSwitchRules {
                    project.points[pointIndex].measuredDoorOffset =
                        distanceToNearestDoorEdge(localX: localX, wall: wall)
                }
            }
        }
    }

    private func updateSurface(
        id: UUID,
        width requestedWidth: Float,
        height requestedHeight: Float,
        colorHex: String?
    ) {
        guard let index = project.surfaces.firstIndex(where: { $0.id == id }),
              let placement = wallPlacement(for: project.surfaces[index]) else {
            return
        }

        let width = min(max(requestedWidth, 0.20), max(0.20, placement.wall.width - 0.08))
        let height = min(max(requestedHeight, 0.20), placement.wall.height)
        let halfWidth = width / 2
        let localX = min(
            max(placement.localX, -placement.wall.width / 2 + halfWidth),
            placement.wall.width / 2 - halfWidth
        )
        let localY = project.surfaces[index].kind == .door
            ? -placement.wall.height / 2 + height / 2
            : min(
                max(placement.localY, -placement.wall.height / 2 + height / 2),
                placement.wall.height / 2 - height / 2
            )
        let matrix = simd_mul(
            placement.wall.matrix,
            translationMatrix(x: localX, y: localY, z: 0.01)
        )

        project.surfaces[index].width = width
        project.surfaces[index].height = height
        project.surfaces[index].transform = matrix.columnMajorValues
        project.surfaces[index].colorHex = colorHex
        project.surfaces[index].isManuallyAdded = true
        selectedElement = nil
        feedbackText = "تم حفظ مقاسات العنصر ولونه."
        onProjectChanged()
    }

    private func updateElectricalPoint(
        id: UUID,
        type: ElectricalDeviceType,
        colorHex: String?
    ) {
        guard let index = project.points.firstIndex(where: { $0.id == id }) else {
            return
        }
        var updatedPoint = project.points.remove(at: index)
        updatedPoint.type = type
        updatedPoint.colorHex = colorHex
        updatedPoint.groupID = nil
        project.normalizeElectricalGroups()
        _ = project.appendElectricalPointMergingNearby(
            updatedPoint,
            mergeDistance: Float(electricalSettings.electricalMergeDistanceMeters)
        )
        selectedElement = nil
        feedbackText = "تم حفظ نوع العنصر ولونه."
        onProjectChanged()
    }

    private func deleteElement(_ selection: Plan2DElementSelection) {
        switch selection {
        case .surface(let id):
            project.surfaces.removeAll { $0.id == id }
        case .electricalPoint(let id):
            project.points.removeAll { $0.id == id }
            project.normalizeElectricalGroups()
        }
        selectedElement = nil
        feedbackText = "تم حذف العنصر."
        onProjectChanged()
    }

    private func distanceFromWallStart(for point: ElectricalPoint) -> Float {
        guard let wall = project.walls.first(where: { $0.id == point.wallID }) else {
            return 0
        }
        return max(0, point.localX + wall.width / 2)
    }

    private func wallPlacement(
        for surface: SurfaceSnapshot
    ) -> (wall: WallSnapshot, localX: Float, localY: Float)? {
        var closest: (
            wall: WallSnapshot,
            localX: Float,
            localY: Float,
            distance: Float
        )?
        let surfaceCenter = surface.matrix.columns.3

        for wall in project.walls {
            let inverseWallMatrix = simd_inverse(wall.matrix)
            let localCenter = simd_mul(inverseWallMatrix, surfaceCenter)
            let horizontalLimit = wall.width / 2 + surface.width / 2
            let verticalLimit = wall.height / 2 + surface.height / 2

            guard abs(localCenter.x) <= horizontalLimit,
                  abs(localCenter.y) <= verticalLimit else {
                continue
            }

            let distance = abs(localCenter.z)
            guard distance <= 0.45 else {
                continue
            }

            if let current = closest, current.distance <= distance {
                continue
            }

            closest = (
                wall: wall,
                localX: localCenter.x,
                localY: localCenter.y,
                distance: distance
            )
        }

        guard let closestPlacement = closest else {
            return nil
        }
        return (
            wall: closestPlacement.wall,
            localX: closestPlacement.localX,
            localY: closestPlacement.localY
        )
    }

    private func isEditableSurface(_ surface: SurfaceSnapshot) -> Bool {
        if surface.isManuallyAdded == true { return true }
        if surface.isManuallyAdded == false { return false }
        return project.walls.contains { wall in
            let localCenter = simd_mul(
                simd_inverse(wall.matrix),
                surface.matrix.columns.3
            )
            return abs(localCenter.z - 0.01) <= 0.003
                && abs(localCenter.x) <= wall.width / 2 + surface.width / 2
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard draggedElement == nil else { return }
                offset = CGSize(
                    width: committedOffset.width - value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard draggedElement == nil else { return }
                committedOffset = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = min(max(committedZoom * value, 0.75), 6)
            }
            .onEnded { _ in
                committedZoom = zoom
            }
    }

    private var rotationGesture: some Gesture {
        RotationGesture()
            .onChanged { value in
                rotation = committedRotation + value
            }
            .onEnded { _ in
                committedRotation = rotation
            }
    }

    private func resetView() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoom = 1
            committedZoom = 1
            rotation = .zero
            committedRotation = .zero
            offset = .zero
            committedOffset = .zero
        }
    }

    private func placeActiveTool(at location: CGPoint, viewSize: CGSize) {
        guard let tool = activeTool else { return }

        guard let placement = nearestWallPlacement(at: location, viewSize: viewSize),
              placement.distance <= 44 else {
            feedbackText = "اضغط أقرب إلى خط الحائط."
            return
        }

        if let type = tool.electricalType {
            beginElectricalPlacement(type, placement: placement)
            return
        }

        guard addOpening(tool, placement: placement) else { return }
        activeTool = nil
        onProjectChanged()
    }

    private func beginElectricalPlacement(
        _ type: ElectricalDeviceType,
        placement: NearestWallPlacement
    ) {
        var draft = Plan2DElectricalDraft(
            type: type,
            placement: placement,
            resolvedLocalX: placement.localX
        )
        electricalDraft = draft

        if type.usesDoorSuggestion,
           let distance = distanceToNearestDoorEdge(
               localX: draft.resolvedLocalX,
               wall: placement.wall
           ),
           isWithin(
               distance,
               minimum: electricalSettings.doorSuggestionMinimumMeters,
               maximum: electricalSettings.doorSuggestionMaximumMeters
           ) {
            smartPrompt = .nearDoor(distance: distance)
            return
        }

        if type.usesSwitchRules,
           let snappedX = positionNearDoor(
               preferredX: draft.resolvedLocalX,
               wall: placement.wall
           ) {
            draft.resolvedLocalX = snappedX
            electricalDraft = draft
        }
        continueToSwitchAlignment(with: draft)
    }

    private func resolveDoorPrompt(keepCurrentPosition: Bool) {
        guard var draft = electricalDraft else {
            cancelSmartPlacement()
            return
        }

        if !keepCurrentPosition,
           let snappedX = positionNearDoor(
               preferredX: draft.resolvedLocalX,
               wall: draft.placement.wall
           ) {
            draft.resolvedLocalX = snappedX
        }
        electricalDraft = draft
        smartPrompt = nil
        continueToSwitchAlignment(with: draft)
    }

    private func continueToSwitchAlignment(with draft: Plan2DElectricalDraft) {
        electricalDraft = draft
        guard draft.type.usesSocketRules,
              let match = nearestSwitch(
                  to: draft.resolvedLocalX,
                  wallID: draft.placement.wall.id
              ),
              isWithin(
                  match.distance,
                  minimum: electricalSettings.switchAlignmentMinimumMeters,
                  maximum: electricalSettings.switchAlignmentMaximumMeters
              ) else {
            finalizeElectricalPlacement(draft)
            return
        }

        smartPrompt = .alignSocket(
            switchPointID: match.point.id,
            distance: match.distance
        )
    }

    private func resolveSwitchAlignment(align: Bool) {
        guard var draft = electricalDraft else {
            cancelSmartPlacement()
            return
        }

        if align,
           case .alignSocket(let switchPointID, _) = smartPrompt,
           let switchPoint = project.points.first(where: { $0.id == switchPointID }) {
            draft.resolvedLocalX = switchPoint.localX
        }
        smartPrompt = nil
        finalizeElectricalPlacement(draft)
    }

    private func finalizeElectricalPlacement(_ draft: Plan2DElectricalDraft) {
        smartPrompt = nil
        electricalDraft = nil
        guard addElectricalPoint(
            draft.type,
            placement: draft.placement,
            localX: draft.resolvedLocalX
        ) else {
            return
        }
        activeTool = nil
        onProjectChanged()
    }

    private func cancelSmartPlacement() {
        smartPrompt = nil
        electricalDraft = nil
        activeTool = nil
        feedbackText = "تم إلغاء الإضافة."
    }

    private func nearestWallPlacement(
        at screenPoint: CGPoint,
        viewSize: CGSize
    ) -> NearestWallPlacement? {
        return project.walls
            .compactMap {
                wallPlacement(on: $0, at: screenPoint, viewSize: viewSize)
            }
            .min { $0.distance < $1.distance }
    }

    private func wallPlacement(
        on wall: WallSnapshot,
        at screenPoint: CGPoint,
        viewSize: CGSize
    ) -> NearestWallPlacement? {
        let projection = PlanProjection(project: project, size: viewSize)
        let endpoints = wallPlanEndpoints(wall)
        let start = transformedCanvasPoint(
            projection.map(endpoints.0),
            size: viewSize
        )
        let end = transformedCanvasPoint(
            projection.map(endpoints.1),
            size: viewSize
        )
        let segmentX = end.x - start.x
        let segmentY = end.y - start.y
        let lengthSquared = segmentX * segmentX + segmentY * segmentY
        guard lengthSquared > 0.01 else { return nil }

        let rawProgress = (
            (screenPoint.x - start.x) * segmentX
                + (screenPoint.y - start.y) * segmentY
        ) / lengthSquared
        let progress = min(max(rawProgress, 0), 1)
        let nearestPoint = CGPoint(
            x: start.x + segmentX * progress,
            y: start.y + segmentY * progress
        )
        return NearestWallPlacement(
            wall: wall,
            localX: -wall.width / 2 + wall.width * Float(progress),
            distance: Float(hypot(
                screenPoint.x - nearestPoint.x,
                screenPoint.y - nearestPoint.y
            ))
        )
    }

    private func transformedCanvasPoint(_ point: CGPoint, size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let scaledX = (point.x - center.x) * zoom
        let scaledY = (point.y - center.y) * zoom
        let cosine = CGFloat(cos(rotation.radians))
        let sine = CGFloat(sin(rotation.radians))
        return CGPoint(
            x: center.x + scaledX * cosine - scaledY * sine + offset.width,
            y: center.y + scaledX * sine + scaledY * cosine + offset.height
        )
    }

    private func distanceFromPoint(
        _ point: CGPoint,
        toSegmentFrom start: CGPoint,
        to end: CGPoint
    ) -> CGFloat {
        let segmentX = end.x - start.x
        let segmentY = end.y - start.y
        let lengthSquared = segmentX * segmentX + segmentY * segmentY
        guard lengthSquared > 0.01 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let progress = min(
            max(
                ((point.x - start.x) * segmentX + (point.y - start.y) * segmentY)
                    / lengthSquared,
                0
            ),
            1
        )
        let nearest = CGPoint(
            x: start.x + segmentX * progress,
            y: start.y + segmentY * progress
        )
        return hypot(point.x - nearest.x, point.y - nearest.y)
    }

    private func positionNearDoor(
        preferredX: Float,
        wall: WallSnapshot
    ) -> Float? {
        guard let door = nearestDoor(to: preferredX, wall: wall) else { return nil }
        let offset = Float(electricalSettings.switchDoorOffsetMeters)
        let left = door.centerX - door.width / 2 - offset
        let right = door.centerX + door.width / 2 + offset
        let prefersRight = preferredX >= door.centerX
        let preferred = prefersRight ? right : left
        let alternate = prefersRight ? left : right
        let margin: Float = 0.04
        let minimum = -wall.width / 2 + margin
        let maximum = wall.width / 2 - margin

        if preferred >= minimum && preferred <= maximum {
            return preferred
        }
        if alternate >= minimum && alternate <= maximum {
            return alternate
        }
        return min(max(preferred, minimum), maximum)
    }

    private func distanceToNearestDoorEdge(
        localX: Float,
        wall: WallSnapshot
    ) -> Float? {
        nearestDoor(to: localX, wall: wall).map {
            distanceFrom(localX, to: $0)
        }
    }

    private func nearestDoor(
        to localX: Float,
        wall: WallSnapshot
    ) -> Plan2DSurfaceProjection? {
        surfaceProjections(on: wall)
            .filter { $0.kind == .door }
            .min {
                distanceFrom(localX, to: $0) < distanceFrom(localX, to: $1)
            }
    }

    private func distanceFrom(
        _ localX: Float,
        to surface: Plan2DSurfaceProjection
    ) -> Float {
        let leftEdge = surface.centerX - surface.width / 2
        let rightEdge = surface.centerX + surface.width / 2
        return min(abs(localX - leftEdge), abs(localX - rightEdge))
    }

    private func nearestSwitch(
        to localX: Float,
        wallID: UUID
    ) -> (point: ElectricalPoint, distance: Float)? {
        project.points
            .filter { $0.wallID == wallID && $0.type.usesSwitchRules }
            .map { point in
                (point: point, distance: abs(point.localX - localX))
            }
            .min { $0.distance < $1.distance }
    }

    private func surfaceProjections(on wall: WallSnapshot) -> [Plan2DSurfaceProjection] {
        let inverseWall = simd_inverse(wall.matrix)
        return project.surfaces.compactMap { surface in
            let localCenter = simd_mul(inverseWall, surface.matrix.columns.3)
            guard abs(localCenter.z) <= 0.30,
                  abs(localCenter.x) <= wall.width / 2 + surface.width / 2 else {
                return nil
            }
            return Plan2DSurfaceProjection(
                kind: surface.kind,
                centerX: localCenter.x,
                centerY: localCenter.y,
                width: surface.width,
                height: surface.height
            )
        }
    }

    private func isWithin(
        _ value: Float,
        minimum: Double,
        maximum: Double
    ) -> Bool {
        let lower = Float(min(minimum, maximum))
        let upper = Float(max(minimum, maximum))
        return value >= lower && value <= upper
    }

    private func addOpening(
        _ tool: Plan2DEditTool,
        placement: NearestWallPlacement
    ) -> Bool {
        let kind: SurfaceSnapshot.Kind = tool == .door ? .door : .window
        let width: Float = tool == .door ? 0.90 : 1.20
        let height: Float = tool == .door ? 2.10 : 1.20
        let centerHeight: Float = tool == .door ? height / 2 : 1.50
        let wall = placement.wall
        let minimumX = -wall.width / 2 + width / 2
        let maximumX = wall.width / 2 - width / 2

        guard minimumX <= maximumX else {
            feedbackText = "الحائط أقصر من عرض \(tool.title) الافتراضي."
            return false
        }

        let localX = min(max(placement.localX, minimumX), maximumX)
        let maximumCenterHeight = max(height / 2, wall.height - height / 2)
        let resolvedCenterHeight = min(max(centerHeight, height / 2), maximumCenterHeight)
        let localY = -wall.height / 2 + resolvedCenterHeight
        let matrix = simd_mul(
            wall.matrix,
            translationMatrix(x: localX, y: localY, z: 0.01)
        )
        let surface = SurfaceSnapshot(
            kind: kind,
            width: width,
            height: height,
            matrix: matrix
        )

        project.surfaces.append(surface)
        lastAddition = .surface(surface.id)
        feedbackText = "تمت إضافة \(tool.title) وحفظه."
        return true
    }

    private func addElectricalPoint(
        _ type: ElectricalDeviceType,
        placement: NearestWallPlacement,
        localX requestedLocalX: Float
    ) -> Bool {
        let settings = electricalSettings
        let wall = placement.wall
        let height = type.recommendedHeight(using: settings)
        let margin: Float = 0.04
        let localX = min(
            max(requestedLocalX, -wall.width / 2 + margin),
            wall.width / 2 - margin
        )
        let localY = min(
            max(-wall.height / 2 + height, -wall.height / 2 + margin),
            wall.height / 2 - margin
        )
        let measuredDoorOffset = type.usesSwitchRules
            ? distanceToNearestDoorEdge(localX: localX, wall: wall)
            : nil

        if settings.avoidOpenings,
           let opening = surfaceProjections(on: wall).first(where: {
               abs(localX - $0.centerX) <= $0.width / 2 + 0.025
                   && abs(localY - $0.centerY) <= $0.height / 2 + 0.025
           }) {
            feedbackText = "الموضع يقع داخل \(surfaceTitle(opening.kind)). اختر نقطة أخرى."
            return false
        }

        let world = simd_mul(wall.matrix, SIMD4(localX, localY, 0.035, 1))
        let point = ElectricalPoint(
            wallID: wall.id,
            type: type,
            status: .proposed,
            localX: localX,
            localY: localY,
            wallHeight: wall.height,
            worldPosition: [world.x, world.y, world.z],
            standardHeightAtCreation: height,
            standardDoorOffsetAtCreation: type.usesSwitchRules
                ? Float(settings.switchDoorOffsetMeters)
                : nil,
            measuredDoorOffset: measuredDoorOffset,
            wasAutomaticallyAdjusted: true
        )

        let merged = project.appendElectricalPointMergingNearby(
            point,
            mergeDistance: Float(settings.electricalMergeDistanceMeters)
        )
        lastAddition = .electricalPoint(point.id)
        feedbackText = merged
            ? "تمت إضافة \(type.title) ودمجه مع عنصر قريب."
            : "تمت إضافة \(type.title) على الارتفاع القياسي."
        return true
    }

    private func undoLastAddition() {
        guard let lastAddition else { return }
        switch lastAddition {
        case .surface(let id):
            project.surfaces.removeAll { $0.id == id }
        case .electricalPoint(let id):
            project.points.removeAll { $0.id == id }
            project.normalizeElectricalGroups()
        }
        self.lastAddition = nil
        feedbackText = "تم التراجع عن آخر إضافة."
        onProjectChanged()
    }

    private func centimeters(_ meters: Float) -> String {
        String(format: "%.0f", meters * 100)
    }

    private func surfaceTitle(_ kind: SurfaceSnapshot.Kind) -> String {
        switch kind {
        case .door: "فتحة الباب"
        case .window: "فتحة الشباك"
        case .opening: "الفتحة المعمارية"
        }
    }

    private func drawPlan(context: inout GraphicsContext, size: CGSize) {
        let projection = PlanProjection(project: project, size: size)
        drawGrid(context: &context, projection: projection)

        if layers.floor {
            for floor in project.floors ?? [] {
                drawFloor(floor, context: &context, projection: projection)
            }
        }

        if layers.furniture {
            for object in project.objects ?? [] {
                drawObject(object, context: &context, projection: projection)
            }
        }

        if layers.walls {
            for wall in project.walls {
                drawWall(wall, context: &context, projection: projection)
            }
        }

        if layers.openings {
            for surface in project.surfaces {
                drawSurface(surface, context: &context, projection: projection)
            }
        }

        if layers.electrical {
            for point in project.points {
                drawElectricalPoint(point, context: &context, projection: projection)
            }
        }
    }

    private func drawGrid(context: inout GraphicsContext, projection: PlanProjection) {
        let startX = Int(projection.minX.rounded(.down))
        let endX = Int(projection.maxX.rounded(.up))
        let startZ = Int(projection.minZ.rounded(.down))
        let endZ = Int(projection.maxZ.rounded(.up))

        for x in startX...endX {
            var path = Path()
            path.move(to: projection.map(SIMD2(Float(x), projection.minZ)))
            path.addLine(to: projection.map(SIMD2(Float(x), projection.maxZ)))
            context.stroke(path, with: .color(.secondary.opacity(0.12)), lineWidth: 0.7)
        }

        for z in startZ...endZ {
            var path = Path()
            path.move(to: projection.map(SIMD2(projection.minX, Float(z))))
            path.addLine(to: projection.map(SIMD2(projection.maxX, Float(z))))
            context.stroke(path, with: .color(.secondary.opacity(0.12)), lineWidth: 0.7)
        }
    }

    private func drawFloor(
        _ floor: FloorSnapshot,
        context: inout GraphicsContext,
        projection: PlanProjection
    ) {
        let corners = floorPlanCorners(floor)
        guard let first = corners.first else { return }
        var path = Path()
        path.move(to: projection.map(first))
        for point in corners.dropFirst() {
            path.addLine(to: projection.map(point))
        }
        path.closeSubpath()
        context.fill(path, with: .color(.gray.opacity(0.12)))
        context.stroke(path, with: .color(.gray.opacity(0.35)), lineWidth: 1)
    }

    private func drawWall(
        _ wall: WallSnapshot,
        context: inout GraphicsContext,
        projection: PlanProjection
    ) {
        let endpoints = wallPlanEndpoints(wall)
        var path = Path()
        path.move(to: projection.map(endpoints.0))
        path.addLine(to: projection.map(endpoints.1))
        context.stroke(
            path,
            with: .color(.blue),
            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        )

        if layers.dimensions {
            let midpoint = (endpoints.0 + endpoints.1) / 2
            let label = Text(String(format: "%.2f م", wall.width))
                .font(.caption2.weight(.semibold))
                .foregroundColor(.primary)
            context.draw(
                label,
                at: projection.map(midpoint),
                anchor: .bottom
            )
        }
    }

    private func drawSurface(
        _ surface: SurfaceSnapshot,
        context: inout GraphicsContext,
        projection: PlanProjection
    ) {
        let endpoints = surfacePlanEndpoints(surface)
        let fallback: UIColor
        switch surface.kind {
        case .door: fallback = .systemOrange
        case .window: fallback = .systemCyan
        case .opening: fallback = .systemPurple
        }
        let color = Color(uiColor: uiColor(hex: surface.colorHex, fallback: fallback))

        var path = Path()
        path.move(to: projection.map(endpoints.0))
        path.addLine(to: projection.map(endpoints.1))
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: 9, lineCap: .butt)
        )
    }

    private func drawObject(
        _ object: RoomObjectSnapshot,
        context: inout GraphicsContext,
        projection: PlanProjection
    ) {
        let corners = objectPlanCorners(object)
        guard let first = corners.first else { return }
        var path = Path()
        path.move(to: projection.map(first))
        for point in corners.dropFirst() {
            path.addLine(to: projection.map(point))
        }
        path.closeSubpath()
        context.fill(path, with: .color(.gray.opacity(0.22)))
        context.stroke(path, with: .color(.gray.opacity(0.65)), lineWidth: 1.2)

        let center = planCenter(object.matrix)
        let label = Text(object.title)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.secondary)
        context.draw(label, at: projection.map(center))
    }

    private func drawElectricalPoint(
        _ point: ElectricalPoint,
        context: inout GraphicsContext,
        projection: PlanProjection
    ) {
        guard point.worldPosition.count >= 3 else { return }
        let groupPoints: [ElectricalPoint]
        if let groupID = point.groupID, point.status == .proposed {
            groupPoints = project.points.filter { $0.groupID == groupID }
            guard groupPoints.first?.id == point.id else { return }
        } else {
            groupPoints = [point]
        }
        let center = projection.map(SIMD2(point.worldPosition[0], point.worldPosition[2]))
        let fallback: UIColor = point.status == .existing ? .systemGreen : .systemOrange
        let color = Color(uiColor: uiColor(hex: point.colorHex, fallback: fallback))
        if groupPoints.count > 1 {
            let width = CGFloat(18 + min(groupPoints.count, 6) * 5)
            let rect = CGRect(
                x: center.x - width / 2,
                y: center.y - 8,
                width: width,
                height: 16
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: 5),
                with: .color(color)
            )
            context.stroke(
                Path(roundedRect: rect, cornerRadius: 5),
                with: .color(.white),
                lineWidth: 1.5
            )
            context.draw(
                Text("\(groupPoints.count)")
                    .font(.caption2.bold())
                    .foregroundColor(.white),
                at: center
            )
        } else {
            let rect = CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)
            context.fill(Path(ellipseIn: rect), with: .color(color))
            context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
        }
    }
}

private struct Plan2DSurfaceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var widthCentimeters: Double
    @State private var heightCentimeters: Double
    @State private var color: ElementColorOption
    @State private var showDeleteConfirmation = false

    let surface: SurfaceSnapshot
    let distanceFromWallStart: Float
    let onSave: (Float, Float, String?) -> Void
    let onDelete: () -> Void

    init(
        surface: SurfaceSnapshot,
        distanceFromWallStart: Float,
        onSave: @escaping (Float, Float, String?) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.surface = surface
        self.distanceFromWallStart = distanceFromWallStart
        self.onSave = onSave
        self.onDelete = onDelete
        _widthCentimeters = State(initialValue: Double(surface.width * 100))
        _heightCentimeters = State(initialValue: Double(surface.height * 100))
        _color = State(initialValue: ElementColorOption(hexValue: surface.colorHex))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("المكان") {
                    LabeledContent(
                        "المسافة من بداية الحائط",
                        value: String(format: "%.0f سم", distanceFromWallStart * 100)
                    )
                }

                Section("الأبعاد") {
                    centimeterValueField("العرض", value: $widthCentimeters)
                    centimeterValueField("الارتفاع", value: $heightCentimeters)
                }

                Section("المظهر") {
                    ColorOptionPicker(selection: $color)
                }

                Section {
                    Button("حذف العنصر", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle(surface.kind == .door ? "خصائص الباب" : "خصائص الشباك")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        onSave(
                            Float(max(20, widthCentimeters) / 100),
                            Float(max(20, heightCentimeters) / 100),
                            color.hexValue
                        )
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "حذف العنصر؟",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("حذف", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("إلغاء", role: .cancel) {}
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func centimeterValueField(
        _ title: String,
        value: Binding<Double>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(
                "0",
                value: value,
                format: .number.precision(.fractionLength(0...1))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 82)
            Text("سم")
                .foregroundStyle(.secondary)
        }
    }
}

private struct Plan2DElectricalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var type: ElectricalDeviceType
    @State private var color: ElementColorOption
    @State private var showDeleteConfirmation = false

    let point: ElectricalPoint
    let distanceFromWallStart: Float
    let onSave: (ElectricalDeviceType, String?) -> Void
    let onDelete: () -> Void

    init(
        point: ElectricalPoint,
        distanceFromWallStart: Float,
        onSave: @escaping (ElectricalDeviceType, String?) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.point = point
        self.distanceFromWallStart = distanceFromWallStart
        self.onSave = onSave
        self.onDelete = onDelete
        _type = State(initialValue: point.type)
        _color = State(initialValue: ElementColorOption(hexValue: point.colorHex))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("المكان") {
                    LabeledContent(
                        "المسافة من بداية الحائط",
                        value: String(format: "%.0f سم", distanceFromWallStart * 100)
                    )
                    LabeledContent(
                        "الارتفاع",
                        value: String(format: "%.0f سم", point.heightFromFloor * 100)
                    )
                    if point.groupID != nil {
                        Label("هذا العنصر ضمن مجموعة مدمجة", systemImage: "square.on.square")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("نوع العنصر") {
                    Picker("العنصر", selection: $type) {
                        ForEach(ElectricalDeviceType.allCases) { item in
                            Label(item.title, systemImage: item.systemImage)
                                .tag(item)
                        }
                    }
                }

                Section("المظهر") {
                    ColorOptionPicker(selection: $color)
                }

                Section {
                    Button("حذف العنصر", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle("خصائص نقطة الكهرباء")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        onSave(type, color.hexValue)
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "حذف العنصر؟",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("حذف", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("إلغاء", role: .cancel) {}
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

private struct ColorOptionPicker: View {
    @Binding var selection: ElementColorOption

    var body: some View {
        Picker("اللون", selection: $selection) {
            ForEach(ElementColorOption.allCases) { option in
                HStack {
                    if let hex = option.hexValue {
                        Circle()
                            .fill(Color(uiColor: uiColor(hex: hex, fallback: .gray)))
                            .frame(width: 14, height: 14)
                    }
                    Text(option.title)
                }
                .tag(option)
            }
        }
    }
}

private struct PlanLegendView: View {
    let layers: ViewerLayerVisibility

    var body: some View {
        HStack(spacing: 9) {
            if layers.walls { legendDot(.blue, title: "حائط") }
            if layers.openings {
                legendDot(.orange, title: "باب")
                legendDot(.cyan, title: "شباك")
            }
            if layers.electrical { legendDot(.green, title: "كهرباء") }
        }
        .font(.caption2)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func legendDot(_ color: Color, title: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
    }
}

private struct PlanProjection {
    let minX: Float
    let maxX: Float
    let minZ: Float
    let maxZ: Float
    let size: CGSize

    init(project: RoomProject, size: CGSize) {
        var points: [SIMD2<Float>] = []
        points.append(contentsOf: project.walls.flatMap { wall in
            let endpoints = wallPlanEndpoints(wall)
            return [endpoints.0, endpoints.1]
        })
        points.append(contentsOf: (project.floors ?? []).flatMap(floorPlanCorners))
        points.append(contentsOf: (project.objects ?? []).flatMap(objectPlanCorners))
        points.append(contentsOf: project.points.compactMap { point in
            guard point.worldPosition.count >= 3 else { return nil }
            return SIMD2(point.worldPosition[0], point.worldPosition[2])
        })

        if points.isEmpty {
            points = [SIMD2(-2, -2), SIMD2(2, 2)]
        }

        let rawMinX = points.map(\.x).min() ?? -2
        let rawMaxX = points.map(\.x).max() ?? 2
        let rawMinZ = points.map(\.y).min() ?? -2
        let rawMaxZ = points.map(\.y).max() ?? 2
        let margin: Float = 0.45
        minX = rawMinX - margin
        maxX = rawMaxX + margin
        minZ = rawMinZ - margin
        maxZ = rawMaxZ + margin
        self.size = size
    }

    func map(_ point: SIMD2<Float>) -> CGPoint {
        CGPoint(
            x: size.width / 2 + CGFloat(point.x - midpointX) * projectionScale,
            y: size.height / 2 + CGFloat(point.y - midpointZ) * projectionScale
        )
    }

    func unmap(_ point: CGPoint) -> SIMD2<Float> {
        SIMD2(
            midpointX + Float((point.x - size.width / 2) / projectionScale),
            midpointZ + Float((point.y - size.height / 2) / projectionScale)
        )
    }

    private var projectionScale: CGFloat {
        let rangeX = max(maxX - minX, 0.5)
        let rangeZ = max(maxZ - minZ, 0.5)
        let padding: CGFloat = 34
        let availableWidth = max(size.width - padding * 2, 1)
        let availableHeight = max(size.height - padding * 2, 1)
        return min(
            availableWidth / CGFloat(rangeX),
            availableHeight / CGFloat(rangeZ)
        )
    }

    private var midpointX: Float { (minX + maxX) / 2 }
    private var midpointZ: Float { (minZ + maxZ) / 2 }
}

private struct USDZRoomView: UIViewRepresentable {
    let url: URL
    let project: RoomProject
    let layers: ViewerLayerVisibility

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .secondarySystemGroupedBackground
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = true
        view.rendersContinuously = true
        context.coordinator.loadScene(into: view)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.resetCamera)
        )
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateScene(in: uiView)
    }

    final class Coordinator: NSObject {
        var parent: USDZRoomView
        private var loadedURL: URL?
        private weak var sceneView: SCNView?
        private var initialCameraPosition = SCNVector3(5, 4, 5)
        private var cameraTarget = SCNVector3Zero

        init(parent: USDZRoomView) {
            self.parent = parent
        }

        func loadScene(into view: SCNView) {
            sceneView = view
            guard let scene = try? SCNScene(url: parent.url, options: nil) else {
                view.scene = SCNScene()
                return
            }
            loadedURL = parent.url
            view.scene = scene
            scene.rootNode.childNode(withName: "Section_grp", recursively: true)?.isHidden = true
            addElectricalMarkers(to: scene)
            addManualOpenings(to: scene)
            configureCamera(for: scene, in: view)
            applyLayerVisibility(to: scene)
        }

        func updateScene(in view: SCNView) {
            if loadedURL != parent.url {
                loadScene(into: view)
                return
            }
            guard let scene = view.scene else { return }
            addElectricalMarkers(to: scene)
            addManualOpenings(to: scene)
            applyLayerVisibility(to: scene)
        }

        private func configureCamera(for scene: SCNScene, in view: SCNView) {
            let bounds = scene.rootNode.boundingBox
            let center = SCNVector3(
                (bounds.min.x + bounds.max.x) / 2,
                (bounds.min.y + bounds.max.y) / 2,
                (bounds.min.z + bounds.max.z) / 2
            )
            let extentX = bounds.max.x - bounds.min.x
            let extentY = bounds.max.y - bounds.min.y
            let extentZ = bounds.max.z - bounds.min.z
            let largest = max(max(extentX, extentY), max(extentZ, 1))

            let camera = SCNCamera()
            camera.fieldOfView = 52
            camera.zNear = 0.01
            camera.zFar = Double(max(largest * 30, 100))

            let cameraNode = SCNNode()
            cameraNode.name = "3e-viewer-camera"
            cameraNode.camera = camera
            initialCameraPosition = SCNVector3(
                center.x + largest * 1.35,
                center.y + largest * 1.05,
                center.z + largest * 1.35
            )
            cameraTarget = center
            cameraNode.position = initialCameraPosition
            cameraNode.look(at: center)
            scene.rootNode.addChildNode(cameraNode)
            view.pointOfView = cameraNode
        }

        private func addElectricalMarkers(to scene: SCNScene) {
            scene.rootNode.childNode(withName: "3e-electrical-markers", recursively: false)?
                .removeFromParentNode()

            let root = SCNNode()
            root.name = "3e-electrical-markers"
            root.isHidden = !parent.layers.electrical
            scene.rootNode.addChildNode(root)

            for point in parent.project.points where point.worldPosition.count >= 3 {
                let sphere = SCNSphere(radius: 0.055)
                let material = SCNMaterial()
                let fallback: UIColor = point.status == .existing ? .systemGreen : .systemOrange
                let color = uiColor(hex: point.colorHex, fallback: fallback)
                material.diffuse.contents = color
                material.emission.contents = color.withAlphaComponent(0.3)
                sphere.materials = [material]

                let node = SCNNode(geometry: sphere)
                node.position = SCNVector3(
                    point.worldPosition[0],
                    point.worldPosition[1],
                    point.worldPosition[2]
                )
                root.addChildNode(node)
            }
        }

        private func addManualOpenings(to scene: SCNScene) {
            scene.rootNode.childNode(withName: "3e-manual-openings", recursively: false)?
                .removeFromParentNode()

            let root = SCNNode()
            root.name = "3e-manual-openings"
            root.isHidden = !parent.layers.openings
            scene.rootNode.addChildNode(root)

            for surface in parent.project.surfaces where shouldRenderManualSurface(surface) {
                let fallback: UIColor = surface.kind == .door ? .systemOrange : .systemCyan
                let color = uiColor(hex: surface.colorHex, fallback: fallback)
                let frame = openingFrameNode(surface: surface, color: color)
                root.addChildNode(frame)
            }
        }

        private func shouldRenderManualSurface(_ surface: SurfaceSnapshot) -> Bool {
            if surface.isManuallyAdded == true { return true }
            if surface.isManuallyAdded == false { return false }
            return parent.project.walls.contains { wall in
                let localCenter = simd_mul(
                    simd_inverse(wall.matrix),
                    surface.matrix.columns.3
                )
                return abs(localCenter.z - 0.01) <= 0.003
                    && abs(localCenter.x) <= wall.width / 2 + surface.width / 2
            }
        }

        private func openingFrameNode(
            surface: SurfaceSnapshot,
            color: UIColor
        ) -> SCNNode {
            let root = SCNNode()
            root.name = "3e-opening-\(surface.id.uuidString)"
            root.simdTransform = surface.matrix
            let barThickness: CGFloat = 0.045
            let depth: CGFloat = 0.035
            let width = CGFloat(surface.width)
            let height = CGFloat(surface.height)

            func addBar(
                width barWidth: CGFloat,
                height barHeight: CGFloat,
                x: Float,
                y: Float
            ) {
                let geometry = SCNBox(
                    width: barWidth,
                    height: barHeight,
                    length: depth,
                    chamferRadius: 0.008
                )
                let material = SCNMaterial()
                material.diffuse.contents = color
                material.emission.contents = color.withAlphaComponent(0.25)
                geometry.materials = [material]
                let node = SCNNode(geometry: geometry)
                node.position = SCNVector3(x, y, 0)
                root.addChildNode(node)
            }

            addBar(
                width: barThickness,
                height: height,
                x: -surface.width / 2,
                y: 0
            )
            addBar(
                width: barThickness,
                height: height,
                x: surface.width / 2,
                y: 0
            )
            addBar(
                width: width,
                height: barThickness,
                x: 0,
                y: surface.height / 2
            )
            if surface.kind != .door {
                addBar(
                    width: width,
                    height: barThickness,
                    x: 0,
                    y: -surface.height / 2
                )
            }
            return root
        }

        private func applyLayerVisibility(to scene: SCNScene) {
            let showArchitecture = parent.layers.walls || parent.layers.openings
            scene.rootNode.childNode(withName: "Arch_grp", recursively: true)?.isHidden = !showArchitecture
            scene.rootNode.childNode(withName: "Floor_grp", recursively: true)?.isHidden = !parent.layers.floor
            scene.rootNode.childNode(withName: "Object_grp", recursively: true)?.isHidden = !parent.layers.furniture
            scene.rootNode.childNode(withName: "3e-electrical-markers", recursively: false)?.isHidden = !parent.layers.electrical
            scene.rootNode.childNode(withName: "3e-manual-openings", recursively: false)?.isHidden = !parent.layers.openings
        }

        @objc func resetCamera() {
            guard let cameraNode = sceneView?.pointOfView else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.3
            cameraNode.position = initialCameraPosition
            cameraNode.look(at: cameraTarget)
            SCNTransaction.commit()
        }
    }
}

private struct ScanInformationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let project: RoomProject

    var body: some View {
        NavigationStack {
            List {
                Section("ملخص المسح") {
                    LabeledContent("الحوائط", value: "\(project.wallCount)")
                    LabeledContent("الأبواب", value: "\(project.doorCount)")
                    LabeledContent("الشبابيك", value: "\(project.windowCount)")
                    LabeledContent("قطع الأثاث", value: "\(project.furnitureCount)")
                    LabeledContent("نقاط الكهرباء", value: "\(project.points.count)")
                    if let settings = project.electricalSettings {
                        LabeledContent("نمط الكهرباء", value: settings.designMode.title)
                    }
                }

                Section("الحصر الكهربائي") {
                    if project.boq.isEmpty {
                        Text("لم تتم إضافة نقاط كهرباء.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(project.boq) { line in
                            HStack {
                                Label(line.type.title, systemImage: line.type.systemImage)
                                Spacer()
                                Text("\(line.count) • \(line.status.title)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !project.points.isEmpty {
                    Section("مراجعة المقاسات") {
                        ForEach(project.points) { point in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label(point.type.title, systemImage: point.type.systemImage)
                                    Spacer()
                                    Text(String(format: "%.2f م", point.heightFromFloor))
                                        .monospacedDigit()
                                }

                                Text(measurementSummary(for: point))
                                    .font(.caption)
                                    .foregroundStyle(measurementColor(for: point))

                                if point.type.usesSwitchRules,
                                   let doorOffset = point.measuredDoorOffset {
                                    Text(
                                        "البعد عن الباب: \(String(format: "%.0f", doorOffset * 100)) سم"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("معلومات المسح")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var electricalSettings: ElectricalPlacementSettings {
        project.electricalSettings ?? .standard
    }

    private func targetHeight(for point: ElectricalPoint) -> Float {
        point.standardHeightAtCreation
            ?? point.type.recommendedHeight(using: electricalSettings)
    }

    private func measurementSummary(for point: ElectricalPoint) -> String {
        let differenceCentimeters = (point.heightFromFloor - targetHeight(for: point)) * 100
        if abs(differenceCentimeters) <= 2 {
            return point.wasAutomaticallyAdjusted == true
                ? "مطابق للقياسي • ضبط تلقائي"
                : "مطابق للارتفاع القياسي"
        }
        if differenceCentimeters > 0 {
            return "أعلى من القياسي بـ \(String(format: "%.0f", differenceCentimeters)) سم"
        }
        return "أقل من القياسي بـ \(String(format: "%.0f", abs(differenceCentimeters))) سم"
    }

    private func measurementColor(for point: ElectricalPoint) -> Color {
        abs(point.heightFromFloor - targetHeight(for: point)) <= 0.02 ? .green : .orange
    }
}

private func uiColor(hex: String?, fallback: UIColor) -> UIColor {
    guard let hex else { return fallback }
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard cleaned.count == 6,
          let value = UInt64(cleaned, radix: 16) else {
        return fallback
    }
    return UIColor(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

private func planCenter(_ matrix: simd_float4x4) -> SIMD2<Float> {
    SIMD2(matrix.columns.3.x, matrix.columns.3.z)
}

private func translationMatrix(x: Float, y: Float, z: Float) -> simd_float4x4 {
    var matrix = matrix_identity_float4x4
    matrix.columns.3 = SIMD4(x, y, z, 1)
    return matrix
}

private func normalizedPlanAxis(_ vector: SIMD4<Float>) -> SIMD2<Float> {
    let axis = SIMD2(vector.x, vector.z)
    let length = simd_length(axis)
    return length > 0.0001 ? axis / length : SIMD2(1, 0)
}

private func wallPlanEndpoints(_ wall: WallSnapshot) -> (SIMD2<Float>, SIMD2<Float>) {
    let center = planCenter(wall.matrix)
    let axis = normalizedPlanAxis(wall.matrix.columns.0)
    let half = axis * (wall.width / 2)
    return (center - half, center + half)
}

private func surfacePlanEndpoints(_ surface: SurfaceSnapshot) -> (SIMD2<Float>, SIMD2<Float>) {
    let matrix = simd_float4x4(columnMajorValues: surface.transform)
    let center = planCenter(matrix)
    let axis = normalizedPlanAxis(matrix.columns.0)
    let half = axis * (surface.width / 2)
    return (center - half, center + half)
}

private func floorPlanCorners(_ floor: FloorSnapshot) -> [SIMD2<Float>] {
    let matrix = floor.matrix
    let center = planCenter(matrix)
    let xAxis = normalizedPlanAxis(matrix.columns.0) * (floor.width / 2)
    let zAxis = normalizedPlanAxis(matrix.columns.1) * (floor.depth / 2)
    return [
        center - xAxis - zAxis,
        center + xAxis - zAxis,
        center + xAxis + zAxis,
        center - xAxis + zAxis
    ]
}

private func objectPlanCorners(_ object: RoomObjectSnapshot) -> [SIMD2<Float>] {
    let matrix = object.matrix
    let center = planCenter(matrix)
    let xAxis = normalizedPlanAxis(matrix.columns.0) * (object.width / 2)
    let zAxis = normalizedPlanAxis(matrix.columns.2) * (object.depth / 2)
    return [
        center - xAxis - zAxis,
        center + xAxis - zAxis,
        center + xAxis + zAxis,
        center - xAxis + zAxis
    ]
}
