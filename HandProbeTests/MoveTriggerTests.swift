import Foundation
import XCTest
@testable import HandProbe

/// Move vs Adjust is decided purely by elapsed time since the last gesture
/// ended (Prompt 11) — never by racing signals. Three cases per the prompt.
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
