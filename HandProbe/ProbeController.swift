import AVFoundation
import Combine
import Foundation
import QuartzCore
import UIKit
import Vision

@MainActor
final class ProbeController: ObservableObject {
    @Published var latest: HandPoseResult?
    @Published var latestRatios: PinchRatioCalculator.Ratios?
    @Published var overlayJoints: [JointSample] = []
    /// Oriented image size after applying `.right` (width/height swapped from buffer).
    @Published var orientedImageSize: CGSize = .zero
    @Published var distanceCm: Int = 40
    @Published var rigNotes: String = "desk mount; lighting TBD; height/tilt TBD"
    @Published var logCondition: String = "pinchratio"
    @Published var isLogging = false
    @Published var logFileName: String = ""
    @Published var cameraAuthorized = false
    @Published var statusMessage: String = "Starting…"
    @Published var smoothedFps: Double = 0
    /// Experimenter label for CSV `ground_truth_state`. Prefer assistant/foot switch.
    @Published var groundTruth: GroundTruthState? = nil

    @Published var wristMCPMin: Double?
    @Published var wristMCPMax: Double?
    @Published var bboxDiagMin: Double?
    @Published var bboxDiagMax: Double?
    @Published var palmWidthMin: Double?
    @Published var palmWidthMax: Double?

    let camera = CameraFeed()
    private let detector = HandPoseDetector()
    private let logger = MetricsLogger()

    private var fpsWindowStart = CACurrentMediaTime()
    private var fpsCount = 0
    private var rollWrist = RollingMinMax()
    private var rollBBox = RollingMinMax()
    private var rollPalm = RollingMinMax()

    func start() {
        requestCameraAccessAndRun()
    }

    func stop() {
        camera.stop()
        logger.stop()
        isLogging = false
    }

    func setGroundTruth(_ state: GroundTruthState) {
        groundTruth = state
    }

    func clearGroundTruth() {
        groundTruth = nil
    }

    func toggleLogging() {
        if isLogging {
            logger.stop()
            isLogging = false
            statusMessage = "Logging stopped"
            return
        }
        do {
            try logger.startNewFile(
                condition: logCondition,
                rigNotes: rigNotes,
                distanceCm: distanceCm
            )
            isLogging = true
            logFileName = logger.fileURL?.lastPathComponent ?? ""
            statusMessage = "Logging → \(logFileName)"
        } catch {
            statusMessage = "Log start failed: \(error.localizedDescription)"
        }
    }

    private func requestCameraAccessAndRun() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorized = true
            beginSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.cameraAuthorized = granted
                    if granted {
                        self?.beginSession()
                    } else {
                        self?.statusMessage = "Camera permission denied"
                    }
                }
            }
        default:
            cameraAuthorized = false
            statusMessage = "Camera permission denied — enable in Settings"
        }
    }

    private func beginSession() {
        statusMessage = "Camera running"
        camera.onFrame = { [weak self] buffer in
            self?.handleFrame(buffer)
        }
        camera.start()
    }

    nonisolated private func handleFrame(_ pixelBuffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let oriented = CGSize(width: height, height: width)
        let box = UncheckedPixelBuffer(buffer: pixelBuffer)

        Task { [detector] in
            let result = await detector.consider(box)
            guard !result.skipped else { return }
            await self.publish(result: result, orientedSize: oriented)
        }
    }

    private func publish(result: HandPoseResult, orientedSize: CGSize) {
        latest = result
        overlayJoints = JointSample.allNames.compactMap { result.joints[$0] }
        orientedImageSize = orientedSize

        let ratios = PinchRatioCalculator.ratios(from: result.joints)
        latestRatios = ratios

        let now = CACurrentMediaTime()
        rollWrist.push(ratios.wristMCP, now: now)
        rollBBox.push(ratios.bboxDiag, now: now)
        rollPalm.push(ratios.palmWidth, now: now)
        wristMCPMin = rollWrist.min
        wristMCPMax = rollWrist.max
        bboxDiagMin = rollBBox.min
        bboxDiagMax = rollBBox.max
        palmWidthMin = rollPalm.min
        palmWidthMax = rollPalm.max

        fpsCount += 1
        let elapsed = now - fpsWindowStart
        if elapsed >= 1.0 {
            smoothedFps = Double(fpsCount) / elapsed
            fpsCount = 0
            fpsWindowStart = now
        }

        if isLogging {
            logger.log(
                result: result,
                ratios: ratios,
                groundTruth: groundTruth,
                distanceCm: distanceCm,
                thermalState: ProcessInfo.processInfo.thermalState,
                fps: smoothedFps
            )
        }
    }
}
