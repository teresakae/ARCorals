import CoreGraphics
import Foundation
import Vision

/// OK-sign detector. Geometrically, an OK sign's thumb-index pinch is
/// identical to a normal pinch/grab (both read as a low pinchRatio) — what
/// distinguishes it is the other three fingers held extended rather than
/// curled. Used as a pause/stop override for an active manipulation
/// (see ARSessionCoordinator.handleVision / ManipulationTracker.forceCommit).
enum HandShapeClassifier {
    static func isOKSign(
        joints: [HumanHandPoseObservation.JointName: LandmarkFrame.JointSample],
        confidenceGate: Float = GestureTuning.default.confidenceGate,
        tuning: GestureTuning = .default
    ) -> Bool {
        guard
            let palmWidth = distance(joints, .indexMCP, .littleMCP, gate: confidenceGate),
            palmWidth > 1e-6,
            let pinch = distance(joints, .thumbTip, .indexTip, gate: confidenceGate),
            pinch / palmWidth < tuning.pinchThreshold
        else { return false }

        return isExtended(joints, tip: .middleTip, mcp: .middleMCP, palmWidth: palmWidth, gate: confidenceGate, tuning: tuning)
            && isExtended(joints, tip: .ringTip, mcp: .ringMCP, palmWidth: palmWidth, gate: confidenceGate, tuning: tuning)
            && isExtended(joints, tip: .littleTip, mcp: .littleMCP, palmWidth: palmWidth, gate: confidenceGate, tuning: tuning)
    }

    /// Pointing detector: index extended, middle/ring/little not, thumb
    /// clearly away from index (not just outside the pinch band — a mid-pinch
    /// hand must never misread as pointing). Used to gate the point-and-dwell
    /// target lookup (see ARSessionCoordinator+Point.swift).
    static func isPointing(
        joints: [HumanHandPoseObservation.JointName: LandmarkFrame.JointSample],
        confidenceGate: Float = GestureTuning.default.confidenceGate,
        tuning: GestureTuning = .default
    ) -> Bool {
        guard
            let palmWidth = distance(joints, .indexMCP, .littleMCP, gate: confidenceGate),
            palmWidth > 1e-6
        else { return false }

        guard isExtended(joints, tip: .indexTip, mcp: .indexMCP, palmWidth: palmWidth, gate: confidenceGate, tuning: tuning)
        else { return false }

        guard
            !isExtended(joints, tip: .middleTip, mcp: .middleMCP, palmWidth: palmWidth, gate: confidenceGate, tuning: tuning),
            !isExtended(joints, tip: .ringTip, mcp: .ringMCP, palmWidth: palmWidth, gate: confidenceGate, tuning: tuning),
            !isExtended(joints, tip: .littleTip, mcp: .littleMCP, palmWidth: palmWidth, gate: confidenceGate, tuning: tuning)
        else { return false }

        // Reuse PinchRatioCalculator's palmWidth ratio rather than re-deriving
        // thumb-index distance here. Pointing requires being clearly above
        // pinchEnterThreshold, not just below the pinch/carry band.
        guard
            let ratio = PinchRatioCalculator.ratios(from: joints, confidenceGate: confidenceGate).palmWidth,
            ratio > tuning.pinchEnterThreshold
        else { return false }

        return true
    }

    private static func isExtended(
        _ joints: [HumanHandPoseObservation.JointName: LandmarkFrame.JointSample],
        tip: HumanHandPoseObservation.JointName,
        mcp: HumanHandPoseObservation.JointName,
        palmWidth: Double,
        gate: Float,
        tuning: GestureTuning
    ) -> Bool {
        guard let d = distance(joints, tip, mcp, gate: gate) else { return false }
        return d / palmWidth > tuning.okSignFingerExtendedRatio
    }

    private static func distance(
        _ joints: [HumanHandPoseObservation.JointName: LandmarkFrame.JointSample],
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
