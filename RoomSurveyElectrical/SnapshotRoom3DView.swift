import SceneKit
import SwiftUI
import UIKit
import simd

/// Renders the app-owned geometry snapshots after a resumed scan. The original
/// RoomPlan USDZ represents only the first capture session and becomes stale as
/// soon as later sessions are merged; 2D and 3D therefore use the same arrays.
struct SnapshotRoom3DView: UIViewRepresentable {
    let project: RoomProject
    let layers: ViewerLayerVisibility
    let focusedWallID: UUID?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.semanticContentAttribute = .forceLeftToRight
        view.backgroundColor = .secondarySystemBackground
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = false
        context.coordinator.rebuild(
            view: view,
            project: project,
            layers: layers,
            focusedWallID: focusedWallID
        )
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let signature = Signature(project: project, layers: layers, focus: focusedWallID)
        guard context.coordinator.signature != signature else { return }
        context.coordinator.rebuild(
            view: view,
            project: project,
            layers: layers,
            focusedWallID: focusedWallID
        )
    }

    struct Signature: Equatable {
        let wallCount: Int
        let surfaceCount: Int
        let floorCount: Int
        let objectCount: Int
        let revision: Int
        let layers: ViewerLayerVisibility
        let focus: UUID?

        init(project: RoomProject, layers: ViewerLayerVisibility, focus: UUID?) {
            wallCount = project.walls.count
            surfaceCount = project.surfaces.count
            floorCount = project.floors?.count ?? 0
            objectCount = project.objects?.count ?? 0
            revision = project.snapshotGeometryRevision ?? 0
            self.layers = layers
            self.focus = focus
        }
    }

    final class Coordinator {
        var signature: Signature?

        func rebuild(
            view: SCNView,
            project: RoomProject,
            layers: ViewerLayerVisibility,
            focusedWallID: UUID?
        ) {
            signature = Signature(project: project, layers: layers, focus: focusedWallID)
            let scene = SCNScene()
            view.scene = scene

            addLighting(to: scene)
            if layers.floor { addFloors(project, to: scene) }
            if layers.walls { addWalls(project, to: scene, focusedWallID: focusedWallID) }
            if layers.openings { addOpeningFrames(project, to: scene) }
            if layers.furniture { addObjects(project, to: scene) }
            if layers.electrical { addElectrical(project, to: scene) }
            if layers.ceilingLighting { addCeilingLights(project, to: scene) }
            configureCamera(in: scene, view: view, project: project, focusedWallID: focusedWallID)
        }

        private func addLighting(to scene: SCNScene) {
            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.intensity = 520
            ambient.color = UIColor.white
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            scene.rootNode.addChildNode(ambientNode)

            let omni = SCNLight()
            omni.type = .omni
            omni.intensity = 900
            omni.castsShadow = true
            omni.shadowRadius = 6
            let omniNode = SCNNode()
            omniNode.light = omni
            omniNode.position = SCNVector3(0, 5, 0)
            scene.rootNode.addChildNode(omniNode)
        }

        private func addWalls(
            _ project: RoomProject,
            to scene: SCNScene,
            focusedWallID: UUID?
        ) {
            let root = SCNNode()
            root.name = "snapshot-architecture-walls"
            scene.rootNode.addChildNode(root)

            for wall in project.walls {
                let wallNode = SCNNode()
                wallNode.name = "snapshot-wall:\(wall.id.uuidString)"
                wallNode.simdTransform = wall.matrix
                root.addChildNode(wallNode)

                let openings = openingRects(on: wall, project: project)
                let cells = solidCells(
                    wallWidth: wall.width,
                    wallHeight: wall.height,
                    openings: openings
                )
                let appearance = project.wallAppearances?.first { $0.wallID == wall.id }
                let baseColor = appearance.flatMap { UIColor(snapshotHex: $0.solidColorHex) }
                    ?? UIColor.systemGray5
                let emphasized = focusedWallID == wall.id

                for cell in cells {
                    let box = SCNBox(
                        width: CGFloat(max(cell.width, 0.005)),
                        height: CGFloat(max(cell.height, 0.005)),
                        length: emphasized ? 0.11 : 0.08,
                        chamferRadius: 0
                    )
                    let material = SCNMaterial()
                    material.diffuse.contents = emphasized
                        ? UIColor.systemCyan.withAlphaComponent(0.82)
                        : baseColor
                    material.roughness.contents = 0.82
                    material.isDoubleSided = true
                    box.materials = [material]
                    let node = SCNNode(geometry: box)
                    node.position = SCNVector3(cell.centerX, cell.centerY, 0)
                    wallNode.addChildNode(node)
                }
            }
        }

        private func addFloors(_ project: RoomProject, to scene: SCNScene) {
            let root = SCNNode()
            root.name = "snapshot-architecture-floors"
            scene.rootNode.addChildNode(root)
            for floor in project.floors ?? [] {
                let plane = SCNPlane(
                    width: CGFloat(max(floor.width, 0.01)),
                    height: CGFloat(max(floor.depth, 0.01))
                )
                let material = SCNMaterial()
                material.diffuse.contents = UIColor.systemGray4
                material.roughness.contents = 0.9
                material.isDoubleSided = true
                plane.materials = [material]
                let node = SCNNode(geometry: plane)
                node.simdTransform = floor.matrix
                root.addChildNode(node)
            }
        }

        private func addObjects(_ project: RoomProject, to scene: SCNScene) {
            let root = SCNNode()
            root.name = "snapshot-furniture"
            scene.rootNode.addChildNode(root)
            for object in project.objects ?? [] {
                let box = SCNBox(
                    width: CGFloat(max(object.width, 0.02)),
                    height: CGFloat(max(object.height, 0.02)),
                    length: CGFloat(max(object.depth, 0.02)),
                    chamferRadius: 0.025
                )
                let material = SCNMaterial()
                material.diffuse.contents = UIColor.systemBrown.withAlphaComponent(0.55)
                material.roughness.contents = 0.75
                box.materials = [material]
                let node = SCNNode(geometry: box)
                node.simdTransform = object.matrix
                root.addChildNode(node)
            }
        }

        private func addElectrical(_ project: RoomProject, to scene: SCNScene) {
            let root = SCNNode()
            root.name = "snapshot-electrical"
            scene.rootNode.addChildNode(root)
            for point in project.points where point.worldPosition.count >= 3 {
                let sphere = SCNSphere(radius: 0.045)
                let material = SCNMaterial()
                material.diffuse.contents = point.status == .existing
                    ? UIColor.systemBlue
                    : UIColor.systemGreen
                material.emission.contents = (material.diffuse.contents as? UIColor)?
                    .withAlphaComponent(0.22)
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

        private func addCeilingLights(_ project: RoomProject, to scene: SCNScene) {
            let root = SCNNode()
            root.name = "snapshot-ceiling-lights"
            scene.rootNode.addChildNode(root)
            for light in project.ceilingLights ?? [] where light.worldPosition.count >= 3 {
                let sphere = SCNSphere(radius: CGFloat(max(light.diameterMeters / 2, 0.025)))
                let material = SCNMaterial()
                material.diffuse.contents = UIColor(snapshotHex: light.colorHex ?? "#FFCC00")
                    ?? UIColor.systemYellow
                material.emission.contents = material.diffuse.contents
                sphere.materials = [material]
                let node = SCNNode(geometry: sphere)
                node.position = SCNVector3(
                    light.worldPosition[0],
                    light.worldPosition[1],
                    light.worldPosition[2]
                )
                root.addChildNode(node)
            }
        }

        private func addOpeningFrames(_ project: RoomProject, to scene: SCNScene) {
            let root = SCNNode()
            root.name = "snapshot-openings"
            scene.rootNode.addChildNode(root)
            for surface in project.surfaces {
                let container = SCNNode()
                container.simdTransform = surface.matrix
                let color: UIColor
                switch surface.kind {
                case .door: color = .systemOrange
                case .window: color = .systemBlue
                case .opening: color = .systemGreen
                }
                addFrame(
                    width: surface.width,
                    height: surface.height,
                    color: color,
                    to: container
                )
                root.addChildNode(container)
            }
        }

        private func addFrame(
            width: Float,
            height: Float,
            color: UIColor,
            to parent: SCNNode
        ) {
            let thickness: CGFloat = 0.025
            func edge(_ w: CGFloat, _ h: CGFloat, x: Float, y: Float) {
                let box = SCNBox(width: w, height: h, length: 0.035, chamferRadius: 0)
                let material = SCNMaterial()
                material.diffuse.contents = color
                material.emission.contents = color.withAlphaComponent(0.18)
                box.materials = [material]
                let node = SCNNode(geometry: box)
                node.position = SCNVector3(x, y, 0.055)
                parent.addChildNode(node)
            }
            edge(CGFloat(width), thickness, x: 0, y: height / 2)
            edge(CGFloat(width), thickness, x: 0, y: -height / 2)
            edge(thickness, CGFloat(height), x: -width / 2, y: 0)
            edge(thickness, CGFloat(height), x: width / 2, y: 0)
        }

        private struct OpeningRect {
            var minX: Float
            var maxX: Float
            var minY: Float
            var maxY: Float
        }

        private struct SolidCell {
            var centerX: Float
            var centerY: Float
            var width: Float
            var height: Float
        }

        private func openingRects(
            on wall: WallSnapshot,
            project: RoomProject
        ) -> [OpeningRect] {
            let inverse = simd_inverse(wall.matrix)
            return project.surfaces.compactMap { surface in
                let local = inverse * surface.matrix.columns.3
                guard abs(local.z) <= 0.45 else { return nil }
                let minX = max(-wall.width / 2, local.x - surface.width / 2)
                let maxX = min(wall.width / 2, local.x + surface.width / 2)
                let minY = max(-wall.height / 2, local.y - surface.height / 2)
                let maxY = min(wall.height / 2, local.y + surface.height / 2)
                guard maxX - minX > 0.04, maxY - minY > 0.04 else { return nil }
                return OpeningRect(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
            }
        }

        private func solidCells(
            wallWidth: Float,
            wallHeight: Float,
            openings: [OpeningRect]
        ) -> [SolidCell] {
            var xCuts = [-wallWidth / 2, wallWidth / 2]
            for opening in openings {
                xCuts.append(opening.minX)
                xCuts.append(opening.maxX)
            }
            xCuts = uniqueSorted(xCuts)
            var cells: [SolidCell] = []

            for xIndex in 0..<(max(xCuts.count - 1, 0)) {
                let minX = xCuts[xIndex]
                let maxX = xCuts[xIndex + 1]
                guard maxX - minX > 0.005 else { continue }
                let midX = (minX + maxX) / 2
                let overlapping = openings.filter {
                    midX > $0.minX + 0.001 && midX < $0.maxX - 0.001
                }
                var yCuts = [-wallHeight / 2, wallHeight / 2]
                for opening in overlapping {
                    yCuts.append(opening.minY)
                    yCuts.append(opening.maxY)
                }
                yCuts = uniqueSorted(yCuts)
                for yIndex in 0..<(max(yCuts.count - 1, 0)) {
                    let minY = yCuts[yIndex]
                    let maxY = yCuts[yIndex + 1]
                    guard maxY - minY > 0.005 else { continue }
                    let midY = (minY + maxY) / 2
                    let insideOpening = openings.contains {
                        midX > $0.minX && midX < $0.maxX
                            && midY > $0.minY && midY < $0.maxY
                    }
                    if !insideOpening {
                        cells.append(SolidCell(
                            centerX: midX,
                            centerY: midY,
                            width: maxX - minX,
                            height: maxY - minY
                        ))
                    }
                }
            }
            return cells.isEmpty
                ? [SolidCell(centerX: 0, centerY: 0, width: wallWidth, height: wallHeight)]
                : cells
        }

        private func uniqueSorted(_ values: [Float]) -> [Float] {
            values.sorted().reduce(into: [Float]()) { result, value in
                if let last = result.last, abs(last - value) < 0.002 { return }
                result.append(value)
            }
        }

        private func configureCamera(
            in scene: SCNScene,
            view: SCNView,
            project: RoomProject,
            focusedWallID: UUID?
        ) {
            let camera = SCNCamera()
            camera.zNear = 0.02
            camera.zFar = 250
            let cameraNode = SCNNode()
            cameraNode.camera = camera

            let centers = project.walls.map {
                SIMD3($0.matrix.columns.3.x, $0.matrix.columns.3.y, $0.matrix.columns.3.z)
            }
            let center: SIMD3<Float>
            if let focusedWallID,
               let wall = project.walls.first(where: { $0.id == focusedWallID }) {
                center = SIMD3(wall.matrix.columns.3.x, wall.matrix.columns.3.y, wall.matrix.columns.3.z)
            } else if !centers.isEmpty {
                center = centers.reduce(.zero, +) / Float(centers.count)
            } else {
                center = .zero
            }
            let radius = max(
                centers.map { simd_distance($0, center) }.max() ?? 2,
                2
            )
            cameraNode.position = SCNVector3(
                center.x + radius * 1.45,
                center.y + radius * 1.05 + 1.5,
                center.z + radius * 1.45
            )
            cameraNode.look(at: SCNVector3(center.x, center.y, center.z))
            scene.rootNode.addChildNode(cameraNode)
            view.pointOfView = cameraNode
        }
    }
}

private extension UIColor {
    convenience init?(snapshotHex value: String) {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let rgb = Int(text, radix: 16) else { return nil }
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
