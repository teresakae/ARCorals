import CoreGraphics
import Foundation
import Vision

/// Pure 2D yaw candidates from landmarks. No ARKit types.
enum YawAngleCalculator {
    struct Candidates: Equatable, Sendable {
        /// thumbTip → indexTip (primary control signal per STEPS).
        let thumbIndex: Double?
        /// indexMCP → littleMCP (palm-axis alternate; logged for A/B). Shares
        /// its vector with pinchRatio's denominator (PinchRatioCalculator's
        /// palmWidth), so it's coupled to scale, not orthogonal to it.
        let palmAxis: Double?
        /// wrist → middleMCP — driving signal (ADR-018 follow-up). Distinct
        /// from both pinchRatio's numerator (thumbTip→indexTip) and
        /// denominator (indexMCP→littleMCP), so wrist twist doesn't spike
        /// scale while rotating this one.
        let wristMiddle: Double?
    }

    /// ARFrame.capturedImage is 1920x1440 (4:3), and Vision's normalized
    /// 0-1 joint coordinates span that non-square buffer — a raw
    /// atan2(dy, dx) over them distorts angles. Scale dy into dx's units
    /// before the atan2.
    /// ponytail: hardcoded from the known capture format (LandmarkFrame's
    /// `orientation: .right` doesn't change the buffer's physical aspect,
    /// just which axis is which); thread real buffer dimensions through if
    /// the capture format ever changes.
    private static let bufferWidth: Double = 1920
    private static let bufferHeight: Double = 1440

    static func angles(
        from frame: LandmarkFrame,
        confidenceGate: Float = GestureTuning.default.confidenceGate
    ) -> Candidates {
        Candidates(
            thumbIndex: angle(
                from: frame.joints,
                a: .thumbTip,
                b: .indexTip,
                gate: confidenceGate
            ),
            palmAxis: angle(
                from: frame.joints,
                a: .indexMCP,
                b: .littleMCP,
                gate: confidenceGate
            ),
            wristMiddle: angle(
                from: frame.joints,
                a: .wrist,
                b: .middleMCP,
                gate: confidenceGate
            )
        )
    }

    private static func angle(
        from joints: [HumanHandPoseObservation.JointName: LandmarkFrame.JointSample],
        a: HumanHandPoseObservation.JointName,
        b: HumanHandPoseObservation.JointName,
        gate: Float
    ) -> Double? {
        guard
            let ja = joints[a], ja.confidence >= gate,
            let jb = joints[b], jb.confidence >= gate
        else { return nil }
        let dx = Double(jb.x - ja.x)
        // Was bufferHeight/bufferWidth (0.75) — inverted. Vision's normalized
        // space here is the .right-rotated image (x spans 1440px, y spans
        // 1920px per LandmarkSpace's axis swap), so removing that anisotropy
        // needs bufferWidth/bufferHeight (1.333), not its reciprocal. The
        // wrong factor was compressing exactly the axis the landscape mount
        // now puts the hand rotation on — see DECISIONS.md.
        let dy = Double(jb.y - ja.y) * (bufferWidth / bufferHeight)
        return atan2(dy, dx)
    }
}
