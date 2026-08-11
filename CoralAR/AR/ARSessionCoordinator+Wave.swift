import CoreGraphics
import Foundation
import RealityKit

/// Wave / stationary-hold dispatch. Reads wrist position every frame,
/// regardless of pinch state, and gates it against a placeholder proximity
/// target (a marker on the cube's top face) before feeding `WaveDetector`.
/// The gate is content-layer only — `WaveDetector` has no concept of "near a
/// target," it just processes whatever `x` it's handed.
extension ARSessionCoordinator {
    /// Screen radius (points) around the placeholder marker inside which
    /// wrist motion is fed to `waveDetector`. Content-layer placeholder, not
    /// a `GestureTuning` constant (plan §2/§3: proximity gating is content-
    /// layer, not part of the recognizer) — a real dirt-patch/annotation hit
    /// volume replaces this once that content exists; this just exercises
    /// the gating pattern on the cube prototype.
    private static let waveProximityRadiusPt: CGFloat = 130

    /// Called from `handleVision`, after point. `frame` is nil on the
    /// dropped/nil-Vision-frame path — must still be fed so wave progress
    /// decays correctly rather than hard-resetting.
    func handleWave(frame: LandmarkFrame?, packet: FramePacket) {
        let x = gatedWristX(frame: frame, packet: packet)
        let events = waveDetector.process(WaveObservation(timestamp: packet.timestamp, x: x))
        if events.contains(.waved) {
            waveCount += 1
        }
    }

    /// The wrist's raw Vision-normalized x, or nil if there's no frame, no
    /// confident wrist landmark, or the wrist isn't near the placeholder
    /// target marker.
    private func gatedWristX(frame: LandmarkFrame?, packet: FramePacket) -> Double? {
        guard let frame,
              let wrist = frame.joints[.wrist], wrist.confidence >= tuning.confidenceGate,
              let markerPoint = waveTargetViewportPoint
        else { return nil }

        let wristViewportPoint = LandmarkSpace.visionToViewport(
            CGPoint(x: wrist.x, y: wrist.y),
            displayTransform: packet.displayTransform,
            viewportSize: packet.viewportSize
        )
        let dx = wristViewportPoint.x - markerPoint.x
        let dy = wristViewportPoint.y - markerPoint.y
        guard sqrt(dx * dx + dy * dy) <= Self.waveProximityRadiusPt else { return nil }

        return Double(wrist.x)
    }

    /// Placeholder target volume: the projected screen point of the active
    /// cube's top-face center. Enough to exercise the proximity-gate pattern
    /// without building real dirt-patch content — a real annotation/hit
    /// volume replaces this marker later.
    private var waveTargetViewportPoint: CGPoint? {
        guard let model = scene.activeModel else { return nil }
        let topFaceCenter = model.position(relativeTo: nil)
            + SIMD3<Float>(0, ModelProvider.halfHeight * model.scale.y, 0)
        return arView.project(topFaceCenter)
    }
}
