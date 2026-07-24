import SceneKit
import SwiftUI
import UIKit

struct RecentProjectsWidget: View {
    let projects: [SurveyProject]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(projects.prefix(6)) { project in
                    NavigationLink {
                        ProjectBrowserView(
                            projectID: project.id,
                            parentItemID: nil,
                            title: project.name
                        )
                    } label: {
                        RecentProjectCard(project: project)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 238)
    }
}

private struct RecentProjectCard: View {
    let project: SurveyProject
    @State private var previewImage: UIImage?

    private var firstRoom: RoomProject? {
        project.scans
            .sorted { $0.createdAt > $1.createdAt }
            .lazy
            .compactMap { ProjectRepository.load(projectID: $0.id) }
            .first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFill()
                    } else if let firstRoom {
                        MiniPlanPreview(project: firstRoom)
                    } else {
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.82),
                                Color.cyan.opacity(0.62)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .overlay {
                            Image(systemName: project.kind.systemImage)
                                .font(.system(size: 44, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                    }
                }
                .frame(width: 260, height: 144)
                .clipped()

                if previewImage != nil {
                    Label("3D", systemImage: "cube.fill")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label("\(project.scanCount)", systemImage: "viewfinder")
                    Label("\(project.roomCount)", systemImage: "door.left.hand.open")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("آخر تعديل \(project.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
        }
        .frame(width: 260)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .task(id: project.updatedAt) {
            previewImage = await ProjectPreviewRenderer.shared.image(
                for: project
            )
        }
    }
}

private struct MiniPlanPreview: View {
    let project: RoomProject

    private var segments: [(SIMD2<Float>, SIMD2<Float>)] {
        project.walls.map {
            ExportGeometry.lineEndpoints(
                matrix: $0.matrix,
                width: $0.width
            )
        }
    }

    var body: some View {
        Canvas { context, size in
            guard !segments.isEmpty else { return }
            let allPoints = segments.flatMap { [$0.0, $0.1] }
            let minimumX = allPoints.map(\.x).min() ?? 0
            let maximumX = allPoints.map(\.x).max() ?? 1
            let minimumY = allPoints.map(\.y).min() ?? 0
            let maximumY = allPoints.map(\.y).max() ?? 1
            let width = max(maximumX - minimumX, 0.1)
            let height = max(maximumY - minimumY, 0.1)
            let padding: CGFloat = 20
            let scale = min(
                (size.width - padding * 2) / CGFloat(width),
                (size.height - padding * 2) / CGFloat(height)
            )

            func point(_ value: SIMD2<Float>) -> CGPoint {
                CGPoint(
                    x: padding + CGFloat(value.x - minimumX) * scale,
                    y: size.height - padding
                        - CGFloat(value.y - minimumY) * scale
                )
            }

            var path = Path()
            for segment in segments {
                path.move(to: point(segment.0))
                path.addLine(to: point(segment.1))
            }
            context.stroke(
                path,
                with: .color(.white),
                style: StrokeStyle(
                    lineWidth: 4,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
        .background(
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.88),
                    Color.blue.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private actor ProjectPreviewRenderer {
    static let shared = ProjectPreviewRenderer()

    func image(for project: SurveyProject) async -> UIImage? {
        guard let previewURL = try? ApplicationFileLayout.previewsDirectory
            .appendingPathComponent("\(project.id.uuidString).png") else {
            return nil
        }

        if let data = try? Data(contentsOf: previewURL),
           let cached = UIImage(data: data) {
            return cached
        }

        guard let scan = project.scans
            .sorted(by: { $0.createdAt > $1.createdAt })
            .first,
              let room = ProjectRepository.load(projectID: scan.id),
              let usdzURL = try? ProjectRepository.fileURL(
                projectID: room.id,
                fileName: room.usdzFile
              ),
              let rendered = Self.renderUSDZ(url: usdzURL) else {
            return nil
        }

        if let data = rendered.pngData() {
            try? data.write(to: previewURL, options: .atomic)
        }
        return rendered
    }

    private static func renderUSDZ(url: URL) -> UIImage? {
        guard let scene = try? SCNScene(url: url, options: nil) else {
            return nil
        }

        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.autoenablesDefaultLighting = true

        let bounds = scene.rootNode.boundingBox
        let center = SCNVector3(
            (bounds.min.x + bounds.max.x) / 2,
            (bounds.min.y + bounds.max.y) / 2,
            (bounds.min.z + bounds.max.z) / 2
        )
        let extent = max(
            bounds.max.x - bounds.min.x,
            bounds.max.y - bounds.min.y,
            bounds.max.z - bounds.min.z,
            1
        )

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 46
        cameraNode.position = SCNVector3(
            center.x + extent * 1.35,
            center.y + extent * 1.05,
            center.z + extent * 1.35
        )
        cameraNode.look(at: center)
        scene.rootNode.addChildNode(cameraNode)
        renderer.pointOfView = cameraNode

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 650
        scene.rootNode.addChildNode(ambient)

        return renderer.snapshot(
            atTime: 0,
            with: CGSize(width: 780, height: 432),
            antialiasingMode: .multisampling4X
        )
    }
}
