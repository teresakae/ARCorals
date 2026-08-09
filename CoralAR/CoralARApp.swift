import RealityKit
import SwiftUI

@main
struct CoralARApp: App {
    @StateObject private var session = ARSessionCoordinator()

    var body: some SwiftUI.Scene {
        WindowGroup {
            ZStack {
                ARViewContainer(session: session)
                    .ignoresSafeArea()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { session.updateViewportSize($0) }

                LandmarkDotsOverlay(viewportJoints: session.viewportJoints)
                    .ignoresSafeArea()

                HandDebugOverlay(
                    pinchViewportPoint: session.pinchViewportPoint,
                    raycastViewportPoint: session.raycastViewportPoint
                )
                .ignoresSafeArea()

                ARStatusHUD(session: session)
            }
            .statusBarHidden()
            .onAppear { session.start() }
            .onDisappear { session.stop() }
        }
    }
}

private struct ARViewContainer: UIViewRepresentable {
    let session: ARSessionCoordinator

    func makeUIView(context: Context) -> ARView {
        session.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Viewport size comes from .onGeometryChange in CoralARApp — updateUIView
        // fires before the view is laid out on first call, so uiView.bounds is .zero then.
    }
}
