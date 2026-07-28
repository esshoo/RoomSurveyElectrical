import ARKit
import CoreImage
import Foundation
import QuartzCore
import SceneKit
import SwiftUI
import UIKit

private enum PhotoScanEdgeDirection: String, Equatable {
    case up
    case down
    case left
    case right
    case upLeft
    case upRight
    case downLeft
    case downRight

    var systemImage: String {
        switch self {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .upLeft: "arrow.up.left"
        case .upRight: "arrow.up.right"
        case .downLeft: "arrow.down.left"
        case .downRight: "arrow.down.right"
        }
    }
}

private struct AdaptivePhotoScanGuidance: Equatable {
    var message: String
    var readiness: Double
    var isReady: Bool
    var activeSegmentID: UUID?
    var activeScreenPoint: CGPoint?
    var edgeDirection: PhotoScanEdgeDirection?

    static let searching = AdaptivePhotoScanGuidance(
        message: "حرّك الهاتف ببطء؛ سيتم تنشيط المربع الموجود أمام الكاميرا.",
        readiness: 0,
        isReady: false,
        activeSegmentID: nil,
        activeScreenPoint: nil,
        edgeDirection: nil
    )
}

struct AdaptivePhotographicWallScanView: View {
    @Binding var project: RoomProject
    let arSession: ARSession
    let worldToProjectTransform: simd_float4x4?
    let performanceProfile: SpatialScanPerformanceProfile
    let targetSegmentIDs: Set<UUID>?
    let onProjectChanged: () -> Void
    let onClose: () -> Void

    @State private var guidance = AdaptivePhotoScanGuidance.searching
    @State private var autoCaptureEnabled = true
    @State private var errorMessage: String?
    @State private var isFinishing = false
    @State private var dirtyCompositeWallIDs: Set<UUID> = []

    init(
        project: Binding<RoomProject>,
        arSession: ARSession,
        worldToProjectTransform: simd_float4x4? = nil,
        performanceProfile: SpatialScanPerformanceProfile,
        targetSegmentIDs: Set<UUID>? = nil,
        onProjectChanged: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        _project = project
        self.arSession = arSession
        self.worldToProjectTransform = worldToProjectTransform
        self.performanceProfile = performanceProfile
        self.targetSegmentIDs = targetSegmentIDs
        self.onProjectChanged = onProjectChanged
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            AdaptivePhotographicWallScanARView(
                project: project,
                arSession: arSession,
                worldToProjectTransform: worldToProjectTransform,
                performanceProfile: performanceProfile,
                targetSegmentIDs: targetSegmentIDs,
                autoCaptureEnabled: autoCaptureEnabled,
                onGuidanceChanged: { newGuidance in
                    guidance = newGuidance
                },
                onCaptured: handleCapture
            )
            .ignoresSafeArea()

            GeometryReader { proxy in
                activeCaptureIndicator(in: proxy.size)
                edgeGuidanceIndicator(in: proxy.size)
            }
            .allowsHitTesting(false)

            VStack(spacing: 12) {
                topBar
                progressCard
                Spacer()
                guidanceCard
                bottomBar
            }
            .padding()
        }
        .background(Color.black)
        .onAppear(perform: prepareScan)
        .alert("تعذر حفظ الصورة", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: finishAndClose) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .disabled(isFinishing)

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("المسح الفوتوغرافي الذكي")
                    .font(.headline)
                Text(activeWallName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    "المتبقي \(remainingCount) من \(totalCount)",
                    systemImage: "square.grid.3x3.fill"
                )
                .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int((coverage * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit().weight(.bold))
            }
            ProgressView(value: coverage)
                .tint(.green)

            Label(
                "وضع \(performanceProfile.title)",
                systemImage: performanceProfile.systemImage
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            if remainingCount == 0 {
                Label(
                    "اكتملت جميع المربعات، وتم تحديث صور الحوائط.",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            } else if guidance.activeSegmentID != nil {
                Text("المربع الملون هو المربع النشط الآن؛ ثبّت الهاتف أمامه فقط.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("لا يوجد ترتيب إجباري: تحرك في أي اتجاه نحو أي مربع متبقٍ.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
    }

    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: guidance.isReady ? "camera.fill" : "viewfinder")
                    .foregroundStyle(guidance.activeSegmentID == nil ? .cyan : .yellow)
                Text(guidance.message)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            ProgressView(value: guidance.readiness)
                .tint(guidance.isReady ? .green : .yellow)
            Text(
                "التطبيق لا يصور بترتيب ثابت ولا يحفظ صورًا عشوائية؛ "
                    + "المربع المواجه للكاميرا يتنشط تلقائيًا ثم يُلتقط بعد ثبات الهاتف."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button {
                guard !isFinishing else { return }
                autoCaptureEnabled.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: autoCaptureEnabled ? "camera.badge.clock" : "pause.circle")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(autoCaptureEnabled ? "الالتقاط التلقائي يعمل" : "الالتقاط التلقائي متوقف")
                            .font(.headline)
                        Text(
                            autoCaptureEnabled
                                ? "وجّه الهاتف لأي مربع متبقٍ وانتظر لحظة"
                                : "اضغط لإعادة تشغيل الالتقاط"
                        )
                        .font(.caption)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .tint(autoCaptureEnabled ? .blue : .gray)
            .disabled(remainingCount == 0 || isFinishing)

            Button(action: finishAndClose) {
                Label(
                    remainingCount == 0
                        ? "إنهاء والعودة للكهرباء"
                        : "إنهاء الآن واستخدام الصور المحلية عند الحاجة",
                    systemImage: "checkmark.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isFinishing)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func activeCaptureIndicator(in size: CGSize) -> some View {
        if let normalized = guidance.activeScreenPoint,
           guidance.activeSegmentID != nil {
            ZStack {
                Circle()
                    .stroke(Color.yellow.opacity(0.35), lineWidth: 7)
                    .frame(width: 62, height: 62)
                Circle()
                    .trim(from: 0, to: max(guidance.readiness, 0.02))
                    .stroke(
                        guidance.isReady ? Color.green : Color.yellow,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 62, height: 62)
                Image(systemName: guidance.isReady ? "camera.fill" : "hourglass")
                    .font(.headline)
                    .foregroundStyle(guidance.isReady ? Color.green : Color.yellow)
            }
            .shadow(color: .black.opacity(0.5), radius: 6)
            .position(
                x: min(max(normalized.x, 0.08), 0.92) * size.width,
                y: min(max(normalized.y, 0.12), 0.88) * size.height
            )
        }
    }

    @ViewBuilder
    private func edgeGuidanceIndicator(in size: CGSize) -> some View {
        if let direction = guidance.edgeDirection,
           remainingCount > 0 {
            PhotoScanEdgePulse(direction: direction, size: size)
        }
    }

    private var segments: [WallPhotoSegment] {
        project.wallPhotoSegments ?? []
    }

    private var sessionSegments: [WallPhotoSegment] {
        guard let targetSegmentIDs else { return segments }
        return segments.filter { targetSegmentIDs.contains($0.id) }
    }

    private var totalCount: Int { sessionSegments.count }

    private var capturedCount: Int {
        sessionSegments.filter(\.isPhotoCaptureSatisfied).count
    }

    private var remainingCount: Int {
        sessionSegments.filter { !$0.isPhotoCaptureSatisfied }.count
    }

    private var coverage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(capturedCount) / Double(totalCount)
    }

    private var activeWallName: String {
        guard let activeID = guidance.activeSegmentID,
              let segment = segments.first(where: { $0.id == activeID }),
              let wallIndex = project.walls.firstIndex(where: { $0.id == segment.wallID }) else {
            return remainingCount == 0 ? "المسح مكتمل" : "حرّك الهاتف نحو أي حائط"
        }
        return project.wallAppearance(for: segment.wallID)?.displayName
            ?? "الحائط \(wallIndex + 1)"
    }

    private func prepareScan() {
        let width = project.photographicScanProgress?.targetSegmentWidthMeters ?? 1.35
        let height = project.photographicScanProgress?.targetSegmentHeightMeters ?? 1.20
        project.ensurePhotographicWallSegments(targetWidth: width, targetHeight: height)
        if var restored = project.wallPhotoSegments {
            for index in restored.indices where restored[index].state == .skipped {
                restored[index].state = .pending
            }
            project.wallPhotoSegments = restored
        }
        dirtyCompositeWallIDs = Set(
            project.walls.compactMap { wall in
                project.photographicSegments(for: wall.id).contains {
                    $0.state == .captured && $0.photoID != nil
                } ? wall.id : nil
            }
        )
        var progress = project.photographicScanProgress ?? WallPhotographicScanProgress()
        progress.startedAt = progress.startedAt ?? Date()
        project.photographicScanProgress = progress
        persist()
    }

    private func handleCapture(
        _ jpegData: Data,
        segmentID: UUID,
        qualityScore: Float
    ) {
        guard let segmentIndex = project.wallPhotoSegments?.firstIndex(where: {
            $0.id == segmentID
        }), let segment = project.wallPhotoSegments?[segmentIndex],
              !segment.isPhotoCaptureSatisfied else {
            return
        }

        do {
            let combinedQualityScore = WallPhotoQualityAnalyzer.combinedCaptureScore(
                geometricScore: qualityScore,
                jpegData: jpegData
            )
            let asset = try WallPhotoStorage.importImage(
                data: jpegData,
                projectID: project.id,
                wallID: segment.wallID,
                source: .photographicScan,
                segmentIDs: [segment.id],
                performanceProfile: performanceProfile
            )
            var photos = project.wallPhotos ?? []
            photos.append(asset)
            project.wallPhotos = photos
            project.wallPhotoSegments?[segmentIndex].state = .captured
            project.wallPhotoSegments?[segmentIndex].photoID = asset.id
            project.wallPhotoSegments?[segmentIndex].qualityScore = combinedQualityScore
            project.wallPhotoSegments?[segmentIndex].capturedAt = Date()
            project.wallPhotoSegments?[segmentIndex].needsRecapture = false
            dirtyCompositeWallIDs.insert(segment.wallID)

            let wallIsComplete = project.photographicSegments(for: segment.wallID)
                .allSatisfy(\.isPhotoCaptureSatisfied)
            if wallIsComplete {
                try rebuildComposite(for: segment.wallID)
            }

            if remainingCount == 0 {
                try rebuildDirtyComposites()
                var progress = project.photographicScanProgress ?? WallPhotographicScanProgress()
                progress.completedAt = Date()
                project.photographicScanProgress = progress
            }
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishAndClose() {
        guard !isFinishing else { return }
        isFinishing = true
        do {
            try rebuildDirtyComposites()
            if remainingCount == 0 {
                var progress = project.photographicScanProgress ?? WallPhotographicScanProgress()
                progress.completedAt = Date()
                project.photographicScanProgress = progress
            }
            try ProjectRepository.save(project)
            onClose()
        } catch {
            isFinishing = false
            errorMessage = error.localizedDescription
        }
    }

    private func rebuildComposite(for wallID: UUID) throws {
        guard dirtyCompositeWallIDs.contains(wallID) else { return }
        try WallPhotoCompositeBuilder.rebuildComposite(
            project: &project,
            wallID: wallID,
            performanceProfile: performanceProfile
        )
        dirtyCompositeWallIDs.remove(wallID)
    }

    private func rebuildDirtyComposites() throws {
        for wallID in Array(dirtyCompositeWallIDs) {
            try rebuildComposite(for: wallID)
        }
    }

    private func persist() {
        do {
            try ProjectRepository.save(project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PhotoScanEdgePulse: View {
    let direction: PhotoScanEdgeDirection
    let size: CGSize
    @State private var pulsing = false

    var body: some View {
        Image(systemName: direction.systemImage)
            .font(.system(size: 28, weight: .black))
            .foregroundStyle(Color.yellow)
            .padding(15)
            .background(Color.black.opacity(0.46), in: Circle())
            .overlay(Circle().stroke(Color.yellow, lineWidth: 3))
            .scaleEffect(pulsing ? 1.18 : 0.84)
            .opacity(pulsing ? 1 : 0.55)
            .shadow(color: .yellow.opacity(0.7), radius: 12)
            .position(position)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }

    private var position: CGPoint {
        let margin: CGFloat = 48
        switch direction {
        case .up:
            return CGPoint(x: size.width / 2, y: margin)
        case .down:
            return CGPoint(x: size.width / 2, y: size.height - margin)
        case .left:
            return CGPoint(x: margin, y: size.height / 2)
        case .right:
            return CGPoint(x: size.width - margin, y: size.height / 2)
        case .upLeft:
            return CGPoint(x: margin, y: margin)
        case .upRight:
            return CGPoint(x: size.width - margin, y: margin)
        case .downLeft:
            return CGPoint(x: margin, y: size.height - margin)
        case .downRight:
            return CGPoint(x: size.width - margin, y: size.height - margin)
        }
    }
}

private struct AdaptivePhotographicWallScanARView: UIViewRepresentable {
    var project: RoomProject
    let arSession: ARSession
    let worldToProjectTransform: simd_float4x4?
    let performanceProfile: SpatialScanPerformanceProfile
    let targetSegmentIDs: Set<UUID>?
    let autoCaptureEnabled: Bool
    let onGuidanceChanged: (AdaptivePhotoScanGuidance) -> Void
    let onCaptured: (Data, UUID, Float) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.session = arSession
        sceneView.scene = SCNScene()
        sceneView.automaticallyUpdatesLighting = false
        sceneView.antialiasingMode = antialiasingMode
        sceneView.preferredFramesPerSecond = performanceProfile.photoScanFramesPerSecond
        sceneView.contentScaleFactor = min(
            UIScreen.main.scale,
            CGFloat(performanceProfile.photoScanContentScaleLimit)
        )
        sceneView.backgroundColor = .black
        context.coordinator.sceneView = sceneView
        context.coordinator.rebuildGuideNodes()
        context.coordinator.startDisplayLink()
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.parent = self
        uiView.antialiasingMode = antialiasingMode
        uiView.preferredFramesPerSecond = performanceProfile.photoScanFramesPerSecond
        uiView.contentScaleFactor = min(
            UIScreen.main.scale,
            CGFloat(performanceProfile.photoScanContentScaleLimit)
        )
        context.coordinator.refreshDisplayLinkForCurrentProfile()
        context.coordinator.rebuildGuideNodesIfNeeded()
    }

    private var antialiasingMode: SCNAntialiasingMode {
        switch performanceProfile.viewerAntialiasingLevel {
        case 4: .multisampling4X
        case 2: .multisampling2X
        default: .none
        }
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        coordinator.stopDisplayLink()
        coordinator.cancelPendingCapture()
        uiView.scene = SCNScene()
        uiView.session = ARSession()
        coordinator.sceneView = nil
    }

    final class Coordinator: NSObject {
        var parent: AdaptivePhotographicWallScanARView
        weak var sceneView: ARSCNView?

        private var displayLink: CADisplayLink?
        private var guideRoot = SCNNode()
        private var lastGuideSignature = ""
        private var currentActiveSegmentID: UUID?
        private var stableSince: TimeInterval?
        private var lastCameraTransform: simd_float4x4?
        private var lastEvaluationTime: TimeInterval = 0
        private var lastCapturedSegmentID: UUID?
        private var captureInProgress = false
        private var lastGuidance = AdaptivePhotoScanGuidance.searching
        private var lastThermalState = ProcessInfo.processInfo.thermalState
        private static let imageContext = CIContext(options: nil)

        init(parent: AdaptivePhotographicWallScanARView) {
            self.parent = parent
            super.init()
            guideRoot.name = "adaptive-photographic-wall-grid"
        }

        func startDisplayLink() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(displayLinkTick))
            configureDisplayLink(link, for: ProcessInfo.processInfo.thermalState)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }

        private func configureDisplayLink(
            _ link: CADisplayLink,
            for thermalState: ProcessInfo.ThermalState
        ) {
            let rates = parent.performanceProfile.photoScanDisplayLinkRates
            let preferred: Float
            switch thermalState {
            case .nominal:
                preferred = Float(rates.nominal)
            case .fair:
                preferred = Float(rates.fair)
            case .serious, .critical:
                preferred = Float(rates.hot)
            @unknown default:
                preferred = Float(rates.fair)
            }
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: min(6, preferred),
                maximum: max(20, preferred),
                preferred: preferred
            )
        }

        func refreshDisplayLinkForCurrentProfile() {
            guard let displayLink else { return }
            configureDisplayLink(
                displayLink,
                for: ProcessInfo.processInfo.thermalState
            )
        }

        private var evaluationInterval: TimeInterval {
            let intervals = parent.performanceProfile.photoScanEvaluationIntervals
            switch ProcessInfo.processInfo.thermalState {
            case .nominal:
                return intervals.nominal
            case .fair:
                return intervals.fair
            case .serious, .critical:
                return intervals.hot
            @unknown default:
                return intervals.fair
            }
        }

        func cancelPendingCapture() {
            captureInProgress = false
            stableSince = nil
            lastCapturedSegmentID = nil
        }

        func rebuildGuideNodesIfNeeded() {
            let signature = guideSignature
            guard signature != lastGuideSignature else { return }
            rebuildGuideNodes()
        }

        func rebuildGuideNodes() {
            guard let sceneView else { return }
            guideRoot.removeFromParentNode()
            guideRoot = SCNNode()
            guideRoot.name = "adaptive-photographic-wall-grid"
            guideRoot.simdTransform = projectToSessionTransform
            sceneView.scene.rootNode.addChildNode(guideRoot)

            for wall in parent.project.walls {
                let wallRoot = SCNNode()
                wallRoot.simdTransform = wall.matrix
                guideRoot.addChildNode(wallRoot)

                for segment in parent.project.photographicSegments(for: wall.id) {
                    let plane = SCNPlane(
                        width: CGFloat(segment.width * 0.985),
                        height: CGFloat(segment.height * 0.985)
                    )
                    let material = SCNMaterial()
                    let isActive = segment.id == currentActiveSegmentID
                    let color: UIColor
                    switch segment.state {
                    case .captured:
                        color = segment.needsRecapture
                            ? UIColor.systemOrange.withAlphaComponent(0.20)
                            : UIColor.systemGreen.withAlphaComponent(0.12)
                    case .skipped:
                        color = UIColor.systemGray.withAlphaComponent(0.08)
                    case .pending:
                        color = isActive
                            ? UIColor.systemYellow.withAlphaComponent(0.32)
                            : UIColor.systemCyan.withAlphaComponent(0.07)
                    }
                    material.diffuse.contents = color
                    material.emission.contents = color.withAlphaComponent(isActive ? 0.75 : 0.15)
                    material.lightingModel = .constant
                    material.isDoubleSided = true
                    material.readsFromDepthBuffer = false
                    material.writesToDepthBuffer = false
                    plane.materials = [material]

                    let node = SCNNode(geometry: plane)
                    node.position = SCNVector3(segment.centerX, segment.centerY, 0.022)
                    node.renderingOrder = 1000
                    node.name = "photo-segment:\(segment.id.uuidString)"
                    wallRoot.addChildNode(node)
                    addBorder(
                        to: node,
                        width: segment.width,
                        height: segment.height,
                        color: isActive
                            ? .systemYellow
                            : (segment.needsRecapture
                                ? .systemOrange
                                : (segment.state == .captured ? .systemGreen : .systemCyan)),
                        thickness: isActive ? 0.018 : 0.006
                    )
                }
            }
            lastGuideSignature = guideSignature
        }

        private var guideSignature: String {
            let segmentState = parent.project.wallPhotoSegments?.map {
                "\($0.id.uuidString):\($0.state.rawValue):\($0.needsRecapture)"
            }.joined(separator: "|") ?? ""
            return segmentState + "#\(currentActiveSegmentID?.uuidString ?? "none")"
        }

        @objc private func displayLinkTick() {
            guard let sceneView,
                  let frame = sceneView.session.currentFrame else {
                stableSince = nil
                publish(.searching)
                return
            }
            let now = CACurrentMediaTime()
            let thermalState = ProcessInfo.processInfo.thermalState
            if thermalState != lastThermalState {
                lastThermalState = thermalState
                if let displayLink {
                    configureDisplayLink(displayLink, for: thermalState)
                }
            }
            guard now - lastEvaluationTime >= evaluationInterval else { return }
            lastEvaluationTime = now

            let pending = (parent.project.wallPhotoSegments ?? []).filter {
                (parent.targetSegmentIDs == nil || parent.targetSegmentIDs?.contains($0.id) == true)
                    && !$0.isPhotoCaptureSatisfied
            }
            guard !pending.isEmpty else {
                currentActiveSegmentID = nil
                stableSince = nil
                rebuildGuideNodesIfNeeded()
                publish(
                    AdaptivePhotoScanGuidance(
                        message: "اكتملت جميع الصور المطلوبة.",
                        readiness: 1,
                        isReady: true,
                        activeSegmentID: nil,
                        activeScreenPoint: nil,
                        edgeDirection: nil
                    )
                )
                return
            }

            let candidate = selectBestCandidate(
                from: pending,
                frame: frame,
                sceneView: sceneView
            )
            let newActiveID = candidate?.segment.id
            if newActiveID != currentActiveSegmentID {
                currentActiveSegmentID = newActiveID
                stableSince = nil
                lastCameraTransform = frame.camera.transform
                rebuildGuideNodes()
            }

            guard let candidate else {
                stableSince = nil
                publish(
                    AdaptivePhotoScanGuidance(
                        message: "حرّك الهاتف نحو اتجاه النبض للوصول إلى مربع متبقٍ.",
                        readiness: 0.08,
                        isReady: false,
                        activeSegmentID: nil,
                        activeScreenPoint: nil,
                        edgeDirection: edgeDirection(
                            for: pending,
                            frame: frame,
                            sceneView: sceneView
                        )
                    )
                )
                return
            }

            let evaluation = evaluateActiveCandidate(
                candidate,
                frame: frame,
                sceneView: sceneView,
                now: now,
                remainingCount: pending.count
            )
            publish(evaluation.guidance)

            guard parent.autoCaptureEnabled,
                  evaluation.guidance.isReady,
                  !captureInProgress,
                  lastCapturedSegmentID != candidate.segment.id else {
                return
            }
            captureInProgress = true
            capture(
                segment: candidate.segment,
                projectedCorners: candidate.projectedCorners,
                qualityScore: evaluation.qualityScore,
                sceneView: sceneView
            )
        }

        private struct Candidate {
            let segment: WallPhotoSegment
            let wall: WallSnapshot
            let projectedCorners: [CGPoint]
            let bounds: CGRect
            let screenPoint: CGPoint
            let facing: Float
            let areaRatio: CGFloat
            let score: Float
        }

        private func selectBestCandidate(
            from segments: [WallPhotoSegment],
            frame: ARFrame,
            sceneView: ARSCNView
        ) -> Candidate? {
            let safeBounds = sceneView.bounds.insetBy(dx: 22, dy: 72)
            let screenCenter = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
            let viewArea = max(sceneView.bounds.width * sceneView.bounds.height, 1)
            var candidates: [Candidate] = []
            let wallsByID = Dictionary(
                uniqueKeysWithValues: parent.project.walls.map { ($0.id, $0) }
            )

            for segment in segments {
                guard let wall = wallsByID[segment.wallID] else { continue }
                let worldCorners = segmentWorldCorners(segment: segment, wall: wall)
                let projected3D = worldCorners.map {
                    let sessionPoint = projectToSessionTransform
                        * SIMD4<Float>($0.x, $0.y, $0.z, 1)
                    return sceneView.projectPoint(
                        SCNVector3(sessionPoint.x, sessionPoint.y, sessionPoint.z)
                    )
                }
                guard projected3D.allSatisfy({ $0.z > 0 && $0.z < 1 }) else {
                    continue
                }
                let projected = projected3D.map {
                    CGPoint(x: CGFloat($0.x), y: CGFloat($0.y))
                }
                let bounds = projected.reduce(CGRect.null) { partial, point in
                    partial.union(CGRect(x: point.x, y: point.y, width: 1, height: 1))
                }
                guard !bounds.isNull,
                      bounds.width > 28,
                      bounds.height > 28 else { continue }
                let intersection = bounds.intersection(safeBounds)
                guard !intersection.isNull else { continue }
                let visibleRatio = (intersection.width * intersection.height)
                    / max(bounds.width * bounds.height, 1)
                guard visibleRatio >= 0.52 else { continue }

                let facing = wallFacing(
                    segment: segment,
                    wall: wall,
                    cameraTransform: worldToProjectTransform * frame.camera.transform
                )
                guard facing >= 0.30 else { continue }
                let center = CGPoint(x: bounds.midX, y: bounds.midY)
                let normalizedDistance = hypot(
                    center.x - screenCenter.x,
                    center.y - screenCenter.y
                ) / max(hypot(sceneView.bounds.width, sceneView.bounds.height), 1)
                let areaRatio = min((bounds.width * bounds.height) / viewArea, 1)
                let score = Float(
                    visibleRatio * 0.34
                        + CGFloat(facing) * 0.30
                        + areaRatio * 0.22
                        + max(1 - normalizedDistance, 0) * 0.14
                )
                candidates.append(
                    Candidate(
                        segment: segment,
                        wall: wall,
                        projectedCorners: projected,
                        bounds: bounds,
                        screenPoint: center,
                        facing: facing,
                        areaRatio: areaRatio,
                        score: score
                    )
                )
            }

            let sorted = candidates.sorted { $0.score > $1.score }
            guard let best = sorted.first else { return nil }
            if let currentID = currentActiveSegmentID,
               let current = candidates.first(where: { $0.segment.id == currentID }),
               current.score >= best.score - 0.09 {
                return current
            }
            return best
        }

        private func evaluateActiveCandidate(
            _ candidate: Candidate,
            frame: ARFrame,
            sceneView: ARSCNView,
            now: TimeInterval,
            remainingCount: Int
        ) -> (guidance: AdaptivePhotoScanGuidance, qualityScore: Float) {
            let normalizedPoint = CGPoint(
                x: candidate.screenPoint.x / max(sceneView.bounds.width, 1),
                y: candidate.screenPoint.y / max(sceneView.bounds.height, 1)
            )
            let edge: PhotoScanEdgeDirection? = nil

            guard frame.camera.trackingState.isUsableForPhotoScan else {
                stableSince = nil
                lastCameraTransform = frame.camera.transform
                return (
                    AdaptivePhotoScanGuidance(
                        message: "حرّك الهاتف ببطء حتى يستقر تتبع الكاميرا.",
                        readiness: 0.06,
                        isReady: false,
                        activeSegmentID: candidate.segment.id,
                        activeScreenPoint: normalizedPoint,
                        edgeDirection: edge
                    ),
                    0
                )
            }

            let safeBounds = sceneView.bounds.insetBy(dx: 24, dy: 72)
            guard safeBounds.contains(candidate.bounds) else {
                stableSince = nil
                return (
                    AdaptivePhotoScanGuidance(
                        message: "المربع نشط؛ حرّك الهاتف قليلًا حتى يظهر كاملًا.",
                        readiness: 0.28,
                        isReady: false,
                        activeSegmentID: candidate.segment.id,
                        activeScreenPoint: normalizedPoint,
                        edgeDirection: edge
                    ),
                    candidate.facing
                )
            }

            let minimumWidth = min(
                sceneView.bounds.width
                    * CGFloat(parent.performanceProfile.photoScanMinimumWidthFraction),
                210
            )
            let minimumHeight = min(
                sceneView.bounds.height
                    * CGFloat(parent.performanceProfile.photoScanMinimumHeightFraction),
                180
            )
            guard candidate.bounds.width >= minimumWidth,
                  candidate.bounds.height >= minimumHeight else {
                stableSince = nil
                return (
                    AdaptivePhotoScanGuidance(
                        message: "المربع نشط؛ اقترب قليلًا من الحائط.",
                        readiness: 0.44,
                        isReady: false,
                        activeSegmentID: candidate.segment.id,
                        activeScreenPoint: normalizedPoint,
                        edgeDirection: edge
                    ),
                    candidate.facing
                )
            }

            guard candidate.facing >= parent.performanceProfile.photoScanMinimumFacing else {
                stableSince = nil
                return (
                    AdaptivePhotoScanGuidance(
                        message: "المربع نشط؛ واجه الحائط باستقامة أكبر.",
                        readiness: 0.58,
                        isReady: false,
                        activeSegmentID: candidate.segment.id,
                        activeScreenPoint: normalizedPoint,
                        edgeDirection: edge
                    ),
                    candidate.facing
                )
            }

            let movement = cameraMovement(
                from: lastCameraTransform,
                to: frame.camera.transform
            )
            lastCameraTransform = frame.camera.transform
            if movement.translation > 0.018 || movement.rotation > 0.018 {
                stableSince = nil
                return (
                    AdaptivePhotoScanGuidance(
                        message: "المربع نشط — ثبّت الهاتف وانتظر قليلًا.",
                        readiness: 0.66,
                        isReady: false,
                        activeSegmentID: candidate.segment.id,
                        activeScreenPoint: normalizedPoint,
                        edgeDirection: edge
                    ),
                    candidate.facing
                )
            }

            if stableSince == nil { stableSince = now }
            let stableDuration = now - (stableSince ?? now)
            let requiredDuration = parent.performanceProfile.photoScanRequiredStabilityDuration
            let readiness = min(0.68 + stableDuration / requiredDuration * 0.32, 1)
            let isReady = stableDuration >= requiredDuration
            let quality = min(
                max(
                    candidate.facing * 0.58
                        + Float(candidate.areaRatio) * 0.42,
                    0
                ),
                1
            )
            return (
                AdaptivePhotoScanGuidance(
                    message: isReady
                        ? "تم الثبات — يتم تصوير المربع الآن."
                        : "انتظر قليلًا… جارٍ تثبيت الصورة.",
                    readiness: readiness,
                    isReady: isReady,
                    activeSegmentID: candidate.segment.id,
                    activeScreenPoint: normalizedPoint,
                    edgeDirection: edge
                ),
                quality
            )
        }

        private func edgeDirection(
            for segments: [WallPhotoSegment],
            frame: ARFrame,
            sceneView: ARSCNView,
            excluding excludedID: UUID? = nil
        ) -> PhotoScanEdgeDirection? {
            let screenCenter = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
            let candidates = segments.compactMap { segment -> (CGPoint, Float)? in
                guard segment.id != excludedID,
                      let wall = parent.project.walls.first(where: { $0.id == segment.wallID }) else {
                    return nil
                }
                let center4 = simd_mul(
                    wall.matrix,
                    SIMD4<Float>(segment.centerX, segment.centerY, 0.006, 1)
                )
                let cameraSpace = simd_mul(
                    simd_inverse(worldToProjectTransform * frame.camera.transform),
                    center4
                )
                guard cameraSpace.z < -0.04 else { return nil }
                let sessionCenter = projectToSessionTransform * center4
                let projected = sceneView.projectPoint(
                    SCNVector3(sessionCenter.x, sessionCenter.y, sessionCenter.z)
                )
                let point = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
                let distance = Float(hypot(point.x - screenCenter.x, point.y - screenCenter.y))
                return (point, distance)
            }
            guard let target = candidates.min(by: { $0.1 < $1.1 })?.0 else {
                return nil
            }
            let dx = target.x - screenCenter.x
            let dy = target.y - screenCenter.y
            let horizontal = abs(dx) > sceneView.bounds.width * 0.12
            let vertical = abs(dy) > sceneView.bounds.height * 0.12
            switch (horizontal, vertical, dx < 0, dy < 0) {
            case (true, true, true, true): return .upLeft
            case (true, true, false, true): return .upRight
            case (true, true, true, false): return .downLeft
            case (true, true, false, false): return .downRight
            case (true, false, true, _): return .left
            case (true, false, false, _): return .right
            case (false, true, _, true): return .up
            case (false, true, _, false): return .down
            default: return nil
            }
        }

        private func publish(_ guidance: AdaptivePhotoScanGuidance) {
            guard guidance != lastGuidance else { return }
            lastGuidance = guidance
            parent.onGuidanceChanged(guidance)
        }

        private func capture(
            segment: WallPhotoSegment,
            projectedCorners: [CGPoint],
            qualityScore: Float,
            sceneView: ARSCNView
        ) {
            guard projectedCorners.count == 4,
                  projectedCorners.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
                  sceneView.bounds.width > 1,
                  sceneView.bounds.height > 1 else {
                captureInProgress = false
                stableSince = nil
                return
            }

            guideRoot.isHidden = true
            sceneView.setNeedsDisplay()
            DispatchQueue.main.async { [weak self, weak sceneView] in
                guard let self, let sceneView else {
                    self?.captureInProgress = false
                    return
                }
                let snapshot = sceneView.snapshot()
                self.guideRoot.isHidden = false
                guard let corrected = self.perspectiveCorrectedImage(
                    snapshot: snapshot,
                    projectedCorners: projectedCorners,
                    viewSize: sceneView.bounds.size
                ), let data = corrected.jpegData(compressionQuality: 0.90) else {
                    self.captureInProgress = false
                    self.stableSince = nil
                    self.publish(
                        AdaptivePhotoScanGuidance(
                            message: "تعذر قص المربع؛ أعد توجيه الكاميرا.",
                            readiness: 0.18,
                            isReady: false,
                            activeSegmentID: segment.id,
                            activeScreenPoint: nil,
                            edgeDirection: nil
                        )
                    )
                    return
                }
                self.lastCapturedSegmentID = segment.id
                self.currentActiveSegmentID = nil
                self.stableSince = nil
                self.parent.onCaptured(data, segment.id, qualityScore)
                self.rebuildGuideNodes()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) {
                    self.captureInProgress = false
                    self.lastCapturedSegmentID = nil
                }
            }
        }

        private func perspectiveCorrectedImage(
            snapshot: UIImage,
            projectedCorners: [CGPoint],
            viewSize: CGSize
        ) -> UIImage? {
            guard projectedCorners.count == 4,
                  let cgImage = snapshot.cgImage,
                  viewSize.width > 0,
                  viewSize.height > 0 else { return nil }

            let imageWidth = CGFloat(cgImage.width)
            let imageHeight = CGFloat(cgImage.height)
            let scaleX = imageWidth / viewSize.width
            let scaleY = imageHeight / viewSize.height
            func ciPoint(_ point: CGPoint) -> CIVector {
                CIVector(
                    x: point.x * scaleX,
                    y: imageHeight - point.y * scaleY
                )
            }

            let input = CIImage(cgImage: cgImage)
            guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
            filter.setValue(input, forKey: kCIInputImageKey)
            filter.setValue(ciPoint(projectedCorners[3]), forKey: "inputTopLeft")
            filter.setValue(ciPoint(projectedCorners[2]), forKey: "inputTopRight")
            filter.setValue(ciPoint(projectedCorners[0]), forKey: "inputBottomLeft")
            filter.setValue(ciPoint(projectedCorners[1]), forKey: "inputBottomRight")
            guard let output = filter.outputImage else { return nil }
            let extent = output.extent.integral
            guard extent.width >= 96,
                  extent.height >= 96,
                  let correctedCG = Self.imageContext.createCGImage(output, from: extent) else {
                return nil
            }
            return UIImage(cgImage: correctedCG)
        }

        private func segmentWorldCorners(
            segment: WallPhotoSegment,
            wall: WallSnapshot
        ) -> [SIMD3<Float>] {
            let localCorners: [SIMD4<Float>] = [
                SIMD4(segment.localMinX, segment.localMinY, 0.006, 1),
                SIMD4(segment.localMaxX, segment.localMinY, 0.006, 1),
                SIMD4(segment.localMaxX, segment.localMaxY, 0.006, 1),
                SIMD4(segment.localMinX, segment.localMaxY, 0.006, 1)
            ]
            return localCorners.map {
                let world = simd_mul(wall.matrix, $0)
                return SIMD3(world.x, world.y, world.z)
            }
        }

        private func wallFacing(
            segment: WallPhotoSegment,
            wall: WallSnapshot,
            cameraTransform: simd_float4x4
        ) -> Float {
            let cameraPosition = SIMD3<Float>(
                cameraTransform.columns.3.x,
                cameraTransform.columns.3.y,
                cameraTransform.columns.3.z
            )
            let center4 = simd_mul(
                wall.matrix,
                SIMD4<Float>(segment.centerX, segment.centerY, 0, 1)
            )
            let center = SIMD3<Float>(center4.x, center4.y, center4.z)
            let vector = center - cameraPosition
            guard simd_length(vector) > 0.001 else { return 0 }
            let toWall = simd_normalize(vector)
            let wallNormal = simd_normalize(
                SIMD3<Float>(
                    wall.matrix.columns.2.x,
                    wall.matrix.columns.2.y,
                    wall.matrix.columns.2.z
                )
            )
            return abs(simd_dot(toWall, wallNormal))
        }

        private func cameraMovement(
            from previous: simd_float4x4?,
            to current: simd_float4x4
        ) -> (translation: Float, rotation: Float) {
            guard let previous else { return (0, 0) }
            let previousPosition = SIMD3<Float>(
                previous.columns.3.x,
                previous.columns.3.y,
                previous.columns.3.z
            )
            let currentPosition = SIMD3<Float>(
                current.columns.3.x,
                current.columns.3.y,
                current.columns.3.z
            )
            let previousForward = simd_normalize(
                -SIMD3(previous.columns.2.x, previous.columns.2.y, previous.columns.2.z)
            )
            let currentForward = simd_normalize(
                -SIMD3(current.columns.2.x, current.columns.2.y, current.columns.2.z)
            )
            return (
                simd_distance(previousPosition, currentPosition),
                1 - max(min(simd_dot(previousForward, currentForward), 1), -1)
            )
        }

        private var worldToProjectTransform: simd_float4x4 {
            parent.worldToProjectTransform ?? matrix_identity_float4x4
        }

        private var projectToSessionTransform: simd_float4x4 {
            simd_inverse(worldToProjectTransform)
        }

        private func addBorder(
            to node: SCNNode,
            width: Float,
            height: Float,
            color: UIColor,
            thickness: CGFloat
        ) {
            func edge(width: CGFloat, height: CGFloat, x: Float, y: Float) -> SCNNode {
                let box = SCNBox(
                    width: width,
                    height: height,
                    length: 0.004,
                    chamferRadius: 0
                )
                let material = SCNMaterial()
                material.diffuse.contents = color
                material.emission.contents = color.withAlphaComponent(0.62)
                material.lightingModel = .constant
                material.readsFromDepthBuffer = false
                material.writesToDepthBuffer = false
                box.materials = [material]
                let edgeNode = SCNNode(geometry: box)
                edgeNode.position = SCNVector3(x, y, 0.008)
                edgeNode.renderingOrder = 1001
                return edgeNode
            }
            node.addChildNode(edge(
                width: CGFloat(width),
                height: thickness,
                x: 0,
                y: height / 2
            ))
            node.addChildNode(edge(
                width: CGFloat(width),
                height: thickness,
                x: 0,
                y: -height / 2
            ))
            node.addChildNode(edge(
                width: thickness,
                height: CGFloat(height),
                x: width / 2,
                y: 0
            ))
            node.addChildNode(edge(
                width: thickness,
                height: CGFloat(height),
                x: -width / 2,
                y: 0
            ))
        }
    }
}

private extension ARCamera.TrackingState {
    var isUsableForPhotoScan: Bool {
        switch self {
        case .normal:
            true
        case .notAvailable, .limited:
            false
        }
    }
}
