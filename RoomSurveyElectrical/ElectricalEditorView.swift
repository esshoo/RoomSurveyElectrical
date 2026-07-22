import ARKit
import Foundation
import SwiftUI

struct ElectricalEditorView: View {
    @State private var project: RoomProject
    @State private var pendingTap: WallTap?
    @State private var showBOQ = false
    @State private var errorMessage: String?

    let arSession: ARSession
    let onClose: () -> Void

    init(initialProject: RoomProject, arSession: ARSession, onClose: @escaping () -> Void) {
        _project = State(initialValue: initialProject)
        self.arSession = arSession
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            ElectricalARView(
                project: project,
                arSession: arSession,
                onWallTapped: { pendingTap = $0 }
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                topBar
                Spacer()
                instructionCard
                actionBar
            }
            .padding()
        }
        .sheet(item: $pendingTap) { tap in
            DevicePickerSheet { type, status in
                addPoint(type: type, status: status, tap: tap)
                pendingTap = nil
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showBOQ) {
            BOQSheet(project: project)
        }
        .alert("تعذر حفظ النقطة", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("توزيع الكهرباء")
                    .font(.headline)
                Text("\(project.points.count) نقطة • \(project.wallCount) حائط")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var instructionCard: some View {
        Label(
            "اضغط داخل حدود أي حائط سماوي، ثم اختر نوع النقطة.",
            systemImage: "hand.tap.fill"
        )
        .font(.subheadline.weight(.medium))
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                showBOQ = true
            } label: {
                Label("الحصر", systemImage: "list.clipboard.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                removeLastPoint()
            } label: {
                Label("تراجع", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(project.points.isEmpty)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func addPoint(type: ElectricalDeviceType, status: PlacementStatus, tap: WallTap) {
        guard let wall = project.walls.first(where: { $0.id == tap.wallID }) else {
            errorMessage = "لم يتم العثور على الحائط المحدد."
            return
        }

        let point = ElectricalPoint(
            wallID: tap.wallID,
            type: type,
            status: status,
            localX: tap.localX,
            localY: tap.localY,
            wallHeight: wall.height,
            worldPosition: tap.worldPosition
        )

        project.points.append(point)
        persistProject()
    }

    private func removeLastPoint() {
        guard !project.points.isEmpty else { return }
        project.points.removeLast()
        persistProject()
    }

    private func persistProject() {
        do {
            try ProjectRepository.save(project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DevicePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var status: PlacementStatus = .existing
    let onSelect: (ElectricalDeviceType, PlacementStatus) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("الحالة") {
                    Picker("الحالة", selection: $status) {
                        ForEach(PlacementStatus.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("نوع النقطة") {
                    ForEach(ElectricalDeviceType.allCases) { type in
                        Button {
                            onSelect(type, status)
                            dismiss()
                        } label: {
                            HStack {
                                Label(type.title, systemImage: type.systemImage)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("إضافة نقطة كهرباء")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

private struct BOQSheet: View {
    @Environment(\.dismiss) private var dismiss
    let project: RoomProject

    var body: some View {
        NavigationStack {
            List {
                Section("بيانات الغرفة") {
                    LabeledContent("الحوائط", value: "\(project.wallCount)")
                    LabeledContent("الأبواب", value: "\(project.doorCount)")
                    LabeledContent("الشبابيك", value: "\(project.windowCount)")
                }

                Section("حصر نقاط الكهرباء") {
                    if project.boq.isEmpty {
                        Text("لم تتم إضافة نقاط بعد.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(project.boq) { line in
                            HStack {
                                Label(line.type.title, systemImage: line.type.systemImage)
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("\(line.count)")
                                        .font(.headline.monospacedDigit())
                                    Text(line.status.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !project.points.isEmpty {
                    Section("الارتفاعات المسجلة") {
                        ForEach(project.points) { point in
                            HStack {
                                Text(point.type.title)
                                Spacer()
                                Text(String(format: "%.2f م", point.heightFromFloor))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .navigationTitle("الحصر")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
