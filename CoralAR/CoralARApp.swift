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

    func makeCoordinator() -> TapBridge {
        TapBridge(session: session)
    }

    func makeUIView(context: Context) -> ARView {
        let view = session.arView
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(TapBridge.handleTap(_:))
        )
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    @MainActor
    final class TapBridge: NSObject {
        let session: ARSessionCoordinator

        init(session: ARSessionCoordinator) {
            self.session = session
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let point = gesture.location(in: view)
            session.handleTap(at: point)
        }
    }
}
