import ARKit
import CoreImage
import Foundation
import QuartzCore
import SceneKit
import SwiftUI
import UIKit

struct PhotographicCaptureGuidance: Equatable {
    var message: String
    var readiness: Double
    var isReady: Bool

    static let waiting = PhotographicCaptureGuidance(
        message: "وجّه الكاميرا نحو الجزء المحدد من الحائط.",
        readiness: 0,
        isReady: false
    )
}

struct PhotographicWallScanView: View {
    @Binding var project: RoomProject
    let arSession: ARSession
    let onProjectChanged: () -> Void
    let onClose: () -> Void

    @State private var activeSegmentID: UUID?
    @State private var guidance = PhotographicCaptureGuidance.waiting
    @State private var autoCaptureEnabled = true
    @State private var errorMessage: String?
    @State private var isFinishing = false

    var body: some View {
        ZStack {
            PhotographicWallScanARView(
                project: project,
                arSession: arSession,
                activeSegmentID: activeSegmentID,
                autoCaptureEnabled: autoCaptureEnabled,
                onGuidanceChanged: { guidance = $0 },
                onCaptured: handleCapture
            )
            .ignoresSafeArea()

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
        .onAppear {
            prepareScan()
        }
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
            Button {
                finishAndClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("المسح الفوتوغرافي")
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
                    "التغطية \(capturedCount) من \(totalCount)",
                    systemImage: "square.grid.3x3.fill"
                )
                .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int((coverage * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit().weight(.bold))
            }
            ProgressView(value: coverage)
                .tint(.green)

            if let segment = activeSegment {
                Text(
                    "الجزء \(segment.column + 1)×\(segment.row + 1) "
                        + "من شبكة \(segment.columnCount)×\(segment.rowCount)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if totalCount > 0 {
                Label("اكتملت جميع الأجزاء المطلوبة.", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
    }

    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: guidance.isReady ? "camera.fill" : "viewfinder")
                    .foregroundStyle(guidance.isReady ? .green : .yellow)
                Text(guidance.message)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            ProgressView(value: guidance.readiness)
                .tint(guidance.isReady ? .green : .yellow)
            Text(
                "يحفظ التطبيق الصورة فقط عندما يكون الجزء واضحًا، داخل الإطار، "
                    + "والهاتف ثابتًا. لا يتم التقاط صور عشوائية متتالية."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                autoCaptureEnabled.toggle()
            } label: {
                Label(
                    autoCaptureEnabled ? "تلقائي" : "متوقف",
                    systemImage: autoCaptureEnabled ? "camera.badge.clock" : "pause.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(autoCaptureEnabled ? .blue : .gray)
            .disabled(activeSegment == nil)

            Button {
                skipActiveSegment()
            } label: {
                Label("تخطي", systemImage: "forward.end.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(activeSegment == nil)

            Button {
                finishAndClose()
            } label: {
                Label("إنهاء", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isFinishing)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var segments: [WallPhotoSegment] {
        project.wallPhotoSegments ?? []
    }

    private var activeSegment: WallPhotoSegment? {
        guard let activeSegmentID else { return nil }
        return segments.first { $0.id == activeSegmentID }
    }

    private var totalCount: Int { segments.count }

    private var capturedCount: Int {
        segments.filter { $0.state == .captured }.count
    }

    private var coverage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(capturedCount) / Double(totalCount)
    }

    private var activeWallName: String {
        guard let segment = activeSegment,
              let wallIndex = project.walls.firstIndex(where: { $0.id == segment.wallID }) else {
            return totalCount > 0 ? "المسح مكتمل" : "لا توجد حوائط"
        }
        return project.wallAppearance(for: segment.wallID)?.displayName
            ?? "الحائط \(wallIndex + 1)"
    }

    private func prepareScan() {
        let width = project.photographicScanProgress?.targetSegmentWidthMeters ?? 1.35
        let height = project.photographicScanProgress?.targetSegmentHeightMeters ?? 1.20
        project.ensurePhotographicWallSegments(targetWidth: width, targetHeight: height)
        if let skippedIndices = project.wallPhotoSegments?.indices.filter({
            project.wallPhotoSegments?[$0].state == .skipped
        }) {
            for index in skippedIndices {
                project.wallPhotoSegments?[index].state = .pending
            }
        }
        var progress = project.photographicScanProgress ?? WallPhotographicScanProgress()
        progress.startedAt = progress.startedAt ?? Date()
        project.photographicScanProgress = progress
        selectNextPendingSegment()
        persist()
    }

    private func handleCapture(
        _ jpegData: Data,
        segmentID: UUID,
        qualityScore: Float
    ) {
        guard let segmentIndex = project.wallPhotoSegments?.firstIndex(where: {
            $0.id == segmentID
        }), let segment = project.wallPhotoSegments?[segmentIndex] else {
            return
        }

        do {
            if let oldPhotoID = segment.photoID,
               let oldPhoto = project.wallPhotos?.first(where: { $0.id == oldPhotoID }) {
                WallPhotoStorage.delete(projectID: project.id, asset: oldPhoto)
                project.wallPhotos?.removeAll { $0.id == oldPhotoID }
            }

            let asset = try WallPhotoStorage.importImage(
                data: jpegData,
                projectID: project.id,
                wallID: segment.wallID,
                source: .photographicScan,
                segmentIDs: [segment.id]
            )
            var photos = project.wallPhotos ?? []
            photos.append(asset)
            project.wallPhotos = photos
            project.wallPhotoSegments?[segmentIndex].state = .captured
            project.wallPhotoSegments?[segmentIndex].photoID = asset.id
            project.wallPhotoSegments?[segmentIndex].qualityScore = qualityScore
            project.wallPhotoSegments?[segmentIndex].capturedAt = Date()

            let wallSegments = project.photographicSegments(for: segment.wallID)
            if wallSegments.count == 1,
               let appearanceIndex = project.wallAppearances?.firstIndex(where: {
                $0.wallID == segment.wallID
               }) {
                project.wallAppearances?[appearanceIndex].primaryPhotoID = asset.id
                project.wallAppearances?[appearanceIndex].visualMode = .capturedPhotos
            }

            persist()
            selectNextPendingSegment(after: segmentID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func skipActiveSegment() {
        guard let activeSegmentID,
              let index = project.wallPhotoSegments?.firstIndex(where: {
                $0.id == activeSegmentID
              }) else { return }
        project.wallPhotoSegments?[index].state = .skipped
        persist()
        selectNextPendingSegment(after: activeSegmentID)
    }

    private func selectNextPendingSegment(after segmentID: UUID? = nil) {
        let ordered = orderedSegments
        if let segmentID,
           let currentIndex = ordered.firstIndex(where: { $0.id == segmentID }) {
            let following = Array(ordered.dropFirst(currentIndex + 1)) + Array(ordered.prefix(currentIndex + 1))
            activeSegmentID = following.first(where: { $0.state == .pending })?.id
        } else {
            activeSegmentID = ordered.first(where: { $0.state == .pending })?.id
        }
        guidance = activeSegmentID == nil
            ? PhotographicCaptureGuidance(
                message: "اكتملت تغطية جميع الأجزاء غير المتخطاة.",
                readiness: 1,
                isReady: true
            )
            : .waiting
    }

    private var orderedSegments: [WallPhotoSegment] {
        let wallOrder = Dictionary(
            uniqueKeysWithValues: project.walls.enumerated().map { ($0.element.id, $0.offset) }
        )
        return segments.sorted { first, second in
            let firstWall = wallOrder[first.wallID] ?? Int.max
            let secondWall = wallOrder[second.wallID] ?? Int.max
            if firstWall != secondWall { return firstWall < secondWall }
            if first.row != second.row { return first.row > second.row }
            return first.column < second.column
        }
    }

    private func finishAndClose() {
        isFinishing = true
        var progress = project.photographicScanProgress ?? WallPhotographicScanProgress()
        if activeSegmentID == nil {
            progress.completedAt = Date()
        }
        project.photographicScanProgress = progress
        persist()
        onClose()
    }

    private func persist() {
        do {
            try ProjectRepository.save(project)
            onProjectChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PhotographicWallScanARView: UIViewRepresentable {
    var project: RoomProject
    let arSession: ARSession
    let activeSegmentID: UUID?
    let autoCaptureEnabled: Bool
    let onGuidanceChanged: (PhotographicCaptureGuidance) -> Void
    let onCaptured: (Data, UUID, Float) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.session = arSession
        sceneView.scene = SCNScene()
        sceneView.automaticallyUpdatesLighting = true
        sceneView.antialiasingMode = .multisampling4X
        sceneView.backgroundColor = .black
        context.coordinator.sceneView = sceneView
        context.coordinator.rebuildGuideNodes()
        context.coordinator.startDisplayLink()
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.rebuildGuideNodesIfNeeded()
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        coordinator.stopDisplayLink()
        coordinator.sceneView = nil
    }

    final class Coordinator: NSObject {
        var parent: PhotographicWallScanARView
        weak var sceneView: ARSCNView?

        private var displayLink: CADisplayLink?
        private var guideRoot = SCNNode()
        private var lastGuideSignature = ""
        private var stableSince: TimeInterval?
        private var lastCameraTransform: simd_float4x4?
        private var lastEvaluationTime: TimeInterval = 0
        private var lastCapturedSegmentID: UUID?
        private var captureInProgress = false

        init(parent: PhotographicWallScanARView) {
            self.parent = parent
            super.init()
            guideRoot.name = "photographic-wall-grid"
        }

        func startDisplayLink() {
            let link = CADisplayLink(target: self, selector: #selector(displayLinkTick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 20, preferred: 15)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }

        func rebuildGuideNodesIfNeeded() {
            let signature = (parent.project.wallPhotoSegments?.map {
                "\($0.id.uuidString):\($0.state.rawValue)"
            }.joined(separator: "|") ?? "")
                + "#\(parent.activeSegmentID?.uuidString ?? "none")"
            guard signature != lastGuideSignature else { return }
            rebuildGuideNodes()
        }

        func rebuildGuideNodes() {
            guard let sceneView else { return }
            guideRoot.removeFromParentNode()
            guideRoot = SCNNode()
            guideRoot.name = "photographic-wall-grid"
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
                    let isActive = segment.id == parent.activeSegmentID
                    let color: UIColor
                    switch segment.state {
                    case .captured:
                        color = UIColor.systemGreen.withAlphaComponent(0.13)
                    case .skipped:
                        color = UIColor.systemGray.withAlphaComponent(0.10)
                    case .pending:
                        color = isActive
                            ? UIColor.systemYellow.withAlphaComponent(0.26)
                            : UIColor.systemBlue.withAlphaComponent(0.08)
                    }
                    material.diffuse.contents = color
                    material.emission.contents = color.withAlphaComponent(isActive ? 0.45 : 0.12)
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
                        color: isActive ? .systemYellow : .systemCyan,
                        thickness: isActive ? 0.016 : 0.007
                    )
                }
            }
            lastGuideSignature = (parent.project.wallPhotoSegments?.map {
                "\($0.id.uuidString):\($0.state.rawValue)"
            }.joined(separator: "|") ?? "")
                + "#\(parent.activeSegmentID?.uuidString ?? "none")"
        }

        @objc private func displayLinkTick() {
            guard let sceneView,
                  let segmentID = parent.activeSegmentID,
                  let segment = parent.project.wallPhotoSegments?.first(where: {
                    $0.id == segmentID
                  }),
                  let wall = parent.project.walls.first(where: {
                    $0.id == segment.wallID
                  }),
                  let frame = sceneView.session.currentFrame else {
                stableSince = nil
                return
            }

            let now = CACurrentMediaTime()
            guard now - lastEvaluationTime >= 0.09 else { return }
            lastEvaluationTime = now

            let evaluation = evaluate(
                segment: segment,
                wall: wall,
                frame: frame,
                sceneView: sceneView,
                now: now
            )
            parent.onGuidanceChanged(evaluation.guidance)

            guard parent.autoCaptureEnabled,
                  evaluation.guidance.isReady,
                  !captureInProgress,
                  lastCapturedSegmentID != segmentID else {
                return
            }
            captureInProgress = true
            capture(
                segment: segment,
                projectedCorners: evaluation.projectedCorners,
                qualityScore: evaluation.qualityScore,
                sceneView: sceneView
            )
        }

        private func evaluate(
            segment: WallPhotoSegment,
            wall: WallSnapshot,
            frame: ARFrame,
            sceneView: ARSCNView,
            now: TimeInterval
        ) -> (
            guidance: PhotographicCaptureGuidance,
            projectedCorners: [CGPoint],
            qualityScore: Float
        ) {
            guard frame.camera.trackingState.isUsableForPhotoScan else {
                stableSince = nil
                lastCameraTransform = frame.camera.transform
                return (
                    PhotographicCaptureGuidance(
                        message: "حرّك الهاتف ببطء حتى يستقر تتبع الكاميرا.",
                        readiness: 0.05,
                        isReady: false
                    ),
                    [],
                    0
                )
            }

            let worldCorners = segmentWorldCorners(segment: segment, wall: wall)
            let projected = worldCorners.map {
                let point = sceneView.projectPoint(SCNVector3($0.x, $0.y, $0.z))
                return CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
            }
            let depths = worldCorners.map {
                sceneView.projectPoint(SCNVector3($0.x, $0.y, $0.z)).z
            }
            guard depths.allSatisfy({ $0 > 0 && $0 < 1 }) else {
                stableSince = nil
                return (
                    PhotographicCaptureGuidance(
                        message: "الجزء خلف الكاميرا أو خارج مجال الرؤية.",
                        readiness: 0.08,
                        isReady: false
                    ),
                    projected,
                    0
                )
            }

            let bounds = projected.reduce(CGRect.null) { partial, point in
                partial.union(CGRect(x: point.x, y: point.y, width: 1, height: 1))
            }
            let safeBounds = sceneView.bounds.insetBy(dx: 24, dy: 70)
            guard safeBounds.contains(bounds) else {
                stableSince = nil
                return (
                    PhotographicCaptureGuidance(
                        message: "حرّك الهاتف حتى يدخل الجزء الأصفر كاملًا داخل الشاشة.",
                        readiness: 0.24,
                        isReady: false
                    ),
                    projected,
                    0
                )
            }

            let minimumWidth = min(sceneView.bounds.width * 0.34, 190)
            let minimumHeight = min(sceneView.bounds.height * 0.23, 170)
            guard bounds.width >= minimumWidth,
                  bounds.height >= minimumHeight else {
                stableSince = nil
                return (
                    PhotographicCaptureGuidance(
                        message: "اقترب قليلًا من الحائط لزيادة وضوح الجزء.",
                        readiness: 0.42,
                        isReady: false
                    ),
                    projected,
                    0
                )
            }

            let cameraPosition = SIMD3<Float>(
                frame.camera.transform.columns.3.x,
                frame.camera.transform.columns.3.y,
                frame.camera.transform.columns.3.z
            )
            let center4 = simd_mul(
                wall.matrix,
                SIMD4<Float>(segment.centerX, segment.centerY, 0, 1)
            )
            let center = SIMD3<Float>(center4.x, center4.y, center4.z)
            let toWall = simd_normalize(center - cameraPosition)
            let wallNormal = simd_normalize(
                SIMD3<Float>(
                    wall.matrix.columns.2.x,
                    wall.matrix.columns.2.y,
                    wall.matrix.columns.2.z
                )
            )
            let facing = abs(simd_dot(toWall, wallNormal))
            guard facing >= 0.48 else {
                stableSince = nil
                return (
                    PhotographicCaptureGuidance(
                        message: "واجه الحائط بشكل أقرب للاستقامة لتقليل تشوه الصورة.",
                        readiness: 0.55,
                        isReady: false
                    ),
                    projected,
                    facing
                )
            }

            let movement = cameraMovement(from: lastCameraTransform, to: frame.camera.transform)
            lastCameraTransform = frame.camera.transform
            if movement.translation > 0.018 || movement.rotation > 0.018 {
                stableSince = nil
                return (
                    PhotographicCaptureGuidance(
                        message: "ثبت الهاتف لحظة واحدة؛ سيتم التصوير تلقائيًا.",
                        readiness: 0.70,
                        isReady: false
                    ),
                    projected,
                    facing
                )
            }

            if stableSince == nil { stableSince = now }
            let stableDuration = now - (stableSince ?? now)
            let readiness = min(0.72 + stableDuration / 0.72 * 0.28, 1)
            let isReady = stableDuration >= 0.72
            let areaRatio = Float(
                min((bounds.width * bounds.height) / max(sceneView.bounds.width * sceneView.bounds.height, 1), 1)
            )
            let quality = min(max(facing * 0.62 + areaRatio * 0.38, 0), 1)
            return (
                PhotographicCaptureGuidance(
                    message: isReady
                        ? "ممتاز — يتم حفظ الجزء الآن."
                        : "ثابت… جارٍ فحص جودة الصورة.",
                    readiness: readiness,
                    isReady: isReady
                ),
                projected,
                quality
            )
        }

        private func capture(
            segment: WallPhotoSegment,
            projectedCorners: [CGPoint],
            qualityScore: Float,
            sceneView: ARSCNView
        ) {
            guideRoot.isHidden = true
            sceneView.setNeedsDisplay()
            DispatchQueue.main.async { [weak self, weak sceneView] in
                guard let self, let sceneView else { return }
                let snapshot = sceneView.snapshot()
                self.guideRoot.isHidden = false
                guard let corrected = self.perspectiveCorrectedImage(
                    snapshot: snapshot,
                    projectedCorners: projectedCorners,
                    viewSize: sceneView.bounds.size
                ), let data = corrected.jpegData(compressionQuality: 0.90) else {
                    self.captureInProgress = false
                    self.stableSince = nil
                    self.parent.onGuidanceChanged(
                        PhotographicCaptureGuidance(
                            message: "تعذر قص الجزء. أعد توجيه الكاميرا وحاول مرة أخرى.",
                            readiness: 0.2,
                            isReady: false
                        )
                    )
                    return
                }
                self.lastCapturedSegmentID = segment.id
                self.stableSince = nil
                self.parent.onCaptured(data, segment.id, qualityScore)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    self.captureInProgress = false
                    if self.parent.activeSegmentID != segment.id {
                        self.lastCapturedSegmentID = nil
                    }
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
                  let correctedCG = CIContext(options: nil).createCGImage(output, from: extent) else {
                return nil
            }
            return UIImage(cgImage: correctedCG)
        }

        private func segmentWorldCorners(
            segment: WallPhotoSegment,
            wall: WallSnapshot
        ) -> [SIMD3<Float>] {
            let locals: [SIMD4<Float>] = [
                SIMD4(segment.localMinX, segment.localMinY, 0.006, 1),
                SIMD4(segment.localMaxX, segment.localMinY, 0.006, 1),
                SIMD4(segment.localMaxX, segment.localMaxY, 0.006, 1),
                SIMD4(segment.localMinX, segment.localMaxY, 0.006, 1)
            ]
            return locals.map {
                let world = simd_mul(wall.matrix, $0)
                return SIMD3(world.x, world.y, world.z)
            }
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

        private func addBorder(
            to node: SCNNode,
            width: Float,
            height: Float,
            color: UIColor,
            thickness: CGFloat
        ) {
            func edge(
                width: CGFloat,
                height: CGFloat,
                x: Float,
                y: Float
            ) -> SCNNode {
                let box = SCNBox(
                    width: width,
                    height: height,
                    length: 0.004,
                    chamferRadius: 0
                )
                let material = SCNMaterial()
                material.diffuse.contents = color
                material.emission.contents = color.withAlphaComponent(0.55)
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
            return true
        case .notAvailable, .limited:
            return false
        }
    }
}

struct PhotographicScanOfferSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onStart: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("المسح الفوتوغرافي") {
                    Label("تصوير موجّه حسب أجزاء الحائط", systemImage: "viewfinder.rectangular")
                        .font(.headline)
                    Text(
                        "يقسم التطبيق كل حائط إلى شبكة تتناسب مع أبعاده، ثم يحفظ صورة "
                            + "فقط عندما يكون الجزء واضحًا وكاملًا والهاتف ثابتًا."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("طريقة العمل") {
                    Label("حرّك الهاتف نحو الجزء الأصفر", systemImage: "iphone.gen3")
                    Label("الالتقاط يتم تلقائيًا عند اكتمال الجودة", systemImage: "camera.badge.clock")
                    Label("يمكن تخطي أي جزء محجوب وإكماله لاحقًا", systemImage: "forward.end")
                }

                Section {
                    Button {
                        dismiss()
                        DispatchQueue.main.async {
                            onStart()
                        }
                    } label: {
                        Label("بدء المسح الفوتوغرافي", systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("صور الجدران")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("لاحقًا") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
