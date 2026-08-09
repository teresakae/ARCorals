import CoreVideo
import Foundation
import QuartzCore
import Vision

/// Runs `DetectHumanHandPoseRequest` on a serial actor. orientation: `.right` (hardcoded).
actor HandPoseDetector {
    private var request = DetectHumanHandPoseRequest()

    init() {
        request.maximumHandCount = 1
    }

    func detect(pixelBuffer: CVPixelBuffer) async -> LandmarkFrame? {
        let start = CACurrentMediaTime()
        do {
            nonisolated(unsafe) let buffer = pixelBuffer
            let observations = try await request.perform(on: buffer, orientation: .right)
            let elapsed = CACurrentMediaTime() - start
            let hz = elapsed > 0 ? 1.0 / elapsed : 0

            guard let hand = observations.first else {
                return LandmarkFrame(
                    timestamp: start,
                    observationConfidence: 0,
                    chirality: nil,
                    joints: [:],
                    inferenceHz: hz
                )
            }

            var joints: [HumanHandPoseObservation.JointName: LandmarkFrame.JointSample] = [:]
            for name in LandmarkFrame.jointNames {
                if let joint = hand.joint(for: name) {
                    joints[name] = LandmarkFrame.JointSample(
                        name: name,
                        x: joint.location.x,
                        y: joint.location.y,
                        confidence: joint.confidence
                    )
                }
            }
            return LandmarkFrame(
                timestamp: start,
                observationConfidence: hand.confidence,
                chirality: hand.chirality,
                joints: joints,
                inferenceHz: hz
            )
        } catch {
            return nil
        }
    }
}
