import RoomPlan
import SwiftUI

struct ContentView: View {
    @StateObject private var store = ProjectStore()
    @State private var showNewProject = false
    @State private var showGlobalSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "viewfinder.rectangular")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(
                                    LinearGradient(
                                        colors: [.cyan, .blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    in: RoundedRectangle(cornerRadius: 13)
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text("3E Room Electrical")
                                    .font(.title2.bold())
                                Text("المسح والحصر الكهربائي للمشروع")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Label(
                                    "الإصدار 1.5 • هوية وبيانات التصدير",
                                    systemImage: "checkmark.seal.fill"
                                )
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.blue)
                            }
                        }

                        Text("أنشئ مشروعًا، ثم نظّم المباني والأدوار والشقق والغرف قبل بدء مسح LiDAR.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if !RoomCaptureSession.isSupported {
                            Label(
                                "المسح يتطلب iPhone أو iPad مزودًا بحساس LiDAR.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("المشروعات") {
                    if store.activeProjects.isEmpty {
                        ContentUnavailableView(
                            "لا توجد مشروعات بعد",
                            systemImage: "folder.badge.plus",
                            description: Text("اضغط زر + لإنشاء أول مشروع.")
                        )
                    } else {
                        ForEach(store.activeProjects) { project in
                            NavigationLink {
                                ProjectBrowserView(
                                    projectID: project.id,
                                    parentItemID: nil,
                                    title: project.name
                                )
                            } label: {
                                SurveyProjectRow(project: project)
                            }
                        }
                    }
                }

                Section("المجلدات") {
                    NavigationLink {
                        ArchivedProjectsView()
                    } label: {
                        Label {
                            HStack {
                                Text("الأرشيف")
                                Spacer()
                                Text("\(store.archivedProjects.count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } icon: {
                            Image(systemName: "archivebox.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("المشروعات")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showGlobalSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("الإعدادات العامة")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    Button {
                        showNewProject = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(.blue, in: Circle())
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                    }
                    .accessibilityLabel("إنشاء مشروع جديد")
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
            }
        }
        .environmentObject(store)
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet(initialSettings: GlobalSettingsRepository.load()) {
                name,
                kind,
                settings in
                do {
                    try store.createProject(name: name, kind: kind, settings: settings)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showGlobalSettings) {
            ElectricalSettingsView(
                title: "الإعدادات العامة",
                initialSettings: GlobalSettingsRepository.load()
            ) { settings in
                GlobalSettingsRepository.save(settings)
            }
        }
        .onAppear(perform: store.reload)
    }
}

private struct ArchivedProjectsView: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        List {
            if store.archivedProjects.isEmpty {
                ContentUnavailableView(
                    "الأرشيف فارغ",
                    systemImage: "archivebox",
                    description: Text("المشروعات التي تؤرشفها ستظهر هنا، ويمكن حذفها نهائيًا من داخلها.")
                )
            } else {
                ForEach(store.archivedProjects) { project in
                    NavigationLink {
                        ProjectBrowserView(
                            projectID: project.id,
                            parentItemID: nil,
                            title: project.name
                        )
                    } label: {
                        SurveyProjectRow(project: project)
                    }
                }
            }
        }
        .navigationTitle("أرشيف المشروعات")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: store.reload)
    }
}

private struct SurveyProjectRow: View {
    let project: SurveyProject

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: project.kind.systemImage)
                .font(.title2)
                .foregroundStyle(project.isImportedArchive ? .orange : .blue)
                .frame(width: 42, height: 42)
                .background(
                    (project.isImportedArchive ? Color.orange : Color.blue).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                Text("\(project.roomCount) غرفة • \(project.scanCount) مسح")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(project.kind.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.secondary.opacity(0.1), in: Capsule())
        }
        .padding(.vertical, 4)
    }
}

private struct ProjectBrowserView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID
    let parentItemID: UUID?
    let title: String

    @State private var selectedItemKind: WorkspaceItemKind?
    @State private var showNewScan = false
    @State private var pendingScanName: String?
    @State private var activeDestination: ScanDestination?
    @State private var showProjectSettings = false
    @State private var showRename = false
    @State private var showMove = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let project = store.project(id: projectID) {
                projectList(project)
            } else {
                ContentUnavailableView(
                    "المشروع غير موجود",
                    systemImage: "folder.badge.questionmark"
                )
            }
        }
        .navigationTitle(currentTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let project = store.project(id: projectID) {
                    managementMenu(project)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if canAddContent {
                addMenu
            }
        }
        .sheet(item: $selectedItemKind) { kind in
            NewWorkspaceItemSheet(kind: kind) { name in
                do {
                    try store.addItem(
                        projectID: projectID,
                        parentID: parentItemID,
                        name: name,
                        kind: kind
                    )
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showNewScan, onDismiss: beginPendingScan) {
            NewScanSheet(defaultName: defaultScanName) { name in
                pendingScanName = name
                showNewScan = false
            }
        }
        .sheet(isPresented: $showProjectSettings) {
            if let project = store.project(id: projectID) {
                ElectricalSettingsView(
                    title: "إعدادات \(project.name)",
                    initialSettings: project.settings
                ) { settings in
                    do {
                        try store.updateSettings(projectID: projectID, settings: settings)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .sheet(isPresented: $showRename) {
            RenameSheet(title: "إعادة تسمية", initialName: currentTitle) { name in
                do {
                    if let parentItemID {
                        try store.renameItem(projectID: projectID, itemID: parentItemID, name: name)
                    } else {
                        try store.renameProject(projectID: projectID, name: name)
                    }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showMove) {
            if let project = store.project(id: projectID) {
                if let parentItemID {
                    MoveDestinationSheet(
                        project: project,
                        excludedItemIDs: project.descendantIDs(of: parentItemID).union([parentItemID]),
                        currentParentID: project.item(id: parentItemID)?.parentID
                    ) { destinationID in
                        do {
                            try store.moveItem(
                                projectID: projectID,
                                itemID: parentItemID,
                                destinationParentID: destinationID
                            )
                            return nil
                        } catch {
                            return error.localizedDescription
                        }
                    }
                } else {
                    ProjectMoveSheet(isArchived: project.archived) { archived in
                        do {
                            try store.setProjectArchived(projectID: projectID, archived: archived)
                            dismiss()
                            return nil
                        } catch {
                            return error.localizedDescription
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $activeDestination, onDismiss: store.reload) { destination in
            RoomWorkflowView(destination: destination) {
                activeDestination = nil
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
            "حذف نهائي",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("حذف نهائيًا", role: .destructive) {
                deleteCurrent()
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("سيتم حذف العنصر وكل المسحات والملفات التابعة له، ولا يمكن التراجع عن ذلك.")
        }
        .onAppear(perform: store.reload)
    }

    @ViewBuilder
    private func projectList(_ project: SurveyProject) -> some View {
        let children = project.children(of: parentItemID)
        let scans = project.scans(in: parentItemID)

        List {
            Section {
                HStack(spacing: 18) {
                    summaryValue("المجلدات", value: children.count, image: "folder.fill")
                    Divider()
                    summaryValue("المسحات", value: scans.count, image: "viewfinder")
                    Divider()
                    summaryValue("الكهرباء", value: pointCount(in: scans), image: "bolt.fill")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            Section("الحصر والتصدير") {
                NavigationLink {
                    ProjectTakeoffView(
                        projectID: projectID,
                        scopeItemID: parentItemID,
                        title: currentTitle
                    )
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("الحصر والحاسبات")
                            Text("الأرضيات والحوائط والأسقف والفتحات")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "function")
                            .foregroundStyle(.blue)
                    }
                }

                NavigationLink {
                    ExportCenterView(
                        surveyProject: project,
                        scopeItemID: parentItemID,
                        title: currentTitle
                    )
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("مركز التصدير")
                            Text("XLSX للحصر وPDF للتقرير ومخطط 2D كامل الطبقات")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "square.and.arrow.up.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }

            if !children.isEmpty {
                Section("المحتويات") {
                    ForEach(children) { item in
                        NavigationLink {
                            ProjectBrowserView(
                                projectID: projectID,
                                parentItemID: item.id,
                                title: item.name
                            )
                        } label: {
                            WorkspaceItemRow(item: item, project: project)
                        }
                    }
                }
            }

            if !scans.isEmpty {
                Section("المسحات") {
                    ForEach(scans) { scan in
                        NavigationLink {
                            ScanDetailLoaderView(projectID: projectID, scanID: scan.id)
                        } label: {
                            ScanReferenceRow(scan: scan)
                        }
                    }
                }
            }

            if parentItemID == nil {
                Section("المجلدات") {
                    NavigationLink {
                        ProjectArchiveView(projectID: projectID)
                    } label: {
                        Label {
                            HStack {
                                Text("الأرشيف")
                                Spacer()
                                Text("\(project.archivedItemCount + project.archivedScanCount)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } icon: {
                            Image(systemName: "archivebox.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            if children.isEmpty && scans.isEmpty {
                Section {
                    ContentUnavailableView(
                        "هذا المجلد فارغ",
                        systemImage: "folder",
                        description: Text(
                            canAddContent
                                ? "استخدم زر + لإضافة مستوى تنظيمي أو بدء مسح جديد."
                                : "استعد هذا العنصر من الأرشيف إذا أردت إضافة محتوى جديد."
                        )
                    )
                }
            }
        }
    }

    private var addMenu: some View {
        HStack {
            Spacer()
            Menu {
                Section("إضافة مستوى") {
                    ForEach(WorkspaceItemKind.allCases) { kind in
                        Button {
                            selectedItemKind = kind
                        } label: {
                            Label(kind.title, systemImage: kind.systemImage)
                        }
                    }
                }

                Section("المسح") {
                    Button {
                        showNewScan = true
                    } label: {
                        Label("بدء مسح جديد هنا", systemImage: "camera.viewfinder")
                    }
                    .disabled(!RoomCaptureSession.isSupported)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.blue, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            }
            .accessibilityLabel("إضافة")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
    }

    private var defaultScanName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar")
        formatter.dateFormat = "d MMM - HH:mm"
        return "مسح \(currentTitle) - \(formatter.string(from: Date()))"
    }

    private var currentTitle: String {
        guard let project = store.project(id: projectID) else { return title }
        if let parentItemID, let item = project.item(id: parentItemID) {
            return item.name
        }
        return project.name
    }

    private var canAddContent: Bool {
        guard let project = store.project(id: projectID), !project.archived else { return false }
        if let parentItemID {
            return project.item(id: parentItemID)?.archived == false
        }
        return true
    }

    @ViewBuilder
    private func managementMenu(_ project: SurveyProject) -> some View {
        Menu {
            if parentItemID == nil {
                Button {
                    showProjectSettings = true
                } label: {
                    Label("إعدادات المشروع", systemImage: "slider.horizontal.3")
                }
            }

            Button {
                showRename = true
            } label: {
                Label("إعادة تسمية", systemImage: "pencil")
            }

            Button {
                duplicateCurrent()
            } label: {
                Label("إنشاء نسخة", systemImage: "plus.square.on.square")
            }

            Button {
                showMove = true
            } label: {
                Label("نقل", systemImage: "folder")
            }

            Divider()

            if currentIsArchived(in: project) {
                Button {
                    setCurrentArchived(false)
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
                    setCurrentArchived(true)
                } label: {
                    Label("أرشفة", systemImage: "archivebox")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func currentIsArchived(in project: SurveyProject) -> Bool {
        if let parentItemID {
            return project.item(id: parentItemID)?.archived ?? false
        }
        return project.archived
    }

    private func duplicateCurrent() {
        do {
            if let parentItemID {
                try store.duplicateItem(projectID: projectID, itemID: parentItemID)
            } else {
                try store.duplicateProject(projectID: projectID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setCurrentArchived(_ archived: Bool) {
        do {
            if let parentItemID {
                try store.setItemArchived(
                    projectID: projectID,
                    itemID: parentItemID,
                    archived: archived
                )
            } else {
                try store.setProjectArchived(projectID: projectID, archived: archived)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCurrent() {
        do {
            if let parentItemID {
                try store.deleteItem(projectID: projectID, itemID: parentItemID)
            } else {
                try store.deleteProject(projectID: projectID)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginPendingScan() {
        guard let pendingScanName else { return }
        self.pendingScanName = nil
        activeDestination = ScanDestination(
            surveyProjectID: projectID,
            parentItemID: parentItemID,
            scanName: pendingScanName
        )
    }

    private func pointCount(in scans: [ScanReference]) -> Int {
        scans.compactMap { ProjectRepository.load(projectID: $0.id) }
            .reduce(0) { $0 + $1.points.count }
    }

    private func summaryValue(_ title: String, value: Int, image: String) -> some View {
        VStack(spacing: 4) {
            Label("\(value)", systemImage: image)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.blue)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WorkspaceItemRow: View {
    let item: WorkspaceItem
    let project: SurveyProject

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.headline)
                Text("\(item.kind.title) • \(project.scans(in: item.id).count) مسح مباشر")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ScanReferenceRow: View {
    let scan: ScanReference

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube.transparent.fill")
                .foregroundStyle(.cyan)
                .frame(width: 34, height: 34)
                .background(.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(scan.name)
                    .font(.headline)
                Text(scan.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !scan.includedInTakeoff {
                    Label("مستبعد من الحصر", systemImage: "minus.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ScopedTakeoffRoom: Identifiable {
    let scan: ScanReference
    let summary: RoomTakeoffSummary?
    let location: String

    var id: UUID { scan.id }
}

private struct ProjectTakeoffView: View {
    @EnvironmentObject private var store: ProjectStore

    let projectID: UUID
    let scopeItemID: UUID?
    let title: String

    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let project = store.project(id: projectID) {
                takeoffList(project)
            } else {
                ContentUnavailableView(
                    "المشروع غير موجود",
                    systemImage: "folder.badge.questionmark"
                )
            }
        }
        .navigationTitle("حصر \(title)")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "تعذر تحديث الحصر",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: store.reload)
    }

    private func takeoffList(_ project: SurveyProject) -> some View {
        let rooms = scopedRooms(in: project)
        let includedRooms = rooms.compactMap { room -> RoomTakeoffSummary? in
            guard room.scan.includedInTakeoff else { return nil }
            return room.summary
        }
        let total = ProjectTakeoffSummary(rooms: includedRooms)

        return List {
            Section("المجموع العام") {
                LabeledContent(
                    "المسحات الداخلة في الحصر",
                    value: "\(includedRooms.count)"
                )
                takeoffAreaRow(
                    "مساحة الأرضيات",
                    value: total.floorArea,
                    image: "square.fill"
                )
                takeoffAreaRow(
                    "مساحة الأسقف",
                    value: total.ceilingArea,
                    image: "square.dashed"
                )
                takeoffAreaRow(
                    "الحوائط قبل الخصم",
                    value: total.grossWallArea,
                    image: "rectangle.split.3x1.fill"
                )
                takeoffAreaRow(
                    "الفتحات المخصومة",
                    value: total.deductedOpeningArea,
                    image: "rectangle.portrait.and.arrow.right"
                )
                takeoffAreaRow(
                    "صافي الحوائط",
                    value: total.netWallArea,
                    image: "checkmark.rectangle.fill"
                )
            }

            Section("الفتحات والكهرباء") {
                takeoffAreaRow(
                    "إجمالي مساحة الفتحات",
                    value: total.totalOpeningArea,
                    image: "rectangle.dashed"
                )
                LabeledContent(
                    "الأبواب",
                    value: "\(total.doorCount)"
                )
                LabeledContent(
                    "الشبابيك",
                    value: "\(total.windowCount)"
                )
                LabeledContent(
                    "الفتحات المعمارية",
                    value: "\(total.architecturalOpeningCount)"
                )
                LabeledContent(
                    "نقاط الكهرباء",
                    value: "\(total.electricalPointCount)"
                )
                LabeledContent(
                    "إضاءة السقف",
                    value: "\(total.ceilingLightCount)"
                )
            }

            Section("ملاحظات الحساب") {
                Label(
                    "مساحة السقف في هذه المرحلة تساوي مساحة الأرضية المكتشفة لكل مسح.",
                    systemImage: "info.circle"
                )
                Label(
                    "لا تُخصم أي فتحة من الحائط إلا بعد ربطها هندسيًا بذلك الحائط.",
                    systemImage: "link"
                )
            }

            Section {
                if rooms.isEmpty {
                    ContentUnavailableView(
                        "لا توجد مسحات للحصر",
                        systemImage: "function",
                        description: Text(
                            "أضف مسحًا داخل هذا المستوى أو أحد المجلدات التابعة له."
                        )
                    )
                } else {
                    ForEach(rooms) { room in
                        takeoffRoomRow(room)
                    }
                }
            } header: {
                Text("المسحات")
            } footer: {
                Text(
                    "استبعد أي إعادة مسح لنفس المكان حتى لا تتكرر المساحات في المجموع."
                )
            }
        }
    }

    private func scopedRooms(in project: SurveyProject) -> [ScopedTakeoffRoom] {
        let allowedParentIDs: Set<UUID>?
        if let scopeItemID {
            allowedParentIDs = project.descendantIDs(of: scopeItemID)
                .union([scopeItemID])
        } else {
            allowedParentIDs = nil
        }

        return project.scans
            .filter { scan in
                guard !scan.archived else { return false }
                guard !hasArchivedAncestor(
                    scan.parentID,
                    in: project
                ) else {
                    return false
                }
                guard let allowedParentIDs else { return true }
                return scan.parentID.map(allowedParentIDs.contains) == true
            }
            .sorted { $0.createdAt < $1.createdAt }
            .map { scan in
                ScopedTakeoffRoom(
                    scan: scan,
                    summary: ProjectRepository.load(projectID: scan.id).map {
                        RoomTakeoffSummary(project: $0)
                    },
                    location: locationPath(for: scan.parentID, in: project)
                )
            }
    }

    private func hasArchivedAncestor(
        _ itemID: UUID?,
        in project: SurveyProject
    ) -> Bool {
        var currentID = itemID
        var visited: Set<UUID> = []
        while let id = currentID,
              !visited.contains(id),
              let item = project.item(id: id) {
            if item.archived {
                return true
            }
            visited.insert(id)
            currentID = item.parentID
        }
        return false
    }

    @ViewBuilder
    private func takeoffRoomRow(_ room: ScopedTakeoffRoom) -> some View {
        HStack(spacing: 10) {
            if let summary = room.summary {
                NavigationLink {
                    ScanTakeoffDetailView(summary: summary)
                } label: {
                    takeoffRoomLabel(room, summary: summary)
                }
            } else {
                takeoffRoomLabel(room, summary: nil)
            }

            Toggle(
                "يدخل في الحصر",
                isOn: Binding(
                    get: { room.scan.includedInTakeoff },
                    set: { included in
                        setIncluded(
                            included,
                            scanID: room.scan.id
                        )
                    }
                )
            )
            .labelsHidden()
            .tint(.blue)
        }
        .opacity(room.scan.includedInTakeoff ? 1 : 0.62)
    }

    private func takeoffRoomLabel(
        _ room: ScopedTakeoffRoom,
        summary: RoomTakeoffSummary?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(room.scan.name)
                .font(.headline)
            if !room.location.isEmpty {
                Text(room.location)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let summary {
                Text(
                    "\(formattedArea(summary.floorArea)) أرضيات • \(formattedArea(summary.netWallArea)) صافي حوائط"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Label(
                    "ملف المسح غير متاح",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    private func locationPath(
        for itemID: UUID?,
        in project: SurveyProject
    ) -> String {
        var names: [String] = []
        var currentID = itemID
        var visited: Set<UUID> = []
        while let id = currentID,
              !visited.contains(id),
              let item = project.item(id: id) {
            visited.insert(id)
            names.append(item.name)
            currentID = item.parentID
        }
        return names.reversed().joined(separator: " ← ")
    }

    private func setIncluded(_ included: Bool, scanID: UUID) {
        do {
            try store.setScanIncludedInTakeoff(
                projectID: projectID,
                scanID: scanID,
                included: included
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func takeoffAreaRow(
        _ title: String,
        value: Float,
        image: String
    ) -> some View {
        LabeledContent {
            Text(formattedArea(value))
                .monospacedDigit()
        } label: {
            Label(title, systemImage: image)
        }
    }
}

struct ScanTakeoffDetailView: View {
    let summary: RoomTakeoffSummary

    var body: some View {
        List {
            Section("ملخص الغرفة") {
                areaRow("الأرضيات", value: summary.floorArea)
                areaRow("الأسقف", value: summary.ceilingArea)
                areaRow("الحوائط قبل الخصم", value: summary.grossWallArea)
                areaRow(
                    "الفتحات المخصومة",
                    value: summary.deductedOpeningArea
                )
                areaRow("صافي الحوائط", value: summary.netWallArea)
            }

            Section("الأرضيات والأسقف") {
                if summary.floors.isEmpty {
                    Label(
                        "لم يكتشف RoomPlan سطح أرضية صالحًا للحساب.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                } else {
                    ForEach(summary.floors) { floor in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("أرضية \(floorNumber(floor.id))")
                                .font(.headline)
                            Text(
                                "\(formattedLength(floor.width)) × \(formattedLength(floor.depth)) = \(formattedArea(floor.area))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("تفاصيل الحوائط") {
                ForEach(summary.walls) { wall in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("حائط \(wallNumber(wall.id))")
                                .font(.headline)
                            Spacer()
                            Text(formattedArea(wall.netArea))
                                .font(.headline.monospacedDigit())
                        }
                        Text(
                            "\(formattedLength(wall.width)) × \(formattedLength(wall.height)) = \(formattedArea(wall.grossArea))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if wall.openingCount > 0 {
                            Text(
                                "خصم \(wall.openingCount) فتحة: \(formattedArea(wall.deductedOpeningArea))"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("الأبواب والشبابيك") {
                if summary.openings.isEmpty {
                    Text("لا توجد فتحات مسجلة.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.openings) { opening in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(opening.title)
                                Text(
                                    "\(formattedLength(opening.width)) × \(formattedLength(opening.height))"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formattedArea(opening.area))
                                .monospacedDigit()
                            if opening.wallID == nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }

            Section("الكهرباء") {
                if summary.electrical.isEmpty
                    && summary.ceilingLightCount == 0 {
                    Text("لا توجد عناصر كهربائية.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.electrical) { line in
                        HStack {
                            Label(
                                line.type.title,
                                systemImage: line.type.systemImage
                            )
                            Spacer()
                            Text("\(line.count) • \(line.status.title)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if summary.manualCeilingLightCount > 0 {
                        LabeledContent(
                            "إضاءة سقف يدوية",
                            value: "\(summary.manualCeilingLightCount)"
                        )
                    }
                    if summary.automaticCeilingLightCount > 0 {
                        LabeledContent(
                            "إضاءة سقف تلقائية",
                            value: "\(summary.automaticCeilingLightCount)"
                        )
                    }
                }
            }

            if summary.unassignedOpeningCount > 0 {
                Section {
                    Label(
                        "\(summary.unassignedOpeningCount) فتحة لم ترتبط بحائط، ولذلك لم تُخصم من صافي الحوائط.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle(summary.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func floorNumber(_ id: UUID) -> Int {
        (summary.floors.firstIndex { $0.id == id } ?? 0) + 1
    }

    private func wallNumber(_ id: UUID) -> Int {
        (summary.walls.firstIndex { $0.id == id } ?? 0) + 1
    }

    private func areaRow(_ title: String, value: Float) -> some View {
        LabeledContent(title, value: formattedArea(value))
    }
}

private func formattedArea(_ squareMeters: Float) -> String {
    String(format: "%.2f م²", squareMeters)
}

private func formattedLength(_ meters: Float) -> String {
    String(format: "%.2f م", meters)
}

private struct ProjectArchiveView: View {
    @EnvironmentObject private var store: ProjectStore

    let projectID: UUID

    var body: some View {
        Group {
            if let project = store.project(id: projectID) {
                archiveList(project)
            } else {
                ContentUnavailableView(
                    "المشروع غير موجود",
                    systemImage: "folder.badge.questionmark"
                )
            }
        }
        .navigationTitle("أرشيف المشروع")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: store.reload)
    }

    @ViewBuilder
    private func archiveList(_ project: SurveyProject) -> some View {
        let items = project.items
            .filter { $0.archived && !hasArchivedAncestor($0, in: project) }
            .sorted { $0.createdAt > $1.createdAt }
        let scans = project.scans
            .filter { $0.archived }
            .sorted { $0.createdAt > $1.createdAt }

        List {
            if !items.isEmpty {
                Section("المجلدات والمساحات") {
                    ForEach(items) { item in
                        NavigationLink {
                            ProjectBrowserView(
                                projectID: projectID,
                                parentItemID: item.id,
                                title: item.name
                            )
                        } label: {
                            WorkspaceItemRow(item: item, project: project)
                        }
                    }
                }
            }

            if !scans.isEmpty {
                Section("المسحات") {
                    ForEach(scans) { scan in
                        NavigationLink {
                            ScanDetailLoaderView(projectID: projectID, scanID: scan.id)
                        } label: {
                            ScanReferenceRow(scan: scan)
                        }
                    }
                }
            }

            if items.isEmpty && scans.isEmpty {
                ContentUnavailableView(
                    "أرشيف المشروع فارغ",
                    systemImage: "archivebox",
                    description: Text("العناصر والمسحات التي تؤرشفها من هذا المشروع ستظهر هنا.")
                )
            }
        }
    }

    private func hasArchivedAncestor(_ item: WorkspaceItem, in project: SurveyProject) -> Bool {
        var candidate = item
        var visited: Set<UUID> = []
        while let parentID = candidate.parentID,
              !visited.contains(parentID),
              let parent = project.item(id: parentID) {
            if parent.archived { return true }
            visited.insert(parentID)
            candidate = parent
        }
        return false
    }
}

struct RenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var errorMessage: String?

    let title: String
    let onSave: (String) -> String?

    init(title: String, initialName: String, onSave: @escaping (String) -> String?) {
        self.title = title
        _name = State(initialValue: initialName)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("الاسم") {
                    TextField("اكتب الاسم الجديد", text: $name)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let error = onSave(cleanName) {
                            errorMessage = error
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("تعذر الحفظ", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("حسنًا", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

struct MoveDestinationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    let project: SurveyProject
    let excludedItemIDs: Set<UUID>
    let currentParentID: UUID?
    let onMove: (UUID?) -> String?

    var body: some View {
        NavigationStack {
            List {
                Section("مكان النقل") {
                    destinationButton(
                        title: "مجلد المشروع الرئيسي",
                        subtitle: project.name,
                        image: project.kind.systemImage,
                        destinationID: nil
                    )

                    ForEach(availableItems) { item in
                        destinationButton(
                            title: item.name,
                            subtitle: item.kind.title,
                            image: item.kind.systemImage,
                            destinationID: item.id
                        )
                    }
                }
            }
            .navigationTitle("نقل إلى")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
            }
            .alert("تعذر النقل", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("حسنًا", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var availableItems: [WorkspaceItem] {
        project.items
            .filter {
                !excludedItemIDs.contains($0.id)
                    && !$0.archived
                    && !hasArchivedAncestor($0)
            }
            .sorted {
                if hierarchyDepth(of: $0) == hierarchyDepth(of: $1) {
                    return $0.createdAt < $1.createdAt
                }
                return hierarchyDepth(of: $0) < hierarchyDepth(of: $1)
            }
    }

    private func hasArchivedAncestor(_ item: WorkspaceItem) -> Bool {
        var candidate = item
        var visited: Set<UUID> = []
        while let parentID = candidate.parentID,
              !visited.contains(parentID),
              let parent = project.item(id: parentID) {
            if parent.archived { return true }
            visited.insert(parentID)
            candidate = parent
        }
        return false
    }

    private func hierarchyDepth(of item: WorkspaceItem) -> Int {
        var depth = 0
        var candidate = item
        var visited: Set<UUID> = []
        while let parentID = candidate.parentID,
              !visited.contains(parentID),
              let parent = project.item(id: parentID) {
            depth += 1
            visited.insert(parentID)
            candidate = parent
        }
        return depth
    }

    private func destinationButton(
        title: String,
        subtitle: String,
        image: String,
        destinationID: UUID?
    ) -> some View {
        let depth = destinationID.flatMap { id in
            project.item(id: id).map { hierarchyDepth(of: $0) }
        } ?? 0

        return Button {
            if let error = onMove(destinationID) {
                errorMessage = error
            } else {
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: image)
                    .foregroundStyle(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if currentParentID == destinationID {
                    Label("الحالي", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, CGFloat(depth) * 14)
        }
        .disabled(currentParentID == destinationID)
    }
}

struct ProjectMoveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    let isArchived: Bool
    let onMove: (Bool) -> String?

    var body: some View {
        NavigationStack {
            List {
                Section("مكان المشروع") {
                    moveButton(
                        title: "المشروعات الحالية",
                        subtitle: "يظهر المشروع في الصفحة الرئيسية",
                        image: "folder.fill",
                        archived: false
                    )
                    moveButton(
                        title: "الأرشيف",
                        subtitle: "يُحفظ بعيدًا عن قائمة المشروعات الحالية",
                        image: "archivebox.fill",
                        archived: true
                    )
                }
            }
            .navigationTitle("نقل المشروع")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
            }
            .alert("تعذر النقل", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("حسنًا", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func moveButton(
        title: String,
        subtitle: String,
        image: String,
        archived: Bool
    ) -> some View {
        Button {
            if let error = onMove(archived) {
                errorMessage = error
            } else {
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: image)
                    .foregroundStyle(archived ? .orange : .blue)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isArchived == archived {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .disabled(isArchived == archived)
    }
}

private struct ScanDetailLoaderView: View {
    let projectID: UUID
    let scanID: UUID

    var body: some View {
        if let project = ProjectRepository.load(projectID: scanID) {
            ProjectDetailView(project: project, surveyProjectID: projectID)
        } else {
            ContentUnavailableView(
                "ملفات المسح غير موجودة",
                systemImage: "exclamationmark.folder"
            )
        }
    }
}

private struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: SurveyProjectKind = .residential
    @State private var settings: ElectricalPlacementSettings
    @State private var errorMessage: String?

    let onCreate: (String, SurveyProjectKind, ElectricalPlacementSettings) -> String?

    init(
        initialSettings: ElectricalPlacementSettings,
        onCreate: @escaping (String, SurveyProjectKind, ElectricalPlacementSettings) -> String?
    ) {
        _settings = State(initialValue: initialSettings)
        self.onCreate = onCreate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("بيانات المشروع") {
                    TextField("اسم المشروع", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("نوع المشروع", selection: $kind) {
                        ForEach(SurveyProjectKind.allCases) { item in
                            Label(item.title, systemImage: item.systemImage).tag(item)
                        }
                    }
                }

                Section("نمط العمل الافتراضي") {
                    Picker("النمط", selection: $settings.designMode) {
                        ForEach(ElectricalDesignMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Text(settings.designMode.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if settings.designMode == .existing {
                    AsBuiltPlacementNotice()
                } else {
                    Section {
                        CentimeterField(
                            title: "المفاتيح",
                            systemImage: "lightswitch.on.fill",
                            meters: $settings.switchHeightMeters
                        )
                        CentimeterField(
                            title: "الأفياش",
                            systemImage: "powerplug.fill",
                            meters: $settings.socketHeightMeters
                        )
                        CentimeterField(
                            title: "الإضاءة الجدارية",
                            systemImage: "light.beacon.max.fill",
                            meters: $settings.wallLightHeightMeters
                        )
                        CentimeterField(
                            title: "بعد المفتاح عن الباب",
                            systemImage: "arrow.left.and.right",
                            meters: $settings.switchDoorOffsetMeters
                        )
                    } header: {
                        Text("ارتفاعات المشروع")
                    } footer: {
                        Text("القياسات من الأرضية النهائية إلى مركز العنصر، ما عدا بُعد الباب فهو أفقي.")
                    }

                    SmartPlacementRangeFields(settings: $settings)
                    LowCurrentAndAirConditioningSettingsFields(
                        settings: $settings
                    )
                }

                ElectricalBoxSettingsFields(settings: $settings)
            }
            .navigationTitle("مشروع جديد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إنشاء") {
                        if let error = onCreate(name, kind, settings) {
                            errorMessage = error
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("تعذر إنشاء المشروع", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("حسنًا", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

private struct NewWorkspaceItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage: String?

    let kind: WorkspaceItemKind
    let onCreate: (String) -> String?

    var body: some View {
        NavigationStack {
            Form {
                Section("بيانات \(kind.title)") {
                    TextField("اسم \(kind.title)", text: $name)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("إضافة \(kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إضافة") {
                        if let error = onCreate(name) {
                            errorMessage = error
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("تعذر الحفظ", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("حسنًا", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

private struct NewScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    let onStart: (String) -> Void

    init(defaultName: String, onStart: @escaping (String) -> Void) {
        _name = State(initialValue: defaultName)
        self.onStart = onStart
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("مثال: غرفة المعيشة", text: $name)
                } header: {
                    Text("اسم المسح")
                } footer: {
                    Text("سيُحفظ JSON وUSDZ ونقاط الكهرباء بهذا الاسم داخل المكان الحالي.")
                }
            }
            .navigationTitle("مسح جديد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("بدء المسح") {
                        onStart(name.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case electrical
    case furniture
    case plumbing
    case finishes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "عام"
        case .electrical: "الكهرباء"
        case .furniture: "الفرش"
        case .plumbing: "السباكة"
        case .finishes: "الدهانات"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .electrical: "bolt.fill"
        case .furniture: "chair.lounge.fill"
        case .plumbing: "drop.fill"
        case .finishes: "paintbrush.fill"
        }
    }
}

private struct ElectricalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings: ElectricalPlacementSettings
    @State private var selectedCategory: SettingsCategory = .general

    let title: String
    let onSave: (ElectricalPlacementSettings) -> Void

    init(
        title: String,
        initialSettings: ElectricalPlacementSettings,
        onSave: @escaping (ElectricalPlacementSettings) -> Void
    ) {
        self.title = title
        _settings = State(initialValue: initialSettings)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                settingsTabs

                Form {
                    selectedSettingsContent
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        onSave(settings)
                        dismiss()
                    }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var settingsTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SettingsCategory.allCases) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedCategory = category
                        }
                    } label: {
                        Label(category.title, systemImage: category.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .foregroundStyle(
                                selectedCategory == category
                                    ? Color.white
                                    : Color.primary
                            )
                            .background(
                                selectedCategory == category
                                    ? Color.accentColor
                                    : Color(uiColor: .secondarySystemGroupedBackground),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder
    private var selectedSettingsContent: some View {
        switch selectedCategory {
        case .general:
            Section("نمط العمل") {
                Picker("النمط الافتراضي", selection: $settings.designMode) {
                    ForEach(ElectricalDesignMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(settings.designMode.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("الوحدات") {
                LabeledContent("الأبعاد المعروضة", value: "سنتيمتر")
                LabeledContent("الحصر والمساحات", value: "متر / متر مربع")
            }

            Section("أقسام الإعدادات") {
                Label("اختر الكهرباء لضبط الارتفاعات وقواعد التثبيت.", systemImage: "bolt.fill")
                Label("تبويبات الفرش والسباكة والدهانات جاهزة للتوسعة القادمة.", systemImage: "square.grid.2x2.fill")
            }

            case .electrical:
                if settings.designMode == .existing {
                    AsBuiltPlacementNotice()
                } else {
                    Section {
                        CentimeterField(
                            title: "ارتفاع المفاتيح",
                            systemImage: "lightswitch.on.fill",
                            meters: $settings.switchHeightMeters
                        )
                        CentimeterField(
                            title: "ارتفاع الأفياش",
                            systemImage: "powerplug.fill",
                            meters: $settings.socketHeightMeters
                        )
                        CentimeterField(
                            title: "الإضاءة الجدارية",
                            systemImage: "light.beacon.max.fill",
                            meters: $settings.wallLightHeightMeters
                        )
                        CentimeterField(
                            title: "بعد المفتاح عن الباب",
                            systemImage: "arrow.left.and.right",
                            meters: $settings.switchDoorOffsetMeters
                        )
                    } header: {
                        Text("الارتفاعات والأبعاد")
                    } footer: {
                        Text("تظهر القيم بالسنتيمتر، ويحفظها التطبيق داخليًا بالمتر.")
                    }

                    SmartPlacementRangeFields(settings: $settings)
                    LowCurrentAndAirConditioningSettingsFields(
                        settings: $settings
                    )
                }

                ElectricalBoxSettingsFields(settings: $settings)

                Section("قواعد التثبيت") {
                    Toggle("منع وضع النقاط داخل فتحات الأبواب والشبابيك", isOn: $settings.avoidOpenings)
                }

                Section {
                    Button("استعادة القيم الافتراضية", role: .destructive) {
                        settings = .standard
                    }
                }

            case .furniture:
                FutureSettingsSection(
                    title: "إعدادات الفرش",
                    systemImage: "chair.lounge.fill",
                    description: "سيُضاف هنا تصنيف الفرش، المقاسات الافتراضية، والإظهار داخل 2D و3D."
                )

            case .plumbing:
                FutureSettingsSection(
                    title: "إعدادات السباكة",
                    systemImage: "drop.fill",
                    description: "مجهز لإضافة نقاط المياه والصرف والأجهزة الصحية والارتفاعات."
                )

            case .finishes:
                FutureSettingsSection(
                    title: "إعدادات الدهانات والتشطيبات",
                    systemImage: "paintbrush.fill",
                    description: "مجهز لإضافة أنواع الدهانات، المحارة، طبقات التشطيب ونسب الهالك."
                )
        }
    }
}

private struct CentimeterField: View {
    let title: String
    let systemImage: String
    @Binding var meters: Double

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
            Spacer()
            TextField(
                "0",
                value: Binding(
                    get: { meters * 100 },
                    set: { meters = max(0, $0) / 100 }
                ),
                format: .number.precision(.fractionLength(0...1))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 72)
            Text("سم")
                .foregroundStyle(.secondary)
        }
    }
}

private struct LowCurrentAndAirConditioningSettingsFields: View {
    @Binding var settings: ElectricalPlacementSettings

    var body: some View {
        Section {
            CentimeterField(
                title: "تيار خفيف – أرضي/طاولة",
                systemImage: "network",
                meters: $settings.lowCurrentLowHeightMeters
            )
            CentimeterField(
                title: "تيار خفيف – علوي معلق",
                systemImage: "arrow.up.to.line",
                meters: $settings.lowCurrentHighHeightMeters
            )
            CentimeterField(
                title: "السبليت أسفل السقف",
                systemImage: "air.conditioner.horizontal.fill",
                meters: $settings.splitAirConditionerCeilingOffsetMeters
            )
            CentimeterField(
                title: "ارتفاع مكيف الشباك",
                systemImage: "air.conditioner.vertical.fill",
                meters: $settings.windowAirConditionerHeightMeters
            )
        } header: {
            Text("التيار الخفيف والتكييف")
        } footer: {
            Text("السبليت يُقاس من السقف إلى مركز رمزه، وبقية القيم من الأرضية النهائية.")
        }
    }
}

private struct FutureSettingsSection: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        Section(title) {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )
        }
    }
}

private struct SmartPlacementRangeFields: View {
    @Binding var settings: ElectricalPlacementSettings

    var body: some View {
        Section {
            CentimeterField(
                title: "قرب الباب – من",
                systemImage: "door.left.hand.open",
                meters: $settings.doorSuggestionMinimumMeters
            )
            CentimeterField(
                title: "قرب الباب – إلى",
                systemImage: "arrow.left.and.right",
                meters: $settings.doorSuggestionMaximumMeters
            )
            CentimeterField(
                title: "قرب المفتاح – من",
                systemImage: "lightswitch.on.fill",
                meters: $settings.switchAlignmentMinimumMeters
            )
            CentimeterField(
                title: "قرب المفتاح – إلى",
                systemImage: "powerplug.fill",
                meters: $settings.switchAlignmentMaximumMeters
            )
        } header: {
            Text("نطاقات الاقتراح الذكي")
        } footer: {
            Text("إذا كان موضع العنصر داخل هذه المسافة، سيسألك التطبيق قبل تغيير مكانه.")
        }
    }
}

private struct ElectricalBoxSettingsFields: View {
    @Binding var settings: ElectricalPlacementSettings

    var body: some View {
        Section {
            CentimeterField(
                title: "علبة 7×7 – العرض",
                systemImage: "square",
                meters: $settings.squareBoxWidthMeters
            )
            CentimeterField(
                title: "علبة 7×7 – الارتفاع",
                systemImage: "arrow.up.and.down",
                meters: $settings.squareBoxHeightMeters
            )
            CentimeterField(
                title: "علبة 5×10 – العرض",
                systemImage: "rectangle",
                meters: $settings.rectangularBoxWidthMeters
            )
            CentimeterField(
                title: "علبة 5×10 – الارتفاع",
                systemImage: "arrow.up.and.down",
                meters: $settings.rectangularBoxHeightMeters
            )
            CentimeterField(
                title: "مسافة دمج العناصر",
                systemImage: "square.on.square",
                meters: $settings.electricalMergeDistanceMeters
            )
        } header: {
            Text("علب الكهرباء والدمج")
        } footer: {
            Text("إذا كانت نقطتان من نفس الفئة أقرب من مسافة الدمج، سيضعهما التطبيق في مجموعة واحدة مع بقائهما بندين في الحصر.")
        }
    }
}

private struct AsBuiltPlacementNotice: View {
    var body: some View {
        Section("المقاسات الفعلية") {
            Label {
                VStack(alignment: .leading, spacing: 5) {
                    Text("سيتم تسجيل العناصر في أماكنها الحالية")
                        .font(.headline)
                    Text("لن يغيّر التطبيق الارتفاع أو البُعد عن الباب. سيقارن التقرير لاحقًا المقاسات الفعلية بالمقاسات القياسية ويُظهر مقدار الاختلاف.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "ruler.fill")
                    .foregroundStyle(.blue)
            }
        }
    }
}

struct RoomWorkflowView: View {
    @StateObject private var model: RoomCaptureModel
    let settings: ElectricalPlacementSettings
    let onClose: () -> Void

    init(destination: ScanDestination, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: RoomCaptureModel(destination: destination))
        settings = WorkspaceRepository.load(projectID: destination.surveyProjectID)?.settings
            ?? GlobalSettingsRepository.load()
        self.onClose = onClose
    }

    var body: some View {
        Group {
            if let project = model.project {
                ElectricalEditorView(
                    initialProject: project,
                    arSession: model.arSession,
                    settings: settings,
                    onClose: {
                        model.arSession.pause()
                        onClose()
                    }
                )
            } else {
                ScanRoomView(model: model, onClose: {
                    model.cancel()
                    onClose()
                })
            }
        }
    }
}

private struct ScanRoomView: View {
    @ObservedObject var model: RoomCaptureModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            RoomCaptureRepresentable(captureView: model.roomCaptureView)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                }
                .padding()

                Spacer()

                VStack(spacing: 12) {
                    if model.phase == .processing {
                        ProgressView("جارٍ تجهيز JSON وUSDZ…")
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        model.finish()
                    } label: {
                        Label("إنهاء المسح وتجهيز الغرفة", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.phase != .scanning)
                }
                .padding()
            }

            if case .failed(let message) = model.phase {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(message)
                        .multilineTextAlignment(.center)
                    Button("إغلاق", action: onClose)
                        .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .padding()
            }
        }
        .onAppear {
            model.start()
        }
    }
}

private struct ProjectDetailView: View {
    let project: RoomProject
    let surveyProjectID: UUID

    var body: some View {
        RoomViewerView(initialProject: project, surveyProjectID: surveyProjectID)
    }
}
