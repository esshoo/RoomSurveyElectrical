import RoomPlan
import SwiftUI

struct ContentView: View {
    @State private var showWorkflow = false
    @State private var projects: [RoomProject] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("مسح الغرف ونقاط الكهرباء", systemImage: "viewfinder.rectangular")
                            .font(.title2.bold())

                        Text("امسح الغرفة بالـLiDAR، ثم اضغط على الحائط لإضافة المفاتيح والأفياش واستخراج الحصر.")
                            .foregroundStyle(.secondary)

                        Button {
                            showWorkflow = true
                        } label: {
                            Label("بدء مسح جديد", systemImage: "camera.viewfinder")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!RoomCaptureSession.isSupported)

                        if !RoomCaptureSession.isSupported {
                            Text("يتطلب iPhone أو iPad مزودًا بحساس LiDAR.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("المشروعات المحفوظة") {
                    if projects.isEmpty {
                        ContentUnavailableView(
                            "لا توجد مشروعات بعد",
                            systemImage: "square.stack.3d.up.slash",
                            description: Text("سيظهر أول مشروع هنا بعد اكتمال المسح.")
                        )
                    } else {
                        ForEach(projects) { project in
                            NavigationLink {
                                ProjectDetailView(project: project)
                            } label: {
                                ProjectRow(project: project)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Room Survey")
        }
        .fullScreenCover(isPresented: $showWorkflow, onDismiss: reloadProjects) {
            RoomWorkflowView {
                showWorkflow = false
            }
        }
        .onAppear(perform: reloadProjects)
    }

    private func reloadProjects() {
        projects = ProjectRepository.loadAll()
    }
}

private struct ProjectRow: View {
    let project: RoomProject

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube.transparent.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 38, height: 38)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                Text("\(project.wallCount) حائط • \(project.points.count) نقطة كهرباء")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct RoomWorkflowView: View {
    @StateObject private var model = RoomCaptureModel()
    let onClose: () -> Void

    var body: some View {
        Group {
            if let project = model.project {
                ElectricalEditorView(
                    initialProject: project,
                    arSession: model.arSession,
                    onClose: {
                        model.arSession.pause()
                        onClose()
                    }
                )
            } else {
                ScanRoomView(model: model, onClose: {
                    model.cancel()
                    onClose()
                })
            }
        }
    }
}

private struct ScanRoomView: View {
    @ObservedObject var model: RoomCaptureModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            RoomCaptureRepresentable(captureView: model.roomCaptureView)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                }
                .padding()

                Spacer()

                VStack(spacing: 12) {
                    if model.phase == .processing {
                        ProgressView("جارٍ تجهيز JSON وUSDZ…")
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        model.finish()
                    } label: {
                        Label("إنهاء المسح وتجهيز الغرفة", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.phase != .scanning)
                }
                .padding()
            }

            if case .failed(let message) = model.phase {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(message)
                        .multilineTextAlignment(.center)
                    Button("إغلاق", action: onClose)
                        .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .padding()
            }
        }
        .onAppear {
            model.start()
        }
    }
}

private struct ProjectDetailView: View {
    let project: RoomProject

    var body: some View {
        List {
            Section("ملخص المسح") {
                LabeledContent("الحوائط", value: "\(project.wallCount)")
                LabeledContent("الأبواب", value: "\(project.doorCount)")
                LabeledContent("الشبابيك", value: "\(project.windowCount)")
                LabeledContent("نقاط الكهرباء", value: "\(project.points.count)")
            }

            Section("الحصر") {
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

            Section("تصدير ملفات الإثبات") {
                if let url = try? ProjectRepository.fileURL(
                    projectID: project.id,
                    fileName: "project.json"
                ) {
                    ShareLink(item: url) {
                        Label("مشاركة المشروع والنقاط JSON", systemImage: "list.bullet.rectangle")
                    }
                }

                if let url = try? ProjectRepository.fileURL(
                    projectID: project.id,
                    fileName: project.processedJSONFile
                ) {
                    ShareLink(item: url) {
                        Label("مشاركة بيانات RoomPlan JSON", systemImage: "doc.text")
                    }
                }

                if let rawFile = project.rawJSONFile,
                   let url = try? ProjectRepository.fileURL(projectID: project.id, fileName: rawFile) {
                    ShareLink(item: url) {
                        Label("مشاركة البيانات الخام JSON", systemImage: "doc.badge.gearshape")
                    }
                }

                if let url = try? ProjectRepository.fileURL(
                    projectID: project.id,
                    fileName: project.usdzFile
                ) {
                    ShareLink(item: url) {
                        Label("مشاركة نموذج USDZ", systemImage: "cube")
                    }
                }
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
