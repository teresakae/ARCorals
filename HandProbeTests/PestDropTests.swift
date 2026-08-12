import Foundation
import XCTest
@testable import HandProbe

/// Pure release-distance check for pest pick-up-and-throw. GESTURES.md pest content.
final class PestDropTests: XCTestCase {
    private let discardDistance: Float = 0.045

    func testReleaseCloseToO1StaysPlaced() {
        let result = shouldDiscardPest(
            releaseWorldPosition: [0.03, 0, 0],
            anchorWorldPosition: [0, 0, 0],
            discardDistance: discardDistance
        )
        XCTAssertFalse(result)
    }

    func testReleaseFarFromO1Discards() {
        let result = shouldDiscardPest(
            releaseWorldPosition: [0.5, 0, 0],
            anchorWorldPosition: [0, 0, 0],
            discardDistance: discardDistance
        )
        XCTAssertTrue(result)
    }

    func testExactlyAtThresholdStaysPlaced() {
        // Strictly-greater-than: right at the boundary counts as a near-drop, not a throw.
        let result = shouldDiscardPest(
            releaseWorldPosition: [0.045, 0, 0],
            anchorWorldPosition: [0, 0, 0],
            discardDistance: discardDistance
        )
        XCTAssertFalse(result)
    }
}
