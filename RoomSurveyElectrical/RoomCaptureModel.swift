import ARKit
import Combine
import CoreImage
import Foundation
import RoomPlan
import SceneKit
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

    private struct WorldMapCapture {
        var worldMap: ARWorldMap
        var quality: SpatialWorldMapQuality
        var capturedAt: Date
        var featurePointCount: Int
        var extent: [Float]
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var project: RoomProject?
    @Published private(set) var thermalState: ProcessInfo.ThermalState
    @Published private(set) var thermalResumeSecondsRemaining = 0
    @Published private(set) var isThermallyReadyToResume = false
    @Published private(set) var relocalizationMessage = "وجّه الكاميرا إلى جزء معروف من الغرفة."
    @Published private(set) var relocalizationFailureMessage = ""
    @Published private(set) var relocalizationEvidenceMessage = ""
    @Published private(set) var relocalizationProgress: Double = 0
    @Published private(set) var referenceWallImage: UIImage?
    @Published private(set) var referenceWallEdgeImage: UIImage?
    @Published private(set) var referenceWallSummary = ""
    @Published private(set) var locationAssistMessage = ""
    @Published var referenceOverlayOpacity: Double = 0.48
    @Published var referenceOverlayMode: SpatialResumeOverlayMode = .photo
    @Published var referenceOverlayFlipHorizontal = false
    @Published var referenceOverlayFlipVertical = false
    @Published private(set) var visualAlignmentConfidence: SpatialVisualAlignmentConfidence = .low
    @Published private(set) var isManualVisualResumeAvailable = false
    @Published private(set) var isPreparingManualVisualResume = false

    let arSession: ARSession
    let captureHostView: SpatialCaptureHostView
    private var roomCaptureView: RoomCaptureView?

    private let configuration = RoomCaptureSession.Configuration()
    private var rawRoomData: CapturedRoomData?
    private let destination: ScanDestination?
    private let includeFurniture: Bool
    private let startsFromExistingProject: Bool
    private let thermalProtectionMode: SpatialScanThermalProtectionMode
    private let thermalResumeStabilitySeconds: Int
    private let relocalizationStrictness: SpatialRelocalizationStrictness
    private let useOptionalLocationAssist: Bool
    private let referenceSensor = SpatialReferenceSensor()

    private var latestRoomSnapshot: CapturedRoom?
    private var pendingWorldMapTask: Task<WorldMapCapture?, Never>?
    private var stopReason: StopReason = .userFinished
    private var isFinalizing = false
    private var isStartingCapture = false
    private var thermalObserver: NSObjectProtocol?
    private var relocalizationTimeoutTask: Task<Void, Never>?
    private var manualVisualResumeUnlockTask: Task<Void, Never>?
    private var fairThermalPauseTask: Task<Void, Never>?
    private var thermalResumeStabilityTask: Task<Void, Never>?
    private var thermalPauseContext: ThermalPauseContext = .beforeStart
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    private var roomCaptureSessionIsRunning = false
    private var latestWallReference: SpatialWallReference?
    private var latestWallReferenceImageData: Data?
    private var latestWallReferenceGeographicReference: SpatialGeographicReference?
    private var lastReferencePairCapturedAt: Date = .distantPast
    private var pendingWallReference: SpatialWallReference?
    private var pendingReferenceImageData: Data?
    private var pendingReferenceCameraTransform: [Float]?
    private var pendingGeographicReference: SpatialGeographicReference?
    private var cachedGoodWorldMap: ARWorldMap?
    private var cachedGoodWorldMapCapturedAt: Date?
    private var cachedGoodWorldMapQuality: SpatialWorldMapQuality?
    private var lastWorldMapCacheRequestAt: Date = .distantPast
    private var worldMapCacheTask: Task<Void, Never>?
    private var referenceAnchorRestored = false
    private var stableTrackingFrameCount = 0
    private var stableWallMatchFrameCount = 0
    private var latestWallMatchScore: Double = 0
    private var lastWallMatchUpdateAt: Date = .distantPast
    private var latestHeadingPass = true
    private var latestLocationPass = true
    private var isCompletingRelocalization = false
    private var liveSessionContinuityAvailable = false
    private var activeIncomingWorldTransform: simd_float4x4?
    private var latestDetectedWallDescription = ""
    private let resumeAnchorName = "3ERoomElectrical.ResumeReference"
    private let referenceImageFileName = "spatial-resume-reference.jpg"
    private let imageContext = CIContext(options: [.cacheIntermediates: false])

    private var savedReferenceCameraTransformValues: [Float]? {
        project?.scanContinuationState?.referenceCameraTransform
            ?? project?.scanContinuationState?.referenceWall?.cameraTransform
    }

    override init() {
        destination = nil
        includeFurniture = true
        startsFromExistingProject = false
        thermalProtectionMode = .balanced
        thermalResumeStabilitySeconds = ThermalResumeStabilityDuration.seconds30.rawValue
        relocalizationStrictness = .balanced
        useOptionalLocationAssist = true
        thermalState = ProcessInfo.processInfo.thermalState
        let sharedSession = ARSession()
        arSession = sharedSession
        captureHostView = SpatialCaptureHostView(arSession: sharedSession)
        roomCaptureView = nil
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
        relocalizationStrictness = settings.spatialRelocalizationStrictness
        useOptionalLocationAssist = settings.useOptionalLocationAssistForResume
        thermalState = ProcessInfo.processInfo.thermalState
        let sharedSession = ARSession()
        arSession = sharedSession
        captureHostView = SpatialCaptureHostView(arSession: sharedSession)
        roomCaptureView = nil
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
        relocalizationStrictness = settings.spatialRelocalizationStrictness
        useOptionalLocationAssist = settings.useOptionalLocationAssistForResume
        thermalState = ProcessInfo.processInfo.thermalState
        let sharedSession = ARSession()
        arSession = sharedSession
        captureHostView = SpatialCaptureHostView(arSession: sharedSession)
        roomCaptureView = nil
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
        relocalizationStrictness = .balanced
        useOptionalLocationAssist = true
        thermalState = ProcessInfo.processInfo.thermalState
        let sharedSession = ARSession()
        arSession = sharedSession
        captureHostView = SpatialCaptureHostView(arSession: sharedSession)
        roomCaptureView = nil
        super.init()
        configureDelegatesAndThermalMonitoring()
    }

    deinit {
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
        relocalizationTimeoutTask?.cancel()
        manualVisualResumeUnlockTask?.cancel()
        fairThermalPauseTask?.cancel()
        thermalResumeStabilityTask?.cancel()
        pendingWorldMapTask?.cancel()
        worldMapCacheTask?.cancel()
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
        let continuation = project.scanContinuationState
        let hasVisualReference = continuation?.referenceImageFile != nil
            && savedReferenceCameraTransformValues?.count == 16
        return canResumeUsingLiveSession
            || ProjectRepository.hasWorldMap(project)
            || hasVisualReference
    }

    var isLiveSessionResumeAvailable: Bool {
        canResumeUsingLiveSession
    }

    var currentWorldToProjectTransform: simd_float4x4? {
        activeIncomingWorldTransform
    }

    var resumeSavedScanTitle: String {
        canResumeUsingLiveSession
            ? "متابعة فورًا بنفس جلسة المسح"
            : "مطابقة آخر لقطة واستكمال المسح"
    }

    var isCurrentThermalStateAcceptableForResume: Bool {
        isResumeThermalStateAcceptable(thermalState)
    }

    var relocalizationStrictnessTitle: String {
        relocalizationStrictness.title
    }

    var savedWorldMapQualityTitle: String? {
        project?.scanContinuationState?.worldMapQuality?.title
    }

    var savedWorldMapDetail: String? {
        guard let state = project?.scanContinuationState else { return nil }
        var parts: [String] = []
        if let count = state.worldMapFeaturePointCount {
            parts.append("نقاط الخريطة: \(count)")
        }
        if let extent = state.worldMapExtent, extent.count == 3 {
            parts.append(
                String(
                    format: "المدى: %.1f × %.1f × %.1f م",
                    extent[0], extent[1], extent[2]
                )
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    var referenceOverlayImage: UIImage? {
        switch referenceOverlayMode {
        case .photo:
            return referenceWallImage
        case .edges:
            return referenceWallEdgeImage ?? referenceWallImage
        }
    }

    var canUseVisualResume: Bool {
        guard let state = project?.scanContinuationState,
              state.referenceImageFile != nil,
              savedReferenceCameraTransformValues?.count == 16,
              arSession.currentFrame != nil else {
            return false
        }
        return phase == .relocalizing || phase == .relocalizationFailed
    }

    var visualAlignmentConfidenceMessage: String {
        switch visualAlignmentConfidence {
        case .low:
            return "طابق الصورة بدقة مع الحائط والفتحات قبل المتابعة."
        case .medium:
            return "الصورة والاتجاه متقاربان؛ ثبّت الهاتف قبل المتابعة."
        case .high:
            return "المؤشرات الحالية قوية، ويمكن المتابعة بعد التأكد البصري."
        }
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

        referenceSensor.start(
            enabled: useOptionalLocationAssist,
            requestPermission: true
        )
        rawRoomData = nil
        latestRoomSnapshot = nil
        latestWallReference = nil
        latestWallReferenceImageData = nil
        latestWallReferenceGeographicReference = nil
        lastReferencePairCapturedAt = .distantPast
        pendingWorldMapTask?.cancel()
        pendingWorldMapTask = nil
        pendingWallReference = nil
        pendingReferenceImageData = nil
        pendingReferenceCameraTransform = nil
        pendingGeographicReference = nil
        activeIncomingWorldTransform = nil
        manualVisualResumeUnlockTask?.cancel()
        isManualVisualResumeAvailable = false
        isPreparingManualVisualResume = false
        visualAlignmentConfidence = .low
        referenceOverlayOpacity = 0.48
        referenceOverlayMode = .photo
        referenceOverlayFlipHorizontal = false
        referenceOverlayFlipVertical = false
        referenceWallImage = nil
        referenceWallEdgeImage = nil
        relocalizationFailureMessage = ""
        relocalizationEvidenceMessage = ""
        relocalizationProgress = 0
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
        // Once the app leaves the foreground, iOS may interrupt the camera and
        // the live AR coordinate space can no longer be assumed continuous.
        liveSessionContinuityAvailable = false
        switch phase {
        case .scanning:
            beginBackgroundSaveTask()
            stopCapture(reason: .applicationBackground)
        case .relocalizing, .relocalizationFailed:
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

        // A manual pause intentionally stops RoomPlan without pausing the
        // underlying ARSession. If this model and session are still alive, the
        // original coordinate system is already valid and must not be reset.
        if canResumeUsingLiveSession {
            resumeUsingLiveSession()
        } else {
            beginRelocalization()
        }
    }

    func retryRelocalization() {
        guard phase == .relocalizationFailed else { return }
        relocalizationFailureMessage = ""
        beginRelocalization()
    }

    func resumeFromVisualAlignment() {
        guard phase == .relocalizing || phase == .relocalizationFailed,
              !isPreparingManualVisualResume,
              isManualVisualResumeAvailable,
              let continuation = project?.scanContinuationState,
              let savedCameraValues = savedReferenceCameraTransformValues,
              savedCameraValues.count == 16 else {
            relocalizationFailureMessage =
                "لا توجد لقطة وبيانات كاميرا كافية لتنفيذ الاستكمال البصري بأمان."
            return
        }

        relocalizationTimeoutTask?.cancel()
        manualVisualResumeUnlockTask?.cancel()
        isPreparingManualVisualResume = true
        phase = .relocalizing
        relocalizationMessage =
            "ثبّت الهاتف على موضع الصورة. جارٍ إنشاء جلسة جديدة وربطها بالمشروع…"
        relocalizationEvidenceMessage =
            "سيتم استخدام وضع الكاميرا الحالي لمعادلة إحداثيات الجلسة الجديدة مع المسح المحفوظ."

        let savedCameraTransform = simd_float4x4(
            columnMajorValues: savedCameraValues
        )
        let previousWorldToProject = continuation.worldToProjectTransform.map {
            simd_float4x4(columnMajorValues: $0)
        } ?? matrix_identity_float4x4
        let previousTimestamp = arSession.currentFrame?.timestamp ?? 0

        let freshConfiguration = ARWorldTrackingConfiguration()
        freshConfiguration.planeDetection = [.horizontal, .vertical]
        arSession.delegate = self
        arSession.run(
            freshConfiguration,
            options: [.resetTracking, .removeExistingAnchors]
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<24 {
                try? await Task.sleep(for: .milliseconds(125))
                guard !Task.isCancelled,
                      self.phase == .relocalizing else { return }
                guard let frame = self.arSession.currentFrame,
                      frame.timestamp > previousTimestamp + 0.01 else {
                    continue
                }

                let newSessionToPreviousWorld = savedCameraTransform
                    * simd_inverse(frame.camera.transform)
                self.activeIncomingWorldTransform = previousWorldToProject
                    * newSessionToPreviousWorld
                self.isPreparingManualVisualResume = false
                self.isManualVisualResumeAvailable = false
                self.relocalizationProgress = 1
                self.relocalizationMessage =
                    "تمت محاذاة الجلسة بصريًا. جارٍ استكمال RoomPlan…"
                self.startCaptureSession()
                return
            }

            self.isPreparingManualVisualResume = false
            self.isManualVisualResumeAvailable = true
            self.relocalizationFailureMessage =
                "تعذر إنشاء إطار تتبع جديد. حرّك الهاتف ببطء ثم حاول الاستكمال البصري مرة أخرى."
            self.phase = .relocalizationFailed
        }
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
        liveSessionContinuityAvailable = false
        thermalResumeStabilityTask?.cancel()
        relocalizationTimeoutTask?.cancel()
        manualVisualResumeUnlockTask?.cancel()
        ProjectRepository.removeAsset(
            projectID: savedProject.id,
            fileName: savedProject.scanContinuationState?.referenceImageFile
        )
        savedProject.scanContinuationState = nil
        do {
            try ProjectRepository.save(savedProject)
            project = savedProject
            activeIncomingWorldTransform = nil
            isManualVisualResumeAvailable = false
            isPreparingManualVisualResume = false
            referenceWallImage = nil
            referenceWallEdgeImage = nil
            phase = .ready
        } catch {
            phase = .failed("تعذر اعتماد الجزء المحفوظ: \(error.localizedDescription)")
        }
    }

    func cancel() {
        liveSessionContinuityAvailable = false
        relocalizationTimeoutTask?.cancel()
        manualVisualResumeUnlockTask?.cancel()
        fairThermalPauseTask?.cancel()
        thermalResumeStabilityTask?.cancel()
        pendingWorldMapTask?.cancel()
        pendingWorldMapTask = nil
        worldMapCacheTask?.cancel()
        worldMapCacheTask = nil
        if phase == .scanning || phase == .processing,
           let roomCaptureView {
            roomCaptureView.captureSession.stop(pauseARSession: true)
            roomCaptureSessionIsRunning = false
        }
        arSession.pause()
        referenceSensor.stop()
        rawRoomData = nil
        latestRoomSnapshot = nil
        latestWallReference = nil
        latestWallReferenceImageData = nil
        latestWallReferenceGeographicReference = nil
        pendingReferenceCameraTransform = nil
        activeIncomingWorldTransform = nil
        isManualVisualResumeAvailable = false
        isPreparingManualVisualResume = false
        endBackgroundSaveTask()
        if project == nil {
            phase = .idle
        }
    }

    private func configureDelegatesAndThermalMonitoring() {
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
              phase == .scanning
                || phase == .relocalizing
                || phase == .relocalizationFailed else { return }

        fairThermalPauseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self,
                  !Task.isCancelled,
                  self.thermalState == .fair,
                  self.phase == .scanning
                    || self.phase == .relocalizing
                    || self.phase == .relocalizationFailed else {
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
        case .relocalizing, .relocalizationFailed:
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
        manualVisualResumeUnlockTask?.cancel()
        isManualVisualResumeAvailable = false
        isPreparingManualVisualResume = false
        stopReason = .userFinished
        rawRoomData = nil
        latestRoomSnapshot = nil
        latestWallReference = nil
        latestWallReferenceImageData = nil
        latestWallReferenceGeographicReference = nil
        lastReferencePairCapturedAt = .distantPast
        pendingWorldMapTask?.cancel()
        pendingWorldMapTask = nil
        relocalizationFailureMessage = ""
        relocalizationEvidenceMessage = ""
        relocalizationProgress = 1
        isCompletingRelocalization = false
        phase = .scanning
        if !roomCaptureSessionIsRunning {
            let captureView = prepareRoomCaptureViewForCurrentSession()
            captureView.captureSession.run(configuration: configuration)
            roomCaptureSessionIsRunning = true
        }
        isStartingCapture = false
        applyThermalPolicy()
    }

    private func prepareRoomCaptureViewForCurrentSession() -> RoomCaptureView {
        if let roomCaptureView {
            captureHostView.showCaptureView(roomCaptureView)
            return roomCaptureView
        }

        // Apple requires a custom ARSession to be running before it is handed
        // to RoomPlan. For a restored scan the session is already relocalized;
        // for a brand-new scan start a normal world-tracking session first.
        if arSession.currentFrame == nil {
            let baseConfiguration = ARWorldTrackingConfiguration()
            baseConfiguration.planeDetection = [.horizontal, .vertical]
            arSession.run(baseConfiguration, options: [])
        }

        let captureView = RoomCaptureView(frame: .zero, arSession: arSession)
        captureView.delegate = self
        captureView.captureSession.delegate = self
        roomCaptureView = captureView
        captureHostView.showCaptureView(captureView)
        return captureView
    }

    private func prepareBareSessionForRelocalization() {
        if let roomCaptureView, roomCaptureSessionIsRunning {
            roomCaptureView.captureSession.stop(pauseARSession: true)
        }
        roomCaptureSessionIsRunning = false
        roomCaptureView = nil
        captureHostView.showRelocalizationPreview()
        arSession.delegate = self
    }

    private func stopCapture(reason: StopReason) {
        guard phase == .scanning else { return }
        stopReason = reason

        // Manual pause keeps the same ARSession running (see stop below with
        // pauseARSession: false), so immediate resume can continue directly.
        // Background and thermal pauses must use the persisted ARWorldMap path.
        switch reason {
        case .manualPause:
            liveSessionContinuityAvailable = arSession.currentFrame != nil
        case .userFinished, .thermalSafety, .applicationBackground:
            liveSessionContinuityAvailable = false
        }

        let frame = arSession.currentFrame
        let currentWallReference = latestRoomSnapshot.flatMap {
            makeWallReference(from: $0, frame: frame)
        }
        pendingWallReference = currentWallReference ?? latestWallReference

        // Always keep the final camera frame, even if RoomPlan has not emitted
        // a reliable wall yet. The frame is the visual fallback reference and
        // the camera transform is what lets a fresh AR session be aligned back
        // into the persistent project coordinate space.
        if let currentImageData = captureReferenceImageData(from: frame) {
            pendingReferenceImageData = currentImageData
            pendingReferenceCameraTransform = frame?.camera.transform.columnMajorValues
                ?? currentWallReference?.cameraTransform
        } else {
            pendingReferenceImageData = latestWallReferenceImageData
            pendingReferenceCameraTransform = latestWallReference?.cameraTransform
        }
        pendingGeographicReference = referenceSensor.snapshot()
            ?? latestWallReferenceGeographicReference

        pendingWorldMapTask?.cancel()
        let fallbackMap = cachedGoodWorldMap
        let fallbackQuality = cachedGoodWorldMapQuality
        let fallbackDate = cachedGoodWorldMapCapturedAt
        let anchorTransform = pendingWallReference?.wallMatrix
            ?? frame?.camera.transform
        pendingWorldMapTask = Task { @MainActor [weak self] in
            guard let self else { return nil }
            let currentQuality = self.worldMapQuality(
                for: self.arSession.currentFrame?.worldMappingStatus
            )
            let currentMap = try? await self.currentWorldMap()

            var candidates: [(map: ARWorldMap, quality: SpatialWorldMapQuality, date: Date)] = []
            if currentQuality.isSuitableForResume, let currentMap {
                candidates.append((currentMap, currentQuality, Date()))
            }
            if let fallbackMap,
               let fallbackQuality,
               fallbackQuality.isSuitableForResume {
                candidates.append((fallbackMap, fallbackQuality, fallbackDate ?? Date()))
            }

            // Never persist a limited/not-available map as resumable. When two
            // suitable snapshots exist, prefer mapped over extending and then
            // the map with the richer feature cloud.
            guard let selected = candidates.max(by: { lhs, rhs in
                if lhs.quality.reliabilityRank != rhs.quality.reliabilityRank {
                    return lhs.quality.reliabilityRank < rhs.quality.reliabilityRank
                }
                return lhs.map.rawFeaturePoints.points.count
                    < rhs.map.rawFeaturePoints.points.count
            }) else { return nil }
            let selectedMap = selected.map
            let selectedQuality = selected.quality
            let capturedAt = selected.date
            if let anchorTransform {
                var anchors = selectedMap.anchors
                anchors.removeAll { $0.name == self.resumeAnchorName }
                anchors.append(
                    ARAnchor(name: self.resumeAnchorName, transform: anchorTransform)
                )
                selectedMap.anchors = anchors
            }
            let extent = selectedMap.extent
            return WorldMapCapture(
                worldMap: selectedMap,
                quality: selectedQuality,
                capturedAt: capturedAt,
                featurePointCount: selectedMap.rawFeaturePoints.points.count,
                extent: [extent.x, extent.y, extent.z]
            )
        }
        phase = .processing
        guard let roomCaptureView else {
            phase = .failed("تعذر الوصول إلى جلسة RoomPlan الحالية لحفظ المسح.")
            return
        }
        roomCaptureView.captureSession.stop(pauseARSession: false)
        roomCaptureSessionIsRunning = false
    }

    private func pauseRelocalization(reason: SpatialScanPauseReason) {
        liveSessionContinuityAvailable = false
        relocalizationTimeoutTask?.cancel()
        manualVisualResumeUnlockTask?.cancel()
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
        var state = savedProject.scanContinuationState
            ?? SpatialScanContinuationState(reason: reason)
        state.reason = reason
        state.pausedAt = Date()
        savedProject.scanContinuationState = state
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
        liveSessionContinuityAvailable = false
        fairThermalPauseTask?.cancel()
        fairThermalPauseTask = nil
        relocalizationTimeoutTask?.cancel()
        manualVisualResumeUnlockTask?.cancel()
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

    private var canResumeUsingLiveSession: Bool {
        guard liveSessionContinuityAvailable,
              project?.scanContinuationState?.reason == .manual,
              let frame = arSession.currentFrame else { return false }

        switch frame.camera.trackingState {
        case .normal:
            return true
        case .limited(.relocalizing), .limited(.initializing), .notAvailable:
            return false
        case .limited(.excessiveMotion), .limited(.insufficientFeatures):
            // The coordinate space is still the same live session. RoomPlan can
            // resume and tracking can recover as the user moves the device.
            return true
        @unknown default:
            return false
        }
    }

    private func resumeUsingLiveSession() {
        guard canResumeUsingLiveSession else {
            beginRelocalization()
            return
        }

        relocalizationTimeoutTask?.cancel()
        relocalizationFailureMessage = ""
        relocalizationEvidenceMessage =
            "تم الحفاظ على جلسة AR الأصلية؛ لا حاجة لإعادة التعرف على المكان."
        relocalizationProgress = 1
        liveSessionContinuityAvailable = false
        startCaptureSession()
    }

    private func beginRelocalization() {
        liveSessionContinuityAvailable = false
        guard let project else {
            relocalizationFailureMessage = "لا يوجد مشروع محفوظ للاستكمال."
            phase = .relocalizationFailed
            return
        }

        let continuation = project.scanContinuationState
        referenceWallSummary = continuationReferenceSummary(continuation)
        referenceWallImage = loadReferenceImage(
            projectID: project.id,
            fileName: continuation?.referenceImageFile
        )
        referenceWallEdgeImage = referenceWallImage.flatMap {
            makeReferenceEdgeImage(from: $0)
        }
        referenceSensor.start(
            enabled: useOptionalLocationAssist,
            requestPermission: true
        )
        referenceAnchorRestored = continuation?.referenceAnchorName == nil
        stableTrackingFrameCount = 0
        stableWallMatchFrameCount = 0
        latestWallMatchScore = 0
        lastWallMatchUpdateAt = .distantPast
        latestHeadingPass = true
        latestLocationPass = true
        relocalizationProgress = 0
        visualAlignmentConfidence = .low
        isCompletingRelocalization = false
        isPreparingManualVisualResume = false
        isManualVisualResumeAvailable = false
        activeIncomingWorldTransform = continuation?.worldToProjectTransform.map {
            simd_float4x4(columnMajorValues: $0)
        }
        relocalizationEvidenceMessage = savedWorldMapDetail.map {
            "جارٍ البحث عن آخر حائط مسجل. • \($0)"
        } ?? "استخدم الصورة الشفافة لمطابقة آخر موضع توقف."
        locationAssistMessage = locationAssistDescription(
            savedReference: continuation?.geographicReference,
            currentReference: referenceSensor.snapshot()
        )

        prepareBareSessionForRelocalization()
        let trackingConfiguration = ARWorldTrackingConfiguration()
        trackingConfiguration.planeDetection = [.horizontal, .vertical]

        var loadedSavedWorldMap = false
        if let worldMapFile = project.worldMapFile,
           let worldMap = try? ProjectRepository.loadWorldMap(
            projectID: project.id,
            fileName: worldMapFile
           ) {
            trackingConfiguration.initialWorldMap = worldMap
            loadedSavedWorldMap = true
        }

        let hasVisualFallback = referenceWallImage != nil
            && savedReferenceCameraTransformValues?.count == 16
        guard loadedSavedWorldMap || hasVisualFallback else {
            relocalizationFailureMessage =
                "لا توجد خريطة AR أو لقطة كاميرا صالحة للاستكمال. الجزء المحفوظ ما زال موجودًا."
            phase = .relocalizationFailed
            return
        }

        arSession.delegate = self
        relocalizationMessage = loadedSavedWorldMap
            ? "طابق الصورة الشفافة مع آخر حائط بينما يحاول التطبيق استعادة خريطة المكان."
            : "لا توجد خريطة AR صالحة؛ طابق الصورة الشفافة ثم استخدم الاستكمال البصري."
        phase = .relocalizing
        arSession.run(
            trackingConfiguration,
            options: [.resetTracking, .removeExistingAnchors]
        )

        scheduleManualVisualResumeUnlock(immediate: !loadedSavedWorldMap)
        if loadedSavedWorldMap {
            scheduleRelocalizationTimeout()
        }
        applyThermalPolicy()
    }

    private func scheduleManualVisualResumeUnlock(immediate: Bool) {
        manualVisualResumeUnlockTask?.cancel()
        guard referenceWallImage != nil,
              savedReferenceCameraTransformValues?.count == 16 else {
            isManualVisualResumeAvailable = false
            return
        }

        if immediate {
            isManualVisualResumeAvailable = true
            return
        }

        let delay: Int
        switch relocalizationStrictness {
        case .strict: delay = 15
        case .balanced: delay = 8
        case .flexible: delay = 3
        }
        manualVisualResumeUnlockTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self,
                  !Task.isCancelled,
                  self.phase == .relocalizing else { return }
            self.isManualVisualResumeAvailable = true
        }
    }

    private func scheduleRelocalizationTimeout() {
        relocalizationTimeoutTask?.cancel()
        let timeout = relocalizationStrictness.timeoutSeconds
        relocalizationTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self, self.phase == .relocalizing else { return }
            self.isManualVisualResumeAvailable = self.referenceWallImage != nil
                && self.savedReferenceCameraTransformValues?.count == 16
            self.relocalizationFailureMessage =
                "لم يكتمل تطابق خريطة المكان وآخر حائط خلال \(timeout) ثانية. "
                    + "الكاميرا ما زالت تعمل: طابق الصورة الشفافة مع الواقع ثم "
                    + "استخدم الاستكمال البصري، أو أعد محاولة التعرف التلقائي."
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
                self.relocalizationMessage =
                    "خريطة AR متطابقة. ثبّت الهاتف على الحائط المرجعي للتأكيد."
            case .limited(.relocalizing):
                self.relocalizationMessage =
                    "حرّك الهاتف ببطء نحو آخر حائط، وابدأ من نفس زاوية الصورة المرجعية."
            case .limited(.insufficientFeatures):
                self.relocalizationMessage =
                    "وجّه الكاميرا إلى باب أو فتحة أو حواف واضحة داخل الحائط المرجعي."
            case .limited(.excessiveMotion):
                self.relocalizationMessage = "حرّك الهاتف ببطء وثبات حتى يثبت التطابق."
            case .limited(.initializing):
                self.relocalizationMessage = "جارٍ تجهيز الكاميرا وخريطة المكان…"
            case .notAvailable:
                self.relocalizationMessage = "التتبع غير متاح مؤقتًا."
            @unknown default:
                self.relocalizationMessage = "جارٍ محاولة التعرف على المكان…"
            }
        }
    }

    nonisolated func session(
        _ session: ARSession,
        didUpdate frame: ARFrame
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.phase == .relocalizing {
                self.evaluateRelocalizationEvidence(frame: frame)
            } else if self.phase == .relocalizationFailed {
                self.updateVisualAlignmentConfidence(frame: frame)
            }
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.liveSessionContinuityAvailable = false
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak self] in
            // Do not silently mark continuity as valid again. A saved world map
            // must re-establish the coordinate system after an interruption.
            self?.liveSessionContinuityAvailable = false
        }
    }

    nonisolated func session(
        _ session: ARSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.liveSessionContinuityAvailable = false
        }
    }

    nonisolated func session(
        _ session: ARSession,
        didAdd anchors: [ARAnchor]
    ) {
        Task { @MainActor [weak self] in
            self?.handleRelocalizationAnchors(anchors)
        }
    }

    nonisolated func session(
        _ session: ARSession,
        didUpdate anchors: [ARAnchor]
    ) {
        Task { @MainActor [weak self] in
            self?.handleRelocalizationAnchors(anchors)
        }
    }

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didUpdate room: CapturedRoom
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.latestRoomSnapshot = room
            let frame = self.arSession.currentFrame
            if let reference = self.makeWallReference(from: room, frame: frame) {
                self.latestWallReference = reference
                if Date().timeIntervalSince(self.lastReferencePairCapturedAt) >= 0.75,
                   let imageData = self.captureReferenceImageData(from: frame) {
                    self.latestWallReferenceImageData = imageData
                    self.latestWallReferenceGeographicReference = self.referenceSensor.snapshot()
                    self.lastReferencePairCapturedAt = Date()
                }
            }
            self.cacheGoodWorldMapIfNeeded()
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
                var state = savedProject.scanContinuationState
                    ?? SpatialScanContinuationState(reason: .interrupted)
                state.reason = .interrupted
                state.pausedAt = Date()
                savedProject.scanContinuationState = state
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
                    includeFurniture: includeFurniture,
                    incomingWorldTransform: activeIncomingWorldTransform
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

            let capturedWorldMap: WorldMapCapture?
            if let pendingWorldMapTask {
                capturedWorldMap = await pendingWorldMapTask.value
            } else if let current = try? await currentWorldMap() {
                let currentQuality = worldMapQuality(
                    for: arSession.currentFrame?.worldMappingStatus
                )
                if currentQuality.isSuitableForResume {
                    let extent = current.extent
                    capturedWorldMap = WorldMapCapture(
                        worldMap: current,
                        quality: currentQuality,
                        capturedAt: Date(),
                        featurePointCount: current.rawFeaturePoints.points.count,
                        extent: [extent.x, extent.y, extent.z]
                    )
                } else {
                    capturedWorldMap = nil
                }
            } else {
                capturedWorldMap = nil
            }
            pendingWorldMapTask = nil
            var worldMapCapturedAt: Date?
            var resolvedWorldMapQuality = savedProject.scanContinuationState?.worldMapQuality
            var worldMapFeaturePointCount = savedProject.scanContinuationState?.worldMapFeaturePointCount
            var worldMapExtent = savedProject.scanContinuationState?.worldMapExtent
            if let capturedWorldMap,
               let fileName = try? ProjectRepository.saveWorldMap(
                capturedWorldMap.worldMap,
                projectID: savedProject.id
               ) {
                savedProject.worldMapFile = fileName
                worldMapCapturedAt = capturedWorldMap.capturedAt
                resolvedWorldMapQuality = capturedWorldMap.quality
                worldMapFeaturePointCount = capturedWorldMap.featurePointCount
                worldMapExtent = capturedWorldMap.extent
            }

            var referenceImageFile = savedProject.scanContinuationState?.referenceImageFile
            if stopReason.continuationReason != nil,
               let data = pendingReferenceImageData,
               let fileName = try? saveReferenceImageData(
                data,
                projectID: savedProject.id
               ) {
                referenceImageFile = fileName
            }

            if let continuationReason = stopReason.continuationReason {
                savedProject.scanContinuationState = SpatialScanContinuationState(
                    reason: continuationReason,
                    worldMapCapturedAt: worldMapCapturedAt
                        ?? savedProject.scanContinuationState?.worldMapCapturedAt,
                    worldMapQuality: resolvedWorldMapQuality
                        ?? savedProject.scanContinuationState?.worldMapQuality,
                    worldMapFeaturePointCount: worldMapFeaturePointCount
                        ?? savedProject.scanContinuationState?.worldMapFeaturePointCount,
                    worldMapExtent: worldMapExtent
                        ?? savedProject.scanContinuationState?.worldMapExtent,
                    referenceWall: pendingWallReference
                        ?? savedProject.scanContinuationState?.referenceWall,
                    referenceImageFile: referenceImageFile,
                    referenceCameraTransform: pendingReferenceCameraTransform
                        ?? pendingWallReference?.cameraTransform
                        ?? savedProject.scanContinuationState?.referenceCameraTransform,
                    worldToProjectTransform: activeIncomingWorldTransform?.columnMajorValues
                        ?? savedProject.scanContinuationState?.worldToProjectTransform,
                    geographicReference: pendingGeographicReference
                        ?? savedProject.scanContinuationState?.geographicReference,
                    referenceAnchorName: resumeAnchorName
                )
            } else {
                ProjectRepository.removeAsset(
                    projectID: savedProject.id,
                    fileName: referenceImageFile
                )
                savedProject.scanContinuationState = nil
            }
            try ProjectRepository.save(savedProject)

            rawRoomData = nil
            latestRoomSnapshot = nil
            latestWallReference = nil
            latestWallReferenceImageData = nil
            latestWallReferenceGeographicReference = nil
            pendingWallReference = nil
            pendingReferenceImageData = nil
            pendingReferenceCameraTransform = nil
            pendingGeographicReference = nil
            project = savedProject
            referenceWallSummary = continuationReferenceSummary(
                savedProject.scanContinuationState
            )

            switch stopReason {
            case .userFinished:
                phase = .ready
            case .manualPause, .applicationBackground:
                phase = .paused
            case .thermalSafety:
                enterCoolingDown(context: .scanningSaved)
            }
        } catch {
            liveSessionContinuityAvailable = false
            rawRoomData = nil
            pendingWorldMapTask?.cancel()
            pendingWorldMapTask = nil
            phase = .failed("فشل حفظ نتيجة المسح: \(error.localizedDescription)")
        }
    }

    private func worldMapQuality(
        for status: ARFrame.WorldMappingStatus?
    ) -> SpatialWorldMapQuality {
        guard let status else { return .notAvailable }
        switch status {
        case .notAvailable:
            return SpatialWorldMapQuality.notAvailable
        case .limited:
            return SpatialWorldMapQuality.limited
        case .extending:
            return SpatialWorldMapQuality.extending
        case .mapped:
            return SpatialWorldMapQuality.mapped
        @unknown default:
            return SpatialWorldMapQuality.limited
        }
    }

    private func cacheGoodWorldMapIfNeeded() {
        guard phase == .scanning,
              worldMapCacheTask == nil,
              let frame = arSession.currentFrame else { return }
        let quality = worldMapQuality(for: frame.worldMappingStatus)
        guard quality.isSuitableForResume,
              Date().timeIntervalSince(lastWorldMapCacheRequestAt) >= 5 else {
            return
        }

        lastWorldMapCacheRequestAt = Date()
        worldMapCacheTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.worldMapCacheTask = nil }
            guard let map = try? await self.currentWorldMap(),
                  self.phase == .scanning else { return }
            self.cachedGoodWorldMap = map
            self.cachedGoodWorldMapCapturedAt = Date()
            self.cachedGoodWorldMapQuality = quality
        }
    }

    private func makeWallReference(
        from room: CapturedRoom,
        frame: ARFrame?
    ) -> SpatialWallReference? {
        guard !room.walls.isEmpty else { return nil }

        let selectedWall: CapturedRoom.Surface
        if let frame {
            let cameraTransform = frame.camera.transform
            let cameraPosition = translation(of: cameraTransform)
            let cameraForward = normalized(
                -SIMD3(
                    cameraTransform.columns.2.x,
                    cameraTransform.columns.2.y,
                    cameraTransform.columns.2.z
                )
            )

            let candidates = room.walls.map { wall in
                (
                    wall: wall,
                    score: wallVisibilityScore(
                        wall: wall,
                        cameraPosition: cameraPosition,
                        cameraForward: cameraForward
                    )
                )
            }
            guard let best = candidates.max(by: { $0.score < $1.score }),
                  best.score >= 0.55 else {
                return nil
            }
            selectedWall = best.wall
        } else {
            selectedWall = room.walls[room.walls.count - 1]
        }

        let allOpenings: [(CapturedRoom.Surface, SurfaceSnapshot.Kind)] =
            room.doors.map { ($0, .door) }
                + room.windows.map { ($0, .window) }
                + room.openings.map { ($0, .opening) }
        let inverseWall = simd_inverse(selectedWall.transform)
        let wallWidth = max(selectedWall.dimensions.x, 0.01)
        let wallHeight = max(selectedWall.dimensions.y, 0.01)
        let openingReferences = allOpenings.compactMap {
            surface, kind -> SpatialOpeningReference? in
            let center = surface.transform.columns.3
            let local = inverseWall * center
            guard abs(local.z) <= 0.40,
                  abs(local.x) <= wallWidth / 2 + 0.45,
                  abs(local.y) <= wallHeight / 2 + 0.45 else {
                return nil
            }
            return SpatialOpeningReference(
                kind: kind,
                centerXRatio: min(max(local.x / wallWidth, -0.5), 0.5),
                widthRatio: min(max(surface.dimensions.x / wallWidth, 0), 1),
                heightRatio: min(max(surface.dimensions.y / wallHeight, 0), 1)
            )
        }
        .sorted { $0.centerXRatio < $1.centerXRatio }

        return SpatialWallReference(
            wallID: selectedWall.identifier,
            width: selectedWall.dimensions.x,
            height: selectedWall.dimensions.y,
            transform: selectedWall.transform.columnMajorValues,
            cameraTransform: frame?.camera.transform.columnMajorValues,
            openings: openingReferences,
            capturedAt: Date()
        )
    }

    private func wallVisibilityScore(
        wall: CapturedRoom.Surface,
        cameraPosition: SIMD3<Float>,
        cameraForward: SIMD3<Float>
    ) -> Float {
        let wallPosition = translation(of: wall.transform)
        let vector = wallPosition - cameraPosition
        let distance = max(simd_length(vector), 0.001)
        let direction = vector / distance
        let forwardScore = simd_dot(cameraForward, direction)
        let wallNormal = normalized(
            SIMD3(
                wall.transform.columns.2.x,
                wall.transform.columns.2.y,
                wall.transform.columns.2.z
            )
        )
        let facingScore = abs(simd_dot(wallNormal, direction))
        return forwardScore * 2 + facingScore - distance * 0.04
    }

    private func captureReferenceImageData(from frame: ARFrame?) -> Data? {
        guard let frame else { return nil }
        let source = CIImage(cvPixelBuffer: frame.capturedImage)
            .oriented(.right)
        guard let cgImage = imageContext.createCGImage(
            source,
            from: source.extent
        ) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.72)
    }

    private func saveReferenceImageData(
        _ data: Data,
        projectID: UUID
    ) throws -> String {
        let url = try ProjectRepository.assetURL(
            projectID: projectID,
            fileName: referenceImageFileName,
            createProjectDirectory: true
        )
        try data.write(to: url, options: .atomic)
        return referenceImageFileName
    }

    private func loadReferenceImage(
        projectID: UUID,
        fileName: String?
    ) -> UIImage? {
        guard let fileName,
              let url = try? ProjectRepository.assetURL(
                projectID: projectID,
                fileName: fileName
              ) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func makeReferenceEdgeImage(from image: UIImage) -> UIImage? {
        guard let source = CIImage(image: image) else { return nil }
        let edges = source
            .applyingFilter(
                "CIEdges",
                parameters: [kCIInputIntensityKey: 7.0]
            )
            .applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputSaturationKey: 0,
                    kCIInputContrastKey: 1.8,
                    kCIInputBrightnessKey: 0.10
                ]
            )
        guard let cgImage = imageContext.createCGImage(
            edges,
            from: source.extent
        ) else { return nil }
        return UIImage(
            cgImage: cgImage,
            scale: image.scale,
            orientation: image.imageOrientation
        )
    }

    private func handleRelocalizationAnchors(_ anchors: [ARAnchor]) {
        guard phase == .relocalizing else { return }
        if anchors.contains(where: { $0.name == resumeAnchorName }) {
            referenceAnchorRestored = true
        }

        let verticalPlanes = anchors.compactMap { $0 as? ARPlaneAnchor }
            .filter { $0.alignment == .vertical }
        guard !verticalPlanes.isEmpty else { return }
        updateWallMatch(using: verticalPlanes)
    }

    private func updateWallMatch(using planes: [ARPlaneAnchor]) {
        guard let reference = project?.scanContinuationState?.referenceWall,
              let frame = arSession.currentFrame else {
            latestWallMatchScore = 1
            stableWallMatchFrameCount = relocalizationStrictness.stableFrameCount
            lastWallMatchUpdateAt = Date()
            return
        }

        let cameraTransform = frame.camera.transform
        let cameraPosition = translation(of: cameraTransform)
        let cameraForward = normalized(
            -SIMD3(
                cameraTransform.columns.2.x,
                cameraTransform.columns.2.y,
                cameraTransform.columns.2.z
            )
        )
        let referenceMatrix = reference.wallMatrix
        let referenceCenter = translation(of: referenceMatrix)
        let referenceNormal = normalized(
            SIMD3(
                referenceMatrix.columns.2.x,
                referenceMatrix.columns.2.y,
                referenceMatrix.columns.2.z
            )
        )
        let centerTolerance = relocalizationStrictness.wallCenterToleranceMeters
        let normalTolerance = relocalizationStrictness.wallNormalToleranceDegrees

        let best = planes.compactMap { plane -> (Double, String)? in
            let centerLocal = SIMD4<Float>(
                plane.center.x,
                plane.center.y,
                plane.center.z,
                1
            )
            let centerWorld4 = plane.transform * centerLocal
            let centerWorld = SIMD3(
                centerWorld4.x,
                centerWorld4.y,
                centerWorld4.z
            )
            let vector = centerWorld - cameraPosition
            let distanceFromCamera = simd_length(vector)
            guard distanceFromCamera >= 0.25,
                  distanceFromCamera <= 7.5 else { return nil }
            let direction = vector / max(distanceFromCamera, 0.001)
            guard simd_dot(cameraForward, direction) >= 0.18 else { return nil }

            let detectedNormal = normalized(
                SIMD3(
                    plane.transform.columns.1.x,
                    plane.transform.columns.1.y,
                    plane.transform.columns.1.z
                )
            )
            let normalDot = min(max(abs(simd_dot(referenceNormal, detectedNormal)), 0), 1)
            let normalDifference = acos(normalDot) * 180 / Float.pi
            let centerDistance = simd_distance(referenceCenter, centerWorld)
            guard centerDistance <= centerTolerance * 1.25,
                  normalDifference <= normalTolerance * 1.35 else {
                return nil
            }

            let detectedWidth = max(plane.planeExtent.width, 0.01)
            let detectedHeight = max(plane.planeExtent.height, 0.01)
            let widthScore = dimensionMatchScore(
                detected: detectedWidth,
                reference: reference.width
            )
            let heightScore = dimensionMatchScore(
                detected: detectedHeight,
                reference: reference.height
            )
            let dimensionScore = widthScore * 0.58 + heightScore * 0.42
            let centerScore = max(0, 1 - centerDistance / max(centerTolerance, 0.01))
            let normalScore = max(0, 1 - normalDifference / max(normalTolerance, 1))
            let score = Double(
                dimensionScore * 0.40
                    + centerScore * 0.35
                    + normalScore * 0.25
            )
            let description = "المكتشف: \(Int((detectedWidth * 100).rounded())) × "
                + "\(Int((detectedHeight * 100).rounded())) سم"
                + " • فرق الموضع \(Int((centerDistance * 100).rounded())) سم"
                + " • فرق الاتجاه \(Int(normalDifference.rounded()))°"
            return (score, description)
        }
        .max { $0.0 < $1.0 }

        lastWallMatchUpdateAt = Date()
        if let best {
            latestWallMatchScore = best.0
            latestDetectedWallDescription = best.1
        } else {
            latestWallMatchScore = 0
            latestDetectedWallDescription =
                "لم يُكتشف الحائط نفسه في موضعه واتجاهه المسجلين بعد."
        }
    }

    private func dimensionMatchScore(
        detected: Float,
        reference: Float
    ) -> Float {
        guard reference > 0.05 else { return 0 }
        let ratio = detected / reference
        let tolerance = relocalizationStrictness.wallDimensionToleranceRatio
        let minimumCoverage = relocalizationStrictness.minimumDetectedWallCoverage

        if ratio > 1 + tolerance {
            let excess = (ratio - 1 - tolerance) / max(0.50, tolerance * 2)
            return max(0, 1 - excess)
        }
        if ratio < minimumCoverage {
            return max(0, ratio / minimumCoverage * 0.55)
        }
        return min(1, 0.55 + (ratio - minimumCoverage)
            / max(1 - minimumCoverage, 0.01) * 0.45)
    }

    private func evaluateRelocalizationEvidence(frame: ARFrame) {
        guard phase == .relocalizing else { return }

        if case .normal = frame.camera.trackingState {
            stableTrackingFrameCount += 1
        } else {
            stableTrackingFrameCount = max(0, stableTrackingFrameCount - 2)
        }

        if Date().timeIntervalSince(lastWallMatchUpdateAt) > 2.0,
           project?.scanContinuationState?.referenceWall != nil {
            latestWallMatchScore = 0
            latestDetectedWallDescription = "جارٍ تثبيت قياس وموضع الحائط الحالي."
        }

        let wallThreshold: Double
        switch relocalizationStrictness {
        case .strict: wallThreshold = 0.80
        case .balanced: wallThreshold = 0.66
        case .flexible: wallThreshold = 0.48
        }
        if project?.scanContinuationState?.referenceWall == nil
            || latestWallMatchScore >= wallThreshold {
            stableWallMatchFrameCount += 1
        } else {
            stableWallMatchFrameCount = max(0, stableWallMatchFrameCount - 1)
        }

        let savedGeo = project?.scanContinuationState?.geographicReference
        let currentGeo = referenceSensor.snapshot()
        let geographicResult = evaluateGeographicEvidence(
            saved: savedGeo,
            current: currentGeo
        )
        latestLocationPass = geographicResult.locationPass
        latestHeadingPass = geographicResult.headingPass
        locationAssistMessage = geographicResult.message

        let required = relocalizationStrictness.stableFrameCount
        let trackingReady = stableTrackingFrameCount >= required
        let wallReady = stableWallMatchFrameCount >= required
        let anchorRequired = project?.scanContinuationState?.referenceAnchorName != nil
        let anchorReady = referenceAnchorRestored || !anchorRequired
        let geographyReady = latestLocationPass && latestHeadingPass

        let trackingProgress = min(Double(stableTrackingFrameCount) / Double(required), 1)
        let wallProgress = project?.scanContinuationState?.referenceWall == nil
            ? 1
            : min(Double(stableWallMatchFrameCount) / Double(required), 1)
        let anchorProgress = anchorReady ? 1.0 : 0.0
        let geographyProgress = geographyReady ? 1.0 : 0.0
        relocalizationProgress = min(
            trackingProgress * 0.45
                + wallProgress * 0.30
                + anchorProgress * 0.15
                + geographyProgress * 0.10,
            1
        )

        var evidence: [String] = []
        evidence.append(trackingReady ? "خريطة AR: متطابقة" : "خريطة AR: جارٍ التثبيت")
        if project?.scanContinuationState?.referenceWall != nil {
            evidence.append(
                wallReady
                    ? "أبعاد الحائط: متطابقة"
                    : "أبعاد الحائط: \(Int((latestWallMatchScore * 100).rounded()))%"
            )
        }
        if anchorRequired {
            evidence.append(anchorReady ? "المرجع المكاني: موجود" : "المرجع المكاني: جارٍ البحث")
        }
        if !latestDetectedWallDescription.isEmpty {
            evidence.append(latestDetectedWallDescription)
        }
        relocalizationEvidenceMessage = evidence.joined(separator: " • ")
        updateVisualAlignmentConfidence(frame: frame)

        let canContinue: Bool
        let stableTrackingFallback = stableTrackingFrameCount >= max(required * 3, 18)
        switch relocalizationStrictness {
        case .strict:
            // ARKit returning to normal is the authoritative proof that the
            // saved coordinate space has been restored. Strict mode also asks
            // for either the saved anchor or the reference wall, plus reliable
            // geographic evidence when it exists.
            canContinue = trackingReady
                && (wallReady || anchorReady)
                && geographyReady
        case .balanced:
            // Plane anchors and the custom anchor are supporting evidence only;
            // they can appear late or be regenerated differently by ARKit.
            // Sustained normal tracking is therefore an accepted fallback.
            canContinue = trackingReady
                && (wallReady || anchorReady || stableTrackingFallback)
        case .flexible:
            // A normal tracking state after loading initialWorldMap already
            // means ARKit reconciled the saved world coordinate system.
            canContinue = trackingReady
        }

        guard canContinue, !isCompletingRelocalization else { return }
        isCompletingRelocalization = true
        relocalizationMessage = "تم تأكيد المكان والحائط. جارٍ استئناف RoomPlan…"
        relocalizationTimeoutTask?.cancel()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(550))
            guard let self, self.phase == .relocalizing else { return }
            self.startCaptureSession()
        }
    }

    private func updateVisualAlignmentConfidence(frame: ARFrame) {
        let trackingNormal: Bool
        switch frame.camera.trackingState {
        case .normal:
            trackingNormal = true
        default:
            trackingNormal = false
        }

        if trackingNormal,
           latestWallMatchScore >= 0.62,
           latestLocationPass,
           latestHeadingPass {
            visualAlignmentConfidence = .high
        } else if trackingNormal || latestWallMatchScore >= 0.35 {
            visualAlignmentConfidence = .medium
        } else {
            visualAlignmentConfidence = .low
        }
    }

    private func evaluateGeographicEvidence(
        saved: SpatialGeographicReference?,
        current: SpatialGeographicReference?
    ) -> (locationPass: Bool, headingPass: Bool, message: String) {
        guard useOptionalLocationAssist else {
            return (true, true, "مساعدة الموقع والاتجاه غير مفعلة.")
        }
        guard let saved else {
            return (true, true, "لا يوجد مرجع موقع سابق؛ لن يمنع ذلك الاستكمال.")
        }
        guard let current else {
            return (true, true, "الموقع أو الاتجاه غير متاح الآن؛ الاعتماد على AR والحائط فقط.")
        }

        var locationPass = true
        var headingPass = true
        var messages: [String] = []

        if saved.hasUsableLocation,
           current.hasUsableLocation,
           let savedLatitude = saved.latitude,
           let savedLongitude = saved.longitude,
           let currentLatitude = current.latitude,
           let currentLongitude = current.longitude {
            let savedLocation = CLLocation(
                latitude: savedLatitude,
                longitude: savedLongitude
            )
            let currentLocation = CLLocation(
                latitude: currentLatitude,
                longitude: currentLongitude
            )
            let distance = currentLocation.distance(from: savedLocation)
            let accuracyAllowance = max(
                saved.horizontalAccuracyMeters ?? 0,
                current.horizontalAccuracyMeters ?? 0
            )
            let limit = relocalizationStrictness.locationDistanceLimitMeters
                + accuracyAllowance
            locationPass = distance <= limit
            messages.append(
                locationPass
                    ? "الموقع التقريبي متوافق"
                    : "الموقع يختلف بنحو \(Int(distance.rounded())) م"
            )
        } else {
            messages.append("الموقع غير دقيق وتم تجاهله")
        }

        if saved.hasUsableHeading,
           current.hasUsableHeading,
           let savedHeading = saved.headingDegrees,
           let currentHeading = current.headingDegrees {
            let difference = angularDifference(savedHeading, currentHeading)
            headingPass = difference <= relocalizationStrictness.headingToleranceDegrees
            messages.append(
                headingPass
                    ? "الاتجاه \(cardinalDirection(currentHeading)) متوافق"
                    : "اتجاه الهاتف مختلف \(Int(difference.rounded()))°"
            )
        } else {
            messages.append("اتجاه البوصلة غير موثوق وتم تجاهله")
        }

        return (locationPass, headingPass, messages.joined(separator: " • "))
    }

    private func continuationReferenceSummary(
        _ continuation: SpatialScanContinuationState?
    ) -> String {
        guard let continuation else { return "" }
        var parts: [String] = []
        if let wall = continuation.referenceWall {
            parts.append(wall.summary)
        }
        if let geographic = continuation.geographicReference,
           geographic.hasUsableHeading,
           let heading = geographic.headingDegrees {
            parts.append("اتجاه الالتقاط: \(cardinalDirection(heading))")
        }
        return parts.joined(separator: " • ")
    }

    private func locationAssistDescription(
        savedReference: SpatialGeographicReference?,
        currentReference: SpatialGeographicReference?
    ) -> String {
        evaluateGeographicEvidence(
            saved: savedReference,
            current: currentReference
        ).message
    }

    private func angularDifference(_ first: Double, _ second: Double) -> Double {
        let difference = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    private func cardinalDirection(_ heading: Double) -> String {
        let normalizedHeading = (heading.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        switch normalizedHeading {
        case 22.5..<67.5:
            return "شمال شرقي"
        case 67.5..<112.5:
            return "شرق"
        case 112.5..<157.5:
            return "جنوب شرقي"
        case 157.5..<202.5:
            return "جنوب"
        case 202.5..<247.5:
            return "جنوب غربي"
        case 247.5..<292.5:
            return "غرب"
        case 292.5..<337.5:
            return "شمال غربي"
        default:
            return "شمال"
        }
    }

    private func translation(of matrix: simd_float4x4) -> SIMD3<Float> {
        SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }

    private func normalized(_ vector: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(vector)
        return length > 0.0001 ? vector / length : SIMD3(0, 0, -1)
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

@MainActor
final class SpatialCaptureHostView: UIView {
    private let arSession: ARSession
    private let relocalizationView: ARSCNView
    private weak var activeCaptureView: RoomCaptureView?

    init(arSession: ARSession) {
        self.arSession = arSession
        relocalizationView = ARSCNView(frame: .zero)
        super.init(frame: .zero)
        backgroundColor = .black
        relocalizationView.session = arSession
        relocalizationView.scene = SCNScene()
        relocalizationView.automaticallyUpdatesLighting = true
        showRelocalizationPreview()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showRelocalizationPreview() {
        activeCaptureView?.removeFromSuperview()
        activeCaptureView = nil
        installFillingSubview(relocalizationView)
    }

    func showCaptureView(_ captureView: RoomCaptureView) {
        guard activeCaptureView !== captureView || captureView.superview !== self else {
            return
        }
        relocalizationView.removeFromSuperview()
        activeCaptureView?.removeFromSuperview()
        activeCaptureView = captureView
        installFillingSubview(captureView)
    }

    private func installFillingSubview(_ view: UIView) {
        guard view.superview !== self else { return }
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

struct SpatialCaptureRepresentable: UIViewRepresentable {
    let hostView: SpatialCaptureHostView

    func makeUIView(context: Context) -> SpatialCaptureHostView {
        hostView
    }

    func updateUIView(_ uiView: SpatialCaptureHostView, context: Context) {}
}
