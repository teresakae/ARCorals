import CoreGraphics
import Foundation
import RealityKit

/// Wave/hold dispatch; content-layer proximity; live x when allowsWave (docs/GESTURES.md §2.10).
extension ARSessionCoordinator {
    /// ⚠️ Screen-pt gate (not world cm); 220pt ad-hoc — docs/GESTURES.md §2.10 / §3.
    private static let waveProximityRadiusPt: CGFloat = 220

    /// After point; nil frame still fed so progress decays (docs/ARCHITECTURE.md §5 seam 5).
    func handleWave(frame: LandmarkFrame?, packet: FramePacket) {
        let x = demoMode.allowsWave ? gatedWristX(frame: frame, packet: packet) : nil
        let events = waveDetector.process(WaveObservation(timestamp: machineTime, x: x))
        if events.contains(.waved) {
            waveCount += 1
        }
    }

    /// Vision wrist x when confident and within waveProximityRadiusPt of the target.
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

    /// Placeholder target: projected top-face center of active cube (docs/GESTURES.md §2.10).
    private var waveTargetViewportPoint: CGPoint? {
        guard let model = scene.activeModel else { return nil }
        let topFaceCenter = model.position(relativeTo: nil)
            + SIMD3<Float>(0, ModelProvider.halfHeight * model.scale.y, 0)
        return arView.project(topFaceCenter)
    }
}
