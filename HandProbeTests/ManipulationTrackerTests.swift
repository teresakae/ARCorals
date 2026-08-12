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

    // MARK: - yawOnly: never enters .scale, even on a pure-scale input that would normally win

    func testYawOnlyNeverLocksScaleOnPureScaleInput() {
        var mt = makeTracker()
        mt.begin(entityScale: 1.0, entityYaw: 0.25, yawOnly: true)

        // yawOnly commits to .yaw the instant arming completes — unlike the raced path
        // (`establishBaseline`), which stays .ambiguous through 3 quiet samples because
        // no real scale/yaw delta has arrived yet. Here the 3rd quiet sample both arms
        // *and* locks in the same call, by design (no deadzone race to wait out).
        _ = mt.update(ratio: 1.0, yaw: 0.0)
        _ = mt.update(ratio: 1.0, yaw: 0.0)
        let armed = mt.update(ratio: 1.0, yaw: 0.0)
        XCTAssertEqual(armed.mode, .yaw)
        XCTAssertTrue(armed.didLock)
        XCTAssertNil(armed.scale)

        // Identical scale-provoking input to testPureScaleLocksScaleAndYieldsZeroYaw
        // (ratio e^0.25, zero yaw delta) — would lock .scale there.
        var last = mt.update(ratio: exp(0.25), yaw: 0.0)
        XCTAssertEqual(last.mode, .yaw)
        XCTAssertNil(last.scale, "scale channel must never write under yawOnly")

        last = mt.update(ratio: exp(0.40), yaw: 0.5)
        XCTAssertEqual(last.mode, .yaw)
        XCTAssertNil(last.scale)
        XCTAssertNotNil(last.appliedYaw)
        XCTAssertEqual(mt.mode, .yaw)
    }

    // MARK: - scaleOnly: never enters .yaw, even on a pure-yaw input that would normally win

    func testScaleOnlyNeverLocksYawOnPureYawInput() {
        var mt = makeTracker()
        mt.begin(entityScale: 1.0, entityYaw: 0.25, scaleOnly: true)

        // scaleOnly commits to .scale the instant arming completes — mirror of
        // testYawOnlyNeverLocksScaleOnPureScaleInput with the roles swapped.
        _ = mt.update(ratio: 1.0, yaw: 0.0)
        _ = mt.update(ratio: 1.0, yaw: 0.0)
        let armed = mt.update(ratio: 1.0, yaw: 0.0)
        XCTAssertEqual(armed.mode, .scale)
        XCTAssertTrue(armed.didLock)
        XCTAssertNil(armed.appliedYaw)

        // Large yaw delta, zero scale delta — would lock .yaw in the raced path.
        var last = mt.update(ratio: 1.0, yaw: 0.5)
        XCTAssertEqual(last.mode, .scale)
        XCTAssertNil(last.appliedYaw, "yaw channel must never write under scaleOnly")

        last = mt.update(ratio: 1.0, yaw: 1.0)
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

    // MARK: - Linear slide (horizontalSlide) accumulates without aliasing — GESTURES.md Rotate history

    func testYawAccumulatesLinearSlideWithoutAliasing() {
        var mt = makeTracker()
        mt.begin(entityScale: 1.0, entityYaw: 0.0)
        establishBaseline(&mt, ratio: 1.0, yaw: 0.0)

        // Steps of 2.0/frame — over π, where the old atan2 unwrap would have aliased.
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
