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
    /// Not `private(set)` — +AdjustSlide.swift writes this directly the same way applyManipulation() does.
    @Published var manipulationModeName = "—"
    /// Mirrors `CarryStateMachine.carried`; all carry-related UI derives from this. Written by +Carry.swift.
    @Published var carriedEntity: EntityID?

    /// Demo control — hard override for what a pinch/point/wave means; six cases, no auto-switch. See docs/GESTURES.md §1.
    enum DemoMode: String, CaseIterable, Sendable {
        case place = "Place"
        /// Adjust A — scale via the finger-spread pinch ratio (today's Adjust scale math,
        /// unchanged, yaw removed — routes through the legacy pinch path with
        /// `ManipulationTracker.begin(scaleOnly: true)`; docs/GESTURES.md §1).
        case adjustSpread = "Adjust A"
        /// Adjust B — scale via vertical hand slide (new signal; standalone `VerticalSlideScale`,
        /// its own routing below, never touches `ManipulationTracker`; docs/GESTURES.md §1).
        case adjustSlide = "Adjust B"
        case move = "Move"
        /// Explicit rotate-only mode: any pinch on a placed object rotates it, yaw-only, no
        /// move capability, no history-based inference (docs/GESTURES.md §1).
        case rotate = "Rotate"
        /// Showcase / quiz stand-in — Point/dwell only.
        case point = "Point"
        /// Sim brush-phase stand-in — Carry + Wave only, never rotate; O2/O3 tools are carried, not spun (§2.3).
        case sim = "Sim"

        var allowsPoint: Bool { self == .point }
        var allowsCarry: Bool { self == .sim }
        /// Carry's own re-grab-rotate stand-in (routeCarryPinch's `allowRotate`) — the mode that
        /// had it (`.carry`) is gone, and `.sim` never rotates on re-grab, so this is always false.
        var allowsRotate: Bool { false }
        var allowsWave: Bool { self == .sim }
        /// `.rotate`'s own routing — any pinch on a placed object rotates it (docs/GESTURES.md §1).
        var allowsRotateMode: Bool { self == .rotate }
        /// `.adjustSlide`'s own routing — vertical-slide scale-only mechanism, bypasses the
        /// legacy pinch path entirely (docs/GESTURES.md §1).
        var allowsAdjustSlide: Bool { self == .adjustSlide }
        var allowsLegacyPinch: Bool {
            self == .place || self == .adjustSpread || self == .move
        }
    }
    @Published var demoMode: DemoMode = .adjustSpread {
        didSet {
            // Edge only: per-frame endCarryIfActive() also killed Adjust's shared ManipulationTracker.
            if oldValue.allowsCarry, !demoMode.allowsCarry {
                endCarryIfActive()
            }
            if oldValue.allowsRotateMode, !demoMode.allowsRotateMode {
                endRotateModeIfActive()
            }
            if oldValue.allowsAdjustSlide, !demoMode.allowsAdjustSlide {
                endAdjustSlideIfActive()
            }
        }
    }

    @Published var showPlaneVisualization = false {
        didSet { applyDebugOptions() }
    }
    @Published var showLandmarks = true
    @Published var hudHidden = false

    /// Device-level property, not a second capture session — coexists with ARKit owning the camera;
    /// Control Center's toggle often can't reach the torch while another app holds it, this can.
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

    /// Annotation currently showing its popup (nil = none). Written by
    /// ARSessionCoordinator+Point.swift on `.hoverBegan` / `.hoverEnded`.
    @Published var activeAnnotationID: AnnotationID?
    /// Live point-and-dwell fill, for a future ring affordance. Written by
    /// ARSessionCoordinator+Point.swift.
    @Published var dwellProgress: Double = 0
    /// Live pinch-commit fill (0–1 during the pendingBegan hysteresis window, 1 once
    /// committed) — drives the user-facing pinch progress ring. See `PinchProgressOverlay`.
    @Published private(set) var pinchProgress: Double = 0

    /// Not `private` — +Rotate.swift sets `exitThresholdOverride` when re-grab rotate locks scale mode.
    var stateMachine = PinchStateMachine(tuning: .default)
    /// Not `private` — +Rotate.swift drives this for `.rotate` demo mode.
    var manipulation = ManipulationTracker(tuning: .default)
    /// Not `private` — also driven from +Carry.swift's `.pickedUp`/`.putDown` (carry reuses Move's follow controller).
    var moveController = MoveController(tuning: .default)
    /// Not `private` — +AdjustSlide.swift drives this for `.adjustSlide` demo mode (Adjust B).
    var adjustSlideScale = VerticalSlideScale(tuning: .default)
    /// Entities Carry has put down at least once; a re-pinch on one routes to ManipulationTracker (yaw) instead of a new carry.
    var previouslyPlacedEntities: Set<EntityID> = []
    /// Pest currently being dragged (Sim mode pick-up-and-throw); nil when none. Not `private` — +Carry.swift drives this.
    var draggedPest: ModelEntity?
    /// Separate from `moveController` — a pest drag and an O1 carry never share one follow state. Not `private` — +Carry.swift drives this.
    var pestMoveController = MoveController(tuning: .default)
    /// Not `private` — mutated only from +Point.swift's `handlePoint` outside `start()`.
    var pointStateMachine = PointStateMachine(tuning: .default)
    /// Not `private` — mutated only from +Wave.swift's `handleWave` outside `start()`.
    var waveDetector = WaveDetector(tuning: .default)
    /// Not `private` — fed only from +Carry.swift's `handleCarryRouting` outside `start()`.
    var carryMachine = CarryStateMachine(tuning: .default)
    /// `.waved` fire count — debug HUD affordance. Not `private(set)` — incremented from +Wave.swift's `handleWave`.
    @Published var waveCount = 0
    /// Last gesture-end timestamp — sole input to the Move-vs-Adjust grab-timing decision.
    private var lastGestureEndTime: TimeInterval?
    /// Live placement-preview raycast hit (refreshed in updateOverlay()); Move reads this instead of re-raycasting.
    /// `private(set)`, not `private` — +Carry.swift reads it the same way.
    private(set) var previewWorldHit: SIMD3<Float>?
    private var rollPalm = RollingMinMax()
    /// Last accepted hand centroid, normalized coords — continuity gate for bystander rejection (ADR-021).
    private var lastHandCentroid: CGPoint?
    /// Median-of-5 on pinchRatio, the chokepoint every consumer reads through — not EMA, since raw noise is
    /// outlier spikes (up to 20x in one frame; ~35% of consecutive frames jump enough to blow the deadzone).
    private var ratioFilterBuffer: [Double] = []
    /// `private(set)` — +Point.swift (and future +Carry/+Wave) read this as the shared frame clock.
    private(set) var machineTime: TimeInterval = 0
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
        moveController.reset()
        adjustSlideScale.reset()
        pointStateMachine.reset()
        waveDetector.tuning = tuning
        waveDetector.reset()
        waveCount = 0
        carryMachine.reset()
        carriedEntity = nil
        previouslyPlacedEntities = []
        draggedPest = nil
        pestMoveController.reset()
        activeAnnotationID = nil
        dwellProgress = 0
        pinchProgress = 0
        lastGestureEndTime = nil
        manipulationModeName = "—"
        publishScanState()
        resetHandUI()
        framesReceivedCounter = 0
        lastHandCentroid = nil
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
            // Nil frame (Vision threw) still must reach every state machine or an in-flight
            // gesture never times out — see docs/ARCHITECTURE.md §5 seam 5.
            clearOverlay()
            machineTime = packet.timestamp
            let events = stateMachine.process(
                PinchObservation(timestamp: machineTime, pinchRatio: nil, confidence: nil)
            )
            gesturePhaseName = stateMachine.phase.name
            pinchProgress = stateMachine.pendingProgress
            if events.contains(.cancelled) {
                lastGestureEndTime = machineTime
                finishManipulation()
            }
            handleCarryRouting(frame: nil, packet: packet, pinchEvents: events)
            handleRotateModeRouting(frame: nil, packet: packet, pinchEvents: events)
            handleAdjustSlideRouting(frame: nil, packet: packet, pinchEvents: events)
            handlePoint(frame: nil, packet: packet)
            handleWave(frame: nil, packet: packet)
            return
        }

        // Bystander-hand rejection (ADR-021): size + frame-to-frame continuity, before this
        // frame's hand gets treated as ours by anything downstream.
        let coverage = handCoveragePct(frame)
        guard passesHandGate(frame, coverage: coverage) else {
            handleVision(frame: nil, packet: packet)
            return
        }

        inferenceHz = frame.inferenceHz
        let ratios = PinchRatioCalculator.ratios(from: frame.joints, confidenceGate: tuning.confidenceGate)
        let filteredRatio = filterRatio(ratios.palmWidth)
        pinchRatio = filteredRatio
        // Real frame timestamp, not a counted-frame clock — Vision's actual rate under AR load can dip
        // below inferenceInterval's assumed 66ms, which would silently stretch hysteresis/grace windows.
        machineTime = packet.timestamp
        rollPalm.push(filteredRatio, now: machineTime)
        palmWidthMin = rollPalm.min
        palmWidthMax = rollPalm.max

        // Order: ratio→overlay→pinch→carry/rotate→point→wave; legacy after, gated (ARCHITECTURE.md §4).
        updateOverlay(frame: frame, packet: packet)

        let observation = PinchObservation(
            timestamp: machineTime,
            pinchRatio: filteredRatio,
            confidence: frame.observationConfidence
        )
        let events = stateMachine.process(observation)
        gesturePhaseName = stateMachine.phase.name
        pinchProgress = stateMachine.pendingProgress

        handleCarryRouting(frame: frame, packet: packet, pinchEvents: events)
        handleRotateModeRouting(frame: frame, packet: packet, pinchEvents: events)
        handleAdjustSlideRouting(frame: frame, packet: packet, pinchEvents: events)
        handlePoint(frame: frame, packet: packet)
        handleWave(frame: frame, packet: packet)

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
        // Yaw = horizontalSlide of pinchViewportPoint × gain (docs/GESTURES.md §2.3).
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
            horizontalSlide: horizontalSlide,
            mode: manipulationModeName.lowercased() == "—" ? "" : manipulationModeName.lowercased()
        )

        // ⚠️ Skip when !allowsLegacyPinch — races Carry's moveController (docs/ARCHITECTURE.md §4).
        guard demoMode.allowsLegacyPinch else { return }

        switch event {
        case .began(let ratio):
            // Stale samples from a previous gesture (or from before any gesture
            // started) must not bleed into the first few frames' median.
            ratioFilterBuffer = []
            if demoMode != .place, scene.hasPlacedEntity,
               let point = pinchViewportPoint, let model = scene.selectModel(at: point) {
                // HUD DemoMode decides; moveOrAdjustTrigger not on live path (docs/GESTURES.md §1).
                let trigger: GrabTrigger = demoMode == .move ? .move : .adjust

                switch trigger {
                case .adjust:
                    // Legacy Adjust path is now exclusively Adjust A (finger-spread scale);
                    // `.adjustSlide` (Adjust B) never reaches here — routed separately via
                    // handleAdjustSlideRouting. scaleOnly: true — yaw lives entirely in
                    // `.rotate` now (docs/GESTURES.md §1).
                    metrics.beginGesture()
                    let scale = model.scale.x
                    beginManipulation(entityScale: scale, entityYaw: scene.modelYaw, scaleOnly: true)
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
                        horizontalSlide: horizontalSlide,
                        yawAtBegan: horizontalSlide,
                        appliedYawRad: scene.modelYaw,
                        mode: "ambiguous"
                    )

                case .move:
                    // ⚠️ Wait for previewWorldHit — model-world hit0 snaps under fingertip (GESTURES.md §2.8).
                    guard let hit = previewWorldHit else { break }
                    metrics.beginGesture()
                    moveController.begin(hit: hit, modelWorld: model.position(relativeTo: nil))
                    scene.setHighlighted(true)
                    manipulationModeName = "MOVE"
                }
            } else if demoMode == .place || !scene.hasPlacedEntity {
                // Place appends; Move/Adjust only place when nothing exists yet (ADR-019).
                placeFromHand(frame: frame, packet: packet)
            }
            // else: miss even with screen-radius fallback → no grab (docs/GESTURES.md §2.1).

        case .changed(let ratio):
            guard manipulation.isActive || moveController.isActive else { break }

            if moveController.isActive {
                let newTarget = moveController.update(hit: previewWorldHit)
                scene.moveModel(toWorld: newTarget)
                break
            }

            // ⚠️ horizontalSlide is linear — don't feed radians w/o ±π unwrap (ARCHITECTURE.md §4).
            let result = manipulation.update(ratio: ratio, yaw: horizontalSlide, now: machineTime)
            applyManipulation(result)

            // ponytail: OK-sign pause removed — uncalibrated, fired ~50ms (docs/GESTURES.md §2.6).

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
                horizontalSlide: horizontalSlide,
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
                    horizontalSlide: horizontalSlide,
                    appliedYawRad: scene.modelYaw,
                    mode: manipulation.mode.rawValue
                )
            }
            // No re-anchor on move-end — moveModel() already works at any
            // offset from the (never-moving) anchor; see SceneController.
            lastGestureEndTime = machineTime
            finishManipulation()

        case .cancelled:
            // Leave transform as-is; do not regenerate.
            lastGestureEndTime = machineTime
            finishManipulation()

        default:
            break
        }
    }

    /// Shared Adjust A / re-grab-rotate start. Not `private` — `+Rotate.swift` calls this.
    /// `yawOnly` defaults false; `.rotate` mode passes true via `beginRotate(yawOnly:)`.
    /// `scaleOnly` defaults false; `.adjustSpread` (Adjust A) passes true — see the legacy
    /// `.began` case below.
    func beginManipulation(entityScale: Float, entityYaw: Float, yawOnly: Bool = false, scaleOnly: Bool = false) {
        manipulation.begin(entityScale: entityScale, entityYaw: entityYaw, yawOnly: yawOnly, scaleOnly: scaleOnly)
        scene.setHighlighted(true)
        manipulationModeName = "—"
        manipulationCommitted = false
    }

    /// Shared Adjust/rotate apply + commit-edge; called from +Rotate.swift.
    func applyManipulation(_ result: ManipulationResult) {
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
        if result.didLock {
            stateMachine.exitThresholdOverride = tuning.scaleModeExitThreshold
        }
        if result.committed, !manipulationCommitted {
            if result.mode == .scale {
                scene.regenerateCollisionShapes()
            }
            stateMachine.exitThresholdOverride = nil
        }
        manipulationCommitted = result.committed
    }

    /// Not `private` — ARSessionCoordinator+Rotate.swift ends a re-grab rotate
    /// the same way Adjust does.
    func finishManipulation() {
        stateMachine.exitThresholdOverride = nil
        manipulation.reset()
        moveController.reset()
        scene.setHighlighted(false)
        manipulationModeName = "—"
        manipulationCommitted = false
        metrics.endGesture()
    }

    /// Not `private` — +AdjustSlide.swift's `.began` case places the same way legacy Adjust/Move do.
    func placeFromHand(frame: LandmarkFrame, packet: FramePacket) {
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

            // Live ray preview (no place); Move reuses previewWorldHit.
            let preview = placement.raycast(from: viewPoint, in: arView)
            if let transform = preview.worldTransform {
                let world = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                raycastViewportPoint = arView.project(world)
                previewWorldHit = world
                // Don't overwrite lastRaycastTier on every frame — only on place.
            } else {
                raycastViewportPoint = nil
                previewWorldHit = nil
            }
        } else {
            pinchViewportPoint = nil
            raycastViewportPoint = nil
            previewWorldHit = nil
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

    /// Bystander-hand rejection (ADR-021). Vision hands us at most one hand already
    /// picked by its own size heuristic — this is the only place we get to say no to it.
    /// Size: implausibly small (background) or large (shoved at the lens) → reject.
    /// Continuity: jumped too far from the last accepted hand in one frame → likely a
    /// different hand, reject and keep tracking the old position rather than snapping to it.
    private func passesHandGate(_ frame: LandmarkFrame, coverage: Double?) -> Bool {
        if let coverage, !(tuning.handCoverageMin...tuning.handCoverageMax).contains(coverage) {
            return false
        }
        guard let centroid = handCentroid(frame) else { return true }
        if let last = lastHandCentroid,
           hypot(centroid.x - last.x, centroid.y - last.y) > tuning.handJumpRejectRadius {
            return false
        }
        lastHandCentroid = centroid
        return true
    }

    private func handCentroid(_ frame: LandmarkFrame) -> CGPoint? {
        let pts = frame.jointList.filter { $0.confidence >= tuning.confidenceGate }
        guard !pts.isEmpty else { return nil }
        let x = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
        let y = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
        return CGPoint(x: x, y: y)
    }

    private func clearOverlay() {
        viewportJoints = []
        pinchViewportPoint = nil
        // Keep last raycast point briefly? Clear for honesty.
        raycastViewportPoint = nil
        previewWorldHit = nil
    }

    /// Median-of-5; nil does not reset — grace is upstream (docs/ARCHITECTURE.md §4).
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
        moveController.reset()
        adjustSlideScale.reset()
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
        // Count every callback, not only Vision hand-offs — else hides packet=nil failures.
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
