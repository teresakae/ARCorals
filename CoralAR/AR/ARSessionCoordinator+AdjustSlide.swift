import Foundation
import RealityKit

/// Adjust B — scale via vertical hand slide. Standalone `VerticalSlideScale` mechanism, never
/// touches `ManipulationTracker`'s log-ratio scale math (docs/GESTURES.md §1). Scale-only by
/// construction — there is no yaw channel here at all, unlike Adjust A's `scaleOnly` lock.
extension ARSessionCoordinator {
    /// `verticalSlide` is the vertical counterpart of `horizontalSlide` (ARSessionCoordinator.swift
    /// / +Carry.swift) — viewport-y fraction of `pinchViewportPoint` × `verticalSlideGain`, a plain
    /// linear signal, same shape as the yaw signal, not log-wrapped.
    private var verticalSlide: Double? {
        pinchViewportPoint.map { point in
            Double(point.y / max(cachedViewportSize.height, 1)) * tuning.verticalSlideGain
        }
    }

    /// `.adjustSlide` mode routing: first pinch on a placed object grabs and starts scaling by
    /// vertical slide; mirrors Adjust A's grab-or-place shape but never enters the shared
    /// `ManipulationTracker` (docs/GESTURES.md §1).
    func handleAdjustSlideRouting(frame: LandmarkFrame?, packet: FramePacket, pinchEvents: [PinchGestureEvent]) {
        guard demoMode.allowsAdjustSlide else { return }

        for pinchEvent in pinchEvents {
            switch pinchEvent {
            case .began:
                guard !adjustSlideScale.isActive else { break }
                if scene.hasPlacedEntity, let point = pinchViewportPoint, let model = scene.selectModel(at: point) {
                    metrics.beginGesture()
                    adjustSlideScale.begin(entityScale: model.scale.x)
                    scene.setHighlighted(true)
                    manipulationModeName = "SCALE"
                } else if !scene.hasPlacedEntity, let frame {
                    placeFromHand(frame: frame, packet: packet)
                }
                // else: miss even with screen-radius fallback → no grab (docs/GESTURES.md §2.1).

            case .changed:
                guard adjustSlideScale.isActive else { break }
                let scale = adjustSlideScale.update(slide: verticalSlide)
                scene.applyScale(scale)
                manipulationModeName = "SCALE"

            case .ended, .cancelled:
                guard adjustSlideScale.isActive else { break }
                scene.regenerateCollisionShapes()
                adjustSlideScale.reset()
                scene.setHighlighted(false)
                manipulationModeName = "—"
                metrics.endGesture()

            case .possible, .failed:
                break
            }
        }
    }

    /// Drop a stranded Adjust B grab on leaving `.adjustSlide` mid-gesture. Not `private` —
    /// `demoMode.didSet` calls this on the allowsAdjustSlide → not edge, mirrors
    /// `endRotateModeIfActive()` / `endCarryIfActive()`.
    func endAdjustSlideIfActive() {
        guard adjustSlideScale.isActive else { return }
        adjustSlideScale.reset()
        scene.setHighlighted(false)
        manipulationModeName = "—"
    }
}
