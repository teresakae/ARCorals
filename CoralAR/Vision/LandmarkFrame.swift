import CoreGraphics
import Foundation
import Vision

/// Immutable Vision output. No CVPixelBuffer, no ARFrame.
struct LandmarkFrame: Sendable {
    let timestamp: TimeInterval
    let observationConfidence: Float
    let chirality: HumanHandPoseObservation.Chirality?
    let joints: [HumanHandPoseObservation.JointName: JointSample]
    let inferenceHz: Double

    struct JointSample: Sendable {
        let name: HumanHandPoseObservation.JointName
        /// Vision-normalized, origin bottom-left, after `orientation: .right`.
        let x: CGFloat
        let y: CGFloat
        let confidence: Float
    }

    static let jointNames: [HumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]

    /// Midpoint of thumbTip + indexTip (placement ray origin). Nil if gated out.
    func pinchPoint(confidenceGate: Float) -> CGPoint? {
        guard
            let thumb = joints[.thumbTip], thumb.confidence >= confidenceGate,
            let index = joints[.indexTip], index.confidence >= confidenceGate
        else { return nil }
        return CGPoint(x: (thumb.x + index.x) / 2, y: (thumb.y + index.y) / 2)
    }

    /// Index fingertip point (point-and-dwell target). Nil if gated out.
    func indexTipPoint(confidenceGate: Float) -> CGPoint? {
        guard let index = joints[.indexTip], index.confidence >= confidenceGate else { return nil }
        return CGPoint(x: index.x, y: index.y)
    }

    var jointList: [JointSample] { Array(joints.values) }
}
