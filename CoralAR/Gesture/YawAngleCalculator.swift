import CoreGraphics
import Foundation
import Vision

/// Pure 2D yaw candidates from landmarks. No ARKit types.
enum YawAngleCalculator {
    struct Candidates: Equatable, Sendable {
        /// thumbTip → indexTip (primary control signal per STEPS).
        let thumbIndex: Double?
        /// Palm-axis (indexMCP→littleMCP); shares pinchRatio denominator — coupled to scale. A/B only.
        let palmAxis: Double?
        /// Wrist→middleMCP candidate (ADR-018); orthogonal to pinchRatio axes. Not live.
        let wristMiddle: Double?
    }

    /// Same default as `PinchRatioCalculator.defaultDyAspectCorrection` — keep in sync. Caller
    /// passes the value matching its live orientation (`LandmarkSpace.dyAspectCorrection(for:)`).
    static let defaultDyAspectCorrection = PinchRatioCalculator.defaultDyAspectCorrection

    static func angles(
        from frame: LandmarkFrame,
        confidenceGate: Float = GestureTuning.default.confidenceGate,
        dyAspectCorrection: Double = defaultDyAspectCorrection
    ) -> Candidates {
        Candidates(
            thumbIndex: angle(
                from: frame.joints,
                a: .thumbTip,
                b: .indexTip,
                gate: confidenceGate,
                dyAspectCorrection: dyAspectCorrection
            ),
            palmAxis: angle(
                from: frame.joints,
                a: .indexMCP,
                b: .littleMCP,
                gate: confidenceGate,
                dyAspectCorrection: dyAspectCorrection
            ),
            wristMiddle: angle(
                from: frame.joints,
                a: .wrist,
                b: .middleMCP,
                gate: confidenceGate,
                dyAspectCorrection: dyAspectCorrection
            )
        )
    }

    private static func angle(
        from joints: [HumanHandPoseObservation.JointName: LandmarkFrame.JointSample],
        a: HumanHandPoseObservation.JointName,
        b: HumanHandPoseObservation.JointName,
        gate: Float,
        dyAspectCorrection: Double
    ) -> Double? {
        guard
            let ja = joints[a], ja.confidence >= gate,
            let jb = joints[b], jb.confidence >= gate
        else { return nil }
        let dx = Double(jb.x - ja.x)
        let dy = Double(jb.y - ja.y) * dyAspectCorrection
        return atan2(dy, dx)
    }
}
