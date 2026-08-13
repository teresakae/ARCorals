import RealityKit
import SwiftUI
import UIKit

@main
struct CoralARApp: App {
    @StateObject private var session = ARSessionCoordinator()

    var body: some SwiftUI.Scene {
        WindowGroup {
            ZStack {
                ARViewContainer(session: session)
                    .ignoresSafeArea()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { session.updateViewportSize($0) }
                    // Interface orientation, not UIDevice.orientation (unreliable near-horizontal —
                    // .faceUp/.faceDown). All 4 orientations supported; each rotation re-derives the
                    // Vision orientation + coordinate mapping (see LandmarkSpace.visionOrientation(for:)).
                    .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                        pushInterfaceOrientation()
                    }
                    .onAppear {
                        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                        pushInterfaceOrientation()
                    }

                LandmarkDotsOverlay(viewportJoints: session.viewportJoints)
                    .ignoresSafeArea()

                HandDebugOverlay(
                    pinchViewportPoint: session.pinchViewportPoint,
                    raycastViewportPoint: session.raycastViewportPoint,
                    pointViewportPoint: session.pointViewportPoint
                )
                .ignoresSafeArea()

                // Always-on user-facing pinch feedback — not gated by showLandmarks/debug toggles.
                PinchProgressOverlay(
                    pinchViewportPoint: session.pinchViewportPoint,
                    progress: session.pinchProgress
                )
                .ignoresSafeArea()

                if session.demoMode == .point {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            PointTestButton(
                                isHovering: session.isPointingAtTestButton,
                                isSelected: session.activeAnnotationID == ARSessionCoordinator.testButtonID,
                                dwellProgress: session.dwellProgress,
                                onFrameChange: { session.updateTestButtonFrame($0) }
                            )
                            .padding(.trailing, 24)
                        }
                        .padding(.bottom, 100)
                    }
                    .ignoresSafeArea()
                }

                ARStatusHUD(session: session)

                AnnotationPopup(annotationID: session.activeAnnotationID)
                    .ignoresSafeArea()
            }
            .statusBarHidden()
            .onAppear { session.start() }
            .onDisappear { session.stop() }
        }
    }

    private func pushInterfaceOrientation() {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
            .first
        guard let orientation else { return }
        session.updateInterfaceOrientation(orientation)
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
        // ⚠️ Viewport via CoralARApp.onGeometryChange — updateUIView first call has bounds == .zero.
    }
}
