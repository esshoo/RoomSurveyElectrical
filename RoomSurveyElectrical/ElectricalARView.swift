import ARKit
import SceneKit
import simd
import SwiftUI

/// A real ceiling position selected from the post-scan camera view.
/// It is intentionally separate from `WallTap` because ceiling lights do not
/// belong to a wall and must never enter socket/switch placement rules.
struct CeilingTap: Identifiable {
    let id = UUID()
    let worldPosition: [Float]
}

struct ElectricalARView: UIViewRepresentable {
    var project: RoomProject
    let arSession: ARSession
    let onWallTapped: (WallTap) -> Void
    let onCeilingTapped: (CeilingTap) -> Void

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
        context.coordinator.buildCapturedSurfaces()
        context.coordinator.renderPoints()
        context.coordinator.renderCeilingLights()

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
        context.coordinator.renderCeilingLights()
    }

    final class Coordinator: NSObject {
        var parent: ElectricalARView
        weak var sceneView: ARSCNView?

        private let wallRootName = "captured-walls"
        private let ceilingRootName = "captured-ceilings"
        private let ceilingLightRootName = "captured-ceiling-lights"
        private let wallPrefix = "wall:"
        private let ceilingPrefix = "ceiling:"
        private let pointPrefix = "electrical-point:"
        private let ceilingLightPrefix = "ceiling-light:"

        init(parent: ElectricalARView) {
            self.parent = parent
        }

        func buildCapturedSurfaces() {
            buildWalls()
            buildCeilings()
        }

        private func buildWalls() {
            guard let sceneView else { return }
            sceneView.scene.rootNode.childNode(
                withName: wallRootName,
                recursively: false
            )?.removeFromParentNode()

            let root = SCNNode()
            root.name = wallRootName
            sceneView.scene.rootNode.addChildNode(root)

            for wall in parent.project.walls {
                let plane = SCNPlane(
                    width: CGFloat(wall.width),
                    height: CGFloat(wall.height)
                )
                let material = SCNMaterial()
                material.diffuse.contents = UIColor.systemCyan.withAlphaComponent(0.08)
                material.emission.contents = UIColor.systemCyan.withAlphaComponent(0.025)
                material.isDoubleSided = true
                material.lightingModel = .constant
                plane.materials = [material]

                let wallNode = SCNNode(geometry: plane)
                wallNode.name = wallPrefix + wall.id.uuidString
                wallNode.simdTransform = wall.matrix
                addWallBorder(
                    to: wallNode,
                    width: wall.width,
                    height: wall.height
                )
                root.addChildNode(wallNode)
            }
        }

        /// RoomPlan does not expose a separate persistent ceiling model in this
        /// project. Reuse each captured floor footprint at the measured wall-top
        /// height, exactly like the existing 2D ceiling reference logic.
        private func buildCeilings() {
            guard let sceneView else { return }
            sceneView.scene.rootNode.childNode(
                withName: ceilingRootName,
                recursively: false
            )?.removeFromParentNode()

            let root = SCNNode()
            root.name = ceilingRootName
            sceneView.scene.rootNode.addChildNode(root)

            let ceilingHeight = parent.project.walls.map {
                $0.matrix.columns.3.y + $0.height / 2
            }.max()

            let floors = parent.project.floors ?? []
            if !floors.isEmpty {
                for floor in floors {
                    let resolvedHeight = ceilingHeight
                        ?? floor.matrix.columns.3.y + 2.70
                    let plane = makeCeilingPlane(
                        width: floor.width,
                        depth: floor.depth
                    )
                    let node = SCNNode(geometry: plane)
                    node.name = ceilingPrefix + floor.id.uuidString
                    var transform = floor.matrix
                    var translation = transform.columns.3
                    translation.y = resolvedHeight - 0.03
                    transform.columns.3 = translation
                    node.simdTransform = transform
                    root.addChildNode(node)
                }
                return
            }

            // Compatibility fallback for older saved scans that predate floor
            // snapshots. It mirrors the bounding reference already used by 2D.
            let endpoints = parent.project.walls.flatMap { wall -> [SIMD2<Float>] in
                let pair = wallPlanEndpoints(wall)
                return [pair.0, pair.1]
            }
            guard let minimumX = endpoints.map(\.x).min(),
                  let maximumX = endpoints.map(\.x).max(),
                  let minimumZ = endpoints.map(\.y).min(),
                  let maximumZ = endpoints.map(\.y).max() else {
                return
            }

            let width = max(maximumX - minimumX, 0.10)
            let depth = max(maximumZ - minimumZ, 0.10)
            let node = SCNNode(geometry: makeCeilingPlane(width: width, depth: depth))
            node.name = ceilingPrefix + "fallback"
            node.eulerAngles.x = -.pi / 2
            node.position = SCNVector3(
                (minimumX + maximumX) / 2,
                (ceilingHeight ?? 2.70) - 0.03,
                (minimumZ + maximumZ) / 2
            )
            root.addChildNode(node)
        }

        private func makeCeilingPlane(width: Float, depth: Float) -> SCNPlane {
            let plane = SCNPlane(width: CGFloat(width), height: CGFloat(depth))
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemYellow.withAlphaComponent(0.045)
            material.emission.contents = UIColor.systemYellow.withAlphaComponent(0.012)
            material.isDoubleSided = true
            material.lightingModel = .constant
            plane.materials = [material]
            return plane
        }

        func renderPoints() {
            guard let root = sceneView?.scene.rootNode.childNode(
                withName: wallRootName,
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
                let fallback: UIColor = point.status == .existing
                    ? .systemGreen
                    : .systemOrange
                let color = electricalUIColor(hex: point.colorHex, fallback: fallback)
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

        func renderCeilingLights() {
            guard let sceneView else { return }
            sceneView.scene.rootNode.childNode(
                withName: ceilingLightRootName,
                recursively: false
            )?.removeFromParentNode()

            let root = SCNNode()
            root.name = ceilingLightRootName
            sceneView.scene.rootNode.addChildNode(root)

            for light in parent.project.ceilingLights ?? [] {
                guard light.worldPosition.count >= 3 else { continue }
                let fillColor = electricalUIColor(
                    hex: light.colorHex,
                    fallback: .systemYellow
                )
                let outlineColor: UIColor
                switch light.resolvedSource {
                case .cameraExisting:
                    outlineColor = .systemGreen
                case .planManual:
                    outlineColor = .white
                case .planAutomatic:
                    outlineColor = .systemBlue
                }

                let radius = CGFloat(max(light.diameterMeters / 2, 0.025))
                let disc = SCNCylinder(radius: radius, height: 0.014)
                let discMaterial = SCNMaterial()
                discMaterial.diffuse.contents = fillColor
                discMaterial.emission.contents = fillColor.withAlphaComponent(
                    CGFloat(0.18 + min(max(light.brightness, 0), 1) * 0.35)
                )
                discMaterial.lightingModel = .constant
                disc.materials = [discMaterial]

                let marker = SCNNode(geometry: disc)
                marker.name = ceilingLightPrefix + light.id.uuidString
                marker.position = SCNVector3(
                    light.worldPosition[0],
                    light.worldPosition[1] - 0.008,
                    light.worldPosition[2]
                )

                let ring = SCNTorus(
                    ringRadius: radius + 0.018,
                    pipeRadius: light.isExistingAsBuilt ? 0.006 : 0.004
                )
                let ringMaterial = SCNMaterial()
                ringMaterial.diffuse.contents = outlineColor
                ringMaterial.emission.contents = outlineColor.withAlphaComponent(0.35)
                ringMaterial.lightingModel = .constant
                ring.materials = [ringMaterial]
                marker.addChildNode(SCNNode(geometry: ring))

                root.addChildNode(marker)
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView else { return }
            let location = gesture.location(in: sceneView)
            let results = sceneView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .ignoreHiddenNodes: true,
                .boundingBoxOnly: false,
                .sortResults: true
            ])

            for hit in results {
                if ceilingNode(from: hit.node) != nil {
                    let world = hit.worldCoordinates
                    parent.onCeilingTapped(
                        CeilingTap(worldPosition: [world.x, world.y, world.z])
                    )
                    return
                }

                if let wallNode = wallNode(from: hit.node),
                   let name = wallNode.name,
                   let wallID = UUID(
                    uuidString: String(name.dropFirst(wallPrefix.count))
                   ) {
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
                    return
                }
            }
        }

        private func wallNode(from node: SCNNode) -> SCNNode? {
            ancestor(from: node, prefix: wallPrefix)
        }

        private func ceilingNode(from node: SCNNode) -> SCNNode? {
            ancestor(from: node, prefix: ceilingPrefix)
        }

        private func ancestor(from node: SCNNode, prefix: String) -> SCNNode? {
            var candidate: SCNNode? = node
            while let current = candidate {
                if current.name?.hasPrefix(prefix) == true {
                    return current
                }
                candidate = current.parent
            }
            return nil
        }

        private func wallPlanEndpoints(
            _ wall: WallSnapshot
        ) -> (SIMD2<Float>, SIMD2<Float>) {
            let halfWidth = wall.width / 2
            let first = simd_mul(
                wall.matrix,
                SIMD4<Float>(-halfWidth, 0, 0, 1)
            )
            let second = simd_mul(
                wall.matrix,
                SIMD4<Float>(halfWidth, 0, 0, 1)
            )
            return (
                SIMD2(first.x, first.z),
                SIMD2(second.x, second.z)
            )
        }

        private func addWallBorder(
            to wallNode: SCNNode,
            width: Float,
            height: Float
        ) {
            let thickness: CGFloat = 0.012
            let color = UIColor.systemCyan.withAlphaComponent(0.9)

            func line(
                width: CGFloat,
                height: CGFloat,
                x: Float,
                y: Float
            ) -> SCNNode {
                let box = SCNBox(
                    width: width,
                    height: height,
                    length: 0.008,
                    chamferRadius: 0
                )
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

private func electricalUIColor(hex: String?, fallback: UIColor) -> UIColor {
    guard let hex else { return fallback }
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard cleaned.count == 6,
          let value = UInt64(cleaned, radix: 16) else {
        return fallback
    }
    return UIColor(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}
