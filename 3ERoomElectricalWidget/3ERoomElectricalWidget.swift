import SwiftUI
import UIKit
import WidgetKit

private enum WidgetSharedConfiguration {
    static let appGroupIdentifier = "group.com.essam.threeroomelectrical"
    static let widgetKind = "3ERoomElectricalRecentProjects"
    static let dataFolderName = "3ERoomElectricalWidgetData"
    static let snapshotFileName = "recent-projects.json"
}

private struct WidgetProjectSnapshot: Codable, Identifiable {
    let projectID: UUID
    let name: String
    let kindTitle: String
    let systemImage: String
    let scanCount: Int
    let roomCount: Int
    let updatedAt: Date
    let previewFileName: String

    var id: UUID { projectID }
    var destinationURL: URL? {
        URL(string: "3eroomelectrical://projects?project=\(projectID.uuidString)")
    }
}

private struct RecentProjectsEntry: TimelineEntry {
    let date: Date
    let projects: [WidgetProjectSnapshot]
}

private struct RecentProjectsProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentProjectsEntry {
        RecentProjectsEntry(
            date: Date(),
            projects: [
                WidgetProjectSnapshot(
                    projectID: UUID(),
                    name: "مشروع الفيلا",
                    kindTitle: "فيلا",
                    systemImage: "house.lodge.fill",
                    scanCount: 8,
                    roomCount: 6,
                    updatedAt: Date(),
                    previewFileName: ""
                )
            ]
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (RecentProjectsEntry) -> Void
    ) {
        let projects = context.isPreview
            ? placeholder(in: context).projects
            : WidgetDataReader.loadProjects()
        completion(RecentProjectsEntry(date: Date(), projects: projects))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<RecentProjectsEntry>) -> Void
    ) {
        let entry = RecentProjectsEntry(
            date: Date(),
            projects: WidgetDataReader.loadProjects()
        )
        let refresh = Calendar.current.date(
            byAdding: .minute,
            value: 30,
            to: Date()
        ) ?? Date().addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

private enum WidgetDataReader {
    static func loadProjects() -> [WidgetProjectSnapshot] {
        guard let directory = sharedDirectory(),
              let data = try? Data(
                contentsOf: directory.appendingPathComponent(
                    WidgetSharedConfiguration.snapshotFileName
                )
              ) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(
            [WidgetProjectSnapshot].self,
            from: data
        )) ?? []
    }

    static func previewImage(
        for project: WidgetProjectSnapshot
    ) -> UIImage? {
        guard !project.previewFileName.isEmpty,
              let directory = sharedDirectory(),
              let data = try? Data(
                contentsOf: directory.appendingPathComponent(
                    project.previewFileName
                )
              ) else {
            return nil
        }
        return UIImage(data: data)
    }

    private static func sharedDirectory() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier:
                WidgetSharedConfiguration.appGroupIdentifier
        )?.appendingPathComponent(
            WidgetSharedConfiguration.dataFolderName,
            isDirectory: true
        )
    }
}

private struct RecentProjectsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecentProjectsEntry

    var body: some View {
        Group {
            if entry.projects.isEmpty {
                emptyView
            } else {
                switch family {
                case .systemSmall:
                    projectLink(entry.projects[0]) {
                        smallView(entry.projects[0])
                    }
                case .systemMedium:
                    mediumView(Array(entry.projects.prefix(2)))
                default:
                    largeView(Array(entry.projects.prefix(4)))
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .containerBackground(for: .widget) {
            Color(red: 0.025, green: 0.055, blue: 0.10)
        }
    }

    private var emptyView: some View {
        Link(destination: URL(string: "3eroomelectrical://projects")!) {
            ZStack {
                backgroundGradient
                VStack(spacing: 10) {
                    Image(systemName: "viewfinder.rectangular")
                        .font(.system(size: 30, weight: .bold))
                    Text("3E Room Electrical")
                        .font(.headline)
                    Text("افتح التطبيق مرة واحدة لإظهار آخر المشروعات")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .foregroundStyle(.white)
                .padding()
            }
        }
    }

    private func projectLink<Content: View>(
        _ project: WidgetProjectSnapshot,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Link(
            destination: project.destinationURL
                ?? URL(string: "3eroomelectrical://projects")!
        ) {
            content()
        }
    }

    private func smallView(_ project: WidgetProjectSnapshot) -> some View {
        ZStack(alignment: .bottomTrailing) {
            projectPreview(project)
            LinearGradient(
                colors: [.clear, .black.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .trailing, spacing: 5) {
                HStack {
                    Text("3E")
                        .font(.caption2.bold())
                        .foregroundStyle(.cyan)
                    Spacer()
                }
                Spacer()
                Text(project.name)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label("\(project.scanCount)", systemImage: "viewfinder")
                    Label(
                        "\(project.roomCount)",
                        systemImage: "door.left.hand.open"
                    )
                }
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.82))
            }
            .foregroundStyle(.white)
            .padding(13)
        }
    }

    private func mediumView(
        _ projects: [WidgetProjectSnapshot]
    ) -> some View {
        ZStack {
            backgroundGradient
            HStack(spacing: 12) {
                if let first = projects.first {
                    projectLink(first) {
                        projectPreview(first)
                            .frame(width: 142)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 16,
                                    style: .continuous
                                )
                            )
                    }
                }

                VStack(alignment: .trailing, spacing: 9) {
                    widgetHeader
                    ForEach(projects) { project in
                        projectLink(project) {
                            projectRow(project)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
        }
    }

    private func largeView(
        _ projects: [WidgetProjectSnapshot]
    ) -> some View {
        ZStack {
            backgroundGradient
            VStack(alignment: .trailing, spacing: 12) {
                widgetHeader
                if let first = projects.first {
                    projectLink(first) {
                        ZStack(alignment: .bottomTrailing) {
                            projectPreview(first)
                                .frame(height: 132)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 18,
                                        style: .continuous
                                    )
                                )
                            Text(first.name)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.58), in: Capsule())
                                .padding(10)
                        }
                    }
                }
                ForEach(projects.dropFirst()) { project in
                    projectLink(project) {
                        projectRow(project)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    private var widgetHeader: some View {
        HStack {
            Image(systemName: "viewfinder.rectangular")
                .foregroundStyle(.cyan)
            Text("آخر المشروعات")
                .font(.headline)
            Spacer()
            Text("3E")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white)
    }

    private func projectRow(
        _ project: WidgetProjectSnapshot
    ) -> some View {
        HStack(spacing: 9) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(project.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(
                    "\(project.scanCount) مسح • \(project.roomCount) غرفة"
                )
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.64))
            }
            Spacer(minLength: 4)
            Image(systemName: project.systemImage)
                .font(.headline)
                .foregroundStyle(.cyan)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.08), in: Circle())
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func projectPreview(
        _ project: WidgetProjectSnapshot
    ) -> some View {
        if let image = WidgetDataReader.previewImage(for: project) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.indigo.opacity(0.9),
                        Color.blue.opacity(0.75),
                        Color.cyan.opacity(0.58)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: project.systemImage)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.07, blue: 0.12),
                Color(red: 0.02, green: 0.12, blue: 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

@main
struct RecentProjectsHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSharedConfiguration.widgetKind,
            provider: RecentProjectsProvider()
        ) { entry in
            RecentProjectsWidgetView(entry: entry)
        }
        .configurationDisplayName("آخر مشروعات 3E")
        .description("اعرض آخر المشروعات والمسحات مباشرة على شاشة iPhone.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
