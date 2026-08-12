import Foundation
import XCTest
@testable import HandProbe

/// Move vs Adjust by time since last gesture end only — never signal race. GESTURES.md §2.8.
final class MoveTriggerTests: XCTestCase {
    private let regrabWindow: TimeInterval = 0.4

    func testNoPriorGestureEntersMove() {
        let trigger = moveOrAdjustTrigger(now: 10.0, lastGestureEnd: nil, regrabWindow: regrabWindow)
        XCTAssertEqual(trigger, .move)
    }

    func testEndedVeryRecentlyEntersAdjust() {
        let trigger = moveOrAdjustTrigger(now: 10.1, lastGestureEnd: 10.0, regrabWindow: regrabWindow)
        XCTAssertEqual(trigger, .adjust)
    }

    func testEndedAWhileAgoEntersMove() {
        let trigger = moveOrAdjustTrigger(now: 12.0, lastGestureEnd: 10.0, regrabWindow: regrabWindow)
        XCTAssertEqual(trigger, .move)
    }
}
