import Foundation

/// Vertical hand slide → absolute scale (Adjust B test mode). Standalone, sized like
/// `MoveController` — deliberately NOT bolted onto `ManipulationTracker`'s log-ratio scale
/// machinery, because that math assumes a multiplicative finger-spread distance ratio and a
/// linear screen-position slide isn't one (docs/GESTURES.md §1/§2.2). Accumulates the raw
/// `verticalSlide` signal (screen-height fraction × `GestureTuning.verticalSlideGain`) the same
/// way `ManipulationTracker.unwrapYaw` accumulates `horizontalSlide` — a plain linear delta, not
/// a log ratio.
struct VerticalSlideScale: Sendable {
    var tuning: GestureTuning

    private(set) var isActive = false
    private var entityScale0: Float = 1
    private var previousSlide: Double?
    private var accumulatedSlide: Double = 0

    init(tuning: GestureTuning = .default) {
        self.tuning = tuning
    }

    mutating func begin(entityScale: Float) {
        isActive = true
        entityScale0 = entityScale
        previousSlide = nil
        accumulatedSlide = 0
    }

    /// `slide` is the raw per-frame `verticalSlide` signal (viewport-y fraction × gain).
    /// Sliding up (viewport y decreasing) grows the object. Same [0.25, 4.0] clamp as
    /// `ManipulationTracker`'s scale path.
    @discardableResult
    mutating func update(slide: Double?) -> Float {
        guard isActive, let slide else { return entityScale0 }
        if let previousSlide {
            accumulatedSlide += slide - previousSlide
        }
        previousSlide = slide
        // Subtract: viewport y grows downward, but "slide up" should grow the object.
        return min(max(entityScale0 - Float(accumulatedSlide), 0.25), 4.0)
    }

    mutating func reset() {
        isActive = false
        entityScale0 = 1
        previousSlide = nil
        accumulatedSlide = 0
    }
}
