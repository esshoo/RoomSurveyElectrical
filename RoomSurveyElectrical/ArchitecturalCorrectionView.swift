import SwiftUI
import simd

struct ArchitecturalCorrectionHubView: View {
    @EnvironmentObject private var store: ProjectStore

    let projectID: UUID

    var body: some View {
        Group {
            if let project = store.project(id: projectID) {
                List {
                    Section {
                        Label(
                            "الهندسة الأصلية لا تُستبدل. تُحفظ التصحيحات داخل طبقة مستقلة مع نقطة استعادة وسجل Change Set.",
                            systemImage: "checkmark.shield.fill"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }

                    Section("المسحات") {
                        if project.scans.filter({ !$0.archived }).isEmpty {
                            ContentUnavailableView(
                                "لا توجد مسحات",
                                systemImage: "viewfinder",
                                description: Text(
                                    "أضف مسحًا إلى المشروع قبل بدء التصحيح المعماري."
                                )
                            )
                        } else {
                            ForEach(
                                project.scans
                                    .filter { !$0.archived }
                                    .sorted { $0.createdAt > $1.createdAt }
                            ) { scan in
                                NavigationLink {
                                    ArchitecturalCorrectionScanView(
                                        projectID: projectID,
                                        scanID: scan.id
                                    )
                                } label: {
                                    ArchitecturalScanRow(
                                        scan: scan,
                                        room: ProjectRepository.load(
                                            projectID: scan.id
                                        ),
                                        draftCount: draftCount(
                                            project: project,
                                            scanID: scan.id
                                        )
                                    )
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "المشروع غير موجود",
                    systemImage: "folder.badge.questionmark"
                )
            }
        }
        .navigationTitle("التصحيح المعماري")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: store.reload)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func draftCount(
        project: SurveyProject,
        scanID: UUID
    ) -> Int {
        (project.changeSets ?? []).filter {
            $0.mode == .architecturalUpdate
                && $0.targetScanID == scanID
                && $0.status == .draft
        }.count
    }
}

private struct ArchitecturalScanRow: View {
    let scan: ScanReference
    let room: RoomProject?
    let draftCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.3.layers.3d")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(scan.name)
                    .font(.headline)
                if let room {
                    Text(
                        "\(room.wallCount) حائط • \(room.architecturalCorrections?.count ?? 0) تصحيح معتمد"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("تعذر تحميل ملفات المسح")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if draftCount > 0 {
                Text("جلسة نشطة")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.orange.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

struct ArchitecturalCorrectionScanView: View {
    @EnvironmentObject private var store: ProjectStore

    let projectID: UUID
    let scanID: UUID

    @State private var room: RoomProject?
    @State private var showNewSession = false
    @State private var errorMessage: String?

    private var project: SurveyProject? {
        store.project(id: projectID)
    }

    private var activeDraft: ProjectChangeSet? {
        (project?.changeSets ?? [])
            .filter {
                $0.mode == .architecturalUpdate
                    && $0.targetScanID == scanID
                    && $0.status == .draft
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    var body: some View {
        Group {
            if let room {
                List {
                    Section {
                        LabeledContent("المسح", value: room.name)
                        LabeledContent("الحوائط", value: "\(room.wallCount)")
                        LabeledContent(
                            "التصحيحات المعتمدة",
                            value: "\(room.architecturalCorrections?.count ?? 0)"
                        )
                        LabeledContent(
                            "الهندسة الأصلية محفوظة",
                            value: room.originalWalls == nil ? "لم تبدأ تصحيحات" : "نعم"
                        )
                    } header: {
                        Text("حالة المسح")
                    } footer: {
                        Text(
                            "Build 49.1 يصحح الحوائط ونقاط الكهرباء المرتبطة فقط. إعادة موضعة الأبواب والشبابيك والفتحات تدخل في Build 49.2، لذلك راجع الحائط الذي يحتوي عليها قبل الاعتماد."
                        )
                    }

                    Section {
                        if let activeDraft {
                            NavigationLink {
                                ArchitecturalWallCorrectionEditorView(
                                    projectID: projectID,
                                    scanID: scanID,
                                    changeSetID: activeDraft.id
                                )
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(activeDraft.name)
                                            .font(.headline)
                                        Text(
                                            "\(activeDraft.changes.filter { $0.entityKind == .architecturalElement }.count) حائط بانتظار الاعتماد"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "pencil.and.outline")
                                        .foregroundStyle(.orange)
                                }
                            }
                        } else {
                            Button {
                                showNewSession = true
                            } label: {
                                Label(
                                    "بدء جلسة تصحيح معماري",
                                    systemImage: "plus.circle.fill"
                                )
                            }
                        }
                    } header: {
                        Text("الجلسة الحالية")
                    } footer: {
                        Text(
                            "تُنشأ نقطة استعادة قبل الجلسة. لا يتغير المسح حتى تضغط اعتماد الجلسة."
                        )
                    }

                    if let corrections = room.architecturalCorrections,
                       !corrections.isEmpty {
                        Section("آخر التصحيحات") {
                            ForEach(Array(corrections.suffix(10).reversed())) { correction in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(wallTitle(correction.wallID, room: room))
                                        .font(.headline)
                                    Text(
                                        "\(meters(correction.beforeState.width)) × \(meters(correction.beforeState.height)) ← \(meters(correction.afterState.width)) × \(meters(correction.afterState.height))"
                                    )
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    Text(
                                        correction.appliedAt.formatted(
                                            date: .abbreviated,
                                            time: .shortened
                                        )
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "تعذر تحميل المسح",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(
                        "تأكد من وجود ملفات المسح داخل مجلد المشروع."
                    )
                )
            }
        }
        .navigationTitle(room?.name ?? "المسح")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNewSession) {
            NewArchitecturalCorrectionSessionSheet(
                scanName: room?.name ?? "المسح"
            ) { name, notes in
                do {
                    try store.beginArchitecturalCorrectionSession(
                        projectID: projectID,
                        scanID: scanID,
                        name: name,
                        notes: notes
                    )
                    reload()
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
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
        .onAppear(perform: reload)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func reload() {
        store.reload()
        room = ProjectRepository.load(projectID: scanID)
    }

    private func wallTitle(_ wallID: UUID, room: RoomProject) -> String {
        let index = room.preservedOriginalWalls.firstIndex {
            $0.id == wallID
        } ?? room.walls.firstIndex { $0.id == wallID } ?? 0
        return "الحائط \(index + 1)"
    }

    private func meters(_ value: Float) -> String {
        String(format: "%.2f م", value)
    }
}

struct ArchitecturalWallCorrectionEditorView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID
    let scanID: UUID
    let changeSetID: UUID

    @State private var room: RoomProject?
    @State private var selectedWallID: UUID?
    @State private var showWallEditor = false
    @State private var pendingApply = false
    @State private var pendingCancel = false
    @State private var errorMessage: String?

    private var changeSet: ProjectChangeSet? {
        store.project(id: projectID)?.changeSets?.first {
            $0.id == changeSetID
        }
    }

    private var architecturalRecords: [ProjectChangeRecord] {
        (changeSet?.changes ?? [])
            .filter {
                $0.entityKind == .architecturalElement
                    && $0.scanID == scanID
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var afterStateByWallID: [UUID: ArchitecturalWallState] {
        var result: [UUID: ArchitecturalWallState] = [:]
        for record in architecturalRecords {
            guard let state = try? ProjectChangePayloadCoder.decode(
                ArchitecturalWallState.self,
                from: record.newState
            ) else { continue }
            result[state.wallID] = state
        }
        return result
    }

    var body: some View {
        Group {
            if let room,
               let changeSet,
               changeSet.status == .draft {
                editorContent(room: room, changeSet: changeSet)
            } else {
                ContentUnavailableView(
                    "الجلسة غير متاحة",
                    systemImage: "pencil.slash",
                    description: Text(
                        "قد تكون الجلسة اعتُمدت أو أُلغيت أو تغيرت ملفات المشروع."
                    )
                )
            }
        }
        .navigationTitle(changeSet?.name ?? "تصحيح الحوائط")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("إلغاء الجلسة", role: .destructive) {
                    pendingCancel = true
                }
                Button("اعتماد") {
                    pendingApply = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(architecturalRecords.isEmpty)
            }
        }
        .sheet(isPresented: $showWallEditor) {
            if let room,
               let wallID = selectedWallID,
               let wall = previewWall(wallID: wallID, room: room) {
                WallCorrectionForm(
                    wallTitle: wallTitle(wallID, room: room),
                    wall: wall,
                    note: architecturalRecords.first {
                        $0.entityID == wallID
                    }?.note
                ) { state, note in
                    saveDraft(
                        state: state,
                        note: note,
                        room: room
                    )
                }
            }
        }
        .alert("اعتماد التصحيحات؟", isPresented: $pendingApply) {
            Button("اعتماد", role: .destructive) {
                perform {
                    try store.applyArchitecturalChangeSet(
                        projectID: projectID,
                        changeSetID: changeSetID
                    )
                    reloadRoom()
                    dismiss()
                }
            }
            Button("مراجعة", role: .cancel) {}
        } message: {
            Text(
                "سيتم حفظ التصحيحات في طبقة معمارية مستقلة مع إبقاء الهندسة الأصلية ونقطة الاستعادة."
            )
        }
        .alert("إلغاء الجلسة؟", isPresented: $pendingCancel) {
            Button("إلغاء الجلسة", role: .destructive) {
                perform {
                    try store.cancelChangeSet(
                        projectID: projectID,
                        changeSetID: changeSetID
                    )
                    dismiss()
                }
            }
            Button("متابعة", role: .cancel) {}
        } message: {
            Text("لن يتغير المسح لأن سجلات هذه الجلسة لم تُعتمد بعد.")
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
        .onAppear(perform: reloadRoom)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func editorContent(
        room: RoomProject,
        changeSet: ProjectChangeSet
    ) -> some View {
        List {
            Section {
                ArchitecturalBeforeAfterPlanView(
                    beforeWalls: room.walls,
                    afterWalls: previewWalls(room: room),
                    changedWallIDs: Set(
                        architecturalRecords.compactMap(\.entityID)
                    ),
                    selectedWallID: selectedWallID
                )
                .frame(height: 270)
                .listRowInsets(EdgeInsets())
            } header: {
                HStack {
                    Text("قبل / بعد")
                    Spacer()
                    Label("الأصل", systemImage: "minus")
                        .foregroundStyle(.secondary)
                    Label("التصحيح", systemImage: "minus")
                        .foregroundStyle(.orange)
                }
                .font(.caption)
            } footer: {
                Text(
                    "المخطط الهندسي يبقى LTR مهما كانت لغة الواجهة. لا يُسمح بالمقياس أو الانعكاس؛ فقط العرض والارتفاع والنقل والدوران حول Y."
                )
            }

            Section {
                LabeledContent(
                    "الجلسة",
                    value: changeSet.name
                )
                LabeledContent(
                    "التعديلات المقبولة",
                    value: "\(architecturalRecords.count)"
                )
                if let notes = changeSet.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("معلومات الجلسة")
            }

            Section("الحوائط") {
                ForEach(Array(room.walls.enumerated()), id: \.element.id) {
                    index, wall in
                    let after = afterStateByWallID[wall.id]?.wall
                    HStack(spacing: 12) {
                        Button {
                            selectedWallID = wall.id
                            showWallEditor = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(
                                    systemName: after == nil
                                        ? "rectangle.portrait"
                                        : "rectangle.portrait.and.arrow.right"
                                )
                                .foregroundStyle(after == nil ? .blue : .orange)
                                .frame(width: 28)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("الحائط \(index + 1)")
                                        .foregroundStyle(.primary)
                                        .font(.headline)
                                    Text(wallDimensions(before: wall, after: after))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if after != nil {
                            Button(role: .destructive) {
                                perform {
                                    try store.removeArchitecturalWallChangeRecord(
                                        projectID: projectID,
                                        changeSetID: changeSetID,
                                        wallID: wall.id
                                    )
                                }
                            } label: {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("رفض تعديل هذا الحائط")
                        }
                    }
                }
            }
        }
    }

    private func previewWalls(room: RoomProject) -> [WallSnapshot] {
        let replacements = afterStateByWallID
        return room.walls.map { wall in
            replacements[wall.id]?.wall ?? wall
        }
    }

    private func previewWall(
        wallID: UUID,
        room: RoomProject
    ) -> WallSnapshot? {
        afterStateByWallID[wallID]?.wall
            ?? room.walls.first { $0.id == wallID }
    }

    private func saveDraft(
        state: ArchitecturalWallState,
        note: String?,
        room: RoomProject
    ) {
        perform {
            guard let originalWall = room.walls.first(where: {
                $0.id == state.wallID
            }) else {
                throw ArchitecturalCorrectionError.wallNotFound
            }
            let originalState = ArchitecturalWallState(wall: originalWall)
            let record = ProjectChangeRecord(
                action: .modify,
                entityKind: .architecturalElement,
                entityID: state.wallID,
                scanID: scanID,
                previousState: try ProjectChangePayloadCoder.encode(
                    originalState
                ),
                newState: try ProjectChangePayloadCoder.encode(state),
                note: note
            )
            try store.upsertArchitecturalWallChangeRecord(
                projectID: projectID,
                changeSetID: changeSetID,
                record: record
            )
        }
    }

    private func reloadRoom() {
        store.reload()
        room = ProjectRepository.load(projectID: scanID)
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
            reloadRoom()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func wallTitle(_ wallID: UUID, room: RoomProject) -> String {
        let index = room.walls.firstIndex { $0.id == wallID } ?? 0
        return "الحائط \(index + 1)"
    }

    private func wallDimensions(
        before: WallSnapshot,
        after: WallSnapshot?
    ) -> String {
        let beforeText = String(
            format: "%.2f × %.2f م",
            before.width,
            before.height
        )
        guard let after else { return beforeText }
        return beforeText + String(
            format: "  ←  %.2f × %.2f م",
            after.width,
            after.height
        )
    }
}

private struct NewArchitecturalCorrectionSessionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let scanName: String
    let onCreate: (String, String?) -> String?

    @State private var name = ""
    @State private var notes = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("الجلسة") {
                    LabeledContent("المسح", value: scanName)
                    TextField("اسم الجلسة", text: $name)
                }

                Section("ملاحظات") {
                    TextField(
                        "وصف التصحيحات المطلوبة",
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }

                Section {
                    Label(
                        "سيُحفظ المسح الحالي في Recovery Snapshot قبل إنشاء أي سجل تعديل.",
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
            .navigationTitle("جلسة تصحيح جديدة")
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

private struct WallCorrectionForm: View {
    @Environment(\.dismiss) private var dismiss

    let wallTitle: String
    let wall: WallSnapshot
    let note: String?
    let onSave: (ArchitecturalWallState, String?) -> Void

    @State private var width: Double
    @State private var height: Double
    @State private var x: Double
    @State private var z: Double
    @State private var yawDegrees: Double
    @State private var editNote: String

    init(
        wallTitle: String,
        wall: WallSnapshot,
        note: String?,
        onSave: @escaping (ArchitecturalWallState, String?) -> Void
    ) {
        self.wallTitle = wallTitle
        self.wall = wall
        self.note = note
        self.onSave = onSave

        let matrix = wall.matrix
        let translation = SpatialCoordinateContract.translation(matrix)
        let yaw = atan2(-matrix.columns.0.z, matrix.columns.0.x)
        _width = State(initialValue: Double(wall.width))
        _height = State(initialValue: Double(wall.height))
        _x = State(initialValue: Double(translation.x))
        _z = State(initialValue: Double(translation.z))
        _yawDegrees = State(initialValue: Double(yaw * 180 / .pi))
        _editNote = State(initialValue: note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("الأبعاد") {
                    MeasurementField(
                        title: "الطول",
                        value: $width,
                        range: 0.05...100
                    )
                    MeasurementField(
                        title: "الارتفاع",
                        value: $height,
                        range: 0.20...20
                    )
                }

                Section("الموضع داخل المشروع") {
                    MeasurementField(
                        title: "X",
                        value: $x,
                        range: -500...500
                    )
                    MeasurementField(
                        title: "Z",
                        value: $z,
                        range: -500...500
                    )
                    HStack {
                        Text("الدوران حول Y")
                        Spacer()
                        TextField("0", value: $yawDegrees, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .frame(maxWidth: 110)
                        Text("°")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("ملاحظات") {
                    TextField(
                        "سبب التصحيح",
                        text: $editNote,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                }

                Section {
                    Label(
                        "يبقى أسفل الحائط على المنسوب نفسه عند تغيير الارتفاع. لا يُطبّق Scale على مصفوفة التحويل.",
                        systemImage: "ruler"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(wallTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("قبول التعديل") {
                        let state = buildState()
                        let cleanNote = editNote.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        onSave(state, cleanNote.isEmpty ? nil : cleanNote)
                        dismiss()
                    }
                    .disabled(!valuesAreValid)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var valuesAreValid: Bool {
        width.isFinite
            && height.isFinite
            && x.isFinite
            && z.isFinite
            && yawDegrees.isFinite
            && width >= 0.05
            && height >= 0.20
    }

    private func buildState() -> ArchitecturalWallState {
        let oldMatrix = wall.matrix
        let oldCenter = SpatialCoordinateContract.translation(oldMatrix)
        let oldBottom = oldCenter.y - wall.height / 2
        let angle = Float(yawDegrees * .pi / 180)
        var matrix = SpatialCoordinateContract.yawRotation(angle)
        matrix.columns.3 = SIMD4<Float>(
            Float(x),
            oldBottom + Float(height) / 2,
            Float(z),
            1
        )
        return ArchitecturalWallState(
            wallID: wall.id,
            width: Float(width),
            height: Float(height),
            transform: matrix.columnMajorValues
        )
    }
}

private struct MeasurementField: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0.00", value: $value, format: .number.precision(.fractionLength(2)))
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(maxWidth: 120)
            Text("م")
                .foregroundStyle(.secondary)
        }
        .onChange(of: value) { _, newValue in
            guard newValue.isFinite else { return }
            value = min(max(newValue, range.lowerBound), range.upperBound)
        }
    }
}

private struct ArchitecturalBeforeAfterPlanView: View {
    let beforeWalls: [WallSnapshot]
    let afterWalls: [WallSnapshot]
    let changedWallIDs: Set<UUID>
    let selectedWallID: UUID?

    var body: some View {
        Canvas { context, size in
            let allWalls = beforeWalls + afterWalls
            let projection = ArchitecturalPlanProjection(
                walls: allWalls,
                size: size
            )

            for wall in beforeWalls {
                draw(
                    wall: wall,
                    color: .secondary.opacity(0.55),
                    width: selectedWallID == wall.id ? 5 : 2,
                    dash: [6, 5],
                    context: &context,
                    projection: projection
                )
            }

            for wall in afterWalls where changedWallIDs.contains(wall.id) {
                draw(
                    wall: wall,
                    color: selectedWallID == wall.id ? .red : .orange,
                    width: selectedWallID == wall.id ? 6 : 4,
                    dash: [],
                    context: &context,
                    projection: projection
                )
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(12)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func draw(
        wall: WallSnapshot,
        color: Color,
        width: CGFloat,
        dash: [CGFloat],
        context: inout GraphicsContext,
        projection: ArchitecturalPlanProjection
    ) {
        let endpoints = architecturalWallEndpoints(wall)
        var path = Path()
        path.move(to: projection.map(endpoints.0))
        path.addLine(to: projection.map(endpoints.1))
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: width,
                lineCap: .round,
                lineJoin: .round,
                dash: dash
            )
        )
    }
}

private struct ArchitecturalPlanProjection {
    let minX: Float
    let maxX: Float
    let minZ: Float
    let maxZ: Float
    let size: CGSize

    init(walls: [WallSnapshot], size: CGSize) {
        let points = walls.flatMap { wall -> [SIMD2<Float>] in
            let endpoints = architecturalWallEndpoints(wall)
            return [endpoints.0, endpoints.1]
        }
        let rawMinX = points.map(\.x).min() ?? -1
        let rawMaxX = points.map(\.x).max() ?? 1
        let rawMinZ = points.map(\.y).min() ?? -1
        let rawMaxZ = points.map(\.y).max() ?? 1
        let margin: Float = 0.40
        minX = rawMinX - margin
        maxX = rawMaxX + margin
        minZ = rawMinZ - margin
        maxZ = rawMaxZ + margin
        self.size = size
    }

    func map(_ point: SIMD2<Float>) -> CGPoint {
        let availableWidth = max(size.width - 28, 1)
        let availableHeight = max(size.height - 28, 1)
        let worldWidth = max(maxX - minX, 0.01)
        let worldHeight = max(maxZ - minZ, 0.01)
        let scale = min(
            availableWidth / CGFloat(worldWidth),
            availableHeight / CGFloat(worldHeight)
        )
        let drawnWidth = CGFloat(worldWidth) * scale
        let drawnHeight = CGFloat(worldHeight) * scale
        let offsetX = (size.width - drawnWidth) / 2
        let offsetY = (size.height - drawnHeight) / 2
        return CGPoint(
            x: offsetX + CGFloat(point.x - minX) * scale,
            y: offsetY + CGFloat(maxZ - point.y) * scale
        )
    }
}

private func architecturalWallEndpoints(
    _ wall: WallSnapshot
) -> (SIMD2<Float>, SIMD2<Float>) {
    let matrix = wall.matrix
    let center = SpatialCoordinateContract.translation(matrix)
    let axis = SpatialCoordinateContract.normalizedHorizontalAxis(
        matrix.columns.0
    )
    let half = axis * wall.width / 2
    return (
        SIMD2(center.x - half.x, center.z - half.z),
        SIMD2(center.x + half.x, center.z + half.z)
    )
}
