import Foundation
import XCTest
@testable import HandProbe

/// Wave / stationary-hold — explicit-clock style, matching
/// ManipulationTrackerSettlingTests (`frame = 1.0/15.0`).
final class WaveDetectorTests: XCTestCase {
    private let frame: TimeInterval = 1.0 / 15.0

    private func makeDetector() -> WaveDetector {
        WaveDetector(tuning: .default)
    }

    /// Oscillating wrist position: enough reversals + amplitude inside
    /// `waveWindow` to read as "waving".
    private func waveX(at t: TimeInterval, center: Double = 0.5, amplitude: Double = 0.08, period: TimeInterval = 0.25) -> Double {
        center + amplitude * sin(2 * .pi * t / period)
    }

    /// Feed `seconds` of wave motion starting at `startTime`; returns all
    /// events fired and the elapsed clock at the end.
    @discardableResult
    private func feedWave(
        _ detector: inout WaveDetector,
        seconds: TimeInterval,
        startTime: TimeInterval,
        phaseOffset: TimeInterval = 0
    ) -> (events: [WaveEvent], endTime: TimeInterval) {
        var events: [WaveEvent] = []
        var t = startTime
        let end = startTime + seconds
        while t < end {
            events += detector.process(WaveObservation(timestamp: t, x: waveX(at: t - phaseOffset)))
            t += frame
        }
        return (events, t)
    }

    func testTwoSecondWaveFiresOnce() {
        var detector = makeDetector()
        let (events, _) = feedWave(&detector, seconds: 3.0, startTime: 0)
        XCTAssertEqual(events.filter { $0 == .waved }.count, 1, "a sustained 3s wave should fire exactly once")
    }

    func testOneSecondWaveDoesNotFire() {
        var detector = makeDetector()
        let (events, _) = feedWave(&detector, seconds: 1.0, startTime: 0)
        XCTAssertTrue(events.isEmpty, "1s of wave motion is under the 2.0s hold duration")
    }

    /// A brief nil-x gap decays progress but must not hard-reset it — the
    /// wave resumes and still reaches the 2.0s hold within a window a hard
    /// reset could not have completed in.
    func testGapOfTwoFramesStillFires() {
        var detector = makeDetector()
        var t: TimeInterval = 0
        var events: [WaveEvent] = []

        // ~1.9s of wave motion.
        let preGapEnd = t + 1.9
        while t < preGapEnd {
            events += detector.process(WaveObservation(timestamp: t, x: waveX(at: t)))
            t += frame
        }

        // 2-frame nil gap.
        for _ in 0..<2 {
            events += detector.process(WaveObservation(timestamp: t, x: nil))
            t += frame
        }

        // Resume for another 1.0s — a hard reset could not reach 2.0s of
        // fresh accumulated progress in only 1.0s; the decay model can,
        // since it only lost the ~0.13s gap's worth of progress.
        let postGapEnd = t + 1.0
        while t < postGapEnd {
            events += detector.process(WaveObservation(timestamp: t, x: waveX(at: t)))
            t += frame
        }

        XCTAssertEqual(events.filter { $0 == .waved }.count, 1, "a short gap must decay progress, not hard-reset it")
    }

    /// Slow, steady drift: per-frame amplitude/reversal criteria never
    /// qualify (monotonic, no reversals), and it walks away from the
    /// stationary anchor rather than orbiting it — so it must never fire.
    func testSlowDriftNeverFires() {
        var detector = makeDetector()
        var events: [WaveEvent] = []
        var t: TimeInterval = 0
        let end: TimeInterval = 6.0
        let driftRate = 0.02 // per second — well beyond stationaryRadius within a fraction of a second
        while t < end {
            let x = 0.5 + driftRate * t
            events += detector.process(WaveObservation(timestamp: t, x: x))
            t += frame
        }
        XCTAssertTrue(events.isEmpty, "monotonic drift is neither a wave nor a stationary hold")
    }

    /// Fast, monotonic lateral translation — the carrying/dragging motion —
    /// must never be mistaken for a wave (no reversals) or a hold (moves
    /// well past the stationary radius every frame).
    func testCarryingSpeedTranslationNeverFires() {
        var detector = makeDetector()
        var events: [WaveEvent] = []
        var t: TimeInterval = 0
        let end: TimeInterval = 3.0
        while t < end {
            let x = 0.2 + 0.15 * t // fast, steady, one direction
            events += detector.process(WaveObservation(timestamp: t, x: min(x, 1.0)))
            t += frame
        }
        XCTAssertTrue(events.isEmpty, "fast one-directional motion must not trigger the wave path")
    }

    /// Stationary-hold fallback: holding still (tiny jitter under the
    /// radius) for the hold duration fires `.waved` via the same timer.
    func testStationaryHoldFallbackFires() {
        var detector = makeDetector()
        var events: [WaveEvent] = []
        var t: TimeInterval = 0
        let end: TimeInterval = 2.5
        var toggle = false
        while t < end {
            // Tiny jitter, well inside waveStationaryRadius (0.02).
            toggle.toggle()
            let x = 0.5 + (toggle ? 0.003 : -0.003)
            events += detector.process(WaveObservation(timestamp: t, x: x))
            t += frame
        }
        XCTAssertEqual(events.filter { $0 == .waved }.count, 1, "holding still for 2s should fire via the fallback")
    }

    /// Cooldown suppresses an immediate second fire right after the first.
    func testCooldownSuppressesImmediateSecondFire() {
        var detector = makeDetector()
        let (firstRun, endTime) = feedWave(&detector, seconds: 3.0, startTime: 0)
        XCTAssertEqual(firstRun.filter { $0 == .waved }.count, 1)

        // Immediately keep waving right after the first fire — still inside cooldown.
        let (secondRun, _) = feedWave(&detector, seconds: 1.0, startTime: endTime)
        XCTAssertTrue(secondRun.filter { $0 == .waved }.isEmpty, "cooldown should block an immediate re-fire")
    }
}
