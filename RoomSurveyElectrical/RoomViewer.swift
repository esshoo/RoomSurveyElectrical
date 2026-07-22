import Foundation
import SceneKit
import simd
import SwiftUI

enum ScanPresentationMode: String, CaseIterable, Identifiable {
    case plan2D
    case model3D

    var id: String { rawValue }
    var title: String { self == .plan2D ? "2D" : "3D" }
    var systemImage: String { self == .plan2D ? "square.grid.2x2" : "cube.fill" }
}

struct ViewerLayerVisibility: Equatable {
    var floor = true
    var walls = true
    var openings = true
    var furniture = true
    var electrical = true
    var dimensions = true
}

struct RoomViewerView: View {
    let project: RoomProject

    @State private var mode: ScanPresentationMode = .plan2D
    @State private var layers = ViewerLayerVisibility()
    @State private var showInformation = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            switch mode {
            case .plan2D:
                Plan2DView(project: project, layers: layers)
            case .model3D:
                model3D
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                optionsMenu
            }
        }
        .safeAreaInset(edge: .bottom) {
            viewerControls
        }
        .sheet(isPresented: $showInformation) {
            ScanInformationSheet(project: project)
        }
    }

    @ViewBuilder
    private var model3D: some View {
        if let url = try? ProjectRepository.fileURL(
            projectID: project.id,
            fileName: project.usdzFile
        ) {
            USDZRoomView(url: url, project: project, layers: layers)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Label(
                        "اسحب للتدوير • قرّب بإصبعين • اضغط مرتين لإعادة العرض",
                        systemImage: "hand.draw.fill"
                    )
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 12)
                }
        } else {
            ContentUnavailableView(
                "نموذج 3D غير موجود",
                systemImage: "cube.transparent",
                description: Text("ملف USDZ الخاص بهذا المسح غير متاح.")
            )
        }
    }

    private var viewerControls: some View {
        HStack(spacing: 12) {
            Picker("طريقة العرض", selection: $mode) {
                ForEach(ScanPresentationMode.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Menu {
                Toggle(isOn: $layers.floor) {
                    Label("الأرضية", systemImage: "square.fill")
                }
                Toggle(isOn: $layers.walls) {
                    Label("الحوائط", systemImage: "rectangle.split.3x1.fill")
                }
                Toggle(isOn: $layers.openings) {
                    Label("الأبواب والشبابيك", systemImage: "door.left.hand.open")
                }
                Toggle(isOn: $layers.furniture) {
                    Label("الأثاث", systemImage: "chair.lounge.fill")
                }
                Toggle(isOn: $layers.electrical) {
                    Label("الكهرباء", systemImage: "bolt.circle.fill")
                }
                if mode == .plan2D {
                    Toggle(isOn: $layers.dimensions) {
                        Label("الأبعاد", systemImage: "ruler.fill")
                    }
                }
            } label: {
                Image(systemName: "square.3.layers.3d")
                    .font(.headline)
                    .frame(width: 42, height: 34)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("طبقات العرض")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var optionsMenu: some View {
        Menu {
            Button {
                showInformation = true
            } label: {
                Label("معلومات المسح والحصر", systemImage: "info.circle")
            }

            Section("تصدير الملفات الأصلية") {
                if let url = try? ProjectRepository.fileURL(
                    projectID: project.id,
                    fileName: "project.json"
                ) {
                    ShareLink(item: url) {
                        Label("المشروع والنقاط JSON", systemImage: "list.bullet.rectangle")
                    }
                }

                if let url = try? ProjectRepository.fileURL(
                    projectID: project.id,
                    fileName: project.processedJSONFile
                ) {
                    ShareLink(item: url) {
                        Label("بيانات RoomPlan JSON", systemImage: "doc.text")
                    }
                }

                if let url = try? ProjectRepository.fileURL(
                    projectID: project.id,
                    fileName: project.usdzFile
                ) {
                    ShareLink(item: url) {
                        Label("نموذج USDZ", systemImage: "cube")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}

private struct Plan2DView: View {
    let project: RoomProject
    let layers: ViewerLayerVisibility

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)

            Canvas { context, size in
                drawPlan(context: &context, size: size)
            }
            .scaleEffect(zoom)
            .offset(offset)
            .gesture(dragGesture)
            .simultaneousGesture(magnificationGesture)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded(resetView)
            )

            VStack {
                HStack {
                    PlanLegendView(layers: layers)
                    Spacer()
                    Button(action: resetView) {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("إعادة ضبط المخطط")
                }
                .padding(12)
                Spacer()
            }
        }
        .clipped()
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                committedOffset = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = min(max(committedZoom * value, 0.75), 6)
            }
            .onEnded { _ in
                committedZoom = zoom
            }
    }

    private func resetView() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoom = 1
            committedZoom = 1
            offset = .zero
            committedOffset = .zero
        }
    }

    private func drawPlan(context: inout GraphicsContext, size: CGSize) {
        let projection = PlanProjection(project: project, size: size)
        drawGrid(context: &context, projection: projection)

        if layers.floor {
            for floor in project.floors ?? [] {
                drawFloor(floor, context: &context, projection: projection)
            }
        }

        if layers.furniture {
            for object in project.objects ?? [] {
                drawObject(object, context: &context, projection: projection)
            }
        }

        if layers.walls {
            for wall in project.walls {
                drawWall(wall, context: &context, projection: projection)
            }
        }

        if layers.openings {
            for surface in project.surfaces {
                drawSurface(surface, context: &context, projection: projection)
            }
        }

        if layers.electrical {
            for point in project.points {
                drawElectricalPoint(point, context: &context, projection: projection)
            }
        }
    }

    private func drawGrid(context: inout GraphicsContext, projection: PlanProjection) {
        let startX = Int(projection.minX.rounded(.down))
        let endX = Int(projection.maxX.rounded(.up))
        let startZ = Int(projection.minZ.rounded(.down))
        let endZ = Int(projection.maxZ.rounded(.up))

        for x in startX...endX {
            var path = Path()
            path.move(to: projection.map(SIMD2(Float(x), projection.minZ)))
            path.addLine(to: projection.map(SIMD2(Float(x), projection.maxZ)))
            context.stroke(path, with: .color(.secondary.opacity(0.12)), lineWidth: 0.7)
        }

        for z in startZ...endZ {
            var path = Path()
            path.move(to: projection.map(SIMD2(projection.minX, Float(z))))
            path.addLine(to: projection.map(SIMD2(projection.maxX, Float(z))))
            context.stroke(path, with: .color(.secondary.opacity(0.12)), lineWidth: 0.7)
        }
    }

    private func drawFloor(
        _ floor: FloorSnapshot,
        context: inout GraphicsContext,
        projection: PlanProjection
    ) {
        let corners = floorPlanCorners(floor)
        guard let first = corners.first else { return }
        var path = Path()
        path.move(to: projection.map(first))
        for point in corners.dropFirst() {
            path.addLine(to: projection.map(point))
        }
        path.closeSubpath()
        context.fill(path, with: .color(.gray.opacity(0.12)))
        context.stroke(path, with: .color(.gray.opacity(0.35)), lineWidth: 1)
    }

    private func drawWall(
        _ wall: WallSnapshot,
        context: inout GraphicsContext,
        projection: PlanProjection
    ) {
        let endpoints = wallPlanEndpoints(wall)
        var path = Path()
        path.move(to: projection.map(endpoints.0))
        path.addLine(to: projection.map(endpoints.1))
        context.stroke(
            path,
            with: .color(.blue),
            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        )

        if layers.dimensions {
            let midpoint = (endpoints.0 + endpoints.1) / 2
            let label = Text(String(format: "%.2f م", wall.width))
                .font(.caption2.weight(.semibold))
                .foregroundColor(.primary)
            context.draw(
                label,
                at: projection.map(midpoint),
                anchor: .bottom
            )
        }
    }

    private func drawSurface(
        _ surface: SurfaceSnapshot,
        context: inout GraphicsContext,
        projection: PlanProjection
    ) {
        let endpoints = surfacePlanEndpoints(surface)
        let color: Color
        switch surface.kind {
        case .door: color = .orange
        case .window: color = .cyan
        case .opening: color = .purple
        }

        var path = Path()
        path.move(to: projection.map(endpoints.0))
        path.addLine(to: projection.map(endpoints.1))
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: 9, lineCap: .butt)
        )
    }

    private func drawObject(
        _ object: RoomObjectSnapshot,
        context: inout GraphicsContext,
        projection: PlanProjection
    ) {
        let corners = objectPlanCorners(object)
        guard let first = corners.first else { return }
        var path = Path()
        path.move(to: projection.map(first))
        for point in corners.dropFirst() {
            path.addLine(to: projection.map(point))
        }
        path.closeSubpath()
        context.fill(path, with: .color(.gray.opacity(0.22)))
        context.stroke(path, with: .color(.gray.opacity(0.65)), lineWidth: 1.2)

        let center = planCenter(object.matrix)
        let label = Text(object.title)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.secondary)
        context.draw(label, at: projection.map(center))
    }

    private func drawElectricalPoint(
        _ point: ElectricalPoint,
        context: inout GraphicsContext,
        projection: PlanProjection
    ) {
        guard point.worldPosition.count >= 3 else { return }
        let center = projection.map(SIMD2(point.worldPosition[0], point.worldPosition[2]))
        let rect = CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)
        let color: Color = point.status == .existing ? .green : .orange
        context.fill(Path(ellipseIn: rect), with: .color(color))
        context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
    }
}

private struct PlanLegendView: View {
    let layers: ViewerLayerVisibility

    var body: some View {
        HStack(spacing: 9) {
            if layers.walls { legendDot(.blue, title: "حائط") }
            if layers.openings {
                legendDot(.orange, title: "باب")
                legendDot(.cyan, title: "شباك")
            }
            if layers.electrical { legendDot(.green, title: "كهرباء") }
        }
        .font(.caption2)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func legendDot(_ color: Color, title: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
    }
}

private struct PlanProjection {
    let minX: Float
    let maxX: Float
    let minZ: Float
    let maxZ: Float
    let size: CGSize

    init(project: RoomProject, size: CGSize) {
        var points: [SIMD2<Float>] = []
        points.append(contentsOf: project.walls.flatMap { wall in
            let endpoints = wallPlanEndpoints(wall)
            return [endpoints.0, endpoints.1]
        })
        points.append(contentsOf: (project.floors ?? []).flatMap(floorPlanCorners))
        points.append(contentsOf: (project.objects ?? []).flatMap(objectPlanCorners))
        points.append(contentsOf: project.points.compactMap { point in
            guard point.worldPosition.count >= 3 else { return nil }
            return SIMD2(point.worldPosition[0], point.worldPosition[2])
        })

        if points.isEmpty {
            points = [SIMD2(-2, -2), SIMD2(2, 2)]
        }

        let rawMinX = points.map(\.x).min() ?? -2
        let rawMaxX = points.map(\.x).max() ?? 2
        let rawMinZ = points.map(\.y).min() ?? -2
        let rawMaxZ = points.map(\.y).max() ?? 2
        let margin: Float = 0.45
        minX = rawMinX - margin
        maxX = rawMaxX + margin
        minZ = rawMinZ - margin
        maxZ = rawMaxZ + margin
        self.size = size
    }

    func map(_ point: SIMD2<Float>) -> CGPoint {
        let rangeX = max(maxX - minX, 0.5)
        let rangeZ = max(maxZ - minZ, 0.5)
        let padding: CGFloat = 34
        let availableWidth = max(size.width - padding * 2, 1)
        let availableHeight = max(size.height - padding * 2, 1)
        let scale = min(
            availableWidth / CGFloat(rangeX),
            availableHeight / CGFloat(rangeZ)
        )
        let midX = (minX + maxX) / 2
        let midZ = (minZ + maxZ) / 2
        return CGPoint(
            x: size.width / 2 + CGFloat(point.x - midX) * scale,
            y: size.height / 2 - CGFloat(point.y - midZ) * scale
        )
    }
}

private struct USDZRoomView: UIViewRepresentable {
    let url: URL
    let project: RoomProject
    let layers: ViewerLayerVisibility

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .secondarySystemGroupedBackground
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = true
        view.rendersContinuously = true
        context.coordinator.loadScene(into: view)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.resetCamera)
        )
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateScene(in: uiView)
    }

    final class Coordinator: NSObject {
        var parent: USDZRoomView
        private var loadedURL: URL?
        private weak var sceneView: SCNView?
        private var initialCameraPosition = SCNVector3(5, 4, 5)
        private var cameraTarget = SCNVector3Zero

        init(parent: USDZRoomView) {
            self.parent = parent
        }

        func loadScene(into view: SCNView) {
            sceneView = view
            guard let scene = try? SCNScene(url: parent.url, options: nil) else {
                view.scene = SCNScene()
                return
            }
            loadedURL = parent.url
            view.scene = scene
            scene.rootNode.childNode(withName: "Section_grp", recursively: true)?.isHidden = true
            addElectricalMarkers(to: scene)
            configureCamera(for: scene, in: view)
            applyLayerVisibility(to: scene)
        }

        func updateScene(in view: SCNView) {
            if loadedURL != parent.url {
                loadScene(into: view)
                return
            }
            guard let scene = view.scene else { return }
            addElectricalMarkers(to: scene)
            applyLayerVisibility(to: scene)
        }

        private func configureCamera(for scene: SCNScene, in view: SCNView) {
            let bounds = scene.rootNode.boundingBox
            let center = SCNVector3(
                (bounds.min.x + bounds.max.x) / 2,
                (bounds.min.y + bounds.max.y) / 2,
                (bounds.min.z + bounds.max.z) / 2
            )
            let extentX = bounds.max.x - bounds.min.x
            let extentY = bounds.max.y - bounds.min.y
            let extentZ = bounds.max.z - bounds.min.z
            let largest = max(max(extentX, extentY), max(extentZ, 1))

            let camera = SCNCamera()
            camera.fieldOfView = 52
            camera.zNear = 0.01
            camera.zFar = Double(max(largest * 30, 100))

            let cameraNode = SCNNode()
            cameraNode.name = "3e-viewer-camera"
            cameraNode.camera = camera
            initialCameraPosition = SCNVector3(
                center.x + largest * 1.35,
                center.y + largest * 1.05,
                center.z + largest * 1.35
            )
            cameraTarget = center
            cameraNode.position = initialCameraPosition
            cameraNode.look(at: center)
            scene.rootNode.addChildNode(cameraNode)
            view.pointOfView = cameraNode
        }

        private func addElectricalMarkers(to scene: SCNScene) {
            scene.rootNode.childNode(withName: "3e-electrical-markers", recursively: false)?
                .removeFromParentNode()

            let root = SCNNode()
            root.name = "3e-electrical-markers"
            root.isHidden = !parent.layers.electrical
            scene.rootNode.addChildNode(root)

            for point in parent.project.points where point.worldPosition.count >= 3 {
                let sphere = SCNSphere(radius: 0.055)
                let material = SCNMaterial()
                let color: UIColor = point.status == .existing ? .systemGreen : .systemOrange
                material.diffuse.contents = color
                material.emission.contents = color.withAlphaComponent(0.3)
                sphere.materials = [material]

                let node = SCNNode(geometry: sphere)
                node.position = SCNVector3(
                    point.worldPosition[0],
                    point.worldPosition[1],
                    point.worldPosition[2]
                )
                root.addChildNode(node)
            }
        }

        private func applyLayerVisibility(to scene: SCNScene) {
            let showArchitecture = parent.layers.walls || parent.layers.openings
            scene.rootNode.childNode(withName: "Arch_grp", recursively: true)?.isHidden = !showArchitecture
            scene.rootNode.childNode(withName: "Floor_grp", recursively: true)?.isHidden = !parent.layers.floor
            scene.rootNode.childNode(withName: "Object_grp", recursively: true)?.isHidden = !parent.layers.furniture
            scene.rootNode.childNode(withName: "3e-electrical-markers", recursively: false)?.isHidden = !parent.layers.electrical
        }

        @objc func resetCamera() {
            guard let cameraNode = sceneView?.pointOfView else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.3
            cameraNode.position = initialCameraPosition
            cameraNode.look(at: cameraTarget)
            SCNTransaction.commit()
        }
    }
}

private struct ScanInformationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let project: RoomProject

    var body: some View {
        NavigationStack {
            List {
                Section("ملخص المسح") {
                    LabeledContent("الحوائط", value: "\(project.wallCount)")
                    LabeledContent("الأبواب", value: "\(project.doorCount)")
                    LabeledContent("الشبابيك", value: "\(project.windowCount)")
                    LabeledContent("قطع الأثاث", value: "\(project.furnitureCount)")
                    LabeledContent("نقاط الكهرباء", value: "\(project.points.count)")
                }

                Section("الحصر الكهربائي") {
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
            }
            .navigationTitle("معلومات المسح")
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

private func planCenter(_ matrix: simd_float4x4) -> SIMD2<Float> {
    SIMD2(matrix.columns.3.x, matrix.columns.3.z)
}

private func normalizedPlanAxis(_ vector: SIMD4<Float>) -> SIMD2<Float> {
    let axis = SIMD2(vector.x, vector.z)
    let length = simd_length(axis)
    return length > 0.0001 ? axis / length : SIMD2(1, 0)
}

private func wallPlanEndpoints(_ wall: WallSnapshot) -> (SIMD2<Float>, SIMD2<Float>) {
    let center = planCenter(wall.matrix)
    let axis = normalizedPlanAxis(wall.matrix.columns.0)
    let half = axis * (wall.width / 2)
    return (center - half, center + half)
}

private func surfacePlanEndpoints(_ surface: SurfaceSnapshot) -> (SIMD2<Float>, SIMD2<Float>) {
    let matrix = simd_float4x4(columnMajorValues: surface.transform)
    let center = planCenter(matrix)
    let axis = normalizedPlanAxis(matrix.columns.0)
    let half = axis * (surface.width / 2)
    return (center - half, center + half)
}

private func floorPlanCorners(_ floor: FloorSnapshot) -> [SIMD2<Float>] {
    let matrix = floor.matrix
    let center = planCenter(matrix)
    let xAxis = normalizedPlanAxis(matrix.columns.0) * (floor.width / 2)
    let zAxis = normalizedPlanAxis(matrix.columns.1) * (floor.depth / 2)
    return [
        center - xAxis - zAxis,
        center + xAxis - zAxis,
        center + xAxis + zAxis,
        center - xAxis + zAxis
    ]
}

private func objectPlanCorners(_ object: RoomObjectSnapshot) -> [SIMD2<Float>] {
    let matrix = object.matrix
    let center = planCenter(matrix)
    let xAxis = normalizedPlanAxis(matrix.columns.0) * (object.width / 2)
    let zAxis = normalizedPlanAxis(matrix.columns.2) * (object.depth / 2)
    return [
        center - xAxis - zAxis,
        center + xAxis - zAxis,
        center + xAxis + zAxis,
        center - xAxis + zAxis
    ]
}
