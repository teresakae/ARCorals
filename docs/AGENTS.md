# AGENTS.md — instructions for AI coding agents in this repo

**Where this stands:** the original build phases 0–5 are complete and verified. Phase 6 (swap the cube placeholder for a real `coral.usdz`) was never built — work moved instead to a gesture build track (Point / Carry / Rotate / Wave) on top of the cube prototype. The content layer hasn't started. The phase-gating system that governed phases 0–5 is retired; it did its job and the work is no longer organised in phases. For scope and what's tested vs not, see [`PROJECT.md`](PROJECT.md). For per-gesture status, see [`GESTURES.md`](GESTURES.md).

---

## What this repo is

An **experiment**, not a product. **Roaming handheld:** user walks with the phone; rear camera watches the free hand; hand gestures place / scale / yaw a coral model on a real surface, rendered on the phone's own screen. Desk/tripod stand was the early de-risking and calibration rig only — not live use (ADR-004 / ADR-020). The goal is a measured yes/no on feasibility. See [`PROJECT.md`](PROJECT.md).

Settled technical decisions trace to [`DECISIONS.md`](DECISIONS.md) — the ADRs are the source of truth for what was chosen and why. Feasibility background, prior art, and live risks are in [`PROJECT.md`](PROJECT.md). **Do not contradict the recorded evidence. Do not do fresh web research to "verify" it.** Where empirical results superseded a researched guess, the measured number wins — e.g. ADR-015's calibrated pinch threshold was itself superseded by ADR-017 once it was measured again in a new context. [`GESTURES.md`](GESTURES.md) tags every tuning constant with its provenance. If something isn't settled anywhere and you're unsure, say you're unsure — do not invent an API or a number.

---

## Stack and versions

| Item | Value |
|---|---|
| Device | **iPhone 17 base (non-Pro)** |
| OS | **iOS 26** |
| Language | Swift, native. No Unity, no Godot, no SceneKit |
| AR | ARKit — `ARWorldTrackingConfiguration` |
| Rendering | RealityKit via **`ARView`** (not `RealityView`) |
| Hand pose | Vision — **`DetectHumanHandPoseRequest` / `HumanHandPoseObservation`** (iOS 18+ Swift API) |
| Assets | Sketchfab models, glb → usdz. **Plain cube placeholder — no `coral.usdz` in the repo yet; `ModelProvider` generates the cube** |

Use the **modern** Vision API, not the legacy `VNDetectHumanHandPoseRequest` / `VNHumanHandPoseObservation`. The modern one is Swift-only, async/await, `Sendable`, and ships coordinate-conversion helpers (`NormalizedPoint.toImageCoordinates(from:imageSize:origin:)`) that remove the need to hand-roll the `1 - y` flip. The legacy API still works — that is not a reason to use it.

---

## Hard constraints

### ⚠️ No LiDAR. Ever. On this device.

iPhone 17 base has **no LiDAR** (confirmed on Apple's spec page; only 12–17 **Pro/Pro Max** have it — iPhone Air and 17e are also excluded). **Do not suggest, scaffold, or reference:**

- `sceneDepth` / `smoothedSceneDepth`
- `sceneReconstruction` / `ARMeshAnchor`
- Real-world occlusion of virtual content
- "Instant placement" / near-instant plane detection

If you find yourself writing `supportsSceneReconstruction` or `supportsFrameSemantics(.sceneDepth)` as anything other than a defensive `guard` that logs and bails, stop. There is no LiDAR fallback path to build, because there is no LiDAR path.

**Also not in v1:** `estimatedDepthData` / `.personSegmentationWithDepth`. It exists on this device and the research says its range behavior actually favors us (degradation is documented *beyond* ~1.5–1.75m, and hands sit at 30–60cm) — but it has real power/thermal cost, no shipped app has been found doing this on a non-LiDAR device, and **v1 needs no hand depth at all.** Park it.

### v1 is 2D landmarks + ARKit raycast, full stop

All three mechanics are expressible without hand depth:

| Mechanic | Source | Needs depth? |
|---|---|---|
| Place | raycast from the 2D pinch point to the plane | No |
| Scale | delta in a scale-invariant 2D ratio | No |
| Yaw | 2D angle between two fingertips in image space | No |

Do not add a depth estimation path "for later." Adding it changes the architecture and is a separate decision.

### Rig: roaming handheld, phone screen is the display

The user walks with the phone. One hand holds it; the other gestures in the rear-camera view. The object renders on the phone's own screen. Desk/tripod stand was calibration/de-risking only (ADR-004); live use is roaming, same binary, no code fork (ADR-020). **Do not design for a headset.** The cardboard-VR-box rig is rejected (single lens cannot produce stereo; documented nausea; unmeasured passthrough latency; thermal throttling in an enclosure). AR glasses are deferred on cost and because they'd need a second device as the "eyes." No stereo rendering, no `UIScreen`/external-display code, no side-by-side output, no head-tracking assumptions.

### It's YAW, not "Z rotation"

Y is up in ARKit/RealityKit; the ground is the X-Z plane. Spinning the coral like a lazy Susan is rotation about **Y**.

```swift
entity.transform.rotation = simd_quatf(angle: yawRadians, axis: [0, 1, 0])
```

Any earlier conversation saying "Z rotation" means yaw. Use `yaw` in all names, comments, and variables. `zRotation` should not appear in this codebase.

### One hand

`maximumHandCount = 1`. Perf, and the interaction design doesn't need two.

---

## The three coordinate gotchas

Ranked by how much time they will cost you. All three are documented in the research; all three produce "the dot is in the wrong place" symptoms that look like different bugs.

### 1. Sensor orientation is ALWAYS landscape-right

`ARFrame.capturedImage` is always in native sensor orientation regardless of device orientation. It does not rotate. **Pass `orientation: .right`** for a portrait-held device. This was the accepted fix in Apple forum thread 665274 — the OP used `.up`, got misaligned points, and `.right` fixed it with no further conversion.

Whatever the exact initializer for the iOS 18+ Swift request handler turns out to be (verify in Xcode — the research did not capture the full signature), **the orientation argument is `.right`.** That's the load-bearing part.

**Hardcode it** (`.right`). Do not consult `UIDevice.current.orientation` — it is unreliable when the device is near-horizontal, reporting `.faceUp` / `.faceDown`, and roaming does not change that. The live path still assumes a typical portrait hold.

### 2. Vision's origin is bottom-left; UIKit's is top-left

Vision normalizes to a **bottom-left** origin. UIKit/SwiftUI is top-left. On iOS 18+ use the provided converter rather than hand-rolling `1 - y`:

`NormalizedPoint.toImageCoordinates(from:imageSize:origin:)`, with `origin: .upperLeft`.

A hand-rolled flip is not wrong per se, but it's one more place for the sign to be wrong, and it will be.

### 3. `frame.displayTransform(for:viewportSize:)` — not width-ratio scaling

`frame.camera.imageResolution` ≠ your view size, and `ARView` applies its own aspect-fill crop on top. **Naive width-ratio scaling is wrong** and produces an offset that is small in the center and large at the edges — which reads as "the tracking is bad near the edges" when it's actually a transform bug.

```swift
let t = frame.displayTransform(for: interfaceOrientation, viewportSize: view.bounds.size)
let viewPoint = normalizedVisionPoint.applying(t)
```

**Diagnostic:** if the debug overlay dot sits on the fingertip in the center of the screen but drifts in the corners, it is gotcha #3, not detection quality.

### 4. With `orientation: .right`, Vision→image is an axis-swap — not a y-flip

`LandmarkSpace.visionToImageNormalized` does `CGPoint(x: 1 - vision.y, y: 1 - vision.x)`. Vision with `.right` is already upright; `displayTransform` expects native landscape buffer coords. A plain `1 - y` flip (gotcha #2) is wrong here and will look like "tracking is rotated 90°."

---

## Known bugs and traps

### Viewport size: use `.onGeometryChange`, not `updateUIView` bounds

`ARViewRepresentable.updateUIView` is called with `bounds == .zero` on the first pass. Feed viewport size from SwiftUI `.onGeometryChange` into `ARSessionCoordinator.updateViewportSize` (see `CoralARApp`). Using `uiView.bounds` too early corrupts `displayTransform` and every raycast downstream.

### Collision shapes don't track scale ⚠️

`generateCollisionShapes(recursive:)` output does **not** correctly account for scale applied afterward (Apple forum 733648). Hit-testing silently desyncs from what's on screen. **Regenerate collision shapes after significant scale changes** — after the gesture Ends is enough; do not regenerate per frame.

### Scale the child, not the anchor

Apply scale to the child `ModelEntity`. Keep the `AnchorEntity`'s transform purely tied to the tracked plane, at identity scale. Scaling the anchor interacts badly with re-anchoring and tracking updates.

### Don't animate long rotations with `move(to:duration:)`

Quaternion slerp takes the short way around past 180°, producing a visible snap in the wrong direction. For continuous hand-driven spin, **set `transform.rotation` directly per frame.**

### `installGestures` is a reference, not a backend

`entity.installGestures(_:for:)` (`.translation` / `.scale` / `.rotation`) still ships and its transform math is exactly what we want — translation re-raycasts every frame to keep the object glued to the surface; rotation maps to yaw about the surface normal. **But** these are `UIGestureRecognizer` subclasses wired to `UIView` touch delivery. You **cannot** feed hand-tracking deltas into them without subclassing/adapting. Read them for the math. Don't try to drive them.

### `ManipulationComponent` — visionOS-only, settled

WWDC25's `ManipulationComponent` is purpose-built for direct-manipulation pick-up/rotate/scale and auto-adds `CollisionComponent` + `InputTargetComponent` + `HoverEffectComponent`. It would have been a more natural backend than adapting touch recognizers — but it **does not exist on iOS.** The header check is done (ADR-013): `RealityFoundation.swiftinterface` on the iPhoneOS 26.5 SDK marks it `@available(visionOS 26.0, *)` with `@available(iOS, unavailable)`. **Do not scaffold against it and do not re-open this.** Scale and yaw are hand-rolled via `ManipulationTracker` plus direct `transform.rotation` writes.

### iOS 26 silently swapped the hand pose model

Per WWDC25 session 272: smaller, faster, more accurate model, still 21 joints, but **"the joints are not in the same location as the previous model."** The swap shipped with **no new revision enum** — only `revision1` is exposed, so you cannot pin, A/B, or feature-detect the version. Consequence for us: any pre-iOS-26 Create ML hand classifier is silently miscalibrated. We aren't using Create ML, so this mostly means: **don't trust landmark constants copied from pre-2025 blog posts or sample code.** Measure our own.

---

## Performance rules

These are not optional. ARKit and Vision are competing for the same camera pipeline.

1. **Vision runs on a serial background queue.** Never on the ARSession delegate queue. Running the request on every `ARFrame` on the session queue will stall ARKit.
2. **Throttle to ~15–20 Hz.** Gesture input does not need 60 Hz. Patterns from the wild: `minInferenceInterval = 0.08s` (~12.5 Hz), or `frameCounter % N == 0`. Either is fine; pick one and make it a named constant.
   - There *is* an existence proof of 60fps ([ogoguel/realtimehand](https://github.com/ogoguel/realtimehand), synchronous per frame, shipped in an App Store app) — but there is also counter-evidence: ARHeadsetKit's author ran at 60fps, the phone got "extremely warm in minutes," iOS throttled display refresh 60→30Hz, and he dropped to every 6th frame (~10Hz). We are not in a sealed enclosure, but we also gain nothing from 60Hz.
3. **`maximumHandCount = 1`.**
4. **Release `ARFrame`s promptly.** Holding many `ARFrame`s starves ARKit's buffer pool and it drops frames. Take `frame.capturedImage` (a `CVPixelBuffer`), hand it to the request handler, and let the frame go. **Never** store an `ARFrame` in a property, an array, or a closure that outlives the callback. If a frame is already in flight, **drop the new one** — do not queue.
5. **Do not open a second `AVCaptureSession`.** ARKit owns the camera. Consume its frames.
6. **No `print()` per frame in `CoralAR`.** The `HandProbe` harness logs deliberately and heavily — that's its job. `CoralAR` uses throttled/structured logging instead.

---

## Things that will look like bugs but aren't

Do not "fix" these. If a task asks you to, push back and cite this section.

| Symptom | Why it's expected |
|---|---|
| **The coral renders on top of the user's hand** instead of being hidden behind it | Real occlusion is LiDAR-only. Accepted non-goal in [`PROJECT.md`](PROJECT.md) |
| **The raycast passes through the hand** and hits the plane behind it | Intended. Raycast is the right tool for "place under where I'm pointing" and the wrong tool for "where is my hand in 3D" |
| **No plane appears for several seconds** at session start | Without LiDAR, planes come from sparse visual feature points and need a couple of seconds of deliberate panning. Requires explicit "scan the surface" onboarding — that's a feature, not a workaround |
| **Plane boundaries are coarse, and planes merge/split/drift** as you look around | Standard non-LiDAR behavior as feature data accumulates |
| **A blank white or glossy desk never produces a plane at all** | Documented non-LiDAR failure. Fix the *table* (textured mat), not the code |
| **`.estimatedPlane` results jump around** as the estimate firms up | That's what estimated means. Its normals can be plain wrong on featureless/reflective surfaces, so objects sit tilted or at the wrong height |
| **Detection returns zero landmarks, not bad landmarks**, when the wrist leaves frame | Detect-then-regress architectures fail completely on truncation/palm occlusion rather than degrading. This is the exact thing Phase 0 measures |
| **Pinch threshold from a blog post doesn't work** at our distance | Fixed pixel/normalized thresholds (0.05 normalized, ~3cm physical) only work at one working distance. That's the entire reason for `pinchRatio` |
| **Gesture state doesn't end the instant fingers separate** | ~100ms hysteresis is deliberate. So is the grace period that keeps a drag alive through 1–2 dropped frames |
| **Placement is precise to ~5cm, not ~5mm** | Vision Pro solves precision with **gaze** ("the eyes select, the hands manipulate"); raw hand pointing is "susceptible to hand jitter — the Heisenberg problem." We have no gaze substitute on iPhone. Sub-centimeter precision is not a target |
| **Arms get tired** | Purdue CHI'17: unsupported mid-air gestures cost significantly more time, energy and exertion than a keyboard. Roaming: one hand holds the phone, the other gestures mid-air — no table rest. Expected, not a tracking bug |

---

## Anti-suggestions

Do not propose these. They have each already been considered and rejected in [`DECISIONS.md`](DECISIONS.md):

- "Just use LiDAR / buy a Pro" — v1 uses no hand depth, so LiDAR would not fix a detection failure
- "Port to Unity" — Unity's XR Hands package states plainly that **"the OpenXR package is the only plug-in provider that supports hand tracking."** ARKit's handheld iOS plugin does not feed that subsystem. You'd write the same native Vision wrapper *plus* an interop layer
- "Use ARKit body tracking to find the hands" — Nomtek tested it: false-positived on water bottles and shadows, and doesn't work on isolated hands without full-body context
- "Use MediaPipe" — Nomtek: accurate, but degraded badly in low light
- "Use ManoMotion" — Nomtek measured ~70% accuracy in good light and rejected it; the vendor's messaging has visibly pivoted toward industrial "Physical AI"
- "Switch to SceneKit" — went into maintenance mode at WWDC25
- "Switch to `RealityView`" — see below
- "Add a Create ML gesture classifier" — see the iOS 26 model swap above; also out of scope

### On `ARView` vs `RealityView`

`RealityView` is Apple's stated direction (WWDC25 session 288: "when using RealityKit, `RealityView` should be used in all cases"). **We use `ARView` anyway.** `ARView` is not deprecated, and `RealityView` still lacks AR parity on iOS: no `debugOptions`, no `@Environment(\.realityKitScene)` outside visionOS, less flexibility. We need direct `ARSession` / `ARFrame` access to feed Vision. One Apple forum participant's summary of the situation: *"a bit of an awkward state right now where you gotta pick and each option brings its own disadvantages."* This is a considered choice, not tech debt.

---

## Working style in this repo

- **Planning docs are not implementation specs.** `ARCHITECTURE.md`, `DECISIONS.md`, `PROJECT.md`, `GESTURES.md` describe intent. Read them before writing code.
- **The `HandProbe` measurement harness is throwaway; the gesture logic it exercises is not.** The capture/overlay/logging scaffolding in `HandProbe/` (detector plumbing, `LandmarkOverlayView`, `MetricsLogger`) exists to produce numbers — don't refactor it for elegance or generalize it. But the gesture state machines and tuning (`GestureTuning`, `HandShapeClassifier`) live in `CoralAR/Gesture/` and are shared into `HandProbe` via `project.yml` — that's production code. `HandProbeTests` is a live unit-test target covering it; add tests there when you touch a state machine, don't skip them because "it's just HandProbe."
- **Every measurement gets written down.** If a change makes logging harder, it's the wrong change.
- **Named constants for every threshold.** Pinch threshold, hysteresis duration, grace period, throttle interval, confidence gate. All in one place, all tunable without hunting. Current values, and the measurement each one came from, are recorded in the ADRs and in [`GESTURES.md`](GESTURES.md) — check there before assuming a number is a placeholder.
- **Confidence gate:** discard landmarks below the configured threshold (`GestureTuning.confidenceGate`, currently **0.3**). If you change it, log how often it fires.
- **If you're unsure whether an API exists on iOS 26 for iPhone, say so.** Do not generate plausible-looking API calls. What's still unverified: exact `VN*` deprecation annotations, and ms benchmarks for the hand pose model on A19. Treat those as unknown, not as things to guess at. (`ManipulationComponent`'s iOS availability used to be on this list — it's settled now, see Known bugs and traps above.)

### Test rig discipline

Before measuring anything: name the condition. **Live use is roaming handheld.** Numbers in ADR-015/017 and [`GESTURES.md`](GESTURES.md) §3 came from a **desk/tripod stand** (height/tilt recorded, don't adjust mid-run, one lighting setup, one hand, distance to lens along a marked optical axis) — a new number is only comparable to those CSVs if that mount is held constant. Roaming retunes are valid but must be tagged as roaming, not mixed into the desk-stand series. **Discard any run where `ProcessInfo.thermalState` exceeds `.fair`** during the run, and note why. Full rig spec and per-gesture checklists: [`GESTURES.md`](GESTURES.md).
