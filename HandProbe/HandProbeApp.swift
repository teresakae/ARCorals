import SwiftUI

@main
struct HandProbeApp: App {
    @StateObject private var probe = ProbeController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(probe)
                .statusBarHidden()
                .onAppear { probe.start() }
                .onDisappear { probe.stop() }
        }
    }
}

private struct ContentView: View {
    @EnvironmentObject private var probe: ProbeController

    var body: some View {
        ZStack(alignment: .top) {
            CameraPreviewView(session: probe.camera.session)
                .ignoresSafeArea()

            LandmarkOverlayView(
                joints: probe.overlayJoints,
                orientedImageSize: probe.orientedImageSize
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                LiveReadoutView(
                    result: probe.latest,
                    ratios: probe.latestRatios,
                    fps: probe.smoothedFps,
                    distanceCm: $probe.distanceCm,
                    rigNotes: $probe.rigNotes,
                    logCondition: $probe.logCondition,
                    isLogging: probe.isLogging,
                    logFileName: probe.logFileName,
                    statusMessage: probe.statusMessage,
                    groundTruth: probe.groundTruth,
                    wristBand: (probe.wristMCPMin, probe.wristMCPMax),
                    bboxBand: (probe.bboxDiagMin, probe.bboxDiagMax),
                    palmBand: (probe.palmWidthMin, probe.palmWidthMax),
                    gesturePhaseName: probe.gesturePhaseName,
                    lastGestureEventName: probe.lastGestureEventName,
                    pinchThreshold: GestureTuning.default.pinchThreshold,
                    onToggleLogging: { probe.toggleLogging() },
                    onSetGroundTruth: { probe.setGroundTruth($0) },
                    onClearGroundTruth: { probe.clearGroundTruth() }
                )
            }
        }
        .background(Color.black)
    }
}
