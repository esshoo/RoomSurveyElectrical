import Foundation
import SwiftUI
import simd

struct ElectricalReviewHubView: View {
  @EnvironmentObject private var store: ProjectStore

  let projectID: UUID

  var body: some View {
    Group {
      if let project = store.project(id: projectID) {
        List {
          Section {
            ForEach(project.scans.filter { !$0.archived }) { scan in
              NavigationLink {
                ElectricalReviewScanView(
                  projectID: projectID,
                  scanID: scan.id
                )
              } label: {
                VStack(alignment: .leading, spacing: 5) {
                  HStack {
                    Label(scan.name, systemImage: "bolt.badge.checkmark")
                      .font(.headline)
                    Spacer()
                    if let draft = activeDraft(
                      in: project,
                      scanID: scan.id
                    ) {
                      Text("\(draft.changes.count) تغيير")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    }
                  }
                  Text(scan.resolvedSpatialAlignmentState.title)
                    .font(.caption)
                    .foregroundStyle(
                      scan.resolvedSpatialAlignmentState == .aligned
                        ? Color.secondary
                        : Color.orange
                    )
                }
                .padding(.vertical, 3)
              }
            }
          } header: {
            Text("اختر المسح")
          } footer: {
            Text(
              "كل جلسة مراجعة مرتبطة بمسح واحد فقط. المسحات المستقلة تبقى منفصلة حتى محاذاتها في محرر 2D ضمن Build 50."
            )
          }

          let applied = (project.changeSets ?? [])
            .filter {
              $0.mode == .elementUpdate && $0.status != .draft
            }
            .sorted { $0.updatedAt > $1.updatedAt }
          if !applied.isEmpty {
            Section("الجلسات السابقة") {
              ForEach(applied.prefix(20)) { session in
                VStack(alignment: .leading, spacing: 4) {
                  HStack {
                    Text(session.name)
                      .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(session.status.title)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  Text(
                    "\(session.changes.count) تغيير • \(session.updatedAt.formatted(date: .abbreviated, time: .shortened))"
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
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
    .navigationTitle("مراجعة الكهرباء")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: store.reload)
    .environment(\.layoutDirection, .rightToLeft)
  }

  private func activeDraft(
    in project: SurveyProject,
    scanID: UUID
  ) -> ProjectChangeSet? {
    (project.changeSets ?? [])
      .filter {
        $0.mode == .elementUpdate
          && $0.status == .draft
          && $0.targetScanID == scanID
      }
      .max { $0.updatedAt < $1.updatedAt }
  }
}

private struct ElectricalReviewScanView: View {
  @EnvironmentObject private var store: ProjectStore

  let projectID: UUID
  let scanID: UUID

  @State private var sessionName = "مراجعة كهرباء"
  @State private var notes = ""
  @State private var designMode: ElectricalDesignMode = .existing
  @State private var errorMessage: String?

  var body: some View {
    Group {
      if let workspace = store.project(id: projectID),
        let scan = workspace.scans.first(where: { $0.id == scanID }),
        let room = ProjectRepository.load(projectID: scanID)
      {
        let settings = workspace.effectiveElectricalSettings(
          appDefaults: GlobalSettingsRepository.loadAppDefaults(),
          scanID: scanID
        )
        if let draft = activeDraft(in: workspace) {
          ElectricalReviewSessionContent(
            projectID: projectID,
            scan: scan,
            room: room,
            changeSet: draft,
            settings: settings
          )
        } else {
          startForm(scan: scan, room: room)
        }
      } else {
        ContentUnavailableView(
          "تعذر فتح المسح",
          systemImage: "viewfinder.trianglebadge.exclamationmark",
          description: Text("تأكد أن ملف المسح ما زال موجودًا داخل المشروع.")
        )
      }
    }
    .navigationTitle("جلسة مراجعة")
    .navigationBarTitleDisplayMode(.inline)
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

  private func startForm(
    scan: ScanReference,
    room: RoomProject
  ) -> some View {
    Form {
      Section("المسح") {
        LabeledContent("الاسم", value: scan.name)
        LabeledContent("العناصر الحالية", value: "\(room.points.count)")
        LabeledContent(
          "حالة المحاذاة",
          value: scan.resolvedSpatialAlignmentState.title
        )
      }

      Section("الجلسة الجديدة") {
        TextField("اسم الجلسة", text: $sessionName)
        Picker("وضع الكهرباء", selection: $designMode) {
          ForEach(ElectricalDesignMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        TextField(
          "ملاحظات اختيارية",
          text: $notes,
          axis: .vertical
        )
        .lineLimit(3...6)
      }

      Section {
        Button {
          beginSession()
        } label: {
          Label(
            "بدء جلسة المراجعة",
            systemImage: "play.circle.fill"
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          sessionName.trimmingCharacters(
            in: .whitespacesAndNewlines
          ).isEmpty
        )
      } footer: {
        Text(
          "سيتم إنشاء نقطة استعادة قبل بدء الجلسة. لا تتغير عناصر المسح الفعلية قبل الضغط على اعتماد الجلسة."
        )
      }
    }
  }

  private func activeDraft(in project: SurveyProject) -> ProjectChangeSet? {
    (project.changeSets ?? [])
      .filter {
        $0.mode == .elementUpdate
          && $0.status == .draft
          && $0.targetScanID == scanID
      }
      .max { $0.updatedAt < $1.updatedAt }
  }

  private func beginSession() {
    do {
      let cleanNotes = notes.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      try store.beginElectricalReviewSession(
        projectID: projectID,
        scanID: scanID,
        name: sessionName,
        designMode: designMode,
        notes: cleanNotes.isEmpty ? nil : cleanNotes
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct ElectricalReviewSessionContent: View {
  @EnvironmentObject private var store: ProjectStore

  let projectID: UUID
  let scan: ScanReference
  let room: RoomProject
  let changeSet: ProjectChangeSet
  let settings: ElectricalPlacementSettings

  @State private var editorRequest: ElectricalReviewEditorRequest?
  @State private var errorMessage: String?
  @State private var confirmApply = false
  @State private var confirmCancel = false

  private var effectivePoints: [ElectricalReviewPointState] {
    ElectricalReviewProjection.states(
      room: room,
      changes: changeSet.changes
    )
  }

  var body: some View {
    List {
      Section {
        LabeledContent("الجلسة", value: changeSet.name)
        LabeledContent("المسح", value: scan.name)
        LabeledContent(
          "الوضع",
          value: (changeSet.electricalDesignMode ?? .existing).title
        )
        LabeledContent(
          "التغييرات المسجلة",
          value: "\(changeSet.changes.count)"
        )
        if let notes = changeSet.notes, !notes.isEmpty {
          Text(notes)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("جلسة قيد العمل")
      } footer: {
        Text(
          "القائمة أدناه معاينة للجلسة. ملف المسح الأصلي لا يتغير حتى اعتماد الجلسة."
        )
      }

      Section {
        Button {
          editorRequest = ElectricalReviewEditorRequest(
            action: .add,
            point: nil
          )
        } label: {
          Label("إضافة عنصر كهربائي", systemImage: "plus.circle.fill")
        }
      }

      Section("العناصر") {
        if effectivePoints.isEmpty {
          Text("لا توجد عناصر كهربائية في هذه المعاينة.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(effectivePoints) { state in
            ElectricalReviewPointRow(
              state: state,
              wall: room.walls.first {
                $0.id == state.point.wallID
              },
              onModify: {
                editorRequest = ElectricalReviewEditorRequest(
                  action: state.originalPoint == nil ? .add : .modify,
                  point: state.point
                )
              },
              onReplace: {
                editorRequest = ElectricalReviewEditorRequest(
                  action: state.originalPoint == nil ? .add : .replace,
                  point: state.point
                )
              },
              onConfirm: {
                recordSimpleAction(
                  .confirmExisting,
                  state: state
                )
              },
              onMissing: {
                recordSimpleAction(.markMissing, state: state)
              },
              onDelete: {
                if state.originalPoint == nil {
                  removeDraftChange(entityID: state.point.id)
                } else {
                  recordSimpleAction(.delete, state: state)
                }
              },
              onResetDraft: {
                removeDraftChange(entityID: state.point.id)
              }
            )
          }
        }
      }

      Section {
        Button {
          confirmApply = true
        } label: {
          Label(
            "اعتماد وتطبيق الجلسة",
            systemImage: "checkmark.seal.fill"
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(changeSet.changes.isEmpty)

        Button(role: .destructive) {
          confirmCancel = true
        } label: {
          Label("إلغاء الجلسة", systemImage: "xmark.circle")
            .frame(maxWidth: .infinity)
        }
      } footer: {
        Text(
          "الاعتماد يطبق الإضافة والتعديل والحذف على هذا المسح فقط. يمكن التراجع عن الجلسة لاحقًا من سجل التعديلات."
        )
      }
    }
    .sheet(item: $editorRequest) { request in
      ElectricalReviewPointEditorSheet(
        room: room,
        initialPoint: request.point,
        action: request.action,
        designMode: changeSet.electricalDesignMode ?? .existing,
        settings: settings
      ) { point in
        saveEditedPoint(point, action: request.action)
      }
    }
    .alert("اعتماد جلسة المراجعة؟", isPresented: $confirmApply) {
      Button("اعتماد وتطبيق") {
        perform {
          try store.applyElectricalChangeSet(
            projectID: projectID,
            changeSetID: changeSet.id
          )
        }
      }
      Button("إلغاء", role: .cancel) {}
    } message: {
      Text(
        "سيتم تطبيق \(changeSet.changes.count) تغيير على مسح \(scan.name). توجد نقطة استعادة محفوظة قبل الجلسة."
      )
    }
    .alert("إلغاء جلسة المراجعة؟", isPresented: $confirmCancel) {
      Button("إلغاء الجلسة", role: .destructive) {
        perform {
          try store.cancelChangeSet(
            projectID: projectID,
            changeSetID: changeSet.id
          )
        }
      }
      Button("عودة", role: .cancel) {}
    } message: {
      Text("لن تتغير عناصر المسح، وستبقى الجلسة في السجل بحالة ملغاة.")
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
  }

  private func saveEditedPoint(
    _ point: ElectricalPoint,
    action: ProjectChangeAction
  ) {
    do {
      let original = room.points.first { $0.id == point.id }
      let record = ProjectChangeRecord(
        action: action,
        entityKind: .electricalElement,
        entityID: point.id,
        scanID: scan.id,
        previousState: try original.map {
          try ProjectChangePayloadCoder.encode($0)
        },
        newState: try ProjectChangePayloadCoder.encode(point),
        note: action.title
      )
      try store.upsertElectricalChangeRecord(
        projectID: projectID,
        changeSetID: changeSet.id,
        record: record
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func recordSimpleAction(
    _ action: ProjectChangeAction,
    state: ElectricalReviewPointState
  ) {
    guard let original = state.originalPoint else {
      errorMessage = "هذا العنصر مضاف داخل الجلسة؛ احذف مسودة الإضافة بدل تسجيل هذا الإجراء."
      return
    }
    do {
      let encoded = try ProjectChangePayloadCoder.encode(original)
      let record = ProjectChangeRecord(
        action: action,
        entityKind: .electricalElement,
        entityID: original.id,
        scanID: scan.id,
        previousState: encoded,
        newState: action == .confirmExisting ? encoded : nil,
        note: action.title
      )
      try store.upsertElectricalChangeRecord(
        projectID: projectID,
        changeSetID: changeSet.id,
        record: record
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func removeDraftChange(entityID: UUID) {
    perform {
      try store.removeElectricalChangeRecord(
        projectID: projectID,
        changeSetID: changeSet.id,
        entityID: entityID
      )
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

private struct ElectricalReviewPointState: Identifiable {
  let point: ElectricalPoint
  let originalPoint: ElectricalPoint?
  let pendingAction: ProjectChangeAction?

  var id: UUID { point.id }
}

private enum ElectricalReviewProjection {
  static func states(
    room: RoomProject,
    changes: [ProjectChangeRecord]
  ) -> [ElectricalReviewPointState] {
    var pointByID = Dictionary(
      uniqueKeysWithValues: room.points.map { ($0.id, $0) }
    )
    let originalByID = pointByID
    var actionByID: [UUID: ProjectChangeAction] = [:]

    for record in changes.sorted(by: { $0.createdAt < $1.createdAt })
    where record.entityKind == .electricalElement {
      guard let entityID = record.entityID else { continue }
      actionByID[entityID] = record.action
      switch record.action {
      case .add, .modify, .replace:
        if let point = try? ProjectChangePayloadCoder.decode(
          ElectricalPoint.self,
          from: record.newState
        ) {
          pointByID[entityID] = point
        }
      case .delete, .markMissing:
        pointByID.removeValue(forKey: entityID)
      case .confirmExisting:
        break
      }
    }

    var result = pointByID.values.map { point in
      ElectricalReviewPointState(
        point: point,
        originalPoint: originalByID[point.id],
        pendingAction: actionByID[point.id]
      )
    }

    for record in changes
    where
      record.action == .delete || record.action == .markMissing
    {
      guard let entityID = record.entityID,
        let original = originalByID[entityID]
      else { continue }
      result.append(
        ElectricalReviewPointState(
          point: original,
          originalPoint: original,
          pendingAction: record.action
        )
      )
    }

    return result.sorted {
      if $0.point.type.title == $1.point.type.title {
        return $0.point.createdAt < $1.point.createdAt
      }
      return $0.point.type.title < $1.point.type.title
    }
  }
}

private struct ElectricalReviewPointRow: View {
  let state: ElectricalReviewPointState
  let wall: WallSnapshot?
  let onModify: () -> Void
  let onReplace: () -> Void
  let onConfirm: () -> Void
  let onMissing: () -> Void
  let onDelete: () -> Void
  let onResetDraft: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: state.point.type.systemImage)
        .foregroundStyle(
          state.point.status == .existing ? Color.green : Color.orange
        )
        .frame(width: 30)

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(state.point.type.title)
            .font(.subheadline.weight(.semibold))
          if let action = state.pendingAction {
            Text(action.title)
              .font(.caption2.weight(.bold))
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(actionColor(action).opacity(0.15), in: Capsule())
              .foregroundStyle(actionColor(action))
          }
        }
        Text(
          "\(state.point.status.title) • ارتفاع \(centimeters(state.point.heightFromFloor)) سم"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        if let wall {
          Text(
            "من بداية الحائط \(centimeters(state.point.localX + wall.width / 2)) سم"
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
      }

      Spacer()

      Menu {
        if state.pendingAction != .delete
          && state.pendingAction != .markMissing
        {
          Button("تعديل", action: onModify)
          Button("استبدال النوع", action: onReplace)
        }
        if state.originalPoint != nil {
          Button("تأكيد الوجود", action: onConfirm)
          Button("غير موجود أثناء المراجعة", action: onMissing)
        }
        Button(
          state.originalPoint == nil ? "إلغاء الإضافة" : "حذف",
          role: .destructive,
          action: onDelete
        )
        if state.pendingAction != nil, state.originalPoint != nil {
          Button("إلغاء التغيير المسجل", action: onResetDraft)
        }
      } label: {
        Image(systemName: "ellipsis.circle")
          .font(.title3)
      }
    }
    .opacity(
      state.pendingAction == .delete || state.pendingAction == .markMissing
        ? 0.55
        : 1
    )
    .padding(.vertical, 4)
  }

  private func centimeters(_ meters: Float) -> String {
    String(format: "%.0f", meters * 100)
  }

  private func actionColor(_ action: ProjectChangeAction) -> Color {
    switch action {
    case .add: .green
    case .modify, .replace: .blue
    case .delete, .markMissing: .red
    case .confirmExisting: .teal
    }
  }
}

private struct ElectricalReviewEditorRequest: Identifiable {
  let id = UUID()
  let action: ProjectChangeAction
  let point: ElectricalPoint?
}

private struct ElectricalReviewPointEditorSheet: View {
  @Environment(\.dismiss) private var dismiss

  let room: RoomProject
  let initialPoint: ElectricalPoint?
  let action: ProjectChangeAction
  let designMode: ElectricalDesignMode
  let settings: ElectricalPlacementSettings
  let onSave: (ElectricalPoint) -> Void

  @State private var wallID: UUID
  @State private var type: ElectricalDeviceType
  @State private var status: PlacementStatus
  @State private var distanceFromWallStartCM: Double
  @State private var heightFromFloorCM: Double
  @State private var errorMessage: String?

  init(
    room: RoomProject,
    initialPoint: ElectricalPoint?,
    action: ProjectChangeAction,
    designMode: ElectricalDesignMode,
    settings: ElectricalPlacementSettings,
    onSave: @escaping (ElectricalPoint) -> Void
  ) {
    self.room = room
    self.initialPoint = initialPoint
    self.action = action
    self.designMode = designMode
    self.settings = settings
    self.onSave = onSave

    let firstWall = room.walls.first
    let resolvedWallID = initialPoint?.wallID ?? firstWall?.id ?? UUID()
    let resolvedWall = room.walls.first { $0.id == resolvedWallID } ?? firstWall
    let defaultStatus: PlacementStatus =
      designMode == .existing
      ? .existing
      : .proposed
    _wallID = State(initialValue: resolvedWallID)
    _type = State(initialValue: initialPoint?.type ?? .socket)
    _status = State(initialValue: initialPoint?.status ?? defaultStatus)
    _distanceFromWallStartCM = State(
      initialValue: Double(
        ((initialPoint?.localX ?? 0) + (resolvedWall?.width ?? 0) / 2) * 100
      )
    )
    _heightFromFloorCM = State(
      initialValue: Double(
        (initialPoint?.heightFromFloor
          ?? ElectricalDeviceType.socket.recommendedHeight(using: settings)) * 100
      )
    )
  }

  var body: some View {
    NavigationStack {
      Form {
        if room.walls.isEmpty {
          ContentUnavailableView(
            "لا توجد حوائط",
            systemImage: "rectangle.slash"
          )
        } else {
          Section("العنصر") {
            Picker("النوع", selection: $type) {
              ForEach(ElectricalDeviceType.allCases) { item in
                Text(item.title).tag(item)
              }
            }
            Picker("الحالة", selection: $status) {
              ForEach(PlacementStatus.allCases) { item in
                Text(item.title).tag(item)
              }
            }
          }

          Section("الموضع") {
            Picker("الحائط", selection: $wallID) {
              ForEach(Array(room.walls.enumerated()), id: \.offset) {
                index, wall in
                Text("الحائط \(index + 1) — \(centimeters(wall.width)) سم")
                  .tag(wall.id)
              }
            }
            TextField(
              "المسافة من بداية الحائط (سم)",
              value: $distanceFromWallStartCM,
              format: .number.precision(.fractionLength(0...1))
            )
            .keyboardType(.decimalPad)
            TextField(
              "الارتفاع عن الأرض (سم)",
              value: $heightFromFloorCM,
              format: .number.precision(.fractionLength(0...1))
            )
            .keyboardType(.decimalPad)
          }

          if let selectedWall {
            Section("الحدود") {
              LabeledContent(
                "عرض الحائط",
                value: "\(centimeters(selectedWall.width)) سم"
              )
              LabeledContent(
                "ارتفاع الحائط",
                value: "\(centimeters(selectedWall.height)) سم"
              )
            }
          }
        }

        if let errorMessage {
          Section {
            Text(errorMessage)
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle(action == .add ? "إضافة عنصر" : action.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("إلغاء") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("حفظ") { save() }
            .disabled(room.walls.isEmpty)
        }
      }
      .onChange(of: type) { _, newType in
        guard initialPoint == nil else { return }
        heightFromFloorCM = Double(
          newType.recommendedHeight(
            using: settings,
            wallHeight: selectedWall?.height
          ) * 100
        )
      }
      .onChange(of: wallID) { _, _ in
        guard initialPoint == nil else { return }
        heightFromFloorCM = Double(
          type.recommendedHeight(
            using: settings,
            wallHeight: selectedWall?.height
          ) * 100
        )
      }
    }
    .environment(\.layoutDirection, .rightToLeft)
  }

  private var selectedWall: WallSnapshot? {
    room.walls.first { $0.id == wallID }
  }

  private func save() {
    guard let wall = selectedWall else {
      errorMessage = "اختر حائطًا صحيحًا."
      return
    }
    let distanceMeters = Float(distanceFromWallStartCM / 100)
    let heightMeters = Float(heightFromFloorCM / 100)
    guard distanceMeters >= 0, distanceMeters <= wall.width else {
      errorMessage = "المسافة يجب أن تكون بين 0 و\(centimeters(wall.width)) سم."
      return
    }
    guard heightMeters >= 0, heightMeters <= wall.height else {
      errorMessage = "الارتفاع يجب أن يكون بين 0 و\(centimeters(wall.height)) سم."
      return
    }

    let localX = distanceMeters - wall.width / 2
    let localY = heightMeters - wall.height / 2
    let world = wall.matrix * SIMD4<Float>(localX, localY, 0.035, 1)
    let source = initialPoint
    let point = ElectricalPoint(
      id: source?.id ?? UUID(),
      wallID: wall.id,
      type: type,
      status: status,
      localX: localX,
      localY: localY,
      wallHeight: wall.height,
      worldPosition: [world.x, world.y, world.z],
      standardHeightAtCreation: source?.standardHeightAtCreation,
      standardDoorOffsetAtCreation: source?.standardDoorOffsetAtCreation,
      measuredDoorOffset: source?.measuredDoorOffset,
      wasAutomaticallyAdjusted: source?.wasAutomaticallyAdjusted,
      colorHex: source?.colorHex,
      groupID: source?.groupID,
      createdAt: source?.createdAt ?? Date()
    )
    onSave(point)
    dismiss()
  }

  private func centimeters(_ meters: Float) -> String {
    String(format: "%.0f", meters * 100)
  }
}
