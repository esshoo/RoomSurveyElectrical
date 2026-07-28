import ARKit
import Combine
import Foundation
import RoomPlan
import SwiftUI
import UIKit

@MainActor
final class RoomCaptureModel: NSObject, ObservableObject,
    RoomCaptureViewDelegate, RoomCaptureSessionDelegate, ARSessionDelegate {

    enum Phase: Equatable {
        case idle
        case relocalizing
        case relocalizationFailed
        case scanning
        case processing
        case coolingDown
        case paused
        case ready
        case failed(String)
    }

    private enum StopReason {
        case userFinished
        case manualPause
        case thermalSafety
        case applicationBackground

        var continuationReason: SpatialScanPauseReason? {
            switch self {
            case .userFinished:
                nil
            case .manualPause:
                .manual
            case .thermalSafety:
                .thermalSafety
            case .applicationBackground:
                .applicationBackground
            }
        }
    }

    private enum ThermalPauseContext {
        case beforeStart
        case scanningSaved
        case relocalization
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var project: RoomProject?
    @Published private(set) var thermalState: ProcessInfo.ThermalState
    @Published private(set) var thermalResumeSecondsRemaining = 0
    @Published private(set) var isThermallyReadyToResume = false
    @Published private(set) var relocalizationMessage = "وجّه الكاميرا إلى جزء معروف من الغرفة."
    @Published private(set) var relocalizationFailureMessage = ""

    let arSession: ARSession
    let roomCaptureView: RoomCaptureView

    private let configuration = RoomCaptureSession.Configuration()
    private var rawRoomData: CapturedRoomData?
    private let destination: ScanDestination?
    private let includeFurniture: Bool
    private let startsFromExistingProject: Bool
    private let thermalProtectionMode: SpatialScanThermalProtectionMode
    private let thermalResumeStabilitySeconds: Int

    private var latestRoomSnapshot: CapturedRoom?
    private var pendingWorldMapTask: Task<ARWorldMap?, Never>?
    private var stopReason: StopReason = .userFinished
    private var isFinalizing = false
    private var isStartingCapture = false
    private var thermalObserver: NSObjectProtocol?
    private var relocalizationTimeoutTask: Task<Void, Never>?
    private var fairThermalPauseTask: Task<Void, Never>?
    private var thermalResumeStabilityTask: Task<Void, Never>?
    private var thermalPauseContext: ThermalPauseContext = .beforeStart
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid

    override init() {
        destination = nil
        includeFurniture = true
        startsFromExistingProject = false
        thermalProtectionMode = .balanced
        thermalResumeStabilitySeconds = ThermalResumeStabilityDuration.seconds30.rawValue
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
        thermalProtectionMode = settings.spatialScanThermalProtectionMode
        thermalResumeStabilitySeconds = settings.thermalResumeStabilityDuration.rawValue
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
        thermalProtectionMode = settings.spatialScanThermalProtectionMode
        thermalResumeStabilitySeconds = settings.thermalResumeStabilityDuration.rawValue
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
        thermalProtectionMode = .balanced
        thermalResumeStabilitySeconds = ThermalResumeStabilityDuration.seconds30.rawValue
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
        fairThermalPauseTask?.cancel()
        thermalResumeStabilityTask?.cancel()
        pendingWorldMapTask?.cancel()
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
        isThermallyReadyToResume
    }

    var savedPauseReason: SpatialScanPauseReason? {
        project?.scanContinuationState?.reason
    }

    var savedPauseDate: Date? {
        project?.scanContinuationState?.pausedAt
    }

    var canResumeSavedScan: Bool {
        guard let project else { return false }
        return ProjectRepository.hasWorldMap(project)
    }

    var isCurrentThermalStateAcceptableForResume: Bool {
        isResumeThermalStateAcceptable(thermalState)
    }

    var thermalProtectionTitle: String {
        thermalProtectionMode.title
    }

    var thermalCoolingTitle: String {
        switch thermalPauseContext {
        case .beforeStart:
            "تم تأجيل بدء المسح"
        case .scanningSaved:
            "تم إيقاف المسح وحفظ ما تم"
        case .relocalization:
            "تم إيقاف استعادة المكان مؤقتًا"
        }
    }

    var thermalCoolingDetail: String {
        switch thermalPauseContext {
        case .beforeStart:
            "حرارة الهاتف لا تسمح ببدء جلسة آمنة حسب وضع الحماية المختار."
        case .scanningSaved:
            "تم إيقاف الكاميرا وحفظ أحدث نتيجة متاحة، مع محاولة حفظ خريطة المكان قبل انتظار التبريد."
        case .relocalization:
            "تم إيقاف الكاميرا قبل استكمال المسح. سيُعاد التعرف على المكان بعد استقرار الحرارة."
        }
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

    var thermalStateMessage: String {
        switch thermalState {
        case .nominal:
            return "الحرارة طبيعية والمسح يعمل بالإعدادات المختارة."
        case .fair:
            if thermalProtectionMode == .earlyProtection {
                return "الهاتف دافئ. ستتوقف الجلسة وتحفظ تلقائيًا إذا استمرت الحالة."
            }
            return "الهاتف دافئ. يستمر المسح مع مراقبة الحرارة."
        case .serious:
            if thermalProtectionMode == .extendedSession {
                return "الحرارة مرتفعة. وضع الجلسة الممتدة يستمر بحذر حتى الحالة الحرجة."
            }
            return "الحرارة مرتفعة. جارٍ الحفظ والإيقاف الوقائي."
        case .critical:
            return "الحرارة حرجة. يجب إيقاف الكاميرا وانتظار التبريد."
        @unknown default:
            return "تعذر تحديد حالة الحرارة."
        }
    }

    func start() {
        guard isSupported else {
            phase = .failed("هذا الجهاز لا يدعم RoomPlan أو لا يحتوي على LiDAR.")
            return
        }
        guard phase == .idle else { return }

        thermalState = ProcessInfo.processInfo.thermalState
        guard !mustPauseImmediately(for: thermalState) else {
            enterCoolingDown(context: .beforeStart)
            return
        }

        rawRoomData = nil
        latestRoomSnapshot = nil
        pendingWorldMapTask?.cancel()
        pendingWorldMapTask = nil
        relocalizationFailureMessage = ""
        if startsFromExistingProject {
            beginRelocalization()
        } else {
            startCaptureSession()
        }
    }

    func finish() {
        stopCapture(reason: .userFinished)
    }

    func pauseAndSave() {
        stopCapture(reason: .manualPause)
    }

    func pauseForApplicationLifecycle() {
        switch phase {
        case .scanning:
            beginBackgroundSaveTask()
            stopCapture(reason: .applicationBackground)
        case .relocalizing:
            pauseRelocalization(reason: .applicationBackground)
        default:
            break
        }
    }

    func pauseRelocalizationManually() {
        guard phase == .relocalizing else { return }
        pauseRelocalization(reason: .manual)
    }

    func resumeSavedScan() {
        guard phase == .paused || phase == .relocalizationFailed,
              project != nil else { return }
        relocalizationFailureMessage = ""
        beginRelocalization()
    }

    func retryRelocalization() {
        guard phase == .relocalizationFailed else { return }
        relocalizationFailureMessage = ""
        beginRelocalization()
    }

    func resumeAfterCooling() {
        guard phase == .coolingDown, canResumeAfterCooling else { return }
        thermalResumeStabilityTask?.cancel()
        isThermallyReadyToResume = false
        thermalResumeSecondsRemaining = 0
        rawRoomData = nil
        latestRoomSnapshot = nil
        pendingWorldMapTask?.cancel()
        pendingWorldMapTask = nil
        stopReason = .userFinished
        if project != nil {
            beginRelocalization()
        } else {
            startCaptureSession()
        }
    }

    func acceptSavedPartialResult() {
        guard phase == .coolingDown
                || phase == .paused
                || phase == .relocalizationFailed,
              var savedProject = project else { return }
        thermalResumeStabilityTask?.cancel()
        relocalizationTimeoutTask?.cancel()
        savedProject.scanContinuationState = nil
        do {
            try ProjectRepository.save(savedProject)
            project = savedProject
            phase = .ready
        } catch {
            phase = .failed("تعذر اعتماد الجزء المحفوظ: \(error.localizedDescription)")
        }
    }

    func cancel() {
        relocalizationTimeoutTask?.cancel()
        fairThermalPauseTask?.cancel()
        thermalResumeStabilityTask?.cancel()
        pendingWorldMapTask?.cancel()
        pendingWorldMapTask = nil
        if phase == .scanning || phase == .processing {
            roomCaptureView.captureSession.stop(pauseARSession: true)
        }
        arSession.pause()
        rawRoomData = nil
        latestRoomSnapshot = nil
        endBackgroundSaveTask()
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

        if phase == .coolingDown {
            beginResumeStabilityMonitoring()
            return
        }

        applyThermalPolicy()
    }

    private func applyThermalPolicy() {
        switch thermalState {
        case .nominal:
            fairThermalPauseTask?.cancel()
            fairThermalPauseTask = nil

        case .fair:
            if let gracePeriod = thermalProtectionMode.fairStateGracePeriod {
                scheduleFairThermalPause(after: gracePeriod)
            }

        case .serious:
            fairThermalPauseTask?.cancel()
            fairThermalPauseTask = nil
            if thermalProtectionMode.stopsImmediatelyAtSerious {
                triggerThermalPause()
            }

        case .critical:
            fairThermalPauseTask?.cancel()
            fairThermalPauseTask = nil
            triggerThermalPause()

        @unknown default:
            break
        }
    }

    private func scheduleFairThermalPause(after delay: TimeInterval) {
        guard fairThermalPauseTask == nil,
              phase == .scanning || phase == .relocalizing else { return }

        fairThermalPauseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self,
                  !Task.isCancelled,
                  self.thermalState == .fair,
                  self.phase == .scanning || self.phase == .relocalizing else {
                return
            }
            self.fairThermalPauseTask = nil
            self.triggerThermalPause()
        }
    }

    private func triggerThermalPause() {
        switch phase {
        case .scanning:
            thermalPauseContext = .scanningSaved
            stopCapture(reason: .thermalSafety)
        case .relocalizing:
            relocalizationTimeoutTask?.cancel()
            arSession.pause()
            guard persistContinuationState(reason: .thermalSafety) else { return }
            enterCoolingDown(context: .relocalization)
        default:
            break
        }
    }

    private func mustPauseImmediately(
        for state: ProcessInfo.ThermalState
    ) -> Bool {
        switch state {
        case .critical:
            return true
        case .serious:
            return thermalProtectionMode.stopsImmediatelyAtSerious
        case .nominal, .fair:
            return false
        @unknown default:
            return false
        }
    }

    private func startCaptureSession() {
        guard !isStartingCapture else { return }
        thermalState = ProcessInfo.processInfo.thermalState
        guard !mustPauseImmediately(for: thermalState) else {
            enterCoolingDown(context: project == nil ? .beforeStart : .relocalization)
            return
        }

        isStartingCapture = true
        relocalizationTimeoutTask?.cancel()
        stopReason = .userFinished
        rawRoomData = nil
        latestRoomSnapshot = nil
        pendingWorldMapTask?.cancel()
        pendingWorldMapTask = nil
        relocalizationFailureMessage = ""
        phase = .scanning
        roomCaptureView.captureSession.run(configuration: configuration)
        isStartingCapture = false
        applyThermalPolicy()
    }

    private func stopCapture(reason: StopReason) {
        guard phase == .scanning else { return }
        stopReason = reason
        pendingWorldMapTask?.cancel()
        pendingWorldMapTask = Task { @MainActor [weak self] in
            guard let self else { return nil }
            return try? await self.currentWorldMap()
        }
        phase = .processing
        roomCaptureView.captureSession.stop(pauseARSession: false)
    }

    private func pauseRelocalization(reason: SpatialScanPauseReason) {
        relocalizationTimeoutTask?.cancel()
        arSession.pause()
        guard project != nil else {
            phase = .idle
            return
        }
        guard persistContinuationState(reason: reason) else { return }
        phase = .paused
    }

    @discardableResult
    private func persistContinuationState(
        reason: SpatialScanPauseReason
    ) -> Bool {
        guard var savedProject = project else { return false }
        savedProject.scanContinuationState = SpatialScanContinuationState(
            reason: reason,
            worldMapCapturedAt: savedProject.scanContinuationState?.worldMapCapturedAt
        )
        do {
            try ProjectRepository.save(savedProject)
            project = savedProject
            return true
        } catch {
            phase = .failed("تعذر حفظ حالة الاستكمال: \(error.localizedDescription)")
            return false
        }
    }

    private func beginBackgroundSaveTask() {
        guard backgroundTaskIdentifier == .invalid else { return }
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(
            withName: "3ERoomElectrical.SaveSpatialScan"
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.endBackgroundSaveTask()
            }
        }
    }

    private func endBackgroundSaveTask() {
        guard backgroundTaskIdentifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
    }

    private func enterCoolingDown(context: ThermalPauseContext) {
        fairThermalPauseTask?.cancel()
        fairThermalPauseTask = nil
        relocalizationTimeoutTask?.cancel()
        thermalPauseContext = context
        arSession.pause()
        phase = .coolingDown
        beginResumeStabilityMonitoring()
    }

    private func beginResumeStabilityMonitoring() {
        thermalResumeStabilityTask?.cancel()
        isThermallyReadyToResume = false
        thermalResumeSecondsRemaining = thermalResumeStabilitySeconds

        guard isResumeThermalStateAcceptable(thermalState) else { return }

        thermalResumeStabilityTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var remaining = self.thermalResumeStabilitySeconds
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled,
                      self.phase == .coolingDown,
                      self.isResumeThermalStateAcceptable(self.thermalState) else {
                    return
                }
                remaining -= 1
                self.thermalResumeSecondsRemaining = remaining
            }
            self.isThermallyReadyToResume = true
        }
    }

    private func isResumeThermalStateAcceptable(
        _ state: ProcessInfo.ThermalState
    ) -> Bool {
        switch state {
        case .nominal:
            return true
        case .fair:
            return !thermalProtectionMode.resumeRequiresNominalState
        case .serious, .critical:
            return false
        @unknown default:
            return false
        }
    }

    private func beginRelocalization() {
        guard let project,
              let worldMapFile = project.worldMapFile else {
            relocalizationFailureMessage =
                "لا توجد خريطة تتبع محفوظة لهذا المسح. الجزء المحفوظ لم يُحذف، "
                    + "ويمكن اعتماده أو إعادة المسح كنسخة جديدة."
            phase = .relocalizationFailed
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
            applyThermalPolicy()
        } catch {
            relocalizationFailureMessage =
                "تعذر تحميل خريطة التتبع المحفوظة: \(error.localizedDescription). "
                    + "الجزء المحفوظ ما زال موجودًا ويمكن اعتماده دون حذفه."
            phase = .relocalizationFailed
        }
    }

    private func scheduleRelocalizationTimeout() {
        relocalizationTimeoutTask?.cancel()
        relocalizationTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(35))
            guard let self, self.phase == .relocalizing else { return }
            self.arSession.pause()
            self.relocalizationFailureMessage =
                "لم يتمكن الهاتف من التعرف على المكان خلال المهلة. "
                    + "الجزء المحفوظ لم يُحذف؛ يمكنك إعادة المحاولة أو اعتماده كما هو."
            self.phase = .relocalizationFailed
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
            endBackgroundSaveTask()
            if var savedProject = project {
                savedProject.scanContinuationState = SpatialScanContinuationState(
                    reason: .interrupted,
                    worldMapCapturedAt: savedProject.scanContinuationState?.worldMapCapturedAt
                )
                try? ProjectRepository.save(savedProject)
                project = savedProject
            }
            phase = .failed(error.localizedDescription)
        }
    }

    private func finalize(capturedRoom: CapturedRoom) async {
        guard !isFinalizing else { return }
        isFinalizing = true
        defer {
            isFinalizing = false
            endBackgroundSaveTask()
        }

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

            let capturedWorldMap: ARWorldMap?
            if let pendingWorldMapTask {
                capturedWorldMap = await pendingWorldMapTask.value
            } else {
                capturedWorldMap = try? await currentWorldMap()
            }
            pendingWorldMapTask = nil
            var worldMapCapturedAt: Date?
            if let capturedWorldMap,
               let fileName = try? ProjectRepository.saveWorldMap(
                capturedWorldMap,
                projectID: savedProject.id
               ) {
                savedProject.worldMapFile = fileName
                worldMapCapturedAt = Date()
            }

            if let continuationReason = stopReason.continuationReason {
                savedProject.scanContinuationState = SpatialScanContinuationState(
                    reason: continuationReason,
                    worldMapCapturedAt: worldMapCapturedAt
                        ?? savedProject.scanContinuationState?.worldMapCapturedAt
                )
            } else {
                savedProject.scanContinuationState = nil
            }
            try ProjectRepository.save(savedProject)

            rawRoomData = nil
            latestRoomSnapshot = nil
            project = savedProject

            switch stopReason {
            case .userFinished:
                phase = .ready
            case .manualPause, .applicationBackground:
                phase = .paused
            case .thermalSafety:
                enterCoolingDown(context: .scanningSaved)
            }
        } catch {
            rawRoomData = nil
            pendingWorldMapTask?.cancel()
            pendingWorldMapTask = nil
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
