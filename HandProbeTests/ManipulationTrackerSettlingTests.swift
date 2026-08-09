import Foundation
import XCTest
@testable import HandProbe

/// Settling window — nothing counts until the pinch has stopped closing.
final class ManipulationTrackerSettlingTests: XCTestCase {
    private let frame: TimeInterval = 1.0 / 15.0

    private func makeTracker() -> ManipulationTracker {
        var t = GestureTuning.default
        t.scaleDeadzoneLog = 0.20
        t.yawDeadzoneRad = 0.20
        t.scaleSensitivity = 1.0
        t.yawSensitivity = 1.0
        t.settleQuietLogDelta = 0.06
        t.settleTimeout = 0.6
        return ManipulationTracker(tuning: t)
    }

    /// Baseline must come from the settled hand, not from the closing motion.
    func testBaselineIsCapturedAfterPinchStopsClosing() {
        var mt = makeTracker()
        mt.begin(entityScale: 1.0, entityYaw: 0.0)

        // ~200ms of continuous closing: 1.6 → 0.6, big per-frame steps.
        var t: TimeInterval = 0
        let closing = [1.60, 1.15, 0.83, 0.62]
        for ratio in closing {
            let r = mt.update(ratio: ratio, yaw: 0.0, now: t)
            XCTAssertFalse(mt.isArmed, "must not arm while the pinch is still closing")
            XCTAssertNil(r.baselineRatio, "no baseline during the closing motion")
            XCTAssertEqual(r.mode, .ambiguous)
            t += frame
        }

        // Hand settles at ~0.60.
        var last = mt.update(ratio: 0.601, yaw: 0.0, now: t); t += frame
        last = mt.update(ratio: 0.599, yaw: 0.0, now: t); t += frame
        XCTAssertTrue(mt.isArmed)
        XCTAssertNotNil(last.baselineRatio)
        XCTAssertEqual(last.baselineRatio ?? 0, 0.60, accuracy: 0.01,
                       "baseline must be the settled value, not a mid-closure sample")

        // A deliberate open from the settled baseline still locks scale.
        last = mt.update(ratio: 0.60 * exp(0.30), yaw: 0.0, now: t)
        XCTAssertEqual(last.mode, .scale)
        XCTAssertTrue(last.didLock)
    }

    /// The timeout arms the gesture even if the hand never goes quiet.
    func testNeverSettlingArmsAtTimeout() {
        var mt = makeTracker()
        mt.begin(entityScale: 1.0, entityYaw: 0.0)

        var t: TimeInterval = 0
        var ratio = 1.0
        for i in 0..<12 {
            ratio *= (i % 2 == 0) ? exp(0.3) : exp(-0.3)   // never quiet
            _ = mt.update(ratio: ratio, yaw: 0.0, now: t)
            t += frame
        }
        XCTAssertGreaterThanOrEqual(t, 0.6)
        XCTAssertTrue(mt.isArmed, "settleTimeout must arm a gesture that never stabilizes")
    }

    /// Bug B: settling jitter on the ratio channel must not win the mode-lock
    /// race against a real, sustained rotation that starts afterwards.
    func testSettlingJitterThenSustainedYawLocksYaw() {
        var mt = makeTracker()
        mt.begin(entityScale: 1.0, entityYaw: 0.0)

        // Closing + jitter big enough to blow past scaleDeadzoneLog (0.20).
        var t: TimeInterval = 0
        for ratio in [1.50, 0.95, 0.70, 0.55, 0.72, 0.58] {
            _ = mt.update(ratio: ratio, yaw: 0.0, now: t)
            t += frame
        }
        XCTAssertEqual(mt.mode, .ambiguous, "settling jitter must not lock a mode")

        // Hand goes quiet, then rotates deliberately while the ratio holds.
        for _ in 0..<3 {
            _ = mt.update(ratio: 0.60, yaw: 0.0, now: t)
            t += frame
        }
        var last = mt.update(ratio: 0.60, yaw: 0.0, now: t)
        for step in 1...6 {
            t += frame
            last = mt.update(ratio: 0.60, yaw: Double(step) * 0.05, now: t)
        }
        XCTAssertEqual(last.mode, .yaw, "sustained rotation should win the race")
        XCTAssertNil(last.scale)
    }

    /// Bug A: closing past the baseline must produce a usable shrink, not ~0.9x.
    func testShrinkFromSettledBaselineReachesUsefulRange() throws {
        var mt = makeTracker()
        mt.tuning.scaleShrinkSensitivity = 1.75
        mt.begin(entityScale: 1.0, entityYaw: 0.0)

        var t: TimeInterval = 0
        for _ in 0..<3 {
            _ = mt.update(ratio: 0.64, yaw: 0.0, now: t)
            t += frame
        }
        // Close to the measured physical floor (~0.31 → log ≈ -0.72).
        var last = mt.update(ratio: 0.64 * exp(-0.25), yaw: 0.0, now: t); t += frame
        XCTAssertEqual(last.mode, .scale)
        last = mt.update(ratio: 0.31, yaw: 0.0, now: t)
        let scale = try XCTUnwrap(last.scale)
        // At the symmetric sensitivity (1.0) this same motion only reaches
        // ~0.48x; the shrink exponent has to carry it well below that.
        XCTAssertLessThan(scale, 0.40, "shrink must reach a visibly smaller model")
    }
}
