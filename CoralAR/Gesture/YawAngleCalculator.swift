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

    /// ⚠️ Aspect-correct dy before atan2 (4:3). Hardcoded 1920×1440; thread size if format changes.
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
        // ⚠️ width/height (1.333) after `.right` swap — reciprocal crushed yaw (GESTURES.md §2.3).
        let dy = Double(jb.y - ja.y) * (bufferWidth / bufferHeight)
        return atan2(dy, dx)
    }
}
