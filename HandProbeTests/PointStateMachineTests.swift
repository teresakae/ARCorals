import Foundation
import XCTest
@testable import HandProbe

final class PointStateMachineTests: XCTestCase {
    private let dt: TimeInterval = 0.066
    private let tuning = GestureTuning.default
    private let annotationA = AnnotationID("A")

    private func machine() -> PointStateMachine {
        PointStateMachine(tuning: tuning)
    }

    private func obs(t: TimeInterval, target: AnnotationID?, isPointing: Bool? = nil, pinchActive: Bool = false) -> PointObservation {
        // Default isPointing to "matches target" so existing target-driven tests don't need
        // updating to reason about the new raw-classifier channel separately.
        PointObservation(timestamp: t, target: target, isPointing: isPointing ?? (target != nil), pinchActive: pinchActive)
    }

    /// Feeds targets on a continuous clock starting at `start`. Returns events and next timestamp.
    private func feed(
        _ sm: inout PointStateMachine,
        targets: [AnnotationID?],
        start: TimeInterval,
        pinchActive: Bool = false
    ) -> (events: [PointEvent], nextTime: TimeInterval) {
        var events: [PointEvent] = []
        var t = start
        for target in targets {
            events += sm.process(obs(t: t, target: target, pinchActive: pinchActive))
            t += dt
        }
        return (events, t)
    }

    /// Feeds explicit (target, isPointing) pairs on a continuous clock — for tests that need to
    /// desync the raw shape-gate reading from whether an annotation was actually under the tip.
    private func feed(
        _ sm: inout PointStateMachine,
        frames: [(target: AnnotationID?, isPointing: Bool)],
        start: TimeInterval
    ) -> (events: [PointEvent], nextTime: TimeInterval) {
        var events: [PointEvent] = []
        var t = start
        for frame in frames {
            events += sm.process(obs(t: t, target: frame.target, isPointing: frame.isPointing))
            t += dt
        }
        return (events, t)
    }

    // MARK: - Dwell completes

    func testDwellCompletesFiresHoverBegan() {
        var sm = machine()
        // 0.4s dwell / 66ms frames needs 7 frames to cross the threshold; 8 is comfortably past it.
        let (events, _) = feed(&sm, targets: Array(repeating: annotationA, count: 8), start: 0)
        XCTAssertEqual(events, [.hoverBegan(annotationA)])
    }

    // MARK: - Dwell abandoned early

    func testDwellAbandonedEarlyFiresNoEvent() {
        var sm = machine()
        var (events, t) = feed(&sm, targets: [annotationA, annotationA, annotationA], start: 0)
        XCTAssertTrue(events.isEmpty)
        // Well past the grace period — the dwell fully lapses before ever completing.
        (events, t) = feed(&sm, targets: Array(repeating: nil, count: 5), start: t)
        _ = t
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Grace: 2 dropped frames

    func testTargetLostTwoFramesSurvivesDwell() {
        var sm = machine()
        var (events, t) = feed(&sm, targets: [annotationA, annotationA, annotationA], start: 0)
        XCTAssertTrue(events.isEmpty)
        // 2 drops @ 66ms = 132ms < 200ms grace
        (events, t) = feed(&sm, targets: [nil, nil], start: t)
        XCTAssertTrue(events.isEmpty)
        (events, t) = feed(&sm, targets: Array(repeating: annotationA, count: 6), start: t)
        _ = t
        XCTAssertEqual(events, [.hoverBegan(annotationA)])
    }

    // MARK: - Grace: 10 dropped frames

    func testTargetLostTenFramesFiresHoverEnded() {
        var sm = machine()
        let (_, t) = feed(&sm, targets: Array(repeating: annotationA, count: 8), start: 0)
        let (events, _) = feed(&sm, targets: Array(repeating: nil, count: 10), start: t)
        XCTAssertTrue(events.contains(.hoverEnded(annotationA)))
    }

    // MARK: - Pinch cancels an in-progress dwell

    func testPinchBeginningMidDwellCancelsWithNoHoverEvent() {
        var sm = machine()
        var (events, t) = feed(&sm, targets: [annotationA, annotationA, annotationA], start: 0)
        XCTAssertTrue(events.isEmpty)
        (events, _) = feed(&sm, targets: [nil], start: t, pinchActive: true)
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Majority-window smoothing (usable-but-wrong classification tolerance)

    /// A single misclassified frame (weak middle/ring/little landmark momentarily read
    /// isPointing:false, even though the annotation is still under the index tip) shouldn't
    /// reset dwell progress to zero — the majority-vote window should still count it as pointing.
    func testSingleMisclassifiedFrameMidDwellDoesNotResetProgress() {
        var sm = machine()
        var (events, t) = feed(
            &sm,
            frames: Array(repeating: (target: annotationA, isPointing: true), count: 3),
            start: 0
        )
        XCTAssertTrue(events.isEmpty)
        XCTAssertGreaterThan(sm.dwellProgress, 0)

        // One usable-but-wrong isPointing:false reading — annotation still under the tip.
        (events, t) = feed(&sm, frames: [(target: annotationA, isPointing: false)], start: t)
        XCTAssertTrue(events.isEmpty)
        XCTAssertGreaterThan(sm.dwellProgress, 0, "majority window should still count this frame as pointing")

        // Resume clean pointing frames — dwell completes on the original schedule, not restarted.
        (events, _) = feed(
            &sm,
            frames: Array(repeating: (target: annotationA, isPointing: true), count: 4),
            start: t
        )
        XCTAssertEqual(events, [.hoverBegan(annotationA)])
    }

    /// A sustained run of isPointing:false readings must still fail to reach .hoverBegan — the
    /// majority window tolerates one bad frame, it doesn't make the gate impossible to fail.
    func testSustainedMisclassificationNeverReachesHoverBegan() {
        var sm = machine()
        let (events, _) = feed(
            &sm,
            frames: Array(repeating: (target: annotationA, isPointing: false), count: 15),
            start: 0
        )
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(sm.dwellProgress, 0)
    }
}
