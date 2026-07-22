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
                    if store.projects.isEmpty {
                        ContentUnavailableView(
                            "لا توجد مشروعات بعد",
                            systemImage: "folder.badge.plus",
                            description: Text("اضغط زر + لإنشاء أول مشروع.")
                        )
                    } else {
                        ForEach(store.projects) { project in
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

    let projectID: UUID
    let parentItemID: UUID?
    let title: String

    @State private var selectedItemKind: WorkspaceItemKind?
    @State private var showNewScan = false
    @State private var pendingScanName: String?
    @State private var activeDestination: ScanDestination?
    @State private var showProjectSettings = false
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        showProjectSettings = true
                    } label: {
                        Label("إعدادات المشروع", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            addMenu
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
                            ScanDetailLoaderView(scanID: scan.id)
                        } label: {
                            ScanReferenceRow(scan: scan)
                        }
                    }
                }
            }

            if children.isEmpty && scans.isEmpty {
                Section {
                    ContentUnavailableView(
                        "هذا المجلد فارغ",
                        systemImage: "folder",
                        description: Text("استخدم زر + لإضافة مستوى تنظيمي أو بدء مسح جديد.")
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
        return "مسح \(title) - \(formatter.string(from: Date()))"
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
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ScanDetailLoaderView: View {
    let scanID: UUID

    var body: some View {
        if let project = ProjectRepository.load(projectID: scanID) {
            ProjectDetailView(project: project)
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

private struct ElectricalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings: ElectricalPlacementSettings

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
            Form {
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

                Section("قواعد التثبيت") {
                    Toggle("منع وضع النقاط داخل فتحات الأبواب والشبابيك", isOn: $settings.avoidOpenings)
                }

                Section {
                    Button("استعادة القيم الافتراضية", role: .destructive) {
                        settings = .standard
                    }
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

struct RoomWorkflowView: View {
    @StateObject private var model: RoomCaptureModel
    let onClose: () -> Void

    init(destination: ScanDestination, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: RoomCaptureModel(destination: destination))
        self.onClose = onClose
    }

    var body: some View {
        Group {
            if let project = model.project {
                ElectricalEditorView(
                    initialProject: project,
                    arSession: model.arSession,
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

    var body: some View {
        List {
            Section("ملخص المسح") {
                LabeledContent("الحوائط", value: "\(project.wallCount)")
                LabeledContent("الأبواب", value: "\(project.doorCount)")
                LabeledContent("الشبابيك", value: "\(project.windowCount)")
                LabeledContent("نقاط الكهرباء", value: "\(project.points.count)")
            }

            Section("الحصر") {
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

            Section("تصدير ملفات الإثبات") {
                if let url = try? ProjectRepository.fileURL(
                    projectID: project.id,
                    fileName: "project.json"
                ) {
                    ShareLink(item: url) {
                        Label("مشاركة المشروع والنقاط JSON", systemImage: "list.bullet.rectangle")
                    }
                }

                if let url = try? ProjectRepository.fileURL(
                    projectID: project.id,
                    fileName: project.processedJSONFile
                ) {
                    ShareLink(item: url) {
                        Label("مشاركة بيانات RoomPlan JSON", systemImage: "doc.text")
                    }
                }

                if let rawFile = project.rawJSONFile,
                   let url = try? ProjectRepository.fileURL(projectID: project.id, fileName: rawFile) {
                    ShareLink(item: url) {
                        Label("مشاركة البيانات الخام JSON", systemImage: "doc.badge.gearshape")
                    }
                }

                if let url = try? ProjectRepository.fileURL(
                    projectID: project.id,
                    fileName: project.usdzFile
                ) {
                    ShareLink(item: url) {
                        Label("مشاركة نموذج USDZ", systemImage: "cube")
                    }
                }
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
