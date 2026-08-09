import Foundation
import XCTest
@testable import HandProbe

/// Fix 3 — dwell-to-commit.
final class ManipulationTrackerDwellTests: XCTestCase {
    private func makeTracker() -> ManipulationTracker {
        var t = GestureTuning.default
        t.scaleDeadzoneLog = 0.20
        t.yawDeadzoneRad = 0.20
        t.scaleSensitivity = 1.0
        t.yawSensitivity = 1.0
        t.dwellLogThreshold = 0.05
        t.dwellDuration = 0.4
        return ManipulationTracker(tuning: t)
    }

    func testHoldingStableRatioCommitsAndFreezesScale() {
        var mt = makeTracker()
        mt.begin(entityScale: 1.0, entityYaw: 0.25)

        var t: TimeInterval = 0
        for _ in 0..<3 {
            _ = mt.update(ratio: 1.0, yaw: 0.0, now: t)
            t += 0.05
        }

        // Cross the scale deadzone and lock.
        var last = mt.update(ratio: exp(0.25), yaw: 0.0, now: t)
        XCTAssertEqual(last.mode, .scale)
        XCTAssertTrue(last.didLock)
        XCTAssertFalse(last.committed)

        // Hold the same ratio for >= dwellDuration.
        let committedScale = last.scale
        t += 0.5
        last = mt.update(ratio: exp(0.25), yaw: 0.0, now: t)
        XCTAssertTrue(last.committed)
        XCTAssertEqual(last.scale, committedScale)

        // A subsequent frame with a very different ratio must not move the
        // frozen value — commit only lifts on reset().
        last = mt.update(ratio: exp(1.0), yaw: 0.0, now: t + 0.1)
        XCTAssertTrue(last.committed)
        XCTAssertEqual(last.scale, committedScale)
    }
}
