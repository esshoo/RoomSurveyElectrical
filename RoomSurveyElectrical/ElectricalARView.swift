import ARKit
import SceneKit
import SwiftUI

struct ElectricalARView: UIViewRepresentable {
    var project: RoomProject
    let arSession: ARSession
    let onWallTapped: (WallTap) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.session = arSession
        sceneView.scene = SCNScene()
        sceneView.automaticallyUpdatesLighting = true
        sceneView.antialiasingMode = .multisampling4X
        sceneView.backgroundColor = .clear

        context.coordinator.sceneView = sceneView
        context.coordinator.buildWalls()
        context.coordinator.renderPoints()

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        sceneView.addGestureRecognizer(tap)
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.renderPoints()
    }

    final class Coordinator: NSObject {
        var parent: ElectricalARView
        weak var sceneView: ARSCNView?

        private let wallPrefix = "wall:"
        private let pointPrefix = "electrical-point:"

        init(parent: ElectricalARView) {
            self.parent = parent
        }

        func buildWalls() {
            guard let sceneView else { return }
            sceneView.scene.rootNode.childNode(withName: "captured-walls", recursively: false)?
                .removeFromParentNode()

            let root = SCNNode()
            root.name = "captured-walls"
            sceneView.scene.rootNode.addChildNode(root)

            for wall in parent.project.walls {
                let plane = SCNPlane(width: CGFloat(wall.width), height: CGFloat(wall.height))
                let material = SCNMaterial()
                material.diffuse.contents = UIColor.systemCyan.withAlphaComponent(0.08)
                material.emission.contents = UIColor.systemCyan.withAlphaComponent(0.025)
                material.isDoubleSided = true
                material.lightingModel = .constant
                plane.materials = [material]

                let wallNode = SCNNode(geometry: plane)
                wallNode.name = wallPrefix + wall.id.uuidString
                wallNode.simdTransform = wall.matrix
                addBorder(to: wallNode, width: wall.width, height: wall.height)
                root.addChildNode(wallNode)
            }
        }

        func renderPoints() {
            guard let root = sceneView?.scene.rootNode.childNode(
                withName: "captured-walls",
                recursively: false
            ) else { return }

            root.enumerateChildNodes { node, _ in
                node.childNodes
                    .filter { $0.name?.hasPrefix(self.pointPrefix) == true }
                    .forEach { $0.removeFromParentNode() }
            }

            for point in parent.project.points {
                guard let wallNode = root.childNode(
                    withName: wallPrefix + point.wallID.uuidString,
                    recursively: false
                ) else { continue }

                let sphere = SCNSphere(radius: 0.045)
                let material = SCNMaterial()
                let color: UIColor = point.status == .existing ? .systemGreen : .systemOrange
                material.diffuse.contents = color
                material.emission.contents = color.withAlphaComponent(0.35)
                sphere.materials = [material]

                let marker = SCNNode(geometry: sphere)
                marker.name = pointPrefix + point.id.uuidString
                marker.position = SCNVector3(point.localX, point.localY, 0.035)

                let ring = SCNTorus(ringRadius: 0.075, pipeRadius: 0.008)
                ring.materials = [material]
                let ringNode = SCNNode(geometry: ring)
                ringNode.eulerAngles.x = .pi / 2
                marker.addChildNode(ringNode)

                let iconPlane = SCNPlane(width: 0.105, height: 0.105)
                let iconMaterial = SCNMaterial()
                iconMaterial.diffuse.contents = UIImage(
                    systemName: point.type.systemImage
                )?.withTintColor(.white, renderingMode: .alwaysOriginal)
                iconMaterial.emission.contents = UIColor.white.withAlphaComponent(0.18)
                iconMaterial.isDoubleSided = true
                iconMaterial.lightingModel = .constant
                iconPlane.materials = [iconMaterial]

                let iconNode = SCNNode(geometry: iconPlane)
                iconNode.position = SCNVector3(0, 0, 0.048)
                marker.addChildNode(iconNode)
                wallNode.addChildNode(marker)
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView else { return }
            let location = gesture.location(in: sceneView)
            let results = sceneView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .ignoreHiddenNodes: true,
                .boundingBoxOnly: false
            ])

            guard let hit = results.first(where: { result in
                wallNode(from: result.node) != nil
            }), let wallNode = wallNode(from: hit.node),
                  let name = wallNode.name,
                  let wallID = UUID(uuidString: String(name.dropFirst(wallPrefix.count))) else {
                return
            }

            let local = wallNode.convertPosition(hit.worldCoordinates, from: nil)
            let world = hit.worldCoordinates
            parent.onWallTapped(
                WallTap(
                    wallID: wallID,
                    localX: local.x,
                    localY: local.y,
                    worldPosition: [world.x, world.y, world.z]
                )
            )
        }

        private func wallNode(from node: SCNNode) -> SCNNode? {
            var candidate: SCNNode? = node
            while let current = candidate {
                if current.name?.hasPrefix(wallPrefix) == true {
                    return current
                }
                candidate = current.parent
            }
            return nil
        }

        private func addBorder(to wallNode: SCNNode, width: Float, height: Float) {
            let thickness: CGFloat = 0.012
            let color = UIColor.systemCyan.withAlphaComponent(0.9)

            func line(width: CGFloat, height: CGFloat, x: Float, y: Float) -> SCNNode {
                let box = SCNBox(width: width, height: height, length: 0.008, chamferRadius: 0)
                let material = SCNMaterial()
                material.diffuse.contents = color
                material.emission.contents = color.withAlphaComponent(0.25)
                material.lightingModel = .constant
                box.materials = [material]
                let node = SCNNode(geometry: box)
                node.position = SCNVector3(x, y, 0.01)
                return node
            }

            wallNode.addChildNode(line(
                width: CGFloat(width),
                height: thickness,
                x: 0,
                y: height / 2
            ))
            wallNode.addChildNode(line(
                width: CGFloat(width),
                height: thickness,
                x: 0,
                y: -height / 2
            ))
            wallNode.addChildNode(line(
                width: thickness,
                height: CGFloat(height),
                x: width / 2,
                y: 0
            ))
            wallNode.addChildNode(line(
                width: thickness,
                height: CGFloat(height),
                x: -width / 2,
                y: 0
            ))
        }
    }
}
