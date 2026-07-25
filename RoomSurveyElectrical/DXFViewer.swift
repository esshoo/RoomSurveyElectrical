import Foundation
import SwiftUI

struct DXFViewerDocument: Sendable {
    let entities: [DXFRenderableEntity]
    let layers: [String]
    let bounds: DXFViewBounds
    let unsupportedEntityCount: Int
}

struct DXFViewPoint: Sendable, Equatable {
    let x: Double
    let y: Double
}

struct DXFViewBounds: Sendable, Equatable {
    let minimumX: Double
    let maximumX: Double
    let minimumY: Double
    let maximumY: Double

    var width: Double { max(maximumX - minimumX, 0.001) }
    var height: Double { max(maximumY - minimumY, 0.001) }
    var center: DXFViewPoint {
        DXFViewPoint(
            x: (minimumX + maximumX) / 2,
            y: (minimumY + maximumY) / 2
        )
    }
}

struct DXFRenderableEntity: Sendable, Identifiable {
    enum Kind: Sendable {
        case line
        case polyline(closed: Bool)
        case circle
        case text
    }

    let id: Int
    let kind: Kind
    let layer: String
    let points: [DXFViewPoint]
    let radius: Double
    let text: String
    let textHeight: Double
    let rotation: Double
}

enum DXFViewerError: LocalizedError {
    case unreadableFile
    case malformedPairs
    case noSupportedEntities

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "تعذر قراءة ملف DXF."
        case .malformedPairs:
            "ملف DXF غير مكتمل أو لا يتبع بنية group code المعتادة."
        case .noSupportedEntities:
            "لم يعثر العارض على خطوط أو دوائر أو نصوص قابلة للعرض."
        }
    }
}

enum DXFViewerParser {
    private struct Pair {
        let code: Int
        let value: String
    }

    static func parse(url: URL) throws -> DXFViewerDocument {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw DXFViewerError.unreadableFile
        }
        let text = String(decoding: data, as: UTF8.self)
        var rawLines = text.split(
            omittingEmptySubsequences: false,
            whereSeparator: \Character.isNewline
        ).map(String.init)
        if rawLines.last?.isEmpty == true {
            rawLines.removeLast()
        }
        guard rawLines.count.isMultiple(of: 2) else {
            throw DXFViewerError.malformedPairs
        }

        var pairs: [Pair] = []
        pairs.reserveCapacity(rawLines.count / 2)
        var lineIndex = 0
        while lineIndex < rawLines.count {
            guard let code = Int(rawLines[lineIndex].trimmingCharacters(
                in: .whitespacesAndNewlines
            )) else {
                throw DXFViewerError.malformedPairs
            }
            pairs.append(
                Pair(
                    code: code,
                    value: rawLines[lineIndex + 1]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            lineIndex += 2
        }

        var entities: [DXFRenderableEntity] = []
        var layerNames: Set<String> = []
        var currentSection: String?
        var currentType: String?
        var currentPairs: [Pair] = []
        var unsupportedCount = 0
        var nextEntityID = 0

        func finishRecord() {
            guard let currentType else { return }
            let type = currentType.uppercased()
            if type == "LAYER",
               let layer = currentPairs.first(where: { $0.code == 2 })?.value,
               !layer.isEmpty {
                layerNames.insert(layer)
            }
            guard currentSection == "ENTITIES" else { return }
            let isPaperSpace = currentPairs.first {
                $0.code == 67
            }.flatMap { Int($0.value) } == 1
            guard !isPaperSpace else { return }
            if let entity = parseEntity(
                id: nextEntityID,
                type: type,
                pairs: currentPairs
            ) {
                entities.append(entity)
                layerNames.insert(entity.layer)
                nextEntityID += 1
            } else if !["SEQEND", "VERTEX"].contains(type) {
                unsupportedCount += 1
            }
        }

        var index = 0
        while index < pairs.count {
            let pair = pairs[index]
            if pair.code == 0 {
                finishRecord()
                currentType = nil
                currentPairs.removeAll(keepingCapacity: true)
                let value = pair.value.uppercased()
                if value == "SECTION" {
                    guard index + 1 < pairs.count,
                          pairs[index + 1].code == 2 else {
                        throw DXFViewerError.malformedPairs
                    }
                    currentSection = pairs[index + 1].value.uppercased()
                    index += 2
                    continue
                }
                if value == "ENDSEC" {
                    currentSection = nil
                    index += 1
                    continue
                }
                if !["EOF", "TABLE", "ENDTAB"].contains(value) {
                    currentType = value
                }
            } else if currentType != nil {
                currentPairs.append(pair)
            }
            index += 1
        }
        finishRecord()

        guard !entities.isEmpty else {
            throw DXFViewerError.noSupportedEntities
        }
        return DXFViewerDocument(
            entities: entities,
            layers: layerNames.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            },
            bounds: calculateBounds(entities),
            unsupportedEntityCount: unsupportedCount
        )
    }

    private static func parseEntity(
        id: Int,
        type: String,
        pairs: [Pair]
    ) -> DXFRenderableEntity? {
        let layer = pairs.first(where: { $0.code == 8 })?.value ?? "0"
        switch type {
        case "LINE":
            guard let start = point(xCode: 10, yCode: 20, pairs: pairs),
                  let end = point(xCode: 11, yCode: 21, pairs: pairs) else {
                return nil
            }
            return DXFRenderableEntity(
                id: id,
                kind: .line,
                layer: layer,
                points: [start, end],
                radius: 0,
                text: "",
                textHeight: 0,
                rotation: 0
            )
        case "LWPOLYLINE":
            var points: [DXFViewPoint] = []
            var pendingX: Double?
            for pair in pairs {
                if pair.code == 10 {
                    pendingX = Double(pair.value)
                } else if pair.code == 20,
                          let x = pendingX,
                          let y = Double(pair.value) {
                    points.append(DXFViewPoint(x: x, y: y))
                    pendingX = nil
                }
            }
            guard points.count >= 2 else { return nil }
            let flags = intValue(code: 70, pairs: pairs) ?? 0
            return DXFRenderableEntity(
                id: id,
                kind: .polyline(closed: flags & 1 == 1),
                layer: layer,
                points: points,
                radius: 0,
                text: "",
                textHeight: 0,
                rotation: 0
            )
        case "CIRCLE":
            guard let center = point(xCode: 10, yCode: 20, pairs: pairs),
                  let radius = doubleValue(code: 40, pairs: pairs),
                  radius > 0 else {
                return nil
            }
            return DXFRenderableEntity(
                id: id,
                kind: .circle,
                layer: layer,
                points: [center],
                radius: radius,
                text: "",
                textHeight: 0,
                rotation: 0
            )
        case "TEXT", "MTEXT":
            guard let insertion = point(
                xCode: 10,
                yCode: 20,
                pairs: pairs
            ) else {
                return nil
            }
            let content = decodeDXFText(
                pairs
                    .filter { $0.code == 1 || $0.code == 3 }
                    .map(\.value)
                    .joined()
            )
            guard !content.isEmpty else { return nil }
            return DXFRenderableEntity(
                id: id,
                kind: .text,
                layer: layer,
                points: [insertion],
                radius: 0,
                text: content,
                textHeight: doubleValue(code: 40, pairs: pairs) ?? 0.1,
                rotation: doubleValue(code: 50, pairs: pairs) ?? 0
            )
        default:
            return nil
        }
    }

    private static func decodeDXFText(_ raw: String) -> String {
        var output = ""
        var index = raw.startIndex
        var pendingHighSurrogate: UInt32?

        func appendCodeUnit(_ codeUnit: UInt32) {
            if (0xD800...0xDBFF).contains(codeUnit) {
                pendingHighSurrogate = codeUnit
                return
            }
            if let high = pendingHighSurrogate,
               (0xDC00...0xDFFF).contains(codeUnit) {
                let scalarValue = 0x10000
                    + ((high - 0xD800) << 10)
                    + (codeUnit - 0xDC00)
                if let scalar = UnicodeScalar(scalarValue) {
                    output.unicodeScalars.append(scalar)
                }
                pendingHighSurrogate = nil
                return
            }
            if let high = pendingHighSurrogate,
               let scalar = UnicodeScalar(high) {
                output.unicodeScalars.append(scalar)
            }
            pendingHighSurrogate = nil
            if let scalar = UnicodeScalar(codeUnit) {
                output.unicodeScalars.append(scalar)
            }
        }

        while index < raw.endIndex {
            if raw[index] == "\\" {
                let uIndex = raw.index(after: index)
                if uIndex < raw.endIndex,
                   raw[uIndex].uppercased() == "U" {
                    let plusIndex = raw.index(after: uIndex)
                    if plusIndex < raw.endIndex, raw[plusIndex] == "+" {
                        let hexStart = raw.index(after: plusIndex)
                        var hexEnd = hexStart
                        for _ in 0..<4 where hexEnd < raw.endIndex {
                            hexEnd = raw.index(after: hexEnd)
                        }
                        if raw.distance(from: hexStart, to: hexEnd) == 4,
                           let value = UInt32(raw[hexStart..<hexEnd], radix: 16) {
                            appendCodeUnit(value)
                            index = hexEnd
                            continue
                        }
                    }
                }
                if uIndex < raw.endIndex, raw[uIndex] == "P" {
                    output.append("\n")
                    index = raw.index(after: uIndex)
                    continue
                }
            }
            if let high = pendingHighSurrogate,
               let scalar = UnicodeScalar(high) {
                output.unicodeScalars.append(scalar)
                pendingHighSurrogate = nil
            }
            output.append(raw[index])
            index = raw.index(after: index)
        }
        if let high = pendingHighSurrogate,
           let scalar = UnicodeScalar(high) {
            output.unicodeScalars.append(scalar)
        }
        return output
            .replacingOccurrences(of: "%%d", with: "°", options: .caseInsensitive)
            .replacingOccurrences(of: "%%p", with: "±", options: .caseInsensitive)
            .replacingOccurrences(of: "%%c", with: "⌀", options: .caseInsensitive)
    }

    private static func point(
        xCode: Int,
        yCode: Int,
        pairs: [Pair]
    ) -> DXFViewPoint? {
        guard let x = doubleValue(code: xCode, pairs: pairs),
              let y = doubleValue(code: yCode, pairs: pairs) else {
            return nil
        }
        return DXFViewPoint(x: x, y: y)
    }

    private static func doubleValue(
        code: Int,
        pairs: [Pair]
    ) -> Double? {
        pairs.first(where: { $0.code == code }).flatMap {
            Double($0.value)
        }
    }

    private static func intValue(
        code: Int,
        pairs: [Pair]
    ) -> Int? {
        pairs.first(where: { $0.code == code }).flatMap {
            Int($0.value)
        }
    }

    private static func calculateBounds(
        _ entities: [DXFRenderableEntity]
    ) -> DXFViewBounds {
        var minimumX = Double.greatestFiniteMagnitude
        var maximumX = -Double.greatestFiniteMagnitude
        var minimumY = Double.greatestFiniteMagnitude
        var maximumY = -Double.greatestFiniteMagnitude

        func include(_ point: DXFViewPoint, padding: Double = 0) {
            minimumX = min(minimumX, point.x - padding)
            maximumX = max(maximumX, point.x + padding)
            minimumY = min(minimumY, point.y - padding)
            maximumY = max(maximumY, point.y + padding)
        }

        for entity in entities {
            switch entity.kind {
            case .circle:
                if let center = entity.points.first {
                    include(center, padding: entity.radius)
                }
            case .text:
                if let point = entity.points.first {
                    include(point, padding: max(entity.textHeight, 0.05))
                }
            case .line, .polyline:
                entity.points.forEach { include($0) }
            }
        }
        guard minimumX.isFinite, maximumX.isFinite,
              minimumY.isFinite, maximumY.isFinite else {
            return DXFViewBounds(
                minimumX: -1,
                maximumX: 1,
                minimumY: -1,
                maximumY: 1
            )
        }
        let padding = max(maximumX - minimumX, maximumY - minimumY) * 0.04
        return DXFViewBounds(
            minimumX: minimumX - padding,
            maximumX: maximumX + padding,
            minimumY: minimumY - padding,
            maximumY: maximumY + padding
        )
    }
}

struct DXFViewerScreen: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL

    @State private var document: DXFViewerDocument?
    @State private var errorMessage: String?
    @State private var hiddenLayers: Set<String> = []
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var showLayers = false
    @GestureState private var gestureZoom: CGFloat = 1
    @GestureState private var gestureOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            Group {
                if let document {
                    GeometryReader { proxy in
                        ZStack(alignment: .bottomLeading) {
                            DXFCanvas(
                                document: document,
                                hiddenLayers: hiddenLayers,
                                zoom: zoom * gestureZoom,
                                offset: CGSize(
                                    width: offset.width + gestureOffset.width,
                                    height: offset.height + gestureOffset.height
                                )
                            )
                            .contentShape(Rectangle())
                            .gesture(panGesture)
                            .simultaneousGesture(zoomGesture)
                            .onTapGesture(count: 2, perform: resetView)

                            HStack(spacing: 10) {
                                Label(
                                    "\(document.entities.count) كيان",
                                    systemImage: "square.3.layers.3d"
                                )
                                Label(
                                    "\(document.layers.count) طبقة",
                                    systemImage: "square.stack.3d.up"
                                )
                                if document.unsupportedEntityCount > 0 {
                                    Label(
                                        "\(document.unsupportedEntityCount) غير معروض",
                                        systemImage: "exclamationmark.triangle"
                                    )
                                }
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.62), in: Capsule())
                            .padding(14)
                        }
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height
                        )
                    }
                } else if let errorMessage {
                    ContentUnavailableView(
                        "تعذر عرض DXF",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text(errorMessage)
                    )
                } else {
                    ProgressView("جاري تحليل ملف DXF…")
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("إغلاق", systemImage: "xmark")
                    }
                    .accessibilityLabel("إغلاق عارض DXF")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: resetView) {
                        Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    }
                    .accessibilityLabel("ملاءمة الرسم للشاشة")

                    Button {
                        showLayers = true
                    } label: {
                        Image(systemName: "square.3.layers.3d")
                    }
                    .accessibilityLabel("إدارة الطبقات")
                }
            }
            .sheet(isPresented: $showLayers) {
                if let document {
                    DXFLayerVisibilitySheet(
                        layers: document.layers,
                        hiddenLayers: $hiddenLayers
                    )
                }
            }
        }
        .task(id: url) {
            do {
                let parsed = try await Task.detached(
                    priority: .userInitiated
                ) {
                    try DXFViewerParser.parse(url: url)
                }.value
                document = parsed
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($gestureOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureZoom) { value, state, _ in
                state = value
            }
            .onEnded { value in
                zoom = min(max(zoom * value, 0.2), 30)
            }
    }

    private func resetView() {
        withAnimation(.easeInOut(duration: 0.22)) {
            zoom = 1
            offset = .zero
        }
    }
}

private struct DXFCanvas: View {
    let document: DXFViewerDocument
    let hiddenLayers: Set<String>
    let zoom: CGFloat
    let offset: CGSize

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            drawGrid(context: context, size: size)
            let bounds = document.bounds
            let availableWidth = max(size.width - 36, 1)
            let availableHeight = max(size.height - 36, 1)
            let fitScale = min(
                availableWidth / CGFloat(bounds.width),
                availableHeight / CGFloat(bounds.height)
            )
            let scale = max(fitScale * zoom, 0.0001)
            let center = bounds.center

            func screenPoint(_ value: DXFViewPoint) -> CGPoint {
                CGPoint(
                    x: size.width / 2
                        + CGFloat(value.x - center.x) * scale
                        + offset.width,
                    y: size.height / 2
                        - CGFloat(value.y - center.y) * scale
                        + offset.height
                )
            }

            for entity in document.entities where
                !hiddenLayers.contains(entity.layer) {
                let color = color(for: entity.layer)
                switch entity.kind {
                case .line:
                    guard entity.points.count >= 2 else { continue }
                    var path = Path()
                    path.move(to: screenPoint(entity.points[0]))
                    path.addLine(to: screenPoint(entity.points[1]))
                    context.stroke(
                        path,
                        with: .color(color),
                        style: strokeStyle(layer: entity.layer)
                    )
                case .polyline(let closed):
                    guard let first = entity.points.first else { continue }
                    var path = Path()
                    path.move(to: screenPoint(first))
                    for point in entity.points.dropFirst() {
                        path.addLine(to: screenPoint(point))
                    }
                    if closed { path.closeSubpath() }
                    context.stroke(
                        path,
                        with: .color(color),
                        style: strokeStyle(layer: entity.layer)
                    )
                case .circle:
                    guard let center = entity.points.first else { continue }
                    let radius = max(CGFloat(entity.radius) * scale, 1.5)
                    let point = screenPoint(center)
                    let rect = CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(color),
                        lineWidth: max(1.2, min(radius * 0.12, 3.5))
                    )
                case .text:
                    guard let insertion = entity.points.first else { continue }
                    let point = screenPoint(insertion)
                    let fontSize = min(
                        max(CGFloat(entity.textHeight) * scale, 8),
                        28
                    )
                    let text = Text(entity.text)
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundStyle(color)
                    var textContext = context
                    textContext.translateBy(x: point.x, y: point.y)
                    textContext.rotate(by: .degrees(-entity.rotation))
                    textContext.draw(
                        textContext.resolve(text),
                        at: .zero,
                        anchor: .center
                    )
                }
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.071, blue: 0.09),
                    Color(red: 0.025, green: 0.035, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func drawGrid(
        context: GraphicsContext,
        size: CGSize
    ) {
        var context = context
        let spacing: CGFloat = 32
        var minor = Path()
        var x: CGFloat = 0
        while x <= size.width {
            minor.move(to: CGPoint(x: x, y: 0))
            minor.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= size.height {
            minor.move(to: CGPoint(x: 0, y: y))
            minor.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        context.stroke(
            minor,
            with: .color(.white.opacity(0.055)),
            lineWidth: 0.6
        )
    }

    private func strokeStyle(layer: String) -> StrokeStyle {
        let width: CGFloat
        switch layer.uppercased() {
        case "WALLS", "DOORS", "WINDOWS", "OPENINGS":
            width = 2.2
        case "DIM_WALLS", "DIM_ELECTRICAL":
            width = 0.8
        default:
            width = 1.35
        }
        return StrokeStyle(
            lineWidth: width,
            lineCap: .round,
            lineJoin: .round
        )
    }

    private func color(for layer: String) -> Color {
        switch layer.uppercased() {
        case "FLOOR": .gray
        case "WALLS": .cyan
        case "DOORS": .orange
        case "WINDOWS": .blue
        case "OPENINGS": .purple
        case "FURNITURE": .mint
        case "ELECTRICAL_EXISTING": .green
        case "ELECTRICAL_PROPOSED": .orange
        case "CEILING_LIGHTING": .yellow
        case "DIM_WALLS": .cyan.opacity(0.8)
        case "DIM_ELECTRICAL": .purple.opacity(0.8)
        case "ANNOTATIONS": .white
        default: .white.opacity(0.85)
        }
    }
}

private struct DXFLayerVisibilitySheet: View {
    @Environment(\.dismiss) private var dismiss
    let layers: [String]
    @Binding var hiddenLayers: Set<String>

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("إظهار كل الطبقات") {
                        hiddenLayers.removeAll()
                    }
                    Button("إخفاء كل الطبقات") {
                        hiddenLayers = Set(layers)
                    }
                }

                Section("الطبقات") {
                    ForEach(layers, id: \.self) { layer in
                        Toggle(
                            layer,
                            isOn: Binding(
                                get: { !hiddenLayers.contains(layer) },
                                set: { visible in
                                    if visible {
                                        hiddenLayers.remove(layer)
                                    } else {
                                        hiddenLayers.insert(layer)
                                    }
                                }
                            )
                        )
                    }
                }
            }
            .navigationTitle("طبقات DXF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
        }
    }
}
