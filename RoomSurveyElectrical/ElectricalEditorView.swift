import ARKit
import Foundation
import simd
import SwiftUI

struct ElectricalEditorView: View {
    @State private var project: RoomProject
    @State private var pendingTap: WallTap?
    @State private var showBOQ = false
    @State private var errorMessage: String?
    @State private var placementMessage: String?

    let arSession: ARSession
    let settings: ElectricalPlacementSettings
    let onClose: () -> Void

    init(
        initialProject: RoomProject,
        arSession: ARSession,
        settings: ElectricalPlacementSettings,
        onClose: @escaping () -> Void
    ) {
        var preparedProject = initialProject
        if preparedProject.electricalSettings == nil {
            preparedProject.electricalSettings = settings
        }
        _project = State(initialValue: preparedProject)
        self.arSession = arSession
        self.settings = settings
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
            DevicePickerSheet(settings: settings) { type, status in
                addPoint(type: type, status: status, tap: tap)
                pendingTap = nil
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showBOQ) {
            BOQSheet(project: project, settings: settings)
        }
        .alert("تعذر تنفيذ العملية", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            persistProject()
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

            VStack(alignment: .trailing, spacing: 3) {
                Text("توزيع الكهرباء")
                    .font(.headline)
                Text("\(project.points.count) نقطة • \(settings.designMode.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(instructionText, systemImage: instructionIcon)
                .font(.subheadline.weight(.semibold))

            if let placementMessage {
                Label(placementMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var instructionText: String {
        switch settings.designMode {
        case .existing:
            "اضغط مكان العنصر الحقيقي على الحائط؛ لن يتم تغيير الارتفاع أو الموضع."
        case .newInstallation:
            "اضغط الحائط واختر العنصر؛ سيطبق التطبيق الارتفاع القياسي وبعد الباب تلقائيًا."
        case .shopDrawing:
            "اضغط الحائط، ثم اختر موجود لحفظ الواقع أو مقترح لتطبيق قواعد التأسيس."
        }
    }

    private var instructionIcon: String {
        settings.designMode == .existing ? "scope" : "ruler.fill"
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

        let standardHeight = type.recommendedHeight(using: settings)
        let appliesRules = status == .proposed
        var localX = tap.localX
        var localY = tap.localY
        var messageParts: [String] = []

        if appliesRules {
            localY = localYForHeight(standardHeight, wall: wall)
            messageParts.append("الارتفاع \(centimeters(standardHeight)) سم")

            if type.usesSwitchRules {
                if let snappedX = switchPositionNearDoor(
                    preferredX: tap.localX,
                    wall: wall,
                    offset: Float(settings.switchDoorOffsetMeters)
                ) {
                    localX = snappedX
                    messageParts.append(
                        "بعد الباب \(centimeters(Float(settings.switchDoorOffsetMeters))) سم"
                    )
                } else {
                    messageParts.append("لم يُعثر على باب بهذا الحائط؛ تم تثبيت الارتفاع فقط")
                }
            }

            if settings.avoidOpenings,
               let opening = openingContaining(localX: localX, localY: localY, wall: wall) {
                errorMessage = "الموضع يقع داخل \(opening.kind.title). اختر نقطة أخرى على الحائط."
                return
            }
        }

        let measuredDoorOffset = type.usesSwitchRules
            ? distanceToNearestDoorEdge(localX: localX, wall: wall)
            : nil
        let resolvedWorldPosition = worldCoordinates(
            localX: localX,
            localY: localY,
            wall: wall
        )

        let point = ElectricalPoint(
            wallID: tap.wallID,
            type: type,
            status: status,
            localX: localX,
            localY: localY,
            wallHeight: wall.height,
            worldPosition: resolvedWorldPosition,
            standardHeightAtCreation: standardHeight,
            standardDoorOffsetAtCreation: type.usesSwitchRules
                ? Float(settings.switchDoorOffsetMeters)
                : nil,
            measuredDoorOffset: measuredDoorOffset,
            wasAutomaticallyAdjusted: appliesRules
        )

        project.points.append(point)
        if appliesRules {
            placementMessage = "تم ضبط \(type.title): \(messageParts.joined(separator: " • "))"
        } else {
            placementMessage = "تم حفظ \(type.title) في موضعه الفعلي."
        }
        persistProject()
    }

    private func removeLastPoint() {
        guard let removedPoint = project.points.popLast() else { return }
        placementMessage = "تم التراجع عن \(removedPoint.type.title)."
        persistProject()
    }

    private func persistProject() {
        do {
            try ProjectRepository.save(project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func localYForHeight(_ height: Float, wall: WallSnapshot) -> Float {
        let margin: Float = 0.04
        let minimum = -wall.height / 2 + margin
        let maximum = wall.height / 2 - margin
        return min(max(-wall.height / 2 + height, minimum), maximum)
    }

    private func switchPositionNearDoor(
        preferredX: Float,
        wall: WallSnapshot,
        offset: Float
    ) -> Float? {
        guard let door = nearestDoor(to: preferredX, wall: wall) else { return nil }
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
        nearestDoor(to: localX, wall: wall).map { door in
            let leftEdge = door.centerX - door.width / 2
            let rightEdge = door.centerX + door.width / 2
            return min(abs(localX - leftEdge), abs(localX - rightEdge))
        }
    }

    private func nearestDoor(
        to localX: Float,
        wall: WallSnapshot
    ) -> WallSurfaceProjection? {
        surfaceProjections(on: wall)
            .filter { $0.kind == .door }
            .min { first, second in
                distanceFrom(localX, to: first) < distanceFrom(localX, to: second)
            }
    }

    private func distanceFrom(_ localX: Float, to surface: WallSurfaceProjection) -> Float {
        let leftEdge = surface.centerX - surface.width / 2
        let rightEdge = surface.centerX + surface.width / 2
        return min(abs(localX - leftEdge), abs(localX - rightEdge))
    }

    private func openingContaining(
        localX: Float,
        localY: Float,
        wall: WallSnapshot
    ) -> WallSurfaceProjection? {
        let tolerance: Float = 0.025
        return surfaceProjections(on: wall).first { surface in
            abs(localX - surface.centerX) <= surface.width / 2 + tolerance
                && abs(localY - surface.centerY) <= surface.height / 2 + tolerance
        }
    }

    private func surfaceProjections(on wall: WallSnapshot) -> [WallSurfaceProjection] {
        let inverseWall = simd_inverse(wall.matrix)
        return project.surfaces.compactMap { surface in
            let localCenter = simd_mul(inverseWall, surface.matrix.columns.3)
            guard abs(localCenter.z) <= 0.30,
                  abs(localCenter.x) <= wall.width / 2 + surface.width / 2 else {
                return nil
            }
            return WallSurfaceProjection(
                kind: surface.kind,
                centerX: localCenter.x,
                centerY: localCenter.y,
                width: surface.width,
                height: surface.height
            )
        }
    }

    private func worldCoordinates(
        localX: Float,
        localY: Float,
        wall: WallSnapshot
    ) -> [Float] {
        let world = simd_mul(wall.matrix, SIMD4(localX, localY, 0.035, 1))
        return [world.x, world.y, world.z]
    }

    private func centimeters(_ meters: Float) -> String {
        String(format: "%.0f", meters * 100)
    }
}

private struct WallSurfaceProjection {
    let kind: SurfaceSnapshot.Kind
    let centerX: Float
    let centerY: Float
    let width: Float
    let height: Float
}

private extension SurfaceSnapshot.Kind {
    var title: String {
        switch self {
        case .door: "فتحة الباب"
        case .window: "فتحة الشباك"
        case .opening: "الفتحة المعمارية"
        }
    }
}

private struct DevicePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var status: PlacementStatus

    let settings: ElectricalPlacementSettings
    let onSelect: (ElectricalDeviceType, PlacementStatus) -> Void

    init(
        settings: ElectricalPlacementSettings,
        onSelect: @escaping (ElectricalDeviceType, PlacementStatus) -> Void
    ) {
        self.settings = settings
        _status = State(initialValue: settings.designMode == .newInstallation ? .proposed : .existing)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            List {
                Section("طريقة الإضافة") {
                    if settings.designMode == .shopDrawing {
                        Picker("الحالة", selection: $status) {
                            ForEach(PlacementStatus.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Label(modeExplanation, systemImage: modeIcon)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                deviceSection(
                    "المفاتيح",
                    types: [.singleSwitch, .doubleSwitch, .tripleSwitch, .airConditionerSwitch]
                )
                deviceSection(
                    "الأفياش",
                    types: [.socket, .heaterSocket]
                )
                deviceSection(
                    "الإضاءة",
                    types: [.wallLight]
                )
                deviceSection(
                    "التيار الخفيف",
                    types: [.dataOutlet, .televisionOutlet]
                )
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

    private var resolvedStatus: PlacementStatus {
        switch settings.designMode {
        case .existing: .existing
        case .newInstallation: .proposed
        case .shopDrawing: status
        }
    }

    private var appliesRules: Bool {
        resolvedStatus == .proposed
    }

    private var modeExplanation: String {
        if appliesRules {
            return "سيُضبط العنصر على الارتفاع القياسي، وتُبعد المفاتيح عن أقرب باب تلقائيًا."
        }
        return "سيُحفظ العنصر في مكان اللمس الفعلي دون تعديل."
    }

    private var modeIcon: String {
        appliesRules ? "ruler.fill" : "scope"
    }

    private func typeDetail(_ type: ElectricalDeviceType) -> String {
        guard appliesRules else { return "فعلي" }
        return "\(Int(type.recommendedHeight(using: settings) * 100)) سم"
    }

    private func deviceSection(
        _ title: String,
        types: [ElectricalDeviceType]
    ) -> some View {
        Section(title) {
            ForEach(types) { type in
                Button {
                    onSelect(type, resolvedStatus)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Label(type.title, systemImage: type.systemImage)
                        Spacer()
                        Text(typeDetail(type))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }
}

private struct BOQSheet: View {
    @Environment(\.dismiss) private var dismiss
    let project: RoomProject
    let settings: ElectricalPlacementSettings

    var body: some View {
        NavigationStack {
            List {
                Section("بيانات الغرفة") {
                    LabeledContent("الحوائط", value: "\(project.wallCount)")
                    LabeledContent("الأبواب", value: "\(project.doorCount)")
                    LabeledContent("الشبابيك", value: "\(project.windowCount)")
                    LabeledContent("نمط العمل", value: settings.designMode.title)
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
                    Section("مراجعة المقاسات") {
                        ForEach(project.points) { point in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Label(point.type.title, systemImage: point.type.systemImage)
                                    Spacer()
                                    Text(point.status.title)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(
                                            point.status == .existing ? .green : .orange
                                        )
                                }

                                HStack {
                                    Text("الارتفاع الفعلي")
                                    Spacer()
                                    Text(String(format: "%.2f م", point.heightFromFloor))
                                        .monospacedDigit()
                                }
                                .font(.caption)

                                HStack {
                                    Text(heightComparison(for: point))
                                    Spacer()
                                    if point.wasAutomaticallyAdjusted == true {
                                        Label("ضبط تلقائي", systemImage: "wand.and.stars")
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(comparisonColor(for: point))

                                if point.type.usesSwitchRules,
                                   let measured = point.measuredDoorOffset {
                                    Text(
                                        "البعد عن الباب: \(String(format: "%.0f", measured * 100)) سم"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
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

    private func targetHeight(for point: ElectricalPoint) -> Float {
        point.standardHeightAtCreation
            ?? point.type.recommendedHeight(using: settings)
    }

    private func heightComparison(for point: ElectricalPoint) -> String {
        let differenceCentimeters = (point.heightFromFloor - targetHeight(for: point)) * 100
        if abs(differenceCentimeters) <= 2 {
            return "مطابق للارتفاع القياسي"
        }
        if differenceCentimeters > 0 {
            return "أعلى من القياسي بـ \(String(format: "%.0f", differenceCentimeters)) سم"
        }
        return "أقل من القياسي بـ \(String(format: "%.0f", abs(differenceCentimeters))) سم"
    }

    private func comparisonColor(for point: ElectricalPoint) -> Color {
        let difference = abs(point.heightFromFloor - targetHeight(for: point))
        return difference <= 0.02 ? .green : .orange
    }
}
