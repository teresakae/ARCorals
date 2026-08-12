import CoreGraphics
import Foundation
import Vision

/// `isOKSign` dead live; `isPointing` gates point-and-dwell. docs/ARCHITECTURE.md
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

        return isExtended(joints, tip: .middleTip, mcp: .middleMCP, palmWidth: palmWidth, gate: confidenceGate, threshold: tuning.okSignFingerExtendedRatio)
            && isExtended(joints, tip: .ringTip, mcp: .ringMCP, palmWidth: palmWidth, gate: confidenceGate, threshold: tuning.okSignFingerExtendedRatio)
            && isExtended(joints, tip: .littleTip, mcp: .littleMCP, palmWidth: palmWidth, gate: confidenceGate, threshold: tuning.okSignFingerExtendedRatio)
    }

    /// Index out, others in, thumb clearly open — blocks mid-pinch false points. docs/GESTURES.md §2.9
    static func isPointing(
        joints: [HumanHandPoseObservation.JointName: LandmarkFrame.JointSample],
        confidenceGate: Float = GestureTuning.default.confidenceGate,
        tuning: GestureTuning = .default
    ) -> Bool {
        guard
            let palmWidth = distance(joints, .indexMCP, .littleMCP, gate: confidenceGate),
            palmWidth > 1e-6
        else { return false }

        guard isExtended(joints, tip: .indexTip, mcp: .indexMCP, palmWidth: palmWidth, gate: confidenceGate, threshold: tuning.pointFingerExtendedRatio)
        else { return false }

        guard
            !isExtended(joints, tip: .middleTip, mcp: .middleMCP, palmWidth: palmWidth, gate: confidenceGate, threshold: tuning.pointFingerExtendedRatio),
            !isExtended(joints, tip: .ringTip, mcp: .ringMCP, palmWidth: palmWidth, gate: confidenceGate, threshold: tuning.pointFingerExtendedRatio),
            !isExtended(joints, tip: .littleTip, mcp: .littleMCP, palmWidth: palmWidth, gate: confidenceGate, threshold: tuning.pointFingerExtendedRatio)
        else { return false }

        // Thumb-index via `PinchRatioCalculator`; must clear `pinchEnterThreshold`.
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
        threshold: Double
    ) -> Bool {
        guard let d = distance(joints, tip, mcp, gate: gate) else { return false }
        return d / palmWidth > threshold
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
