import CoreGraphics
import Foundation
import Vision

/// `isOKSign` dead live; `isPointing` gates point-and-dwell. docs/ARCHITECTURE.md
enum HandShapeClassifier {
    /// Same default as `PinchRatioCalculator.defaultDyAspectCorrection` — keep in sync.
    static let defaultDyAspectCorrection = PinchRatioCalculator.defaultDyAspectCorrection

    static func isOKSign(
        joints: [HumanHandPoseObservation.JointName: LandmarkFrame.JointSample],
        confidenceGate: Float = GestureTuning.default.confidenceGate,
        tuning: GestureTuning = .default,
        dyAspectCorrection: Double = defaultDyAspectCorrection
    ) -> Bool {
        guard
            let palmWidth = distance(joints, .indexMCP, .littleMCP, gate: confidenceGate, dyAspectCorrection: dyAspectCorrection),
            palmWidth > 1e-6,
            let pinch = distance(joints, .thumbTip, .indexTip, gate: confidenceGate, dyAspectCorrection: dyAspectCorrection),
            pinch / palmWidth < tuning.pinchThreshold
        else { return false }

        return isExtended(joints, tip: .middleTip, mcp: .middleMCP, palmWidth: palmWidth, gate: confidenceGate, threshold: tuning.okSignFingerExtendedRatio, dyAspectCorrection: dyAspectCorrection)
            && isExtended(joints, tip: .ringTip, mcp: .ringMCP, palmWidth: palmWidth, gate: confidenceGate, threshold: tuning.okSignFingerExtendedRatio, dyAspectCorrection: dyAspectCorrection)
            && isExtended(joints, tip: .littleTip, mcp: .littleMCP, palmWidth: palmWidth, gate: confidenceGate, threshold: tuning.okSignFingerExtendedRatio, dyAspectCorrection: dyAspectCorrection)
    }

    /// Index out, thumb clearly open, and at least 2 of {middle, ring, little} read curled —
    /// relaxed from "all 3" because those three tips are this project's least-reliable landmarks
    /// (7.9-11.7% confidence dropout / jitter misreads vs. 2.1-2.3% for thumb/index, Phase 0 data).
    /// Tolerating one ambiguous reading stops a single weak-landmark misread from killing the
    /// whole gate. Stays pure/stateless — no history; temporal smoothing lives in
    /// `PointStateMachine`, not here. docs/GESTURES.md §2.9
    static func isPointing(
        joints: [HumanHandPoseObservation.JointName: LandmarkFrame.JointSample],
        confidenceGate: Float = GestureTuning.default.confidenceGate,
        tuning: GestureTuning = .default,
        dyAspectCorrection: Double = defaultDyAspectCorrection
    ) -> Bool {
        guard
            let palmWidth = distance(joints, .indexMCP, .littleMCP, gate: confidenceGate, dyAspectCorrection: dyAspectCorrection),
            palmWidth > 1e-6
        else { return false }

        guard isExtended(joints, tip: .indexTip, mcp: .indexMCP, palmWidth: palmWidth, gate: confidenceGate, threshold: tuning.pointFingerExtendedRatio, dyAspectCorrection: dyAspectCorrection)
        else { return false }

        let middleCurled = !isExtended(joints, tip: .middleTip, mcp: .middleMCP, palmWidth: palmWidth, gate: confidenceGate, threshold: tuning.pointFingerExtendedRatio, dyAspectCorrection: dyAspectCorrection)
        let ringCurled = !isExtended(joints, tip: .ringTip, mcp: .ringMCP, palmWidth: palmWidth, gate: confidenceGate, threshold: tuning.pointFingerExtendedRatio, dyAspectCorrection: dyAspectCorrection)
        let littleCurled = !isExtended(joints, tip: .littleTip, mcp: .littleMCP, palmWidth: palmWidth, gate: confidenceGate, threshold: tuning.pointFingerExtendedRatio, dyAspectCorrection: dyAspectCorrection)
        let curledCount = [middleCurled, ringCurled, littleCurled].filter { $0 }.count
        guard curledCount >= 2 else { return false }

        // Thumb-index via `PinchRatioCalculator`; must clear `pinchEnterThreshold`.
        guard
            let ratio = PinchRatioCalculator.ratios(from: joints, confidenceGate: confidenceGate, dyAspectCorrection: dyAspectCorrection).palmWidth,
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
        threshold: Double,
        dyAspectCorrection: Double = defaultDyAspectCorrection
    ) -> Bool {
        guard let d = distance(joints, tip, mcp, gate: gate, dyAspectCorrection: dyAspectCorrection) else { return false }
        return d / palmWidth > threshold
    }

    private static func distance(
        _ joints: [HumanHandPoseObservation.JointName: LandmarkFrame.JointSample],
        _ a: HumanHandPoseObservation.JointName,
        _ b: HumanHandPoseObservation.JointName,
        gate: Float,
        dyAspectCorrection: Double = defaultDyAspectCorrection
    ) -> Double? {
        guard
            let ja = joints[a], ja.confidence >= gate,
            let jb = joints[b], jb.confidence >= gate
        else { return nil }
        let dx = Double(ja.x - jb.x)
        let dy = Double(ja.y - jb.y) * dyAspectCorrection
        return sqrt(dx * dx + dy * dy)
    }
}
