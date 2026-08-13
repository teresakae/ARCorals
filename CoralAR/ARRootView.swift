import RealityKit
import SwiftUI

/// The AR screen. Was `CoralARApp`'s scene body until the room flow and the AR flow were
/// merged into one target — the contents are unchanged, only the wrapper is now a `View` so
/// the session screen can present it.
///
/// Owns the `ARSessionCoordinator`, so the `ARSession` starts when this view appears rather
/// than at launch. In the room flow that means no camera and no world tracking until the
/// player actually enters AR.
struct ARRootView: View {
    @StateObject private var session = ARSessionCoordinator()

    var body: some View {
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

            // Always-on user-facing pinch feedback — not gated by showLandmarks/debug toggles.
            PinchProgressOverlay(
                pinchViewportPoint: session.pinchViewportPoint,
                progress: session.pinchProgress
            )
            .ignoresSafeArea()

            ARStatusHUD(session: session)

            AnnotationPopup(annotationID: session.activeAnnotationID)
                .ignoresSafeArea()
        }
        .statusBarHidden()
        .onAppear { session.start() }
        .onDisappear { session.stop() }
    }
}

/// Placeholder popup for point-and-dwell — scaffold, not real annotations. GESTURES.md §2.9.
private struct AnnotationPopup: View {
    let annotationID: AnnotationID?

    var body: some View {
        VStack {
            Spacer()
            if let annotationID {
                Text(annotationID.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.bottom, 40)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: annotationID)
    }
}

private struct ARViewContainer: UIViewRepresentable {
    let session: ARSessionCoordinator

    func makeUIView(context: Context) -> ARView {
        session.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // ⚠️ Viewport via ARRootView.onGeometryChange — updateUIView first call has bounds == .zero.
    }
}
