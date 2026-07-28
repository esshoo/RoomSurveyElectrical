import SwiftUI

struct ProjectFoundationView: View {
    @EnvironmentObject private var store: ProjectStore

    let projectID: UUID

    @State private var showElectricalSettings = false
    @State private var showNewChangeSet = false
    @State private var pendingRestore: RecoverySnapshotMetadata?
    @State private var pendingRevert: ProjectChangeSet?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let project = store.project(id: projectID) {
                projectContent(project)
            } else {
                ContentUnavailableView(
                    "المشروع غير موجود",
                    systemImage: "folder.badge.questionmark"
                )
            }
        }
        .navigationTitle("تحديث وتحرير المشروع")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showElectricalSettings) {
            if let project = store.project(id: projectID) {
                ElectricalSettingsView(
                    title: "إعدادات \(project.name)",
                    initialSettings: project.settings
                ) { settings in
                    perform {
                        try store.updateSettings(
                            projectID: projectID,
                            settings: settings
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showNewChangeSet) {
            NewProjectChangeSetSheet { name, mode, notes in
                do {
                    try store.beginChangeSet(
                        projectID: projectID,
                        name: name,
                        mode: mode,
                        notes: notes
                    )
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
        }
        .alert(
            "استعادة نقطة محفوظة؟",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            presenting: pendingRestore
        ) { snapshot in
            Button("استعادة", role: .destructive) {
                perform {
                    try store.restoreRecoverySnapshot(
                        projectID: projectID,
                        snapshotID: snapshot.id
                    )
                }
                pendingRestore = nil
            }
            Button("إلغاء", role: .cancel) {
                pendingRestore = nil
            }
        } message: { snapshot in
            Text(
                "سيتم إنشاء نقطة أمان للحالة الحالية أولًا، ثم استعادة: \(snapshot.reason)."
            )
        }
        .alert(
            "التراجع عن جلسة التعديل؟",
            isPresented: Binding(
                get: { pendingRevert != nil },
                set: { if !$0 { pendingRevert = nil } }
            ),
            presenting: pendingRevert
        ) { changeSet in
            Button("تراجع", role: .destructive) {
                perform {
                    try store.revertChangeSet(
                        projectID: projectID,
                        changeSetID: changeSet.id
                    )
                }
                pendingRevert = nil
            }
            Button("إلغاء", role: .cancel) {
                pendingRevert = nil
            }
        } message: { changeSet in
            Text(
                "سيعود المشروع إلى نقطة البداية المحفوظة قبل جلسة \(changeSet.name). لا يمكن التراجع عن جلسة إذا وُجدت جلسات أحدث نشطة."
            )
        }
        .alert(
            "تعذر تنفيذ العملية",
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
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func projectContent(_ project: SurveyProject) -> some View {
        let worldMapSummary = WorkspaceRepository.worldMapSummary(for: project)
        let changeSets = (project.changeSets ?? [])
            .sorted { $0.createdAt > $1.createdAt }
        let snapshots = (project.recoverySnapshots ?? [])
            .sorted { $0.createdAt > $1.createdAt }

        return List {
            Section {
                LabeledContent(
                    "إصدار بنية التحديث",
                    value: "\(project.foundationSchemaVersion ?? 1)"
                )
                LabeledContent(
                    "الوضع المفضل",
                    value: (project.preferredWorkspaceMode ?? .presentation).title
                )
                LabeledContent(
                    "إعدادات الغرف والمسحات",
                    value: "\(project.roomSettings?.count ?? 0)"
                )
                LabeledContent(
                    "استثناءات العناصر",
                    value: "\(project.elementOverrides?.count ?? 0)"
                )
            } header: {
                Text("أساس المشروع")
            } footer: {
                Text(
                    "المسح الأصلي يظل محفوظًا، بينما التعديلات والإعدادات والطبقات تُحفظ بصورة مستقلة وقابلة للمراجعة."
                )
            }

            Section("أوضاع المشروع") {
                ForEach(ProjectWorkspaceMode.allCases) { mode in
                    Button {
                        perform {
                            try store.setPreferredWorkspaceMode(
                                projectID: projectID,
                                mode: mode
                            )
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.systemImage)
                                .frame(width: 28)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title)
                                    .foregroundStyle(.primary)
                                Text(modeAvailabilityText(mode))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if project.preferredWorkspaceMode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

            Section {
                LabeledContent(
                    "مصدر الكهرباء والمسح",
                    value: project.projectSettings?.usesInheritedElectricalSettings == false
                        ? "مخصص للمشروع"
                        : "موروث من التطبيق"
                )

                Button {
                    showElectricalSettings = true
                } label: {
                    Label(
                        "تعديل إعدادات المشروع",
                        systemImage: "slider.horizontal.3"
                    )
                }

                if project.projectSettings?.usesInheritedElectricalSettings == false {
                    Button(role: .destructive) {
                        perform {
                            try store.resetProjectElectricalSettings(
                                projectID: projectID
                            )
                        }
                    } label: {
                        Label(
                            "الرجوع إلى إعدادات التطبيق",
                            systemImage: "arrow.uturn.backward.circle"
                        )
                    }
                }
            } header: {
                Text("وراثة الإعدادات")
            } footer: {
                Text(
                    "الترتيب المعتمد: التطبيق ← المشروع ← الغرفة أو المسح ← العنصر. المستوى الأكثر تخصيصًا هو المستخدم."
                )
            }

            Section {
                ForEach(
                    ProjectLayerState.normalized(
                        project.layerStates ?? ProjectLayerState.standardStates
                    )
                ) { layer in
                    HStack(spacing: 12) {
                        Image(systemName: layer.kind.systemImage)
                            .foregroundStyle(.blue)
                            .frame(width: 26)

                        Toggle(
                            layer.kind.title,
                            isOn: Binding(
                                get: { layer.isVisible },
                                set: { visible in
                                    perform {
                                        try store.updateLayerState(
                                            projectID: projectID,
                                            kind: layer.kind,
                                            isVisible: visible
                                        )
                                    }
                                }
                            )
                        )
                        .disabled(layer.isLocked)

                        Button {
                            perform {
                                try store.updateLayerState(
                                    projectID: projectID,
                                    kind: layer.kind,
                                    isLocked: !layer.isLocked
                                )
                            }
                        } label: {
                            Image(
                                systemName: layer.isLocked
                                    ? "lock.fill"
                                    : "lock.open"
                            )
                            .foregroundStyle(
                                layer.isLocked ? Color.orange : Color.secondary
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            layer.isLocked ? "إلغاء قفل الطبقة" : "قفل الطبقة"
                        )
                    }
                }
            } header: {
                Text("طبقات المشروع")
            } footer: {
                Text(
                    "قفل الطبقة يمنع تغيير ظهورها من عارض المسح. فصل الموجود عن المقترح داخل الرسم نفسه سيكتمل مع جلسات تحديث العناصر."
                )
            }

            Section {
                LabeledContent(
                    "المسحات القابلة للاستكمال",
                    value: "\(worldMapSummary.availableCount) من \(worldMapSummary.totalCount)"
                )
                if let latest = worldMapSummary.latestSavedAt {
                    LabeledContent(
                        "آخر حفظ للخريطة",
                        value: latest.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }

                ForEach(worldMapSummary.scans) { scan in
                    HStack {
                        Label(
                            scan.scanName,
                            systemImage: scan.isAvailable
                                ? "checkmark.location.fill"
                                : "location.slash.fill"
                        )
                        Spacer()
                        Text(scan.isAvailable ? "متاحة" : "غير متاحة")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                scan.isAvailable ? Color.green : Color.orange
                            )
                    }
                }
            } header: {
                Text("ARWorldMap والاستكمال")
            } footer: {
                if project.scans.isEmpty {
                    Text("لا توجد مسحات داخل المشروع بعد.")
                } else {
                    Text(
                        "وجود الخريطة يعني أن التطبيق يستطيع محاولة إعادة التعرف على المكان؛ نجاح التموضع النهائي يُختبر في الموقع نفسه."
                    )
                }
            }

            Section {
                Button {
                    showNewChangeSet = true
                } label: {
                    Label("بدء جلسة تعديل", systemImage: "plus.circle.fill")
                }

                if changeSets.isEmpty {
                    Text("لا توجد جلسات تعديل مسجلة.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(changeSets) { changeSet in
                        ChangeSetRow(
                            changeSet: changeSet,
                            canRevert: canRevert(
                                changeSet,
                                among: changeSets
                            ),
                            onComplete: {
                                perform {
                                    try store.completeChangeSet(
                                        projectID: projectID,
                                        changeSetID: changeSet.id
                                    )
                                }
                            },
                            onRevert: {
                                pendingRevert = changeSet
                            }
                        )
                    }
                }
            } header: {
                Text("سجل التعديلات")
            } footer: {
                Text(
                    "كل جلسة جديدة تنشئ نقطة استعادة قبل بدايتها. إضافة تفاصيل العناصر داخل الجلسة ستُستخدم بدءًا من Build 47."
                )
            }

            Section {
                Button {
                    perform {
                        try store.createRecoverySnapshot(
                            projectID: projectID,
                            reason: "نقطة استعادة يدوية"
                        )
                    }
                } label: {
                    Label(
                        "إنشاء نقطة استعادة الآن",
                        systemImage: "externaldrive.badge.plus"
                    )
                }

                if snapshots.isEmpty {
                    Text("لا توجد نقاط استعادة محفوظة.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshots.prefix(12)) { snapshot in
                        Button {
                            pendingRestore = snapshot
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snapshot.reason)
                                    .foregroundStyle(.primary)
                                Text(
                                    snapshot.createdAt.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("نقاط الاستعادة")
            } footer: {
                Text(
                    "عند الاستعادة، تُحفظ الحالة الحالية أولًا كنقطة أمان جديدة. الحد الافتراضي 12 نقطة مع حماية النقاط المرتبطة بجلسات نشطة."
                )
            }
        }
    }

    private func modeAvailabilityText(_ mode: ProjectWorkspaceMode) -> String {
        switch mode.implementationBuild {
        case 45:
            return "تم تجهيز الأساس في Build 45"
        default:
            return "الأدوات التنفيذية مخططة لـ Build \(mode.implementationBuild)"
        }
    }

    private func canRevert(
        _ target: ProjectChangeSet,
        among changeSets: [ProjectChangeSet]
    ) -> Bool {
        guard (target.status == .draft || target.status == .applied),
              target.recoverySnapshotID != nil else {
            return false
        }
        return !changeSets.contains {
            $0.createdAt > target.createdAt
                && ($0.status == .draft || $0.status == .applied)
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ChangeSetRow: View {
    let changeSet: ProjectChangeSet
    let canRevert: Bool
    let onComplete: () -> Void
    let onRevert: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(changeSet.name, systemImage: changeSet.mode.systemImage)
                    .font(.headline)
                Spacer()
                Text(changeSet.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            HStack {
                Text(changeSet.mode.title)
                Text("•")
                Text(
                    changeSet.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                Text("•")
                Text("\(changeSet.changes.count) تغيير")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let notes = changeSet.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if changeSet.status == .draft {
                Button("اعتماد الجلسة", action: onComplete)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else if changeSet.status == .applied {
                Button("التراجع عن الجلسة", role: .destructive, action: onRevert)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canRevert)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch changeSet.status {
        case .draft: .orange
        case .applied: .green
        case .reverted: .blue
        case .cancelled: .secondary
        }
    }
}

private struct NewProjectChangeSetSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var mode: ProjectWorkspaceMode = .elementUpdate
    @State private var notes = ""
    @State private var errorMessage: String?

    let onCreate: (String, ProjectWorkspaceMode, String?) -> String?

    var body: some View {
        NavigationStack {
            Form {
                Section("الجلسة") {
                    TextField("اسم الجلسة", text: $name)
                    Picker("النوع", selection: $mode) {
                        ForEach(ProjectWorkspaceMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("ملاحظات") {
                    TextField(
                        "وصف مختصر لما سيتم تحديثه",
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }

                Section {
                    Label(
                        "سيتم إنشاء نقطة استعادة تلقائيًا قبل بدء الجلسة.",
                        systemImage: "externaldrive.badge.checkmark"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("جلسة تعديل جديدة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إنشاء") {
                        let cleanNotes = notes.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        if let message = onCreate(
                            name,
                            mode,
                            cleanNotes.isEmpty ? nil : cleanNotes
                        ) {
                            errorMessage = message
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(
                        name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

struct ProjectFoundationDefaultsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var defaults = GlobalSettingsRepository.loadAppDefaults()

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    "الحفظ قبل العمليات الخطرة",
                    value: "مفعّل دائمًا"
                )

                Stepper(
                    value: $defaults.recoveryPolicy.maximumSnapshotCount,
                    in: 3...50
                ) {
                    LabeledContent(
                        "عدد نقاط الاستعادة",
                        value: "\(defaults.recoveryPolicy.maximumSnapshotCount)"
                    )
                }
            } header: {
                Text("الاستعادة الافتراضية")
            } footer: {
                Text(
                    "تُحمى نقاط الجلسات النشطة حتى لو تجاوز عددها الحد المختار."
                )
            }

            Section {
                ForEach(defaults.layerStates.indices, id: \.self) { index in
                    let layer = defaults.layerStates[index]
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: layer.kind.systemImage)
                                .foregroundStyle(.blue)
                                .frame(width: 26)

                            Toggle(
                                layer.kind.title,
                                isOn: Binding(
                                    get: {
                                        defaults.layerStates[index].isVisible
                                    },
                                    set: { value in
                                        defaults.layerStates[index].isVisible = value
                                    }
                                )
                            )
                            .disabled(defaults.layerStates[index].isLocked)

                            Button {
                                defaults.layerStates[index].isLocked.toggle()
                            } label: {
                                Image(
                                    systemName: defaults.layerStates[index].isLocked
                                        ? "lock.fill"
                                        : "lock.open"
                                )
                                .foregroundStyle(
                                    defaults.layerStates[index].isLocked
                                        ? Color.orange
                                        : Color.secondary
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        HStack {
                            Text("الشفافية")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(
                                value: Binding(
                                    get: {
                                        defaults.layerStates[index].opacity
                                    },
                                    set: { value in
                                        defaults.layerStates[index].opacity = value
                                    }
                                ),
                                in: 0.10...1
                            )
                            Text(
                                "\(Int(defaults.layerStates[index].opacity * 100))%"
                            )
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("طبقات المشروعات الجديدة")
            } footer: {
                Text(
                    "هذه القيم تُستخدم عند إنشاء مشروع جديد. تعديلها لا يغيّر مشروعات موجودة."
                )
            }

            Section {
                Button("استعادة الإعدادات الموصى بها", role: .destructive) {
                    defaults = ProjectAppDefaults(
                        electrical: defaults.electrical
                    )
                }
            }
        }
        .navigationTitle("إعدادات تحديث المشروع")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("إلغاء") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("حفظ") {
                    defaults.recoveryPolicy
                        .automaticSnapshotBeforeRiskyOperations = true
                    defaults.layerStates = ProjectLayerState.normalized(
                        defaults.layerStates
                    )
                    GlobalSettingsRepository.saveAppDefaults(defaults)
                    dismiss()
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
