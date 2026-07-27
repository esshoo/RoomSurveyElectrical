import ARKit
import SceneKit
import SwiftUI

@MainActor
final class ARWorldMapRelocalizationController: NSObject, ObservableObject, ARSessionDelegate {
    enum Stage: Equatable {
        case idle
        case relocalizing
        case ready
        case failed(String)
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var message = "وجّه الكاميرا إلى جزء معروف من الغرفة."

    let session = ARSession()
    private let project: RoomProject
    private var timeoutTask: Task<Void, Never>?

    init(project: RoomProject) {
        self.project = project
        super.init()
        session.delegate = self
    }

    deinit {
        timeoutTask?.cancel()
    }

    func start() {
        guard stage == .idle else { return }
        guard let fileName = project.worldMapFile else {
            stage = .failed(
                "لا توجد خريطة تتبع محفوظة لهذا المسح. المشاريع القديمة تحتاج إعادة مسح "
                    + "مرة واحدة بالإصدار الحالي، أو يمكن استخدام رفع الصور المحلية."
            )
            return
        }

        do {
            let map = try ProjectRepository.loadWorldMap(
                projectID: project.id,
                fileName: fileName
            )
            let configuration = ARWorldTrackingConfiguration()
            configuration.initialWorldMap = map
            configuration.planeDetection = [.horizontal, .vertical]
            message = "وجّه الكاميرا إلى حائط أو باب سبق تصويره."
            stage = .relocalizing
            session.run(
                configuration,
                options: [.resetTracking, .removeExistingAnchors]
            )
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(35))
                guard let self, self.stage == .relocalizing else { return }
                self.stage = .failed(
                    "لم يتم التعرف على المكان. عد إلى منطقة المسح الأصلية وحرّك الهاتف ببطء، "
                        + "أو استخدم صورة محلية لهذا الحائط."
                )
            }
        } catch {
            stage = .failed(
                "تعذر فتح خريطة تتبع المكان: \(error.localizedDescription)"
            )
        }
    }

    func stop() {
        timeoutTask?.cancel()
        session.pause()
    }

    nonisolated func session(
        _ session: ARSession,
        cameraDidChangeTrackingState camera: ARCamera
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.stage == .relocalizing else { return }
            switch camera.trackingState {
            case .normal:
                self.timeoutTask?.cancel()
                self.message = "تم التعرف على المكان."
                self.stage = .ready
            case .limited(.relocalizing):
                self.message = "حرّك الهاتف ببطء نحو منطقة سبق مسحها."
            case .limited(.insufficientFeatures):
                self.message = "وجّه الكاميرا إلى حائط به تفاصيل أو فتحة واضحة."
            case .limited(.excessiveMotion):
                self.message = "الحركة سريعة؛ حرّك الهاتف ببطء وثبات."
            case .limited(.initializing):
                self.message = "جارٍ تحميل خريطة المكان وتجهيز الكاميرا…"
            case .notAvailable:
                self.message = "التتبع غير متاح مؤقتًا."
            @unknown default:
                self.message = "جارٍ محاولة التعرف على المكان…"
            }
        }
    }
}

struct WallPhotoRecaptureWorkflowView: View {
    @State private var project: RoomProject
    @StateObject private var relocalizer: ARWorldMapRelocalizationController
    @State private var isScanning = false

    let performanceProfile: SpatialScanPerformanceProfile
    let targetSegmentIDs: Set<UUID>
    let onClose: () -> Void

    init(
        initialProject: RoomProject,
        performanceProfile: SpatialScanPerformanceProfile,
        targetSegmentIDs: Set<UUID>,
        onClose: @escaping () -> Void
    ) {
        _project = State(initialValue: initialProject)
        _relocalizer = StateObject(
            wrappedValue: ARWorldMapRelocalizationController(project: initialProject)
        )
        self.performanceProfile = performanceProfile
        self.targetSegmentIDs = targetSegmentIDs
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            if isScanning {
                AdaptivePhotographicWallScanView(
                    project: $project,
                    arSession: relocalizer.session,
                    performanceProfile: performanceProfile,
                    targetSegmentIDs: targetSegmentIDs,
                    onProjectChanged: persist,
                    onClose: finish
                )
            } else {
                RelocalizationCameraPreview(session: relocalizer.session)
                    .ignoresSafeArea()

                VStack {
                    HStack {
                        Button(action: finish) {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        Spacer()
                    }
                    .padding()

                    Spacer()

                    relocalizationCard
                        .padding()
                }
            }
        }
        .onAppear {
            relocalizer.start()
        }
        .onChange(of: relocalizer.stage) { _, stage in
            if stage == .ready {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    guard relocalizer.stage == .ready else { return }
                    isScanning = true
                }
            }
        }
        .onDisappear {
            relocalizer.stop()
        }
    }

    @ViewBuilder
    private var relocalizationCard: some View {
        VStack(spacing: 13) {
            switch relocalizer.stage {
            case .idle, .relocalizing:
                ProgressView()
                    .controlSize(.large)
                Text("التعرف على مكان المسح")
                    .font(.headline)
                Text(relocalizer.message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text("المطلوب إعادة تصويره: \(targetSegmentIDs.count) جزء")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            case .ready:
                ProgressView("جارٍ فتح جلسة التصوير…")
            case .failed(let message):
                Image(systemName: "location.slash.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("تعذر استعادة مكان المسح")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("إغلاق", action: finish)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func persist() {
        try? ProjectRepository.save(project)
    }

    private func finish() {
        persist()
        relocalizer.stop()
        onClose()
    }
}

private struct RelocalizationCameraPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = false
        view.antialiasingMode = .none
        view.preferredFramesPerSecond = 30
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if uiView.session !== session {
            uiView.session = session
        }
    }
}
