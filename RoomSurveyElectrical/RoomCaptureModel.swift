import ARKit
import Combine
import RoomPlan
import SwiftUI

@MainActor
final class RoomCaptureModel: NSObject, ObservableObject, RoomCaptureViewDelegate {
    enum Phase: Equatable {
        case idle
        case scanning
        case processing
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var project: RoomProject?

    let arSession: ARSession
    let roomCaptureView: RoomCaptureView

    private let configuration = RoomCaptureSession.Configuration()
    private var rawRoomData: CapturedRoomData?

    override init() {
        let sharedSession = ARSession()
        arSession = sharedSession
        roomCaptureView = RoomCaptureView(frame: .zero, arSession: sharedSession)
        super.init()
        roomCaptureView.delegate = self
    }

    required init?(coder: NSCoder) {
        let sharedSession = ARSession()
        arSession = sharedSession
        roomCaptureView = RoomCaptureView(frame: .zero, arSession: sharedSession)
        super.init()
        roomCaptureView.delegate = self
    }

    nonisolated func encode(with coder: NSCoder) {
        // RoomCaptureViewDelegate inherits from NSCoding. This model has no
        // state that should be archived, but the protocol requirement must be
        // implemented for the project to compile.
    }

    var isSupported: Bool {
        RoomCaptureSession.isSupported
    }

    func start() {
        guard isSupported else {
            phase = .failed("هذا الجهاز لا يدعم RoomPlan أو لا يحتوي على LiDAR.")
            return
        }
        guard phase == .idle else { return }

        rawRoomData = nil
        project = nil
        phase = .scanning
        roomCaptureView.captureSession.run(configuration: configuration)
    }

    func finish() {
        guard phase == .scanning else { return }
        phase = .processing

        // Keep the AR session alive so the electrical editor uses the exact
        // coordinate system produced by RoomPlan.
        roomCaptureView.captureSession.stop(pauseARSession: false)
    }

    func cancel() {
        if phase == .scanning || phase == .processing {
            roomCaptureView.captureSession.stop(pauseARSession: true)
        }
        arSession.pause()
        phase = .idle
    }

    nonisolated func captureView(
        shouldPresent roomDataForProcessing: CapturedRoomData,
        error: Error?
    ) -> Bool {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                self.phase = .failed(error.localizedDescription)
            } else {
                self.rawRoomData = roomDataForProcessing
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
                self.phase = .failed(error.localizedDescription)
                return
            }

            do {
                self.project = try ProjectRepository.createProject(
                    room: processedResult,
                    rawData: self.rawRoomData
                )
                self.phase = .ready
            } catch {
                self.phase = .failed("فشل حفظ نتيجة المسح: \(error.localizedDescription)")
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
