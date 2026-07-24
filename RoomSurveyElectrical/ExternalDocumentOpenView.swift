import QuickLook
import SwiftUI

struct ExternalDocumentOpenView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ProjectStore

    let inspection: ExternalDocumentInspection
    @State private var showPreview = false

    private var matchedProject: SurveyProject? {
        guard let projectID = inspection.registryRecord?.projectID else {
            return nil
        }
        return store.project(id: projectID)
    }

    private var matchedProjectMetrics: ProjectMetrics? {
        guard let matchedProject else { return nil }
        return ProjectMetrics(project: matchedProject)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: statusImage)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(statusColor)
                            .frame(width: 52, height: 52)
                            .background(
                                statusColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 14)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(inspection.localURL.lastPathComponent)
                                .font(.headline)
                                .lineLimit(2)
                            Text(inspection.confidence.title)
                                .font(.subheadline)
                                .foregroundStyle(statusColor)
                            Text(inspection.detectedKind.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                if let record = inspection.registryRecord {
                    Section("سجل التصدير") {
                        LabeledContent("المشروع", value: record.projectName)
                        LabeledContent("طريقة التصدير", value: record.kind.title)
                        LabeledContent(
                            "تاريخ التصدير",
                            value: record.exportedAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                        LabeledContent(
                            "الحجم",
                            value: ByteCountFormatter.string(
                                fromByteCount: record.byteCount,
                                countStyle: .file
                            )
                        )
                    }
                }

                if let metrics = matchedProjectMetrics {
                    Section("بيانات المشروع الأصلية") {
                        CountRow(title: "المسحات", value: metrics.scans)
                        CountRow(title: "الأرضيات", value: metrics.floors)
                        CountRow(title: "الجدران", value: metrics.walls)
                        CountRow(title: "الأبواب", value: metrics.doors)
                        CountRow(title: "الشبابيك", value: metrics.windows)
                        CountRow(title: "الفتحات", value: metrics.openings)
                        CountRow(title: "الأثاث", value: metrics.furniture)
                        CountRow(
                            title: "نقاط الكهرباء",
                            value: metrics.electrical
                        )
                        CountRow(
                            title: "إضاءة السقف",
                            value: metrics.ceilingLights
                        )
                    } footer: {
                        Text(
                            "هذه الأرقام مأخوذة من المشروع المرتبط ببصمة الملف على هذا الجهاز."
                        )
                    }
                }

                if let counts = inspection.dxfCounts, counts.hasValues {
                    Section("تحليل DXF") {
                        CountRow(title: "الأرضيات", value: counts.floors)
                        CountRow(title: "الجدران", value: counts.walls)
                        CountRow(title: "الأبواب", value: counts.doors)
                        CountRow(title: "الشبابيك", value: counts.windows)
                        CountRow(title: "الفتحات", value: counts.openings)
                        CountRow(title: "الأثاث", value: counts.furniture)
                        CountRow(
                            title: "نقاط الكهرباء",
                            value: counts.totalElectrical
                        )
                        CountRow(
                            title: "إضاءة السقف",
                            value: counts.ceilingLights
                        )
                    } footer: {
                        Text(
                            "الأرقام محسوبة من طبقات وكيانات DXF التي ينشئها التطبيق، وليست تخمينًا بصريًا."
                        )
                    }
                }

                Section("الإجراءات") {
                    if inspection.format == .pdf {
                        Button {
                            showPreview = true
                        } label: {
                            Label("معاينة PDF", systemImage: "doc.text.magnifyingglass")
                        }
                    }

                    if let matchedProject {
                        NavigationLink {
                            ProjectBrowserView(
                                projectID: matchedProject.id,
                                parentItemID: nil,
                                title: matchedProject.name
                            )
                        } label: {
                            Label(
                                "فتح المشروع الأصلي",
                                systemImage: "folder.fill"
                            )
                        }
                    }

                    ShareLink(item: inspection.localURL) {
                        Label("مشاركة الملف", systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    LabeledContent("النوع", value: inspection.format.title)
                    LabeledContent(
                        "البصمة",
                        value: String(inspection.sha256.prefix(16)) + "…"
                    )
                    .textSelection(.enabled)
                } footer: {
                    if inspection.confidence == .brandedFile {
                        Text(
                            "الملف يحمل وسم التطبيق، لكن سجل التصدير غير موجود على هذا الجهاز. لذلك يعرض التطبيق ما يمكن قراءته مباشرة من الملف ولا يدّعي استعادة بيانات غير موجودة."
                        )
                    } else if inspection.confidence == .unknown {
                        Text(
                            "يمكن الاحتفاظ بالملف وفتحه، لكن التطبيق لم يتأكد أنه صادر من 3ERoomElectrical."
                        )
                    }
                }
            }
            .navigationTitle("فتح ملف")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
            .sheet(isPresented: $showPreview) {
                QuickLookFilePreview(url: inspection.localURL)
                    .ignoresSafeArea()
            }
        }
    }

    private var statusImage: String {
        switch inspection.confidence {
        case .exactRegistryMatch: "checkmark.seal.fill"
        case .brandedFile: "seal.fill"
        case .unknown: "questionmark.folder.fill"
        }
    }

    private var statusColor: Color {
        switch inspection.confidence {
        case .exactRegistryMatch: .green
        case .brandedFile: .blue
        case .unknown: .orange
        }
    }
}

private struct ProjectMetrics {
    var scans = 0
    var floors = 0
    var walls = 0
    var doors = 0
    var windows = 0
    var openings = 0
    var furniture = 0
    var electrical = 0
    var ceilingLights = 0

    init(project: SurveyProject) {
        for scan in project.scans where !scan.archived {
            guard let room = ProjectRepository.load(projectID: scan.id) else {
                continue
            }
            scans += 1
            floors += room.floors?.count ?? 0
            walls += room.wallCount
            doors += room.doorCount
            windows += room.windowCount
            openings += room.surfaces.filter { $0.kind == .opening }.count
            furniture += room.furnitureCount
            electrical += room.points.count
            ceilingLights += room.ceilingLightCount
        }
    }
}

private struct CountRow: View {
    let title: String
    let value: Int

    var body: some View {
        LabeledContent(title) {
            Text("\(value)")
                .monospacedDigit()
                .fontWeight(.semibold)
        }
    }
}

private struct QuickLookFilePreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(
        context: Context
    ) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ uiViewController: QLPreviewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(
            in controller: QLPreviewController
        ) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}
