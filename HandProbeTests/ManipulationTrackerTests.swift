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

    // MARK: - Unwrap across ±π

    func testYawSweepAcrossPiIsMonotonicWithoutTwoPiJump() {
        var mt = makeTracker()
        mt.begin(entityScale: 1.0, entityYaw: 0.0)
        establishBaseline(&mt, ratio: 1.0, yaw: 0.0)

        var angles: [Double] = []
        let start = Double.pi - 0.30
        for i in 0..<20 {
            let yaw = start + Double(i) * 0.05
            var wrapped = yaw
            while wrapped > .pi { wrapped -= 2 * .pi }
            while wrapped <= -.pi { wrapped += 2 * .pi }
            let r = mt.update(ratio: 1.0, yaw: wrapped)
            if r.mode == .yaw, let applied = r.appliedYaw {
                angles.append(Double(applied))
            }
        }

        XCTAssertGreaterThanOrEqual(angles.count, 5, "should be in yaw mode for most of the sweep")
        for i in 1..<angles.count {
            let delta = angles[i] - angles[i - 1]
            XCTAssertGreaterThan(delta, -0.01, "accumulated yaw must not jump backward across ±π")
            XCTAssertLessThan(abs(delta), .pi, "no 2π discontinuity between frames")
        }
        if let first = angles.first, let last = angles.last {
            XCTAssertGreaterThan(last - first, 0.4)
        }
    }
}
