import ARKit
import Combine
import RealityKit
import SwiftUI

/// Owns ARView + ARSession. Horizontal plane detection only. No Vision, no LiDAR semantics.
@MainActor
final class ARSessionCoordinator: NSObject, ObservableObject {
    let arView: ARView
    let planeScan = PlaneScanCoordinator()
    let placement = PlacementService()
    let scene: SceneController
    let metrics = MetricsLogger()

    @Published private(set) var planeCount = 0
    @Published private(set) var secondsToFirstPlane: TimeInterval?
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var needsScanPrompt = true
    @Published private(set) var lastRaycastTier: PlacementService.Tier = .none
    @Published private(set) var trackingStateLabel = "—"
    @Published private(set) var isRunning = false
    @Published var showPlaneVisualization = true {
        didSet { applyDebugOptions() }
    }

    private var tick: AnyCancellable?
    /// Latest extent from plane updates — don't hold ARFrame.
    private var latestExtentM2: Float = 0
    private var latestTrackingState: ARCamera.TrackingState = .notAvailable

    override init() {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView = view
        scene = SceneController(arView: view)
        super.init()
        arView.session.delegate = self
        applyDebugOptions()
    }

    func start() {
        guard !isRunning else { return }
        guard ARWorldTrackingConfiguration.isSupported else {
            trackingStateLabel = "ARKit unsupported"
            return
        }

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        // No sceneDepth / sceneReconstruction — device has no LiDAR (AGENTS.md).

        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        scene.clearAll()
        planeScan.sessionDidStart()
        publishScanState()
        lastRaycastTier = .none
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
                self?.elapsedSeconds = self?.planeScan.secondsSinceStart ?? 0
            }
    }

    func stop() {
        tick?.cancel()
        tick = nil
        arView.session.pause()
        isRunning = false
        metrics.stop()
    }

    func handleTap(at viewPoint: CGPoint) {
        let result = placement.raycast(from: viewPoint, in: arView)
        lastRaycastTier = result.tier

        if let transform = result.worldTransform {
            scene.place(at: transform)
        }

        metrics.log(
            event: .placement,
            secondsSinceStart: planeScan.secondsSinceStart,
            planeCount: planeScan.planeCount,
            planeExtentM2: latestExtentM2,
            raycastTier: result.tier,
            trackingState: latestTrackingState
        )
    }

    private func applyDebugOptions() {
        if showPlaneVisualization {
            arView.debugOptions = [.showAnchorGeometry, .showFeaturePoints]
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
            self.trackingStateLabel = Self.label(for: state)
        }
    }

    private static func label(for state: ARCamera.TrackingState) -> String {
        switch state {
        case .notAvailable:
            return "notAvailable"
        case .normal:
            return "normal"
        case .limited(let reason):
            switch reason {
            case .initializing: return "limited:initializing"
            case .excessiveMotion: return "limited:excessiveMotion"
            case .insufficientFeatures: return "limited:insufficientFeatures"
            case .relocalizing: return "limited:relocalizing"
            @unknown default: return "limited:unknown"
            }
        }
    }
}
