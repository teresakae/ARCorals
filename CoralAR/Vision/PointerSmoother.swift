import CoreGraphics
import QuartzCore

/// Exponential moving average over a viewport point. Ported from posehandtest's
/// `PointerMapping.swift:PointerSmoother` — the piece we were missing that made its cursor
/// track cleanly while ours jittered in and out of small hit-test targets.
///
/// Vision's per-frame output wobbles by a few pixels even for a perfectly still hand, which is
/// enough to make a point-mode dwell target flicker between "hit" and "miss". A light low-pass
/// fixes that without adding lag the user can feel.
final class PointerSmoother {
    /// 0 = frozen, 1 = no smoothing. 0.35 keeps ~2 frames of latency.
    var smoothingFactor: CGFloat = 0.35

    /// Re-acquire (snap instead of glide) if the hand was lost for longer than this.
    var reacquireTimeout: CFTimeInterval = 0.25

    private var smoothed: CGPoint?
    private var lastUpdate: CFTimeInterval = 0

    func smooth(_ point: CGPoint, now: CFTimeInterval = CACurrentMediaTime()) -> CGPoint {
        defer { lastUpdate = now }

        guard let previous = smoothed, now - lastUpdate <= reacquireTimeout else {
            smoothed = point
            return point
        }

        let next = CGPoint(x: previous.x + (point.x - previous.x) * smoothingFactor,
                            y: previous.y + (point.y - previous.y) * smoothingFactor)
        smoothed = next
        return next
    }

    func reset() {
        smoothed = nil
        lastUpdate = 0
    }
}
