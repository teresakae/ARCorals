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

                AnnotationPopup(annotationID: session.activeAnnotationID)
                    .ignoresSafeArea()
            }
            .statusBarHidden()
            .onAppear { session.start() }
            .onDisappear { session.stop() }
        }
    }
}

/// Placeholder text popup for point-and-dwell (Gesture Build Prompt B) — just
/// enough content to exercise the gesture, not a real annotation system.
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
        // Viewport size comes from .onGeometryChange in CoralARApp — updateUIView
        // fires before the view is laid out on first call, so uiView.bounds is .zero then.
    }
}
