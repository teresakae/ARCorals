import CoreGraphics
import Foundation
import Vision

/// OK-sign detector — mirrored from CoralAR/Gesture/HandShapeClassifier.swift
/// for HandProbeTests coverage. Tight thumb-index pinch (same geometry as a
/// normal pinch, per GestureTuning.pinchThreshold) plus middle/ring/little
/// fingers extended, which a normal pinch/grab does not have.
enum HandShapeClassifier {
    static func isOKSign(joints: [HumanHandPoseObservation.JointName: JointSample]) -> Bool {
        let gate = GestureTuning.default.confidenceGate
        guard
            let palmWidth = distance(joints, .indexMCP, .littleMCP, gate: gate),
            palmWidth > 1e-6,
            let pinch = distance(joints, .thumbTip, .indexTip, gate: gate),
            pinch / palmWidth < GestureTuning.default.pinchThreshold
        else { return false }

        return isExtended(joints, tip: .middleTip, mcp: .middleMCP, palmWidth: palmWidth, gate: gate)
            && isExtended(joints, tip: .ringTip, mcp: .ringMCP, palmWidth: palmWidth, gate: gate)
            && isExtended(joints, tip: .littleTip, mcp: .littleMCP, palmWidth: palmWidth, gate: gate)
    }

    private static func isExtended(
        _ joints: [HumanHandPoseObservation.JointName: JointSample],
        tip: HumanHandPoseObservation.JointName,
        mcp: HumanHandPoseObservation.JointName,
        palmWidth: Double,
        gate: Float
    ) -> Bool {
        guard let d = distance(joints, tip, mcp, gate: gate) else { return false }
        return d / palmWidth > GestureTuning.default.okSignFingerExtendedRatio
    }

    private static func distance(
        _ joints: [HumanHandPoseObservation.JointName: JointSample],
        _ a: HumanHandPoseObservation.JointName,
        _ b: HumanHandPoseObservation.JointName,
        gate: Float
    ) -> Double? {
        guard
            let ja = joints[a], ja.confidence >= gate,
            let jb = joints[b], jb.confidence >= gate
        else { return nil }
        let dx = ja.x - jb.x
        let dy = ja.y - jb.y
        return Double(sqrt(dx * dx + dy * dy))
    }
}
