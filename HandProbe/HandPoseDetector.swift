import CoreGraphics
import CoreVideo
import Foundation
import QuartzCore
import Vision

/// CVPixelBuffer is not Sendable; we retain one buffer while Vision runs and drop others.
struct UncheckedPixelBuffer: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

/// Throttled Vision hand-pose runner. Actor-serial; returns `.skipped` when throttled or busy.
actor HandPoseDetector {
    /// ~15 Hz. Named so Phase 1 can retune without hunting.
    static let inferenceInterval: TimeInterval = 0.066

    private var request = DetectHumanHandPoseRequest()
    private var lastInferenceTime: CFTimeInterval = 0
    private var inFlight = false

    init() {
        request.maximumHandCount = 1
    }

    func consider(_ box: UncheckedPixelBuffer) async -> HandPoseResult {
        let pixelBuffer = box.buffer
        let now = CACurrentMediaTime()
        if now - lastInferenceTime < Self.inferenceInterval || inFlight {
            return .skipped
        }
        inFlight = true
        lastInferenceTime = now
        defer { inFlight = false }

        let start = now
        do {
            // Vision API is not isolation-aware; buffer is exclusively ours while inFlight.
            nonisolated(unsafe) let buffer = pixelBuffer
            let observations = try await request.perform(
                on: buffer,
                orientation: .right
            )
            let elapsed = CACurrentMediaTime() - start
            let hz = elapsed > 0 ? 1.0 / elapsed : 0

            guard let hand = observations.first else {
                return HandPoseResult(
                    skipped: false,
                    observationCount: 0,
                    observationConfidence: 0,
                    joints: [:],
                    chirality: nil,
                    inferenceHz: hz,
                    timestamp: Date()
                )
            }

            var joints: [HumanHandPoseObservation.JointName: JointSample] = [:]
            for name in JointSample.allNames {
                if let joint = hand.joint(for: name) {
                    joints[name] = JointSample(
                        name: name,
                        x: joint.location.x,
                        y: joint.location.y,
                        confidence: joint.confidence
                    )
                }
            }
            return HandPoseResult(
                skipped: false,
                observationCount: observations.count,
                observationConfidence: hand.confidence,
                joints: joints,
                chirality: hand.chirality,
                inferenceHz: hz,
                timestamp: Date()
            )
        } catch {
            return HandPoseResult(
                skipped: false,
                observationCount: 0,
                observationConfidence: 0,
                joints: [:],
                chirality: nil,
                inferenceHz: 0,
                timestamp: Date()
            )
        }
    }
}

struct JointSample: Sendable {
    let name: HumanHandPoseObservation.JointName
    /// Vision-normalized, origin bottom-left, in the *oriented* image after `.right`.
    let x: CGFloat
    let y: CGFloat
    let confidence: Float

    static let allNames: [HumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]
}

struct HandPoseResult: Sendable {
    /// True when throttle/in-flight dropped this frame (do not log or update HUD rate).
    let skipped: Bool
    let observationCount: Int
    let observationConfidence: Float
    let joints: [HumanHandPoseObservation.JointName: JointSample]
    let chirality: HumanHandPoseObservation.Chirality?
    let inferenceHz: Double
    let timestamp: Date

    static let skipped = HandPoseResult(
        skipped: true,
        observationCount: 0,
        observationConfidence: 0,
        joints: [:],
        chirality: nil,
        inferenceHz: 0,
        timestamp: Date()
    )
}
