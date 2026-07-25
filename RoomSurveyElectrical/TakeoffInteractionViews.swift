import Foundation
import SwiftUI

struct TakeoffElectricalGroupDetailView: View {
    let project: RoomProject
    let type: ElectricalDeviceType
    let status: PlacementStatus

    @State private var focusedTarget: Plan2DHighlightTarget?

    private var points: [ElectricalPoint] {
        project.points
            .filter { $0.type == type && $0.status == status }
            .sorted { first, second in
                let firstWall = wallNumber(for: first.wallID)
                let secondWall = wallNumber(for: second.wallID)
                if firstWall == secondWall {
                    return first.localX < second.localX
                }
                return firstWall < secondWall
            }
    }

    var body: some View {
        List {
            Section("ملخص البند") {
                LabeledContent("العدد", value: "\(points.count)")
                LabeledContent("الحالة", value: status.title)
                LabeledContent("نطاق الارتفاع", value: heightRangeText)
                LabeledContent("عدد الحوائط", value: "\(wallCount)")
            }

            Section("تفاصيل العناصر") {
                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    Button {
                        focusedTarget = .electricalPoint(point.id)
                    } label: {
                        electricalPointRow(point, index: index)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("\(type.title) – \(status.title)")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $focusedTarget) { target in
            TakeoffFocusedPlanView(
                project: project,
                target: target,
                title: type.title
            )
        }
    }

    private func electricalPointRow(
        _ point: ElectricalPoint,
        index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    "\(type.title) \(index + 1)",
                    systemImage: type.systemImage
                )
                .font(.headline)
                Spacer()
                Text(point.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        point.status == .existing ? Color.green : Color.orange
                    )
            }

            detailLine(
                "الارتفاع من الأرض",
                value: metres(point.heightFromFloor)
            )
            detailLine(
                "الحائط",
                value: "حائط \(wallNumber(for: point.wallID))"
            )
            detailLine(
                "من بداية الحائط",
                value: centimetres(distanceFromWallStart(for: point))
            )

            if let doorOffset = point.measuredDoorOffset {
                detailLine(
                    "من أقرب باب",
                    value: centimetres(doorOffset)
                )
            }

            detailLine(
                "الارتفاع القياسي",
                value: centimetres(targetHeight(for: point))
            )

            HStack(spacing: 5) {
                Image(systemName: point.wasAutomaticallyAdjusted == true
                    ? "wand.and.stars"
                    : "scope")
                Text(placementDescription(for: point))
                Spacer()
                Label("عرض على المخطط", systemImage: "scope")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func detailLine(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(.caption)
    }

    private var settings: ElectricalPlacementSettings {
        project.electricalSettings ?? .standard
    }

    private var heightRangeText: String {
        guard let minimum = points.map(\.heightFromFloor).min(),
              let maximum = points.map(\.heightFromFloor).max() else {
            return "—"
        }
        if abs(maximum - minimum) <= 0.005 {
            return metres(minimum)
        }
        return "\(metres(minimum)) – \(metres(maximum))"
    }

    private var wallCount: Int {
        Set(points.map(\.wallID)).count
    }

    private func wallNumber(for wallID: UUID) -> Int {
        (project.walls.firstIndex { $0.id == wallID } ?? 0) + 1
    }

    private func distanceFromWallStart(for point: ElectricalPoint) -> Float {
        guard let wall = project.walls.first(where: {
            $0.id == point.wallID
        }) else {
            return 0
        }
        return max(0, point.localX + wall.width / 2)
    }

    private func targetHeight(for point: ElectricalPoint) -> Float {
        point.standardHeightAtCreation
            ?? point.type.recommendedHeight(
                using: settings,
                wallHeight: project.walls.first(where: {
                    $0.id == point.wallID
                })?.height
            )
    }

    private func placementDescription(for point: ElectricalPoint) -> String {
        if point.status == .existing {
            return "موضع فعلي محفوظ دون قواعد التأسيس"
        }
        return point.wasAutomaticallyAdjusted == true
            ? "تم تطبيق قواعد التأسيس تلقائيًا"
            : "عنصر مقترح"
    }
}

struct TakeoffCeilingLightGroupDetailView: View {
    let project: RoomProject
    let source: CeilingLightSource

    @State private var focusedTarget: Plan2DHighlightTarget?

    private var lights: [CeilingLight] {
        (project.ceilingLights ?? [])
            .filter { $0.resolvedSource == source }
            .sorted { first, second in
                let firstX = first.worldPosition.first ?? 0
                let secondX = second.worldPosition.first ?? 0
                if abs(firstX - secondX) <= 0.001 {
                    return (first.worldPosition.count >= 3 ? first.worldPosition[2] : 0)
                        < (second.worldPosition.count >= 3 ? second.worldPosition[2] : 0)
                }
                return firstX < secondX
            }
    }

    var body: some View {
        List {
            Section("ملخص البند") {
                LabeledContent("العدد", value: "\(lights.count)")
                LabeledContent("التصنيف", value: source.takeoffTitle)
                LabeledContent("نطاق الارتفاع", value: heightRangeText)
                LabeledContent("نطاق القطر", value: diameterRangeText)
            }

            Section("تفاصيل وحدات الإضاءة") {
                ForEach(Array(lights.enumerated()), id: \.element.id) { index, light in
                    Button {
                        focusedTarget = .ceilingLight(light.id)
                    } label: {
                        ceilingLightRow(light, index: index)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(source.takeoffTitle)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $focusedTarget) { target in
            TakeoffFocusedPlanView(
                project: project,
                target: target,
                title: "إضاءة السقف"
            )
        }
    }

    private func ceilingLightRow(
        _ light: CeilingLight,
        index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    "إضاءة سقف \(index + 1)",
                    systemImage: "light.recessed"
                )
                .font(.headline)
                Spacer()
                Text(source.shortTakeoffTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(source.takeoffColor)
            }

            detailLine("الارتفاع من الأرض", value: ceilingHeightText(light))
            detailLine(
                "قطر وحدة الإضاءة",
                value: centimetres(light.diameterMeters)
            )
            detailLine(
                "شدة الإضاءة",
                value: "\(Int((light.brightness * 100).rounded()))%"
            )
            if light.worldPosition.count >= 3 {
                detailLine(
                    "الموقع على المخطط",
                    value: String(
                        format: "X %.2f م • Y %.2f م",
                        light.worldPosition[0],
                        light.worldPosition[2]
                    )
                )
            }

            HStack {
                Spacer()
                Label("عرض مكانها على المخطط", systemImage: "scope")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func detailLine(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(.caption)
    }

    private var floorHeight: Float {
        (project.floors ?? []).map {
            $0.matrix.columns.3.y
        }.min() ?? project.walls.map {
            $0.matrix.columns.3.y - $0.height / 2
        }.min() ?? 0
    }

    private func resolvedHeight(_ light: CeilingLight) -> Float? {
        guard light.worldPosition.count >= 2 else { return nil }
        return max(0, light.worldPosition[1] - floorHeight)
    }

    private func ceilingHeightText(_ light: CeilingLight) -> String {
        guard let height = resolvedHeight(light) else { return "موضع غير مكتمل" }
        return metres(height)
    }

    private var heightRangeText: String {
        let values = lights.compactMap(resolvedHeight)
        guard let minimum = values.min(), let maximum = values.max() else {
            return "—"
        }
        if abs(maximum - minimum) <= 0.005 {
            return metres(minimum)
        }
        return "\(metres(minimum)) – \(metres(maximum))"
    }

    private var diameterRangeText: String {
        guard let minimum = lights.map(\.diameterMeters).min(),
              let maximum = lights.map(\.diameterMeters).max() else {
            return "—"
        }
        if abs(maximum - minimum) <= 0.005 {
            return centimetres(minimum)
        }
        return "\(centimetres(minimum)) – \(centimetres(maximum))"
    }
}

extension CeilingLightSource {
    var takeoffTitle: String {
        switch self {
        case .cameraExisting:
            return "إضاءة سقف موجودة – كاميرا"
        case .planManual:
            return "إضاءة سقف يدوية – 2D"
        case .planAutomatic:
            return "إضاءة سقف تلقائية – 2D"
        }
    }

    var shortTakeoffTitle: String {
        switch self {
        case .cameraExisting: "موجودة"
        case .planManual: "يدوية"
        case .planAutomatic: "تلقائية"
        }
    }

    var takeoffColor: Color {
        switch self {
        case .cameraExisting: .green
        case .planManual: .orange
        case .planAutomatic: .blue
        }
    }
}

func electricalTakeoffHeightSummary(
    project: RoomProject,
    type: ElectricalDeviceType,
    status: PlacementStatus
) -> String {
    let heights = project.points.filter {
        $0.type == type && $0.status == status
    }.map(\.heightFromFloor)
    guard let minimum = heights.min(), let maximum = heights.max() else {
        return "—"
    }
    if abs(maximum - minimum) <= 0.005 {
        return metres(minimum)
    }
    return "\(metres(minimum)) – \(metres(maximum))"
}

private func metres(_ value: Float) -> String {
    String(format: "%.2f م", value)
}

private func centimetres(_ value: Float) -> String {
    String(format: "%.0f سم", value * 100)
}
