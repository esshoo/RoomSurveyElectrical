import RoomPlan
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var store = ProjectStore()
    @State private var showNewProject = false
    @State private var showGlobalSettings = false
    @State private var showProjectImporter = false
    @State private var showDocumentImporter = false
    @State private var pendingImport: PreparedProjectPackage?
    @State private var pendingExternalDocument: ExternalDocumentInspection?
    @State private var packageNotice: ProjectPackageNotice?
    @State private var pendingWidgetProject: SurveyProject?

    var body: some View {
        NavigationStack {
            List {
                if !store.activeProjects.isEmpty {
                    Section("آخر المشروعات") {
                        RecentProjectsWidget(
                            projects: store.activeProjects.sorted {
                                $0.updatedAt > $1.updatedAt
                            }
                        )
                        .listRowInsets(
                            EdgeInsets(
                                top: 6,
                                leading: 0,
                                bottom: 8,
                                trailing: 0
                            )
                        )
                        .listRowBackground(Color.clear)

                    }
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
                    .accessibilityLabel("الإعدادات")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showDocumentImporter = true
                        } label: {
                            Label(
                                "فتح PDF أو DXF",
                                systemImage: "doc.text.magnifyingglass"
                            )
                        }

                        Button {
                            showProjectImporter = true
                        } label: {
                            Label(
                                "استيراد مشروع .3eroom",
                                systemImage: "archivebox.fill"
                            )
                        }
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                    .accessibilityLabel("فتح أو استيراد ملف")
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
                title: "الإعدادات",
                initialSettings: GlobalSettingsRepository.load()
            ) { settings in
                GlobalSettingsRepository.save(settings)
            }
        }
        .sheet(item: $pendingImport) { package in
            ProjectPackageImportSheet(
                package: package,
                existingProjects: store.projects
            ) { strategy in
                do {
                    let project = try store.importProjectPackage(
                        package,
                        strategy: strategy
                    )
                    pendingImport = nil
                    packageNotice = ProjectPackageNotice(
                        title: "تم استيراد المشروع",
                        message:
                            "تمت إضافة «\(project.name)» بكل المجلدات والمسحات والملفات التابعة له."
                    )
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
        }
        .sheet(item: $pendingExternalDocument) { inspection in
            ExternalDocumentOpenView(inspection: inspection)
                .environmentObject(store)
        }
        .sheet(item: $pendingWidgetProject) { project in
            WidgetProjectDestinationView(project: project)
                .environmentObject(store)
        }
        .fileImporter(
            isPresented: $showDocumentImporter,
            allowedContentTypes: [UTType.pdf, UTType.threeEDXF],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    handleOpenedURL(url)
                }
            case .failure(let error):
                packageNotice = ProjectPackageNotice(
                    title: "تعذر اختيار الملف",
                    message: error.localizedDescription
                )
            }
        }
        .fileImporter(
            isPresented: $showProjectImporter,
            allowedContentTypes: [UTType.threeERoomProject],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    prepareProjectImport(from: url)
                }
            case .failure(let error):
                packageNotice = ProjectPackageNotice(
                    title: "تعذر اختيار الملف",
                    message: error.localizedDescription
                )
            }
        }
        .onOpenURL(perform: handleOpenedURL)
        .alert(item: $packageNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("حسنًا"))
            )
        }
        .onAppear(perform: store.reload)
    }

    private func handleOpenedURL(_ url: URL) {
        if url.scheme?.lowercased() == "3eroomelectrical" {
            store.reload()
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let projectValue = components?.queryItems?.first(
                where: { $0.name == "project" }
            )?.value
            if let projectValue,
               let projectID = UUID(uuidString: projectValue),
               let project = store.project(id: projectID) {
                pendingWidgetProject = project
            }
            return
        }
        switch url.pathExtension.lowercased() {
        case "3eroom":
            prepareProjectImport(from: url)
        case "pdf", "dxf":
            Task {
                do {
                    let inspection = try await Task.detached(
                        priority: .userInitiated
                    ) {
                        try ExternalDocumentInspector.inspect(url)
                    }.value
                    pendingExternalDocument = inspection
                } catch {
                    packageNotice = ProjectPackageNotice(
                        title: "تعذر فتح الملف",
                        message: error.localizedDescription
                    )
                }
            }
        default:
            packageNotice = ProjectPackageNotice(
                title: "نوع ملف غير مدعوم",
                message: "يدعم التطبيق ملفات .3eroom وPDF وDXF."
            )
        }
    }

    private func prepareProjectImport(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            pendingImport = try ProjectPackageService.prepareImport(
                from: url
            )
        } catch {
            packageNotice = ProjectPackageNotice(
                title: "تعذر استيراد المشروع",
                message: error.localizedDescription
            )
        }
    }
}

private struct WidgetProjectDestinationView: View {
    @Environment(\.dismiss) private var dismiss
    let project: SurveyProject

    var body: some View {
        NavigationStack {
            ProjectBrowserView(
                projectID: project.id,
                parentItemID: nil,
                title: project.name
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("إغلاق المشروع")
                }
            }
        }
    }
}

private struct ProjectPackageNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ProjectPackageImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let package: PreparedProjectPackage
    let existingProjects: [SurveyProject]
    let onImport: (ProjectPackageImportStrategy) -> String?

    @State private var renamedProject = ""
    @State private var errorMessage: String?
    @State private var replacementProjectID: UUID?

    private var conflictingProject: SurveyProject? {
        existingProjects.first {
            $0.id == package.preview.projectID
        } ?? existingProjects.first {
            namesMatch($0.name, package.preview.name)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("ملف المشروع") {
                    LabeledContent(
                        "الاسم",
                        value: package.preview.name
                    )
                    LabeledContent(
                        "النوع",
                        value: package.preview.kind.title
                    )
                    LabeledContent(
                        "تاريخ الإنشاء",
                        value: package.preview.createdAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    LabeledContent(
                        "المجلدات والمساحات",
                        value: "\(package.preview.folderCount)"
                    )
                    LabeledContent(
                        "المسحات",
                        value: "\(package.preview.scanCount)"
                    )
                    LabeledContent(
                        "حجم البيانات",
                        value: ByteCountFormatter.string(
                            fromByteCount:
                                Int64(package.preview.totalBytes),
                            countStyle: .file
                        )
                    )
                }

                if package.preview.missingAssetCount > 0 {
                    Section {
                        Label(
                            "الحزمة لا تحتوي على \(package.preview.missingAssetCount) من ملفات المسح الاختيارية التي كانت مفقودة أصلًا عند التصدير.",
                            systemImage:
                                "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                if let conflictingProject {
                    Section("يوجد مشروع مطابق") {
                        Label(
                            "يوجد مشروع باسم «\(conflictingProject.name)». اختر طريقة الاستيراد.",
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .foregroundStyle(.orange)

                        Button {
                            runImport(.copy)
                        } label: {
                            Label(
                                "استيراد كنسخة جديدة",
                                systemImage:
                                    "plus.square.on.square"
                            )
                        }

                        TextField(
                            "اسم جديد للمشروع",
                            text: $renamedProject
                        )
                        Button {
                            runImport(.rename(renamedProject))
                        } label: {
                            Label(
                                "استيراد بالاسم الجديد",
                                systemImage: "pencil"
                            )
                        }
                        .disabled(
                            renamedProject.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        )

                        Button(role: .destructive) {
                            replacementProjectID =
                                conflictingProject.id
                        } label: {
                            Label(
                                "استبدال المشروع الموجود",
                                systemImage:
                                    "arrow.triangle.2.circlepath"
                            )
                        }
                    }
                } else {
                    Section {
                        Button {
                            runImport(.add)
                        } label: {
                            Label(
                                "استيراد المشروع",
                                systemImage: "square.and.arrow.down"
                            )
                        }
                    } footer: {
                        Text(
                            "سيتم استعادة الهيكل التنظيمي والمسحات والأبواب والشبابيك والكهرباء والإضاءة والإعدادات وملفات JSON وUSDZ."
                        )
                    }
                }

                if let errorMessage {
                    Section {
                        Label(
                            errorMessage,
                            systemImage:
                                "exclamationmark.octagon.fill"
                        )
                        .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("استيراد مشروع")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                renamedProject = "\(package.preview.name) مستورد"
            }
            .confirmationDialog(
                "استبدال المشروع الموجود؟",
                isPresented: Binding(
                    get: { replacementProjectID != nil },
                    set: {
                        if !$0 {
                            replacementProjectID = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button(
                    "استبدال المشروع وكل مسحاته",
                    role: .destructive
                ) {
                    if let replacementProjectID {
                        runImport(
                            .replace(replacementProjectID)
                        )
                        self.replacementProjectID = nil
                    }
                }
                Button("إلغاء", role: .cancel) {
                    replacementProjectID = nil
                }
            } message: {
                Text(
                    "سيُحذف محتوى المشروع الموجود ويحل محله محتوى الملف المستورد. لا يمكن التراجع عن هذه العملية."
                )
            }
        }
    }

    private func runImport(
        _ strategy: ProjectPackageImportStrategy
    ) {
        errorMessage = onImport(strategy)
        if errorMessage == nil {
            dismiss()
        }
    }

    private func namesMatch(
        _ first: String,
        _ second: String
    ) -> Bool {
        first.compare(
            second,
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "ar")
        ) == .orderedSame
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

struct ProjectBrowserView: View {
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
    @State private var exportedProjectFile: ExportedFile?

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
        .sheet(item: $exportedProjectFile) { file in
            ExportShareSheet(items: [file.url])
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

            if parentItemID == nil {
                Section("تحديث وتحرير المشروع") {
                    NavigationLink {
                        ProjectFoundationView(projectID: projectID)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("مركز تحديث المشروع")
                                Text("الإعدادات الموروثة والطبقات وسجل التعديلات ونقاط الاستعادة")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "square.3.layers.3d")
                                .foregroundStyle(.blue)
                        }
                    }
                }
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
                    exportProjectPackage()
                } label: {
                    Label(
                        "تصدير ملف المشروع .3eroom",
                        systemImage: "doc.zipper"
                    )
                }

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

    private func exportProjectPackage() {
        do {
            guard let project = store.project(id: projectID) else {
                throw WorkspaceRepository.RepositoryError.projectNotFound
            }
            let temporaryURL = try ProjectPackageService.makePackage(
                projectID: projectID
            )
            let savedURL = try ExportRegistry.register(
                sourceURL: temporaryURL,
                kind: .projectPackage,
                project: project,
                scopeItemID: parentItemID,
                roomIDs: project.scans.map(\.id)
            )
            exportedProjectFile = ExportedFile(url: savedURL)
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
        if scan.resolvedSpatialAlignmentState == .independentNeedsAlignment {
          Label(
            "مسح مستقل — المحاذاة في Build 49",
            systemImage: scan.resolvedSpatialAlignmentState.systemImage
          )
          .font(.caption2)
          .foregroundStyle(.orange)
        }
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
    let project: RoomProject?
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
                let roomProject = ProjectRepository.load(projectID: scan.id)
                return ScopedTakeoffRoom(
                    scan: scan,
                    project: roomProject,
                    summary: roomProject.map { RoomTakeoffSummary(project: $0) },
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
                    ScanTakeoffDetailView(
                        summary: summary,
                        project: room.project
                    )
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
    let project: RoomProject?

    init(
        summary: RoomTakeoffSummary,
        project: RoomProject? = nil
    ) {
        self.summary = summary
        self.project = project
    }

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

            if let objects = project?.objects, !objects.isEmpty {
                Section("تفاصيل الأثاث") {
                    ForEach(Array(objects.enumerated()), id: \.element.id) {
                        index, object in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(object.title) \(index + 1)")
                                .font(.headline)
                            Text(
                                "\(formattedLength(object.width)) × "
                                    + "\(formattedLength(object.depth)) × "
                                    + "\(formattedLength(object.height))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        }
                        .padding(.vertical, 2)
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
                        if let project {
                            NavigationLink {
                                TakeoffElectricalGroupDetailView(
                                    project: project,
                                    type: line.type,
                                    status: line.status
                                )
                            } label: {
                                electricalLineLabel(line, project: project)
                            }
                        } else {
                            electricalLineLabel(line, project: nil)
                        }
                    }
                    ceilingLightLine(
                        source: .cameraExisting,
                        count: summary.existingCeilingLightCount
                    )
                    ceilingLightLine(
                        source: .planManual,
                        count: summary.manualCeilingLightCount
                    )
                    ceilingLightLine(
                        source: .planAutomatic,
                        count: summary.automaticCeilingLightCount
                    )
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

    @ViewBuilder
    private func electricalLineLabel(
        _ line: ElectricalTakeoffLine,
        project: RoomProject?
    ) -> some View {
        HStack(spacing: 12) {
            Label(
                line.type.title,
                systemImage: line.type.systemImage
            )
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(line.count) • \(line.status.title)")
                    .font(.headline.monospacedDigit())
                if let project {
                    Text(
                        "ارتفاع "
                            + electricalTakeoffHeightSummary(
                                project: project,
                                type: line.type,
                                status: line.status
                            )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func ceilingLightLine(
        source: CeilingLightSource,
        count: Int
    ) -> some View {
        if count > 0 {
            if let project {
                NavigationLink {
                    TakeoffCeilingLightGroupDetailView(
                        project: project,
                        source: source
                    )
                } label: {
                    LabeledContent(source.takeoffTitle, value: "\(count)")
                }
            } else {
                LabeledContent(source.takeoffTitle, value: "\(count)")
            }
        }
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
    case app
    case electrical
    case furniture
    case plumbing
    case finishes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "عام"
        case .app: "التطبيق"
        case .electrical: "الكهرباء"
        case .furniture: "الفرش"
        case .plumbing: "السباكة"
        case .finishes: "الدهانات"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .app: "info.circle.fill"
        case .electrical: "bolt.fill"
        case .furniture: "chair.lounge.fill"
        case .plumbing: "drop.fill"
        case .finishes: "paintbrush.fill"
        }
    }
}

struct ElectricalSettingsView: View {
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
                Label("معلومات الإصدار وتوافق الجهاز والويدجت داخل تبويب التطبيق.", systemImage: "info.circle.fill")
            }

        case .app:
            appInformationSections

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

    @ViewBuilder
    private var appInformationSections: some View {
        Section("المسح المكاني") {
            Picker(
                "محتوى المسح",
                selection: $settings.spatialScanContentMode
            ) {
                ForEach(SpatialScanContentMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Text(settings.spatialScanContentMode.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                "الأداء والجودة",
                selection: $settings.spatialScanPerformanceProfile
            ) {
                ForEach(SpatialScanPerformanceProfile.allCases) { profile in
                    Label(profile.title, systemImage: profile.systemImage)
                        .tag(profile)
                }
            }
            .pickerStyle(.menu)

            Text(settings.spatialScanPerformanceProfile.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(
                "إبقاء الشاشة مضاءة أثناء المسح المكاني",
                isOn: $settings.keepScreenAwakeDuringSpatialScan
            )
            Text(
                "يُعطّل التطبيق القفل التلقائي أثناء مرحلة RoomPlan فقط، "
                    + "ثم يعيد إعداد الشاشة الطبيعي فور إنهاء المسح أو الخروج منه."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("الحماية الحرارية") {
            Picker(
                "مستوى الحماية",
                selection: $settings.spatialScanThermalProtectionMode
            ) {
                ForEach(SpatialScanThermalProtectionMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.menu)

            Text(settings.spatialScanThermalProtectionMode.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                "استقرار الحرارة قبل المتابعة",
                selection: $settings.thermalResumeStabilityDuration
            ) {
                ForEach(ThermalResumeStabilityDuration.allCases) { duration in
                    Text(duration.title).tag(duration)
                }
            }
            .pickerStyle(.menu)

            Toggle(
                "إظهار حالة الحرارة أثناء المسح",
                isOn: $settings.showThermalStateDuringSpatialScan
            )

            LabeledContent("الحفظ التلقائي قبل الإيقاف", value: "مفعّل دائمًا")

            Text(
                "لا يمكن تعطيل الحفظ الوقائي أو الإيقاف عند الحالة الحرجة. "
                    + "التطبيق يعتمد حالات الحرارة التي يحددها iOS لكل جهاز، وليس درجة ثابتة بالسيلسيوس."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("استكمال المسح والتعرف على المكان") {
            Picker(
                "صرامة التعرف",
                selection: $settings.spatialRelocalizationStrictness
            ) {
                ForEach(SpatialRelocalizationStrictness.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.menu)

            Text(settings.spatialRelocalizationStrictness.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(
                "استخدام الموقع والاتجاه كعامل مساعد اختياري",
                isOn: $settings.useOptionalLocationAssistForResume
            )

            Text(
                "يطلب التطبيق إذن الموقع أثناء المسح فقط عند تفعيل هذا الخيار. "
                    + "يستخدم موقعًا تقريبيًا واتجاه البوصلة لمنع الاستكمال في مكان مختلف، "
                    + "ولا يعتمد عليهما وحدهما ولا يمنع رفض الإذن من استخدام المسح. "
                    + "تُحفظ هذه البيانات على الجهاز فقط ولا تُضمّن في حزمة مشاركة المشروع."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            LabeledContent(
                "المرجع الأساسي",
                value: "خريطة AR + آخر حائط وأبعاده وفتحاته"
            )
        }

        Section("تحديث وتحرير المشروع") {
            NavigationLink {
                ProjectFoundationDefaultsView()
            } label: {
                Label(
                    "إعدادات الطبقات ونقاط الاستعادة",
                    systemImage: "square.3.layers.3d"
                )
            }

            Text(
                "تحدد القيم الافتراضية للمشروعات الجديدة، بينما يمكن لكل مشروع أو غرفة أو عنصر استخدام إعدادات مخصصة."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("تأثير الوضع الحالي") {
            LabeledContent(
                "الفرش داخل المشروع",
                value: settings.spatialScanContentMode.includesFurniture
                    ? "محفوظ ومعروض"
                    : "غير محفوظ"
            )
            LabeledContent(
                "صور المسح الفوتوغرافي",
                value: "حتى \(Int(settings.spatialScanPerformanceProfile.capturedPhotoMaximumDimension)) px"
            )
            LabeledContent(
                "صورة الحائط المركبة",
                value: "حتى \(Int(settings.spatialScanPerformanceProfile.photoCompositeMaximumDimension)) px"
            )
            LabeledContent(
                "العرض ثلاثي الأبعاد",
                value: "\(settings.spatialScanPerformanceProfile.viewerFramesPerSecond) إطار/ث"
            )
            LabeledContent(
                "الحماية الحرارية",
                value: settings.spatialScanThermalProtectionMode.title
            )
            Text(
                "وضع الحوائط والفتحات فقط يمنع حفظ ورسم الفرش في المشروع، "
                    + "لكن RoomPlan قد يستمر في ملاحظته داخليًا أثناء فهم المشهد."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("حول التطبيق") {
            LabeledContent("الاسم", value: "3E Room Electrical")
            LabeledContent("الإصدار", value: appVersion)
            LabeledContent("رقم البناء", value: appBuild)
            LabeledContent("Bundle ID", value: appBundleIdentifier)
        }

        Section("توافق الجهاز") {
            Label(
                RoomCaptureSession.isSupported
                    ? "المسح ثلاثي الأبعاد وLiDAR متاحان على هذا الجهاز."
                    : "المسح يتطلب iPhone أو iPad مزودًا بحساس LiDAR.",
                systemImage: RoomCaptureSession.isSupported
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(
                RoomCaptureSession.isSupported ? Color.green : Color.orange
            )

            LabeledContent("ملفات المشروع", value: ".3eroom")
            LabeledContent("المعاينة", value: "PDF وDXF")
            LabeledContent("تصدير CAD", value: "DXF 2007 • UTF-8 • Model Space")
        }

        Section("ويدجت الشاشة الرئيسية") {
            let widgetReport = HomeWidgetDiagnostics.report

            Label(
                widgetReport.status.message,
                systemImage: widgetReport.status.systemImage
            )
            .font(.caption)
            .foregroundStyle(
                widgetReport.status == .ready ? Color.green : Color.red
            )

            LabeledContent(
                "Bundle ID التطبيق",
                value: widgetReport.hostBundleIdentifier
            )
            .font(.caption2)

            LabeledContent(
                "Bundle ID الويدجت",
                value: widgetReport.widgetBundleIdentifier
            )
            .font(.caption2)

            LabeledContent(
                "المتوقع",
                value: widgetReport.expectedWidgetBundleIdentifier
            )
            .font(.caption2)

            LabeledContent(
                "Extension Point",
                value: widgetReport.extensionPointIdentifier
            )
            .font(.caption2)

            Divider()

            Label(
                widgetReport.provisioningMessage,
                systemImage: widgetReport.provisioningIsValid
                    ? "checkmark.shield.fill"
                    : "xmark.shield.fill"
            )
            .font(.caption)
            .foregroundStyle(
                widgetReport.provisioningIsValid ? Color.green : Color.orange
            )

            LabeledContent(
                "App Profile ID",
                value: widgetReport.hostProfile.applicationIdentifier
            )
            .font(.caption2)

            LabeledContent(
                "Widget Profile ID",
                value: widgetReport.widgetProfile.applicationIdentifier
            )
            .font(.caption2)

            LabeledContent(
                "فريق التطبيق",
                value: widgetReport.hostProfile.teamIdentifier
            )
            .font(.caption2)

            LabeledContent(
                "فريق الويدجت",
                value: widgetReport.widgetProfile.teamIdentifier
            )
            .font(.caption2)
        }
    }

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "غير معروف"
    }

    private var appBuild: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "غير معروف"
    }

    private var appBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "غير معروف"
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
        let resolvedSettings = WorkspaceRepository.load(
            projectID: destination.surveyProjectID
        )?.settings ?? GlobalSettingsRepository.load()
        settings = resolvedSettings
        _model = StateObject(
            wrappedValue: RoomCaptureModel(
                destination: destination,
                settings: resolvedSettings
            )
        )
        self.onClose = onClose
    }

    init(
        existingProject: RoomProject,
        surveyProjectID: UUID,
        onClose: @escaping () -> Void
    ) {
        let resolvedSettings = WorkspaceRepository.load(
            projectID: surveyProjectID
        )?.settings ?? existingProject.electricalSettings ?? GlobalSettingsRepository.load()
        settings = resolvedSettings
        _model = StateObject(
            wrappedValue: RoomCaptureModel(
                existingProject: existingProject,
                settings: resolvedSettings
            )
        )
        self.onClose = onClose
    }

    var body: some View {
        Group {
            if model.phase == .ready, let project = model.project {
                ElectricalEditorView(
                    initialProject: project,
                    arSession: model.arSession,
                    worldToProjectTransform: model.currentWorldToProjectTransform,
                    settings: settings,
                    onClose: {
                        model.arSession.pause()
                        onClose()
                    }
                )
            } else {
                ScanRoomView(
                    model: model,
                    keepScreenAwakeDuringSpatialScan: settings.keepScreenAwakeDuringSpatialScan,
                    scanContentMode: settings.spatialScanContentMode,
                    showThermalState: settings.showThermalStateDuringSpatialScan,
                    onClose: {
                        model.cancel()
                        onClose()
                    }
                )
            }
        }
    }
}

private struct ScanRoomView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: RoomCaptureModel
    let keepScreenAwakeDuringSpatialScan: Bool
    let scanContentMode: SpatialScanContentMode
    let showThermalState: Bool
    let onClose: () -> Void

    @State private var closeAfterSave = false
    @State private var showManualVisualResumeConfirmation = false

    var body: some View {
        ZStack {
            SpatialCaptureRepresentable(hostView: model.captureHostView)
                .ignoresSafeArea()

            if (model.phase == .relocalizing
                    || model.phase == .relocalizationFailed),
               let overlayImage = model.referenceOverlayImage {
                Image(uiImage: overlayImage)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(
                        x: model.referenceOverlayFlipHorizontal ? -1 : 1,
                        y: model.referenceOverlayFlipVertical ? -1 : 1
                    )
                    .opacity(model.referenceOverlayOpacity)
                    .blendMode(
                        model.referenceOverlayMode == .edges ? .screen : .normal
                    )
                    .ignoresSafeArea()
                    .overlay {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(.white.opacity(0.75), lineWidth: 2)
                                .padding(22)
                            Rectangle()
                                .fill(.white.opacity(0.72))
                                .frame(width: 2, height: 42)
                            Rectangle()
                                .fill(.white.opacity(0.72))
                                .frame(width: 42, height: 2)
                        }
                        .shadow(color: .black.opacity(0.55), radius: 3)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            VStack {
                HStack {
                    Button(action: requestSafeClose) {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                    Label(
                        scanContentMode.title,
                        systemImage: scanContentMode.includesFurniture
                            ? "chair.lounge.fill"
                            : "rectangle.3.group.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .padding()

                if showThermalState,
                   model.phase == .scanning
                    || model.phase == .relocalizing
                    || model.phase == .relocalizationFailed {
                    HStack {
                        Spacer()
                        Label(
                            "الحرارة: \(model.thermalStateTitle)",
                            systemImage: thermalStateSystemImage
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(thermalStateColor)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.horizontal)
                    .accessibilityLabel(model.thermalStateMessage)
                }

                Spacer()

                VStack(spacing: 12) {
                    switch model.phase {
                    case .relocalizing:
                        VStack(spacing: 10) {
                            Text("مطابقة موضع الاستكمال")
                                .font(.headline)

                            visualResumeControls

                            if !model.referenceWallSummary.isEmpty {
                                Text(model.referenceWallSummary)
                                    .font(.caption.weight(.semibold))
                            }

                            ProgressView(value: model.relocalizationProgress)
                                .tint(.blue)

                            Text(model.relocalizationMessage)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)

                            if !model.relocalizationEvidenceMessage.isEmpty {
                                Text(model.relocalizationEvidenceMessage)
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                            }

                            if !model.locationAssistMessage.isEmpty {
                                Label(
                                    model.locationAssistMessage,
                                    systemImage: "location.north.line.fill"
                                )
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                            }

                            Text("صرامة التعرف: \(model.relocalizationStrictnessTitle)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)

                            if model.isManualVisualResumeAvailable {
                                Button {
                                    showManualVisualResumeConfirmation = true
                                } label: {
                                    Label(
                                        model.isPreparingManualVisualResume
                                            ? "جارٍ تجهيز الاستكمال…"
                                            : "استكمال بعد المطابقة البصرية",
                                        systemImage: "viewfinder.circle.fill"
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .disabled(model.isPreparingManualVisualResume)
                            }

                            Button {
                                model.pauseRelocalizationManually()
                            } label: {
                                Label(
                                    "إيقاف المحاولة والعودة للجزء المحفوظ",
                                    systemImage: "pause.circle"
                                )
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 14)
                        )

                    case .processing:
                        ProgressView(
                            model.thermalState == .serious || model.thermalState == .critical
                                ? "جارٍ إيقاف الكاميرا وحفظ المسح لحماية الهاتف…"
                                : "جارٍ حفظ الجزء الحالي وخريطة المكان…"
                        )
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 14)
                        )

                    case .coolingDown:
                        thermalCoolingCard

                    case .paused:
                        savedPauseCard

                    case .relocalizationFailed:
                        relocalizationFailureCard

                    default:
                        EmptyView()
                    }

                    if model.phase == .scanning {
                        VStack(spacing: 10) {
                            Button {
                                model.pauseAndSave()
                            } label: {
                                Label(
                                    "إيقاف مؤقت وحفظ",
                                    systemImage: "pause.circle.fill"
                                )
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)

                            Button {
                                model.finish()
                            } label: {
                                Label(
                                    "إنهاء المسح وتجهيز الغرفة",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
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
            updateIdleTimer(for: model.phase)
        }
        .onChange(of: model.phase) { _, newPhase in
            updateIdleTimer(for: newPhase)
            if closeAfterSave,
               newPhase == .paused
                    || newPhase == .ready
                    || newPhase == .coolingDown
                    || newPhase == .relocalizationFailed {
                closeAfterSave = false
                onClose()
            }
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            if newScenePhase == .background {
                model.pauseForApplicationLifecycle()
            }
            updateIdleTimer(for: model.phase)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .confirmationDialog(
            "تأكيد المطابقة البصرية",
            isPresented: $showManualVisualResumeConfirmation,
            titleVisibility: .visible
        ) {
            Button("استكمال المسح من هذا الموضع") {
                model.resumeFromVisualAlignment()
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text(
                "ثبّت الهاتف بحيث تتطابق الصورة الشفافة مع الحائط والفتحات. "
                    + "سيستخدم التطبيق اتجاهًا أفقيًا مرتبطًا بالجاذبية فقط، ثم سيمنع الدمج إذا لم يجد حائطًا مشتركًا مؤكدًا."
            )
        }
    }

    private var savedPauseCard: some View {
        VStack(spacing: 12) {
            Image(systemName: model.savedPauseReason?.systemImage ?? "pause.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("تم حفظ المسح وإيقافه مؤقتًا")
                .font(.headline)

            if let reason = model.savedPauseReason {
                Text("السبب: \(reason.title)")
                    .font(.subheadline.weight(.semibold))
                Text(reason.detail)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if let savedPauseDate = model.savedPauseDate {
                Text("آخر حفظ: \(savedPauseDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let quality = model.savedWorldMapQualityTitle {
                LabeledContent("جودة خريطة المكان", value: quality)
                    .font(.caption)
            }

            if let detail = model.savedWorldMapDetail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !model.referenceWallSummary.isEmpty {
                Text(model.referenceWallSummary)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
            }

            if model.isLiveSessionResumeAvailable {
                Label(
                    "جلسة AR الأصلية ما زالت مستمرة؛ سيتم الاستكمال مباشرة دون إعادة التعرف.",
                    systemImage: "link.circle.fill"
                )
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.green)
            }

            if model.hasRecoveredResumeCheckpoint {
                Button {
                    model.recoverLatestResumeCheckpoint()
                } label: {
                    Label(
                        "استعادة آخر نقطة حفظ آمنة",
                        systemImage: "arrow.counterclockwise.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }

            if !model.spatialMergeSafetyMessage.isEmpty {
                Text(model.spatialMergeSafetyMessage)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if model.canResumeSavedScan {
                Button {
                    model.resumeSavedScan()
                } label: {
                    Label(
                        model.resumeSavedScanTitle,
                        systemImage: model.isLiveSessionResumeAvailable
                            ? "play.circle.fill"
                            : "viewfinder.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Label(
                    "لا توجد خريطة مكان صالحة للاستكمال الدقيق.",
                    systemImage: "map.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Button {
                model.acceptSavedPartialResult()
            } label: {
                Label(
                    "اعتماد الجزء المحفوظ والانتقال للكهرباء",
                    systemImage: "checkmark.shield.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button("إغلاق والعودة للمشروع", action: onClose)
                .buttonStyle(.borderless)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    @ViewBuilder
    private var visualResumeControls: some View {
        if model.referenceWallImage != nil {
            VStack(spacing: 9) {
                Picker("طريقة عرض المرجع", selection: $model.referenceOverlayMode) {
                    ForEach(SpatialResumeOverlayMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.secondary)
                    Slider(
                        value: $model.referenceOverlayOpacity,
                        in: 0.12...0.88
                    )
                    Text("\(Int((model.referenceOverlayOpacity * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 42, alignment: .trailing)
                }

                HStack(spacing: 8) {
                    Button {
                        model.referenceOverlayFlipHorizontal.toggle()
                    } label: {
                        Label("قلب أفقي", systemImage: "arrow.left.and.right")
                    }
                    .buttonStyle(.bordered)
                    .tint(model.referenceOverlayFlipHorizontal ? .orange : .blue)

                    Button {
                        model.referenceOverlayFlipVertical.toggle()
                    } label: {
                        Label("قلب رأسي", systemImage: "arrow.up.and.down")
                    }
                    .buttonStyle(.bordered)
                    .tint(model.referenceOverlayFlipVertical ? .orange : .blue)
                }
                .font(.caption)

                Label(
                    "ثقة المطابقة: \(model.visualAlignmentConfidence.title)",
                    systemImage: model.visualAlignmentConfidence.systemImage
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(visualAlignmentColor)

                Text(model.visualAlignmentConfidenceMessage)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        } else {
            Label(
                "لا توجد لقطة مرجعية محفوظة لهذا المسح.",
                systemImage: "photo.badge.exclamationmark"
            )
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    private var visualAlignmentColor: Color {
        switch model.visualAlignmentConfidence {
        case .low: .orange
        case .medium: .yellow
        case .high: .green
        }
    }

    private var relocalizationFailureCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.slash.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("تعذر التعرف على المكان")
                .font(.headline)

            Text(model.relocalizationFailureMessage)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            visualResumeControls

            if model.isManualVisualResumeAvailable {
                Button {
                    showManualVisualResumeConfirmation = true
                } label: {
                    Label(
                        model.isPreparingManualVisualResume
                            ? "جارٍ تجهيز الاستكمال…"
                            : "استكمال بعد المطابقة البصرية",
                        systemImage: "viewfinder.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(model.isPreparingManualVisualResume)
            }

            if model.hasRecoveredResumeCheckpoint {
                Button {
                    model.recoverLatestResumeCheckpoint()
                } label: {
                    Label(
                        "استعادة آخر نقطة حفظ آمنة",
                        systemImage: "arrow.counterclockwise.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }

            if model.canResumeSavedScan {
                Button {
                    model.retryRelocalization()
                } label: {
                    Label("إعادة محاولة التعرف", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                model.acceptSavedPartialResult()
            } label: {
                Label(
                    "اعتماد الجزء المحفوظ دون استكمال",
                    systemImage: "checkmark.shield.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button("إغلاق والعودة للمشروع", action: onClose)
                .buttonStyle(.borderless)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func requestSafeClose() {
        switch model.phase {
        case .scanning:
            closeAfterSave = true
            model.pauseAndSave()
        case .processing:
            closeAfterSave = true
        case .relocalizing:
            model.pauseRelocalizationManually()
            onClose()
        default:
            onClose()
        }
    }

    private var thermalCoolingCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "thermometer.high")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text(model.thermalCoolingTitle)
                .font(.headline)

            Text(
                "حالة حرارة الهاتف: \(model.thermalStateTitle). "
                    + model.thermalCoolingDetail
            )
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)

            Text("وضع الحماية: \(model.thermalProtectionTitle)")
                .font(.caption.weight(.semibold))

            if model.canResumeAfterCooling {
                Button {
                    model.resumeAfterCooling()
                } label: {
                    Label(
                        "متابعة المسح من نفس المكان",
                        systemImage: "play.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else if model.isCurrentThermalStateAcceptableForResume {
                ProgressView()
                    .controlSize(.regular)
                Text(
                    "تأكد استقرار الحرارة… متبقٍ \(model.thermalResumeSecondsRemaining) ثانية"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ProgressView(
                    model.thermalState == .fair
                        ? "الحماية المبكرة تنتظر عودة الحرارة إلى طبيعية…"
                        : "انتظر حتى تنخفض حرارة الهاتف…"
                )
            }

            if model.project != nil {
                Button {
                    model.acceptSavedPartialResult()
                } label: {
                    Label(
                        "اعتماد الجزء المحفوظ والانتقال للكهرباء",
                        systemImage: "checkmark.shield.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private var thermalStateSystemImage: String {
        switch model.thermalState {
        case .nominal: return "thermometer.low"
        case .fair: return "thermometer.medium"
        case .serious, .critical: return "thermometer.high"
        @unknown default: return "thermometer"
        }
    }

    private var thermalStateColor: Color {
        switch model.thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }

    private func updateIdleTimer(for phase: RoomCaptureModel.Phase) {
        UIApplication.shared.isIdleTimerDisabled =
            keepScreenAwakeDuringSpatialScan
                && phase == .scanning
                && scenePhase == .active
    }
}

private struct ProjectDetailView: View {
    let project: RoomProject
    let surveyProjectID: UUID

    var body: some View {
        RoomViewerView(initialProject: project, surveyProjectID: surveyProjectID)
    }
}
