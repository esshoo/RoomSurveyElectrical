import ARKit
import Combine
import Foundation
import RoomPlan
import SwiftUI

@MainActor
final class RoomCaptureModel: NSObject, ObservableObject,
    RoomCaptureViewDelegate, RoomCaptureSessionDelegate, ARSessionDelegate {

    enum Phase: Equatable {
        case idle
        case relocalizing
        case scanning
        case processing
        case coolingDown
        case ready
        case failed(String)
    }

    private enum StopReason {
        case userFinished
        case thermalSafety
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var project: RoomProject?
    @Published private(set) var thermalState: ProcessInfo.ThermalState
    @Published private(set) var relocalizationMessage = "وجّه الكاميرا إلى جزء معروف من الغرفة."

    let arSession: ARSession
    let roomCaptureView: RoomCaptureView

    private let configuration = RoomCaptureSession.Configuration()
    private var rawRoomData: CapturedRoomData?
    private let destination: ScanDestination?
    private let includeFurniture: Bool
    private let startsFromExistingProject: Bool

    private var latestRoomSnapshot: CapturedRoom?
    private var stopReason: StopReason = .userFinished
    private var isFinalizing = false
    private var isStartingCapture = false
    private var thermalObserver: NSObjectProtocol?
    private var relocalizationTimeoutTask: Task<Void, Never>?

    override init() {
        destination = nil
        includeFurniture = true
        startsFromExistingProject = false
        thermalState = ProcessInfo.processInfo.thermalState
        let sharedSession = ARSession()
        arSession = sharedSession
        roomCaptureView = RoomCaptureView(frame: .zero, arSession: sharedSession)
        super.init()
        configureDelegatesAndThermalMonitoring()
    }

    init(
        destination: ScanDestination,
        settings: ElectricalPlacementSettings
    ) {
        self.destination = destination
        includeFurniture = settings.spatialScanContentMode.includesFurniture
        startsFromExistingProject = false
        thermalState = ProcessInfo.processInfo.thermalState
        let sharedSession = ARSession()
        arSession = sharedSession
        roomCaptureView = RoomCaptureView(frame: .zero, arSession: sharedSession)
        super.init()
        configureDelegatesAndThermalMonitoring()
    }

    init(
        existingProject: RoomProject,
        settings: ElectricalPlacementSettings
    ) {
        destination = nil
        includeFurniture = settings.spatialScanContentMode.includesFurniture
        startsFromExistingProject = true
        thermalState = ProcessInfo.processInfo.thermalState
        let sharedSession = ARSession()
        arSession = sharedSession
        roomCaptureView = RoomCaptureView(frame: .zero, arSession: sharedSession)
        super.init()
        project = existingProject
        configureDelegatesAndThermalMonitoring()
    }

    required init?(coder: NSCoder) {
        destination = nil
        includeFurniture = true
        startsFromExistingProject = false
        thermalState = ProcessInfo.processInfo.thermalState
        let sharedSession = ARSession()
        arSession = sharedSession
        roomCaptureView = RoomCaptureView(frame: .zero, arSession: sharedSession)
        super.init()
        configureDelegatesAndThermalMonitoring()
    }

    deinit {
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
        relocalizationTimeoutTask?.cancel()
    }

    nonisolated func encode(with coder: NSCoder) {
        // RoomCaptureViewDelegate inherits from NSCoding. This model has no
        // state that should be archived, but the protocol requirement must be
        // implemented for the project to compile.
    }

    var isSupported: Bool {
        RoomCaptureSession.isSupported
    }

    var canResumeAfterCooling: Bool {
        thermalState == .nominal || thermalState == .fair
    }

    var thermalStateTitle: String {
        switch thermalState {
        case .nominal: "طبيعية"
        case .fair: "دافئ"
        case .serious: "مرتفعة"
        case .critical: "حرجة"
        @unknown default: "غير معروفة"
        }
    }

    func start() {
        guard isSupported else {
            phase = .failed("هذا الجهاز لا يدعم RoomPlan أو لا يحتوي على LiDAR.")
            return
        }
        guard phase == .idle else { return }

        rawRoomData = nil
        latestRoomSnapshot = nil
        if startsFromExistingProject {
            beginRelocalization()
        } else {
            startCaptureSession()
        }
    }

    func finish() {
        stopCapture(reason: .userFinished)
    }

    func resumeAfterCooling() {
        guard phase == .coolingDown, canResumeAfterCooling else { return }
        rawRoomData = nil
        latestRoomSnapshot = nil
        stopReason = .userFinished
        beginRelocalization()
    }

    func acceptSavedPartialResult() {
        guard phase == .coolingDown, project != nil else { return }
        phase = .ready
    }

    func cancel() {
        relocalizationTimeoutTask?.cancel()
        if phase == .scanning || phase == .processing {
            roomCaptureView.captureSession.stop(pauseARSession: true)
        }
        arSession.pause()
        rawRoomData = nil
        latestRoomSnapshot = nil
        if project == nil {
            phase = .idle
        }
    }

    private func configureDelegatesAndThermalMonitoring() {
        roomCaptureView.delegate = self
        roomCaptureView.captureSession.delegate = self
        _ = ProcessInfo.processInfo.thermalState
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: ProcessInfo.processInfo,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleThermalStateChange()
            }
        }
    }

    private func handleThermalStateChange() {
        thermalState = ProcessInfo.processInfo.thermalState
        switch thermalState {
        case .serious, .critical:
            if phase == .scanning {
                stopCapture(reason: .thermalSafety)
            } else if phase == .relocalizing {
                relocalizationTimeoutTask?.cancel()
                arSession.pause()
                phase = .coolingDown
            }
        case .nominal, .fair:
            break
        @unknown default:
            break
        }
    }

    private func startCaptureSession() {
        guard !isStartingCapture else { return }
        isStartingCapture = true
        relocalizationTimeoutTask?.cancel()
        rawRoomData = nil
        latestRoomSnapshot = nil
        phase = .scanning
        roomCaptureView.captureSession.run(configuration: configuration)
        isStartingCapture = false
    }

    private func stopCapture(reason: StopReason) {
        guard phase == .scanning else { return }
        stopReason = reason
        phase = .processing
        roomCaptureView.captureSession.stop(pauseARSession: false)
    }

    private func beginRelocalization() {
        guard let project,
              let worldMapFile = project.worldMapFile else {
            phase = .failed(
                "لا توجد خريطة تتبع محفوظة لهذا المسح. يمكن إعادة المسح كنسخة جديدة، "
                    + "أما الاستكمال الدقيق فيحتاج مشروعًا تم إنشاؤه بالإصدار الحالي."
            )
            return
        }

        do {
            let worldMap = try ProjectRepository.loadWorldMap(
                projectID: project.id,
                fileName: worldMapFile
            )
            let configuration = ARWorldTrackingConfiguration()
            configuration.initialWorldMap = worldMap
            configuration.planeDetection = [.horizontal, .vertical]
            arSession.delegate = self
            relocalizationMessage = "وجّه الكاميرا إلى الحائط أو الباب الذي سبق مسحه."
            phase = .relocalizing
            arSession.run(
                configuration,
                options: [.resetTracking, .removeExistingAnchors]
            )
            scheduleRelocalizationTimeout()
        } catch {
            phase = .failed(
                "تعذر تحميل خريطة التتبع المحفوظة: \(error.localizedDescription)"
            )
        }
    }

    private func scheduleRelocalizationTimeout() {
        relocalizationTimeoutTask?.cancel()
        relocalizationTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(35))
            guard let self, self.phase == .relocalizing else { return }
            self.phase = .failed(
                "لم يتمكن الهاتف من التعرف على المكان. ارجع إلى الجزء الذي بدأ عنده المسح "
                    + "ووجّه الكاميرا ببطء، أو أعد المسح كنسخة جديدة."
            )
        }
    }

    nonisolated func session(
        _ session: ARSession,
        cameraDidChangeTrackingState camera: ARCamera
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.phase == .relocalizing else { return }
            switch camera.trackingState {
            case .normal:
                self.relocalizationMessage = "تم التعرف على المكان. جارٍ استئناف المسح…"
                self.relocalizationTimeoutTask?.cancel()
                try? await Task.sleep(for: .milliseconds(450))
                guard self.phase == .relocalizing else { return }
                self.startCaptureSession()
            case .limited(.relocalizing):
                self.relocalizationMessage = "حرّك الهاتف ببطء نحو منطقة سبق مسحها."
            case .limited(.insufficientFeatures):
                self.relocalizationMessage = "وجّه الكاميرا إلى حائط به تفاصيل أو باب واضح."
            case .limited(.excessiveMotion):
                self.relocalizationMessage = "حرّك الهاتف ببطء وثبات حتى يتعرف على المكان."
            case .limited(.initializing):
                self.relocalizationMessage = "جارٍ تجهيز الكاميرا وخريطة المكان…"
            case .notAvailable:
                self.relocalizationMessage = "التتبع غير متاح مؤقتًا."
            @unknown default:
                self.relocalizationMessage = "جارٍ محاولة التعرف على المكان…"
            }
        }
    }

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didUpdate room: CapturedRoom
    ) {
        Task { @MainActor [weak self] in
            self?.latestRoomSnapshot = room
        }
    }

    nonisolated func captureView(
        shouldPresent roomDataForProcessing: CapturedRoomData,
        error: Error?
    ) -> Bool {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                self.rawRoomData = nil
                self.handleProcessingFailure(error)
            } else {
                self.rawRoomData = self.includeFurniture
                    ? roomDataForProcessing
                    : nil
            }
        }
        return error == nil
    }

    nonisolated func captureView(
        didPresent processedResult: CapturedRoom,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                self.handleProcessingFailure(error)
                return
            }
            await self.finalize(capturedRoom: processedResult)
        }
    }

    private func handleProcessingFailure(_ error: Error) {
        guard !isFinalizing else { return }
        if let latestRoomSnapshot {
            Task { @MainActor [weak self] in
                await self?.finalize(capturedRoom: latestRoomSnapshot)
            }
        } else {
            rawRoomData = nil
            phase = .failed(error.localizedDescription)
        }
    }

    private func finalize(capturedRoom: CapturedRoom) async {
        guard !isFinalizing else { return }
        isFinalizing = true
        defer { isFinalizing = false }

        do {
            var savedProject: RoomProject
            if let currentProject = project {
                savedProject = RoomProjectGeometryMerger.merge(
                    capturedRoom: capturedRoom,
                    into: currentProject,
                    includeFurniture: includeFurniture
                )
                try ProjectRepository.save(savedProject)
            } else {
                savedProject = try ProjectRepository.createProject(
                    room: capturedRoom,
                    rawData: rawRoomData,
                    name: destination?.scanName,
                    includeFurniture: includeFurniture
                )
                if let destination {
                    _ = try WorkspaceRepository.attachScan(savedProject, to: destination)
                }
            }

            if let worldMap = try? await currentWorldMap(),
               let fileName = try? ProjectRepository.saveWorldMap(
                worldMap,
                projectID: savedProject.id
               ) {
                savedProject.worldMapFile = fileName
                try ProjectRepository.save(savedProject)
            }

            rawRoomData = nil
            latestRoomSnapshot = nil
            project = savedProject

            switch stopReason {
            case .userFinished:
                phase = .ready
            case .thermalSafety:
                arSession.pause()
                phase = .coolingDown
            }
        } catch {
            rawRoomData = nil
            phase = .failed("فشل حفظ نتيجة المسح: \(error.localizedDescription)")
        }
    }

    private func currentWorldMap() async throws -> ARWorldMap {
        try await withCheckedThrowingContinuation { continuation in
            arSession.getCurrentWorldMap { worldMap, error in
                if let worldMap {
                    continuation.resume(returning: worldMap)
                } else {
                    continuation.resume(
                        throwing: error ?? NSError(
                            domain: "3ERoomElectrical.ARWorldMap",
                            code: 1,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "تعذر حفظ خريطة تتبع المكان."
                            ]
                        )
                    )
                }
            }
        }
    }
}

struct RoomCaptureRepresentable: UIViewRepresentable {
    let captureView: RoomCaptureView

    func makeUIView(context: Context) -> RoomCaptureView {
        captureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}
