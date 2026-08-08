import CoreGraphics
import Foundation
import Vision

/// Named confidence gate (guess until Phase 1 numbers say otherwise). AGENTS: 0.3–0.5.
enum GestureTuning {
    static let confidenceGate: Float = 0.3
}

/// Pure pinch-ratio math. No threshold — Phase 1 is measurement only.
enum PinchRatioCalculator {
    struct Ratios: Sendable {
        /// dist(thumbTip, indexTip) / dist(wrist, middleMCP)
        let wristMCP: Double?
        /// dist(thumbTip, indexTip) / bbox diagonal of confidence-gated joints
        let bboxDiag: Double?
        /// dist(thumbTip, indexTip) / dist(indexMCP, littleMCP)
        let palmWidth: Double?
        let rawThumbIndexDist: Double?
    }

    static func ratios(from joints: [HumanHandPoseObservation.JointName: JointSample]) -> Ratios {
        let raw = distance(joints, .thumbTip, .indexTip)
        return Ratios(
            wristMCP: ratio(numerator: raw, denominator: distance(joints, .wrist, .middleMCP)),
            bboxDiag: ratio(numerator: raw, denominator: bboxDiagonal(joints)),
            palmWidth: ratio(numerator: raw, denominator: distance(joints, .indexMCP, .littleMCP)),
            rawThumbIndexDist: raw
        )
    }

    private static func ratio(numerator: Double?, denominator: Double?) -> Double? {
        guard let numerator, let denominator, denominator > 1e-6 else { return nil }
        return numerator / denominator
    }

    private static func distance(
        _ joints: [HumanHandPoseObservation.JointName: JointSample],
        _ a: HumanHandPoseObservation.JointName,
        _ b: HumanHandPoseObservation.JointName
    ) -> Double? {
        guard
            let ja = joints[a], ja.confidence >= GestureTuning.confidenceGate,
            let jb = joints[b], jb.confidence >= GestureTuning.confidenceGate
        else { return nil }
        let dx = ja.x - jb.x
        let dy = ja.y - jb.y
        return Double(sqrt(dx * dx + dy * dy))
    }

    private static func bboxDiagonal(
        _ joints: [HumanHandPoseObservation.JointName: JointSample]
    ) -> Double? {
        let pts = joints.values.filter { $0.confidence >= GestureTuning.confidenceGate }
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

/// Rolling min/max over a wall-clock window (Phase 1 noise-band HUD).
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
