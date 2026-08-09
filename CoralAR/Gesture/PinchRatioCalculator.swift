import CoreGraphics
import Foundation
import Vision

/// Pure pinch-ratio math. Primary signal: `palmWidth` (ADR-015).
enum PinchRatioCalculator {
    struct Ratios: Sendable {
        let wristMCP: Double?
        let bboxDiag: Double?
        let palmWidth: Double?
        let rawThumbIndexDist: Double?
    }

    static func ratios(
        from joints: [HumanHandPoseObservation.JointName: LandmarkFrame.JointSample],
        confidenceGate: Float = GestureTuning.default.confidenceGate
    ) -> Ratios {
        let raw = distance(joints, .thumbTip, .indexTip, gate: confidenceGate)
        return Ratios(
            wristMCP: ratio(numerator: raw, denominator: distance(joints, .wrist, .middleMCP, gate: confidenceGate)),
            bboxDiag: ratio(numerator: raw, denominator: bboxDiagonal(joints, gate: confidenceGate)),
            palmWidth: ratio(numerator: raw, denominator: distance(joints, .indexMCP, .littleMCP, gate: confidenceGate)),
            rawThumbIndexDist: raw
        )
    }

    private static func ratio(numerator: Double?, denominator: Double?) -> Double? {
        guard let numerator, let denominator, denominator > 1e-6 else { return nil }
        return numerator / denominator
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

    private static func bboxDiagonal(
        _ joints: [HumanHandPoseObservation.JointName: LandmarkFrame.JointSample],
        gate: Float
    ) -> Double? {
        let pts = joints.values.filter { $0.confidence >= gate }
        guard pts.count >= 2 else { return nil }
        let xs = pts.map(\.x)
        let ys = pts.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        let dx = Double(maxX - minX)
        let dy = Double(maxY - minY)
        let diag = sqrt(dx * dx + dy * dy)
        return diag > 1e-6 ? diag : nil
    }
}

/// Rolling min/max for calibration HUD.
struct RollingMinMax {
    private var samples: [(t: TimeInterval, v: Double)] = []
    private let window: TimeInterval

    init(windowSeconds: TimeInterval = 2.0) {
        self.window = windowSeconds
    }

    mutating func push(_ value: Double?, now: TimeInterval) {
        samples.removeAll { now - $0.t > window }
        guard let value else { return }
        samples.append((now, value))
    }

    var min: Double? { samples.map(\.v).min() }
    var max: Double? { samples.map(\.v).max() }
}

enum GroundTruthState: String, Sendable {
    case open
    case pinched
}
