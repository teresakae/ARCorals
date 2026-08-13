import Foundation
import XCTest
@testable import HandProbe

final class PinchStateMachineTests: XCTestCase {
    private let dt: TimeInterval = 0.066
    private var tuning = GestureTuning.default

    private func machine() -> PinchStateMachine {
        PinchStateMachine(tuning: tuning)
    }

    private func obs(
        t: TimeInterval,
        ratio: Double?,
        confidence: Float? = 0.9
    ) -> PinchObservation {
        PinchObservation(timestamp: t, pinchRatio: ratio, confidence: confidence)
    }

    /// Feeds ratios on a continuous clock starting at `start`. Returns events and next timestamp.
    private func feed(
        _ sm: inout PinchStateMachine,
        ratios: [Double?],
        start: TimeInterval,
        confidence: Float? = 0.9
    ) -> (events: [PinchGestureEvent], nextTime: TimeInterval) {
        var events: [PinchGestureEvent] = []
        var t = start
        for r in ratios {
            events += sm.process(obs(t: t, ratio: r, confidence: confidence))
            t += dt
        }
        return (events, t)
    }

    private func names(_ events: [PinchGestureEvent]) -> [String] {
        events.map(\.name)
    }

    private func armPinch(_ sm: inout PinchStateMachine, start: TimeInterval = 0) -> TimeInterval {
        let (_, t) = feed(&sm, ratios: [0.5, 0.5, 0.5], start: start)
        return t
    }

    // MARK: - Clean pinch

    func testCleanPinch() {
        var sm = machine()
        var t: TimeInterval = 0
        var events: [PinchGestureEvent]

        (events, t) = feed(&sm, ratios: [10, 10, 10], start: t)
        XCTAssertEqual(names(events), [])

        (events, t) = feed(&sm, ratios: [0.5, 0.5, 0.5], start: t)
        XCTAssertEqual(events.first?.name, "Began")

        (events, t) = feed(&sm, ratios: [0.5, 0.5, 0.5], start: t)
        XCTAssertTrue(events.allSatisfy { $0.name == "Changed" })

        (events, t) = feed(&sm, ratios: [12, 12, 12], start: t)
        XCTAssertTrue(names(events).contains("Ended"))
        XCTAssertTrue(names(events).contains("Possible"))
    }

    // MARK: - Chatter in noise band

    func testChatterInNoiseBandDoesNotBegin() {
        var sm = machine()
        // Noise band around shipping pinchThreshold 1.98 ± hysteresisBand/2 → [1.48, 2.48].
        let chatter: [Double?] = (0..<30).map { i in i % 2 == 0 ? 1.7 : 2.2 }
        let (events, _) = feed(&sm, ratios: chatter, start: 0)
        XCTAssertFalse(names(events).contains("Began"), "band chatter must not arm a pinch")
    }

    func testChatterDoesNotEndActiveDrag() {
        var sm = machine()
        var t = armPinch(&sm)
        let band: [Double?] = (0..<20).map { i in i % 2 == 0 ? 1.7 : 2.3 }
        let (events, _) = feed(&sm, ratios: band, start: t)
        XCTAssertFalse(names(events).contains("Ended"))
        XCTAssertFalse(names(events).contains("Cancelled"))
        XCTAssertTrue(events.allSatisfy { $0.name == "Changed" })
    }

    // MARK: - Grace: 2 dropped frames

    func testDragSurvivesTwoDroppedFrames() {
        var sm = machine()
        var t = armPinch(&sm)
        // 2 drops @ 66ms = 132ms < 200ms grace
        var events: [PinchGestureEvent]
        (events, t) = feed(&sm, ratios: [nil, nil], start: t)
        XCTAssertFalse(names(events).contains("Cancelled"))
        (events, t) = feed(&sm, ratios: [0.5, 0.5], start: t)
        XCTAssertTrue(events.allSatisfy { $0.name == "Changed" })
    }

    // MARK: - Grace: 10 dropped frames

    func testDragCancelsAfterTenDroppedFrames() {
        var sm = machine()
        let t = armPinch(&sm)
        let (events, _) = feed(&sm, ratios: Array(repeating: nil, count: 10), start: t)
        XCTAssertTrue(names(events).contains("Cancelled"))
        XCTAssertTrue(names(events).contains("Possible"))
    }

    // MARK: - Grace applies on the way in too (pendingBegan)

    func testPendingBeganSurvivesOneMarginalFrame() {
        var sm = machine()
        var t: TimeInterval = 0

        // Frame 1: enters pendingBegan (start = 0).
        var events = sm.process(obs(t: t, ratio: 0.5))
        XCTAssertTrue(events.isEmpty)
        t += dt

        // Frame 2: unusable (low confidence) — previously reset straight to idle.
        events = sm.process(obs(t: t, ratio: 0.5, confidence: 0.0))
        XCTAssertTrue(events.isEmpty, "a single marginal frame must not cancel pendingBegan")
        t += dt

        // Frame 3: resumes below threshold. t - originalStart (0) = 0.132 >= hysteresisDuration (0.1),
        // so time accumulated before the dropped frame must still count toward Began.
        events = sm.process(obs(t: t, ratio: 0.5))
        XCTAssertTrue(names(events).contains("Began"), "earlier accumulated frames should still count toward hysteresis")
    }

    func testPendingBeganCancelsAfterLongDropout() {
        var sm = machine()
        var t: TimeInterval = 0

        var events = sm.process(obs(t: t, ratio: 0.5))
        XCTAssertTrue(events.isEmpty)
        t += dt

        // Drop for longer than gracePeriod (0.200s): 10 frames @ 66ms = 0.66s.
        var allEvents: [PinchGestureEvent] = []
        for _ in 0..<10 {
            allEvents += sm.process(obs(t: t, ratio: nil))
            t += dt
        }
        XCTAssertFalse(names(allEvents).contains("Began"), "a long dropout mid-approach must not silently begin a pinch")

        // If state had truly reset to idle, one resumed frame is not enough to reach Began —
        // it needs a fresh hysteresis window, not the stale start time.
        events = sm.process(obs(t: t, ratio: 0.5))
        XCTAssertFalse(names(events).contains("Began"), "state must have reset to idle, not silently preserved pendingBegan")
    }

    // MARK: - Confidence collapse

    func testConfidenceCollapseTreatedAsDrop() {
        var sm = machine()
        var t = armPinch(&sm)
        var events: [PinchGestureEvent] = []
        for _ in 0..<10 {
            events += sm.process(obs(t: t, ratio: 0.5, confidence: 0.0))
            t += dt
        }
        XCTAssertTrue(names(events).contains("Cancelled"))
    }

    func testBriefConfidenceCollapseDoesNotCancel() {
        var sm = machine()
        var t = armPinch(&sm)
        var events: [PinchGestureEvent] = []
        events += sm.process(obs(t: t, ratio: 0.5, confidence: 0.0))
        t += dt
        events += sm.process(obs(t: t, ratio: 0.5, confidence: 0.0))
        t += dt
        events += sm.process(obs(t: t, ratio: 0.5, confidence: 0.9))
        XCTAssertFalse(names(events).contains("Cancelled"))
        XCTAssertTrue(names(events).contains("Changed"))
    }

    // MARK: - pendingProgress

    func testPendingProgressBuildsThenCommitsToOne() {
        var sm = machine()
        var t: TimeInterval = 0
        XCTAssertEqual(sm.pendingProgress, 0)

        // First qualifying frame enters pendingBegan at elapsed 0.
        _ = sm.process(obs(t: t, ratio: 0.5))
        XCTAssertEqual(sm.pendingProgress, 0, accuracy: 0.001)

        // Midway through the 100ms hysteresis window.
        t += tuning.hysteresisDuration / 2
        _ = sm.process(obs(t: t, ratio: 0.5))
        XCTAssertEqual(sm.pendingProgress, 0.5, accuracy: 0.05)

        // Past the window — commits to Began, progress saturates at 1.
        t += tuning.hysteresisDuration
        let events = sm.process(obs(t: t, ratio: 0.5))
        XCTAssertTrue(names(events).contains("Began"))
        XCTAssertEqual(sm.pendingProgress, 1)
    }

    func testPendingProgressResetsWhenAttemptDropsBeforeCommit() {
        var sm = machine()
        var t: TimeInterval = 0
        _ = sm.process(obs(t: t, ratio: 0.5))
        t += tuning.hysteresisDuration / 2
        _ = sm.process(obs(t: t, ratio: 0.5))
        XCTAssertGreaterThan(sm.pendingProgress, 0)

        // Ratio stays out of the enter band well past gracePeriod — attempt dies silently, not
        // just a single marginal frame (which is forgiven — see testPendingBeganSurvivesOneMarginalFrame).
        for _ in 0..<10 {
            t += dt
            _ = sm.process(obs(t: t, ratio: 10))
        }
        XCTAssertEqual(sm.pendingProgress, 0)
    }
}
