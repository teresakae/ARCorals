import ARKit
import AVFoundation
import Combine
import RealityKit
import SwiftUI
import UIKit

/// Owns ARView + ARSession. Horizontal planes + Vision hand pipeline (Phase 4).
@MainActor
final class ARSessionCoordinator: NSObject, ObservableObject {
    let arView: ARView
    let planeScan = PlaneScanCoordinator()
    let placement = PlacementService()
    let scene: SceneController
    let metrics = MetricsLogger()
    let tuning = GestureTuning.default

    @Published private(set) var planeCount = 0
    @Published private(set) var secondsToFirstPlane: TimeInterval?
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var needsScanPrompt = true
    @Published private(set) var lastRaycastTier: PlacementService.Tier = .none
    @Published private(set) var trackingStateLabel = "—"
    @Published private(set) var isRunning = false

    @Published private(set) var gesturePhaseName = "Possible"
    @Published private(set) var pinchRatio: Double?
    @Published private(set) var palmWidthMin: Double?
    @Published private(set) var palmWidthMax: Double?
    @Published private(set) var inferenceHz: Double = 0
    @Published private(set) var framesReceived = 0
    @Published private(set) var framesProcessed = 0

    @Published private(set) var pinchViewportPoint: CGPoint?
    @Published private(set) var raycastViewportPoint: CGPoint?
    @Published private(set) var viewportJoints: [(point: CGPoint, confidence: Float)] = []
    @Published private(set) var manipulationModeName = "—"

    @Published var showPlaneVisualization = false {
        didSet { applyDebugOptions() }
    }
    @Published var showLandmarks = true
    @Published var hudHidden = false

    /// Torch works alongside an active ARSession — it's a device-level
    /// property, not a second capture session, so this doesn't conflict
    /// with ARKit owning the camera. Control Center's toggle often can't
    /// reach the torch while another app holds the camera; this can.
    @Published private(set) var torchOn = false

    func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = torchOn ? .off : .on
            torchOn = device.torchMode == .on
            device.unlockForConfiguration()
        } catch {
            // No torch this session — not worth surfacing, debug affordance only.
        }
    }
    @Published var groundTruth: GroundTruthState?

    private var stateMachine = PinchStateMachine(tuning: .default)
    private var manipulation = ManipulationTracker(tuning: .default)
    private var rollPalm = RollingMinMax()
    /// Median-of-5 on pinchRatio — the single chokepoint every downstream
    /// consumer (state machine, manipulation, HUD, CSV) reads through.
    /// Raw per-frame Vision noise on this ratio is large (measured: ~35% of
    /// consecutive frames jump enough on their own to blow through the scale
    /// deadzone, hand held still) — median, not EMA, since the noise is
    /// outlier spikes (up to 20x in one frame) that an EMA would smear
    /// through rather than reject.
    private var ratioFilterBuffer: [Double] = []
    private var machineTime: TimeInterval = 0
    /// Tracks committed→false transition edge for the one-shot commit reaction
    /// (collision regen + exit-threshold reset) in `.changed`.
    private var manipulationCommitted = false
    private var tick: AnyCancellable?
    private var latestExtentM2: Float = 0
    private var latestTrackingState: ARCamera.TrackingState = .notAvailable

    /// Written from main (layout); read on session queue for displayTransform snapshot.
    nonisolated(unsafe) var cachedViewportSize: CGSize = .zero
    /// Frame gate mutated on the session queue under `frameTapLock`.
    nonisolated(unsafe) private var frameTap = FrameTap()
    private let frameTapLock = NSLock()
    nonisolated(unsafe) private var framesReceivedCounter = 0
    /// Actor reference is immutable; safe to hop from the session queue.
    private let detectorRef: HandPoseDetector

    override init() {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView = view
        scene = SceneController(arView: view)
        detectorRef = HandPoseDetector()
        super.init()
        arView.session.delegate = self
        frameTap.inferenceInterval = tuning.inferenceInterval
        applyDebugOptions()
    }

    func updateViewportSize(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        cachedViewportSize = size
    }

    func start() {
        guard !isRunning else { return }
        guard ARWorldTrackingConfiguration.isSupported else {
            trackingStateLabel = "ARKit unsupported"
            return
        }

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        // No sceneDepth / sceneReconstruction — no LiDAR (AGENTS.md).

        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        UIApplication.shared.isIdleTimerDisabled = true
        scene.clearAll()
        planeScan.sessionDidStart()
        stateMachine.reset()
        manipulation.reset()
        manipulationModeName = "—"
        publishScanState()
        resetHandUI()
        framesReceivedCounter = 0
        isRunning = true

        metrics.startNewFile()
        metrics.log(
            event: .sessionStart,
            secondsSinceStart: 0,
            planeCount: 0,
            planeExtentM2: 0,
            raycastTier: .none,
            trackingState: .notAvailable
        )

        tick = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.elapsedSeconds = self.planeScan.secondsSinceStart
            }
    }

    func stop() {
        tick?.cancel()
        tick = nil
        arView.session.pause()
        UIApplication.shared.isIdleTimerDisabled = false
        isRunning = false
        metrics.stop()
    }

    func setGroundTruth(_ state: GroundTruthState?) {
        groundTruth = state
    }

    // MARK: - Vision result (main)

    private func handleVision(frame: LandmarkFrame?, packet: FramePacket) {
        frameTapLock.lock()
        frameTap.markCompleted()
        frameTapLock.unlock()
        framesProcessed += 1

        guard let frame else {
            clearOverlay()
            return
        }

        inferenceHz = frame.inferenceHz
        let ratios = PinchRatioCalculator.ratios(from: frame.joints, confidenceGate: tuning.confidenceGate)
        let filteredRatio = filterRatio(ratios.palmWidth)
        pinchRatio = filteredRatio
        // Real frame timestamp, not a counted-frame fake clock — Vision's actual
        // rate under AR load can be well below `tuning.inferenceInterval`'s assumed
        // 66ms, which would silently stretch the hysteresis/grace windows.
        machineTime = packet.timestamp
        rollPalm.push(filteredRatio, now: machineTime)
        palmWidthMin = rollPalm.min
        palmWidthMax = rollPalm.max

        let coverage = handCoveragePct(frame)
        updateOverlay(frame: frame, packet: packet)

        let observation = PinchObservation(
            timestamp: machineTime,
            pinchRatio: filteredRatio,
            confidence: frame.observationConfidence
        )
        let events = stateMachine.process(observation)
        gesturePhaseName = stateMachine.phase.name

        if let gt = groundTruth, ratios.palmWidth != nil {
            metrics.log(
                event: .calibration,
                secondsSinceStart: planeScan.secondsSinceStart,
                planeCount: planeScan.planeCount,
                planeExtentM2: latestExtentM2,
                raycastTier: .none,
                trackingState: latestTrackingState,
                gesturePhase: gesturePhaseName,
                pinchRatio: ratios.palmWidth,
                handCoveragePct: coverage,
                framesReceived: framesReceived,
                framesProcessed: framesProcessed,
                groundTruth: gt.rawValue
            )
        }

        for event in events {
            handleGestureEvent(event, frame: frame, packet: packet, coverage: coverage)
        }
    }

    private func handleGestureEvent(
        _ event: PinchGestureEvent,
        frame: LandmarkFrame,
        packet: FramePacket,
        coverage: Double?
    ) {
        let yawCandidates = YawAngleCalculator.angles(from: frame, confidenceGate: tuning.confidenceGate)
        // Driving yaw signal: horizontal slide of the pinch point (screen-width
        // fraction, gained up), not a hand-rotation angle. Reuses the same
        // pinchViewportPoint the raycast preview already computes this frame in
        // updateOverlay(), so it rides the tested displayTransform pipeline
        // instead of a new raw-Vision-space axis computation. Position signal,
        // not periodic — see GestureTuning.horizontalSlideGain.
        let horizontalSlide: Double? = pinchViewportPoint.map { point in
            Double(point.x / max(cachedViewportSize.width, 1)) * tuning.horizontalSlideGain
        }

        metrics.log(
            event: .gesture,
            secondsSinceStart: planeScan.secondsSinceStart,
            planeCount: planeScan.planeCount,
            planeExtentM2: latestExtentM2,
            raycastTier: lastRaycastTier,
            trackingState: latestTrackingState,
            gesturePhase: event.name,
            pinchRatio: pinchRatio,
            handCoveragePct: coverage,
            framesReceived: framesReceived,
            framesProcessed: framesProcessed,
            yawAngle2D: yawCandidates.thumbIndex,
            yawPalmAxis: yawCandidates.palmAxis,
            yawWristAxis: horizontalSlide,
            mode: manipulationModeName.lowercased() == "—" ? "" : manipulationModeName.lowercased()
        )

        switch event {
        case .began(let ratio):
            // Stale samples from a previous gesture (or from before any gesture
            // started) must not bleed into the first few frames' median.
            ratioFilterBuffer = []
            if scene.hasPlacedEntity, let model = scene.activeModel {
                metrics.beginGesture()
                let scale = model.scale.x
                manipulation.begin(entityScale: scale, entityYaw: scene.modelYaw)
                scene.setHighlighted(true)
                manipulationModeName = "—"
                manipulationCommitted = false
                metrics.log(
                    event: .manipulation,
                    secondsSinceStart: planeScan.secondsSinceStart,
                    planeCount: planeScan.planeCount,
                    planeExtentM2: latestExtentM2,
                    raycastTier: lastRaycastTier,
                    trackingState: latestTrackingState,
                    gesturePhase: "Began",
                    pinchRatio: ratio,
                    handCoveragePct: coverage,
                    framesReceived: framesReceived,
                    framesProcessed: framesProcessed,
                    pinchRatioAtBegan: ratio,
                    scaleFactor: scale,
                    yawAngle2D: yawCandidates.thumbIndex,
                    yawPalmAxis: yawCandidates.palmAxis,
                    yawWristAxis: horizontalSlide,
                    yawAtBegan: horizontalSlide,
                    appliedYawRad: scene.modelYaw,
                    mode: "ambiguous"
                )
            } else {
                placeFromHand(frame: frame, packet: packet)
            }

        case .changed(let ratio):
            guard manipulation.isActive else { break }
            // wrist->middleMCP, not palmAxis (indexMCP->littleMCP) or thumbIndex:
            // both of those share a vector with pinchRatio's numerator/denominator
            // (PinchRatioCalculator.palmWidth), so wrist twist foreshortens them and
            // spikes a spurious scale signal instead of a clean yaw one. wristMiddle
            // is a distinct vector from both — see YawAngleCalculator.Candidates.
            let result = manipulation.update(ratio: ratio, yaw: horizontalSlide, now: machineTime)
            applyManipulation(result)
            if result.didLock {
                stateMachine.exitThresholdOverride = tuning.scaleModeExitThreshold
            }
            if result.committed, !manipulationCommitted {
                // Fires once, on the committed=false->true edge.
                if result.mode == .scale {
                    scene.regenerateCollisionShapes()
                }
                stateMachine.exitThresholdOverride = nil
            }
            manipulationCommitted = result.committed

            // ponytail: OK-sign pause override removed — okSignFingerExtendedRatio
            // was an uncalibrated guess and fired on ordinary scaling pinches,
            // force-committing the gesture within ~50ms (see DECISIONS.md).
            // HandShapeClassifier/isOKSign stay in the codebase, unused, for
            // whenever this gets a real hold-duration gate + calibrated data.

            metrics.log(
                event: .manipulation,
                secondsSinceStart: planeScan.secondsSinceStart,
                planeCount: planeScan.planeCount,
                planeExtentM2: latestExtentM2,
                raycastTier: lastRaycastTier,
                trackingState: latestTrackingState,
                gesturePhase: "Changed",
                pinchRatio: ratio,
                handCoveragePct: coverage,
                framesReceived: framesReceived,
                framesProcessed: framesProcessed,
                pinchRatioAtBegan: result.baselineRatio,
                scaleFactor: result.scaleFactor,
                yawAngle2D: yawCandidates.thumbIndex,
                yawPalmAxis: yawCandidates.palmAxis,
                yawWristAxis: horizontalSlide,
                yawAtBegan: result.baselineYaw,
                appliedYawRad: result.appliedYaw ?? scene.modelYaw,
                mode: result.mode.rawValue
            )

        case .ended:
            if manipulation.isActive {
                if manipulation.mode == .scale {
                    scene.regenerateCollisionShapes()
                }
                metrics.log(
                    event: .manipulation,
                    secondsSinceStart: planeScan.secondsSinceStart,
                    planeCount: planeScan.planeCount,
                    planeExtentM2: latestExtentM2,
                    raycastTier: lastRaycastTier,
                    trackingState: latestTrackingState,
                    gesturePhase: "Ended",
                    pinchRatio: pinchRatio,
                    handCoveragePct: coverage,
                    framesReceived: framesReceived,
                    framesProcessed: framesProcessed,
                    scaleFactor: scene.activeModel?.scale.x,
                    yawAngle2D: yawCandidates.thumbIndex,
                    yawPalmAxis: yawCandidates.palmAxis,
                    yawWristAxis: horizontalSlide,
                    appliedYawRad: scene.modelYaw,
                    mode: manipulation.mode.rawValue
                )
            }
            finishManipulation()

        case .cancelled:
            // Leave transform as-is; do not regenerate.
            finishManipulation()

        default:
            break
        }
    }

    private func applyManipulation(_ result: ManipulationResult) {
        switch result.mode {
        case .ambiguous:
            manipulationModeName = "—"
        case .scale:
            manipulationModeName = result.committed ? "SCALE ✓" : "SCALE"
            if let scale = result.scale {
                scene.applyScale(scale)
            }
        case .yaw:
            manipulationModeName = result.committed ? "YAW ✓" : "YAW"
            if let yaw = result.appliedYaw {
                scene.applyYaw(yaw)
            }
        }
    }

    private func finishManipulation() {
        stateMachine.exitThresholdOverride = nil
        manipulation.reset()
        scene.setHighlighted(false)
        manipulationModeName = "—"
        manipulationCommitted = false
        metrics.endGesture()
    }

    private func placeFromHand(frame: LandmarkFrame, packet: FramePacket) {
        guard let visionPinch = frame.pinchPoint(confidenceGate: tuning.confidenceGate) else {
            lastRaycastTier = .none
            return
        }

        let viewPoint = LandmarkSpace.visionToViewport(
            visionPinch,
            displayTransform: packet.displayTransform,
            viewportSize: packet.viewportSize
        )
        pinchViewportPoint = viewPoint

        let result = placement.raycast(from: viewPoint, in: arView)
        lastRaycastTier = result.tier

        if let transform = result.worldTransform {
            scene.place(at: transform)
            let world = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            raycastViewportPoint = arView.project(world)
        } else {
            raycastViewportPoint = nil
        }

        metrics.log(
            event: .placement,
            secondsSinceStart: planeScan.secondsSinceStart,
            planeCount: planeScan.planeCount,
            planeExtentM2: latestExtentM2,
            raycastTier: result.tier,
            trackingState: latestTrackingState,
            gesturePhase: "Began",
            pinchRatio: pinchRatio,
            framesReceived: framesReceived,
            framesProcessed: framesProcessed
        )
    }

    private func updateOverlay(frame: LandmarkFrame, packet: FramePacket) {
        if showLandmarks {
            viewportJoints = frame.jointList.map { joint in
                let p = LandmarkSpace.visionToViewport(
                    CGPoint(x: joint.x, y: joint.y),
                    displayTransform: packet.displayTransform,
                    viewportSize: packet.viewportSize
                )
                return (p, joint.confidence)
            }
        } else {
            viewportJoints = []
        }

        if let visionPinch = frame.pinchPoint(confidenceGate: tuning.confidenceGate) {
            let viewPoint = LandmarkSpace.visionToViewport(
                visionPinch,
                displayTransform: packet.displayTransform,
                viewportSize: packet.viewportSize
            )
            pinchViewportPoint = viewPoint

            // Live ray preview (does not place) so misalignment is visible before pinch.
            let preview = placement.raycast(from: viewPoint, in: arView)
            if let transform = preview.worldTransform {
                let world = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                raycastViewportPoint = arView.project(world)
                // Don't overwrite lastRaycastTier on every frame — only on place.
            } else {
                raycastViewportPoint = nil
            }
        } else {
            pinchViewportPoint = nil
            raycastViewportPoint = nil
        }
    }

    private func handCoveragePct(_ frame: LandmarkFrame) -> Double? {
        let pts = frame.jointList.filter { $0.confidence >= tuning.confidenceGate }
        guard pts.count >= 2 else { return nil }
        let xs = pts.map(\.x)
        let ys = pts.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        let area = Double((maxX - minX) * (maxY - minY))
        return min(100, area * 100)
    }

    private func clearOverlay() {
        viewportJoints = []
        pinchViewportPoint = nil
        // Keep last raycast point briefly? Clear for honesty.
        raycastViewportPoint = nil
    }

    /// Median-of-5 rolling filter. A dropped/gated frame (nil) doesn't reset
    /// the window — a real gap in tracking is handled upstream by the state
    /// machine's grace period, not here.
    private func filterRatio(_ raw: Double?) -> Double? {
        guard let raw else { return nil }
        ratioFilterBuffer.append(raw)
        if ratioFilterBuffer.count > 5 { ratioFilterBuffer.removeFirst() }
        let sorted = ratioFilterBuffer.sorted()
        return sorted[sorted.count / 2]
    }

    private func resetHandUI() {
        lastRaycastTier = .none
        gesturePhaseName = "Possible"
        pinchRatio = nil
        palmWidthMin = nil
        palmWidthMax = nil
        framesReceived = 0
        framesProcessed = 0
        machineTime = 0
        rollPalm = RollingMinMax()
        ratioFilterBuffer = []
        manipulation.reset()
        manipulationModeName = "—"
        clearOverlay()
    }

    private func applyDebugOptions() {
        if showPlaneVisualization {
            // .showFeaturePoints dropped — adds nothing for plane debugging and
            // camouflages the (also-green) hand landmark dots.
            arView.debugOptions = [.showAnchorGeometry]
        } else {
            arView.debugOptions = []
        }
    }

    private func publishScanState() {
        planeCount = planeScan.planeCount
        secondsToFirstPlane = planeScan.secondsToFirstPlane
        needsScanPrompt = planeScan.needsScanPrompt
        latestExtentM2 = planeScan.totalExtentM2
    }

    private func ingestPlanes(_ anchors: [ARAnchor], removed: Bool) {
        let planes = anchors.compactMap { $0 as? ARPlaneAnchor }
        guard !planes.isEmpty else { return }

        if removed {
            planeScan.remove(planeAnchors: planes)
            publishScanState()
            return
        }

        let isFirst = planeScan.ingest(planeAnchors: planes)
        publishScanState()

        metrics.log(
            event: isFirst ? .firstPlane : .planeUpdate,
            secondsSinceStart: planeScan.secondsSinceStart,
            planeCount: planeScan.planeCount,
            planeExtentM2: planeScan.totalExtentM2,
            raycastTier: .none,
            trackingState: latestTrackingState
        )
    }
}

extension ARSessionCoordinator: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        framesReceivedCounter += 1
        let received = framesReceivedCounter
        // Publish on every delegate callback, not just successful hand-off to
        // Vision below — otherwise this counter reads 0 whenever `packet` is nil
        // (e.g. viewport size not yet known), hiding exactly the failure it
        // exists to surface.
        Task { @MainActor in self.framesReceived = received }

        let viewport = cachedViewportSize

        frameTapLock.lock()
        let packet = frameTap.tryBegin(frame: frame, viewportSize: viewport, interfaceOrientation: .landscapeRight)
        frameTapLock.unlock()

        guard let packet else { return }

        Task {
            let result = await detectorRef.detect(pixelBuffer: packet.pixelBuffer)
            await MainActor.run {
                self.handleVision(frame: result, packet: packet)
            }
        }
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            self.ingestPlanes(anchors, removed: false)
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor in
            self.ingestPlanes(anchors, removed: false)
        }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        Task { @MainActor in
            self.ingestPlanes(anchors, removed: true)
        }
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let state = camera.trackingState
        Task { @MainActor in
            self.latestTrackingState = state
            self.trackingStateLabel = MetricsLogger.trackingLabel(state)
        }
    }
}
