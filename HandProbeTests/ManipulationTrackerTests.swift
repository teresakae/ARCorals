import Foundation
import XCTest
@testable import HandProbe

final class ManipulationTrackerTests: XCTestCase {
    private func makeTracker() -> ManipulationTracker {
        var t = GestureTuning.default
        // Tight, deterministic deadzones for unit tests.
        t.scaleDeadzoneLog = 0.20
        t.yawDeadzoneRad = 0.20
        t.scaleSensitivity = 1.0
        t.yawSensitivity = 1.0
        return ManipulationTracker(tuning: t)
    }

    /// Three identical samples establish baseline (median of first 3 usable frames).
    private func establishBaseline(
        _ mt: inout ManipulationTracker,
        ratio: Double,
        yaw: Double
    ) {
        for _ in 0..<3 {
            let r = mt.update(ratio: ratio, yaw: yaw)
            XCTAssertEqual(r.mode, .ambiguous)
            XCTAssertNil(r.scale)
            XCTAssertNil(r.appliedYaw)
        }
    }

    // MARK: - Pure scale → locks scale, zero yaw applied

    func testPureScaleLocksScaleAndYieldsZeroYaw() {
        var mt = makeTracker()
        mt.begin(entityScale: 1.0, entityYaw: 0.25)
        establishBaseline(&mt, ratio: 1.0, yaw: 0.0)

        // ratio e^0.25 ≈ 1.284 → scaleProgress = 0.25/0.20 > 1; yaw stays 0.
        var last = mt.update(ratio: exp(0.25), yaw: 0.0)
        XCTAssertEqual(last.mode, .scale)
        XCTAssertTrue(last.didLock)
        XCTAssertNil(last.appliedYaw, "yaw channel must not write after scale lock")

        last = mt.update(ratio: exp(0.40), yaw: 0.5)
        XCTAssertEqual(last.mode, .scale)
        XCTAssertNil(last.appliedYaw)
        XCTAssertNotNil(last.scale)
        XCTAssertEqual(mt.mode, .scale)
    }

    // MARK: - Pure yaw → locks yaw, zero scale applied

    func testPureYawLocksYawAndYieldsZeroScale() {
        var mt = makeTracker()
        mt.begin(entityScale: 1.0, entityYaw: 0.0)
        establishBaseline(&mt, ratio: 1.0, yaw: 0.0)

        var last = mt.update(ratio: 1.0, yaw: 0.10)
        for step in 2...5 {
            last = mt.update(ratio: 1.0, yaw: Double(step) * 0.10)
        }
        XCTAssertEqual(last.mode, .yaw)
        XCTAssertNil(last.scale, "scale channel must not write after yaw lock")
        XCTAssertNotNil(last.appliedYaw)

        last = mt.update(ratio: 1.5, yaw: 0.80)
        XCTAssertEqual(last.mode, .yaw)
        XCTAssertNil(last.scale)
        XCTAssertNotNil(last.appliedYaw)
    }

    // MARK: - Linear slide signal (current generation) accumulates without aliasing
    //
    // The production `yaw:` input is horizontalSlide (screen-position fraction
    // × gain 12.0) — bounded, not periodic, not an angle. This replaces a
    // prior test that fed a genuinely periodic angle wrapping across ±π
    // (generation-2 signal, thumb/index or wrist/middleMCP angle — see
    // GESTURE_LOG.md §3). That signal isn't what production sends anymore;
    // asserting periodic unwrap behavior against it was pinning dead code.
    // This test instead proves the thing that actually matters for the
    // current signal: large per-frame deltas (well over π, which the old
    // atan2 unwrap would have aliased) must still accumulate exactly, with
    // no sign flips and no wrap-related jumps.

    func testYawAccumulatesLinearSlideWithoutAliasing() {
        var mt = makeTracker()
        mt.begin(entityScale: 1.0, entityYaw: 0.0)
        establishBaseline(&mt, ratio: 1.0, yaw: 0.0)

        // Steps of 2.0 rad-equivalent units per frame — comfortably over π,
        // the exact magnitude the old periodic unwrap would have aliased.
        var applied: [Float] = []
        var slide = 0.0
        for _ in 0..<10 {
            slide += 2.0
            let r = mt.update(ratio: 1.0, yaw: slide)
            if r.mode == .yaw, let value = r.appliedYaw {
                applied.append(value)
            }
        }

        XCTAssertGreaterThanOrEqual(applied.count, 5, "should be in yaw mode for most of the sweep")
        for i in 1..<applied.count {
            let delta = applied[i] - applied[i - 1]
            XCTAssertEqual(delta, 2.0, accuracy: 0.01, "each 2.0-unit slide step must accumulate exactly, not alias")
        }
    }
}
