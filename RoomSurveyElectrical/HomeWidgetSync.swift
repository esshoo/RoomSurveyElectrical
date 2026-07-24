import Foundation
import WidgetKit

struct HomeWidgetProjectSnapshot: Codable, Sendable {
    let projectID: UUID
    let name: String
    let kindTitle: String
    let systemImage: String
    let scanCount: Int
    let roomCount: Int
    let updatedAt: Date
    let previewFileName: String
}

enum HomeWidgetSharedConfiguration {
    static let appGroupIdentifier = "group.com.personal.roomsurveyelectrical"
    static let widgetKind = "3ERoomElectricalRecentProjects"
    static let dataFolderName = "3ERoomElectricalWidgetData"
    static let snapshotFileName = "recent-projects.json"
}

enum HomeWidgetSnapshotStore {
    private static let fileManager = FileManager.default

    static func update(projects: [SurveyProject]) {
        guard let directory = sharedDirectory() else { return }
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let snapshots = projects
                .filter { !$0.archived }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(6)
                .map { project in
                    HomeWidgetProjectSnapshot(
                        projectID: project.id,
                        name: project.name,
                        kindTitle: project.kind.title,
                        systemImage: project.kind.systemImage,
                        scanCount: project.scanCount,
                        roomCount: project.roomCount,
                        updatedAt: project.updatedAt,
                        previewFileName: "\(project.id.uuidString).png"
                    )
                }

            try copyAvailablePreviews(
                projectIDs: Set(snapshots.map(\.projectID)),
                to: directory
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Array(snapshots))
            try data.write(
                to: directory.appendingPathComponent(
                    HomeWidgetSharedConfiguration.snapshotFileName
                ),
                options: .atomic
            )
            WidgetCenter.shared.reloadTimelines(
                ofKind: HomeWidgetSharedConfiguration.widgetKind
            )
        } catch {
            // Widget synchronization must never prevent the main app from
            // loading or saving a project.
        }
    }

    static func publishPreview(projectID: UUID, data: Data) {
        guard let directory = sharedDirectory() else { return }
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(
                to: directory.appendingPathComponent(
                    "\(projectID.uuidString).png"
                ),
                options: .atomic
            )
            WidgetCenter.shared.reloadTimelines(
                ofKind: HomeWidgetSharedConfiguration.widgetKind
            )
        } catch {
            // The in-app preview remains available even when the shared
            // App Group container isn't configured by the signer yet.
        }
    }

    private static func sharedDirectory() -> URL? {
        fileManager.containerURL(
            forSecurityApplicationGroupIdentifier:
                HomeWidgetSharedConfiguration.appGroupIdentifier
        )?.appendingPathComponent(
            HomeWidgetSharedConfiguration.dataFolderName,
            isDirectory: true
        )
    }

    private static func copyAvailablePreviews(
        projectIDs: Set<UUID>,
        to destinationDirectory: URL
    ) throws {
        guard let previewsDirectory = try? ApplicationFileLayout
            .previewsDirectory else {
            return
        }

        for projectID in projectIDs {
            let name = "\(projectID.uuidString).png"
            let source = previewsDirectory.appendingPathComponent(name)
            let destination = destinationDirectory
                .appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else {
                continue
            }
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }
    }
}
