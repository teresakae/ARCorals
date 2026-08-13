# DECISIONS — Coral AR Placement Experiment

ADR-style log. One entry per decision. All evidence traces to [`AR-hand-gesture-research.md`](../AR-hand-gesture-research.md) (dated 2026-08-07); citations name the specific source.

**Status vocabulary:** `Accepted` · `Accepted (revisit at Phase N)` · `Deferred` · `Rejected` · `Open` · `Superseded (in part)`

| # | Decision | Status |
|---|---|---|
| [001](#adr-001--native-swift-not-unity) | Native Swift, not Unity | Accepted |
| [002](#adr-002--arview-not-realityview) | `ARView`, not `RealityView` | Accepted |
| [003](#adr-003--2d-landmarks--raycast-not-3d-hand-reconstruction) | 2D landmarks + raycast, not 3D hand reconstruction | Accepted |
| [004](#adr-004--desk-stand-rig-not-a-cardboard-headset) | Desk stand rig, not a cardboard headset | Superseded in part — see [020](#adr-020--roaming-handheld-not-desk-stand) |
| [005](#adr-005--no-lidar--not-buying-a-pro) | No LiDAR — not buying a Pro | Accepted |
| [006](#adr-006--scale-invariant-pinch-ratio-not-a-fixed-pixel-threshold) | Scale-invariant pinch ratio, not a fixed threshold | Accepted (revisit at Phase 1) |
| [007](#adr-007--cube-before-coral) | Cube before coral | Accepted |
| [008](#adr-008--modern-detecthumanhandposerequest-not-the-legacy-vn-api) | Modern `DetectHumanHandPoseRequest`, not legacy `VN*` | Accepted |
| [009](#adr-009--phases-02-contain-no-arkit-and-are-throwaway) | Phases 0–2 contain no ARKit and are throwaway | Accepted |
| [010](#adr-010--yaw-not-z-rotation) | Yaw, not "Z rotation" | Accepted |
| [011](#adr-011--throttle-vision-to-1520hz-on-a-background-queue) | Throttle Vision to 15–20Hz on a background queue | Accepted |
| [012](#adr-012--raw-landmark-math-not-a-create-ml-classifier) | Raw landmark math, not a Create ML classifier | Accepted |
| [013](#adr-013--manipulationcomponent-is-visionos-only--do-not-build-on-it) | `ManipulationComponent` is visionOS-only | Accepted |
| [014](#adr-014--ar-glasses-over-usb-c--deferred-not-rejected) | AR glasses over USB-C — deferred, not rejected | Deferred |
| [015](#adr-015--pinch-ratio-calibrated-at-a-single-fixed-distance--cross-distance-stability-untested) | Pinch ratio calibrated at a single fixed distance — cross-distance stability untested | Accepted |
| [016](#adr-016--phase-3-plane-detection--touch-placement-passed-on-informal-verdict--no-rulermatrix-data-recorded) | Phase 3 (plane detection + touch placement) passed on informal verdict — no ruler/matrix data recorded | Accepted |
| [017](#adr-017--handprobe-pinchratio-threshold-adr-015-59-did-not-transfer-to-coralar--re-derived-to-198) | HandProbe pinchRatio threshold (ADR-015, 5.9) did not transfer to CoralAR — re-derived to 1.98 | Accepted |
| [018](#adr-018--mode-disambiguation-resolved--dominant-axis-lock-at-first-deadzone-crossing-implemented) | Mode disambiguation resolved — dominant-axis lock at first deadzone crossing, implemented | Accepted |
| [019](#adr-019--pick-up-and-move-multi-object-placement-and-real-object-selection--built-two-bugs-found-and-fixed-testing-them) | Pick up and move, multi-object placement, and real object selection — built, two bugs found and fixed testing them | Accepted |
| [020](#adr-020--roaming-handheld-not-desk-stand) | Roaming handheld use; desk-stand was calibration/de-risking only | Accepted |
| [021](#adr-021--bystander-hand-rejection-size--continuity-gate-not-chirality) | Bystander-hand rejection: size + continuity gate, not chirality | Accepted (revisit — thresholds uncalibrated) |
| [022](#adr-022--peer-to-peer-rooms-as-their-own-target-star-topology-and-a-protocol-seam-to-ar) | Peer-to-peer rooms as their own target; star topology; protocol seam to AR | Superseded in part — see [023](#adr-023--one-app-one-main-two-schemes) |
| [023](#adr-023--one-app-one-main-one-scheme-rooms-first) | One app, one `@main`, one scheme — rooms first | Accepted |

---

## ADR-001 — Native Swift, not Unity

**Date:** 2026-08-08 · **Status:** Accepted

**Context.** The default assumption for AR work is Unity + AR Foundation, on the theory that it abstracts platform detail and gives you hand tracking for free.

It does not. Unity's **XR Hands** package states plainly: *"Currently, the OpenXR package is the only plug-in provider that supports hand tracking."* ARKit's handheld-iOS plugin does not feed the XR Hands subsystem. Every reference to "ARKit hand tracking" in Unity's docs means **visionOS via PolySpatial**, not handheld iPhone. To get hand tracking in Unity on iPhone you would write your own native plugin wrapping the Vision hand pose request and marshal joint data across the interop boundary — i.e. **all the same native work, plus an interop layer.**

**Alternatives considered.**

| Option | Verdict |
|---|---|
| **Unity + AR Foundation + XR Hands** | Doesn't work on handheld iOS. OpenXR-only. Decisive |
| **Unity + ManoMotion** | The one real Unity option. Maintained (SDK v2.1.2, Feb 2026), 21-joint skeleton with x/y/z plus a normalized 0–1 relative depth, AR Foundation integration, free Lite tier. Its genuine value is **higher-level gesture classification out of the box** — the thing raw Vision doesn't give you. **But:** Nomtek measured it at **~70% accuracy in good light** and rejected it, and the company's messaging has visibly pivoted toward "Physical AI" / industrial safety with mobile AR now one product page among several. No shutdown evidence, but worth a licensing check before betting on it |
| **Godot** | No meaningful ARKit or hand-tracking story found. Non-option |
| **SceneKit** | Went into maintenance mode at WWDC25. Don't start anything there |

**Consequences.**
- No cross-platform path. Fine — the target is one device.
- Full access to `ARSession` / `ARFrame`, which the Vision feed requires and which an engine abstraction would fight.
- Everything above the landmark layer is bespoke. That was true in Unity too.
- ManoMotion stays in the back pocket **only** if we decide we want gesture *classification* rather than building it. That is not a Phase 0 escape hatch.

---

## ADR-002 — `ARView`, not `RealityView`

**Date:** 2026-08-08 · **Status:** Accepted

**Context.** RealityKit has two hosts. `RealityView` is cross-platform since iOS 18 and is Apple's stated direction — WWDC25 session 288: *"when using RealityKit, `RealityView` should be used in all cases."* Following that guidance would normally be automatic.

The research finds this **genuinely unresolved as of iOS 26, and Apple's own forum engineers acknowledge it.** `ARView` is **not deprecated.** `RealityView` still lacks AR-specific parity on iOS: no `debugOptions`, no `@Environment(\.realityKitScene)` outside visionOS, less flexibility generally. One forum participant's summary: *"a bit of an awkward state right now where you gotta pick and each option brings its own disadvantages."*

The deciding factor is that this app **needs direct `ARSession` / `ARFrame` access** to feed `frame.capturedImage` to Vision, plus `frame.displayTransform(for:viewportSize:)` for the coordinate conversion, plus `ARView.raycast(from:allowing:alignment:)`. The research's conclusion: *"For an iPhone-only app needing `ARSession`/`ARFrame` access — which yours does, for the Vision feed — `ARView` remains the pragmatic choice."*

**Alternatives considered.**
- **`RealityView`** — Apple's direction, but missing `debugOptions` (which we want for plane visualization during Phase 3) and awkward for the frame access this design is built on.
- **Abstract over both behind a protocol** — rejected. Speculative generality on a six-phase experiment.

**Consequences.**
- We're on the API Apple is steering away from. Accept it; `ARView` is not deprecated and this project has a defined end.
- We get `debugOptions` for plane visualization, which materially helps Phase 3.
- If this ever became a real product, this is the migration to budget for. It won't.
- ⚠️ **Do not let an agent "modernize" this to `RealityView`.** Recorded in [`AGENTS.md`](AGENTS.md) as an anti-suggestion.

---

## ADR-003 — 2D landmarks + raycast, not 3D hand reconstruction

**Date:** 2026-08-08 · **Status:** Accepted

**Context.** The original framing assumed Vision would give hand position in 3D. It does not — **Vision returns 21 landmarks in 2D image space only. No depth, no z.** The research calls this "the single fact everything else follows from."

The architectural insight that rescues the project: **all three mechanics are expressible in 2D + raycast.**

| Mechanic | Implementation | Needs hand depth? |
|---|---|---|
| Place | ARKit raycast from the 2D pinch point to the detected plane | No |
| Scale | Ratio of 2D pinch distance to a reference — scale-invariant if you use ratios | No |
| Yaw | 2D angle of the line between two fingertips → rotation angle | No |

**Alternatives considered.**

| Option | Verdict |
|---|---|
| **LiDAR `sceneDepth` fusion** | Not available. See ADR-005. This is the *only proven* Vision→3D-hand pipeline in the wild ([ogoguel/realtimehand](https://github.com/ogoguel/realtimehand), 262★, shipped in *Let's All Be Wizards!*) — **and we cannot copy that architecture** |
| **`estimatedDepthData` via `.personSegmentationWithDepth`** | The sleeper option, and genuinely interesting: ML-estimated (not LiDAR, not dual-camera), A12+ so A19 is fine, generated at full frame rate at reduced resolution, returns depth **only for person-segmented pixels** (Apple engineer, forum 654208) — and Apple states people occlusion works on hands and fingers alone with no full body needed (WWDC19 607). **Range behavior actively favors us:** documented degradation is *beyond* ~1.5–1.75m; hands at 30–60cm are in the good zone. **But:** real power/thermal cost on a device already running ARKit + RealityKit + Vision, mutually exclusive with `bodyDetection`, and **no shipped app found doing this on a non-LiDAR device.** Plausible but unproven. **Deferred, not rejected** |
| **Hand-size heuristics** | Apparent hand span in px + assumed physical width + `camera.intrinsics` → rough z. ±20–30% across users, breaks on truncation and rotation. Fallback only |

**Consequences.**
- **The hardest blocker is dissolved,** and risk #3 (no LiDAR) is mitigated by scope rather than hardware.
- The raycast **passes through the hand** and hits the plane behind it. This is the right tool for "place object under where I'm pointing" and the **wrong** tool for "where is my hand in 3D." Design accordingly — no reaching out and grabbing a floating object.
- Nothing in v1 knows the metric distance to the hand. Everything must be ratio- or angle-based.
- If a later version genuinely needs 3D hand position, `estimatedDepthData` is the first thing to try, not LiDAR.

---

## ADR-004 — Desk stand rig, not a cardboard headset

**Date:** 2026-08-08 · **Status:** Superseded in part — headset rejection still stands; **live use is roaming handheld (ADR-020).** Desk-stand remains the calibration condition for ADR-015/017.

**Context.** The original idea was the phone in a cardboard VR box as "your eyes," rear-camera passthrough. The research recommends against this in the strongest terms it uses anywhere, and calls it "the weakest part of the plan and the easiest to drop."

**Evidence against the box.**

- **No stereo is physically possible from one lens.** One optical center = no parallax data. Stewart Smith's build used **two phones, one camera per eye**, precisely because *"taking the single camera feed and presenting it to both of your eyes at once is perceptually confusing; you'd have a lack of depth perception."* Duplicating the image with a horizontal offset is a fake cue, not stereopsis.
- **Vergence-accommodation conflict.** Eyes verge to a stereo cue while focusing on a screen at fixed physical distance. Documented discomfort source.
- **Camera-eye parallax.** The rear camera sits ~10cm below and in front of your actual eyes. Karl Guttag documented that even Vision Pro — $3,500, purpose-built, eye-adjacent cameras — doesn't fully correct this: *"if you try to touch your nose looking at the displays you will hit below it."* Cardboard will be categorically worse. **This is fatal specifically for a hands-in-front-of-you manipulation task.**
- **Latency.** Vision Pro hits ~11–12ms passthrough with a dedicated pipeline; research suggests sub-5ms for imperceptibility. Generic ARKit camera-to-display latency on iPhone is **unmeasured in public sources** (loosest anchor found: ~150ms for Animoji-class pipelines). 100ms+ glass-to-glass head-worn is a known nausea trigger.
- **Thermals.** ARHeadsetKit's author hit iOS display throttling (60→30Hz) in minutes with an **unenclosed** phone. Sealed in cardboard, worse — and the throttling itself *made the motion sickness worse.*
- Stewart Smith's own summary: *"using it too much would very likely make you sick."*
- One hand is often occupied steadying the rig — leaving one hand for a gesture system that needs a hand.

**Alternatives considered.**

| Option | Verdict |
|---|---|
| **Desk/tripod stand, object on the phone's own screen** | **Chosen.** Sidesteps stereo, vergence, nausea, weight and thermals at once. Costs immersion. The research: *"Given that you said micro-display isn't a priority, this is arguably the correct default rig and the fastest path to answering your actual feasibility question"* |
| **Handheld phone** | Zero rig risk, works today, and is the fallback. But it reproduces exactly the ergonomic problem Nomtek named: *"the awkwardness of making gestures with one hand in front of a device that is held in another"* |
| **Chest/lanyard mount** | Phone chest harnesses are a mature *capture* accessory, but **no prior art found** for real-time AR hand tracking mirrored to a second screen. Genuinely under-explored — which also means nobody has proven it works |
| **Cardboard VR box** | **Rejected**, above |
| **AR glasses** | Deferred — ADR-014 |
| **Vision Pro** | Not a rig choice, a **platform pivot**. ADR-005 |

**Consequences.**
- **Zero immersion.** The coral is on a phone screen on a stand, not in your visual field. Accepted — immersion is not what's being tested.
- Detection geometry is *better* than the headset case: the camera looks down at hands on a table rather than out past a truncated wrist. This **may materially improve Phase 0's odds** versus the egocentric case the research flags as risk #1 — though the risk is not eliminated, because it's still not the third-person framing every Apple demo uses.
- Hands can **rest on the table**, which directly addresses the Purdue CHI'17 finding that arm support brings gesture fatigue near keyboard levels.
- No thermal enclosure problem.
- ⚠️ Do not design anything for a headset. No stereo rendering, no head tracking, no external display code.
- **Usage update (2026-08-12):** live use is roaming handheld — see ADR-020. This ADR's headset rejection and "phone screen is the display" still apply; the desk stand is no longer the described use case.

---

## ADR-005 — No LiDAR / not buying a Pro

**Date:** 2026-08-08 · **Status:** Accepted

**Context.** iPhone 17 base has **no LiDAR** — confirmed on Apple's own spec page; the sensor list is Face ID, barometer, gyro, accelerometer, proximity, ambient light. Only 12/13/14/15/16/**17 Pro & Pro Max** have it; iPhone Air and 17e are also excluded.

What we lose: `sceneReconstruction` / `ARMeshAnchor`, `sceneDepth` / `smoothedSceneDepth`, real object occlusion, and near-instant plane detection.

The research's direct recommendation: *"don't buy a Pro yet. Your iPhone 17 is enough to answer the feasibility question."*

**Alternatives considered.**
- **Buy an iPhone 17 Pro (~$1,100).** Would enable the realtimehand architecture — the only proven Vision→3D-hand pipeline. But **v1 uses no hand depth at all** (ADR-003), so LiDAR buys nothing v1 needs. It also would not fix a Phase 0 landmark-detection failure, because that failure is in the 2D model, not in depth.
- **Vision Pro (~$3,699 after the reported June 2026 price rise).** Everything hard here is a platform primitive there: `HandTrackingProvider` gives **27 joints per hand in 3D world space**, pinch is a **system gesture** the OS interprets so you often write no recognition logic at all, plus real depth, real occlusion, no camera-offset problem. But it is a **platform pivot, not a rig choice** — no iPhone camera involved, different product. And there's momentum risk: reports from spring 2026 indicate Apple significantly deprioritized Vision Pro after the M5 refresh underperformed, with next-gen development reportedly paused and no successor expected for 2+ years.

**Consequences.**
- Plane detection is via sparse visual feature points: a couple of seconds of deliberate panning before the first plane; coarse boundaries that drift, merge and split; and **a blank white, glossy, or dimly-lit table may never produce a plane at all.** An explicit "move your phone around to scan the surface" onboarding step is mandatory, not polish.
- **No real occlusion.** The coral renders over the hand. Known, accepted, recorded in [`AGENTS.md`](AGENTS.md).
- Gate any depth feature behind `supportsSceneReconstruction(.mesh)` / `supportsFrameSemantics(.sceneDepth)` — as a defensive log-and-bail, since there is no path behind those guards.
- ⚠️ **A Phase 0 failure is not authorized to trigger a hardware purchase.** It should produce a written result. See kill criteria in [`PRD.md`](PRD.md).

---

## ADR-006 — Scale-invariant pinch ratio, not a fixed pixel threshold

**Date:** 2026-08-08 · **Status:** Accepted (revisit at Phase 1)

**Decision.**

```swift
pinchRatio = dist(thumbTip, indexTip) / dist(wrist, middleMCP)
```

Thresholded, with ~100ms hysteresis. Denominator is swappable so Phase 1 can A/B three candidates on the same recorded data.

**Context.** Standard practice is Euclidean distance between `thumbTip` and `indexTip`, confidence-gated and thresholded. Real values found in the wild: **0.05 normalized distance** (multiple implementations), and **~3cm physical** with a noted noise band at 2.9–3.1cm requiring the reading to persist ~**100ms** before flipping state.

The problem the research calls out as a genuine gap: **raw 2D thumb–index distance shrinks and grows purely with how far the hand is from the camera, independent of whether you're actually pinching.** A fixed threshold works at exactly one working distance. Without LiDAR there is no depth to normalize against — so the normalization has to come from inside the image.

Critically: **"No iPhone-Vision-specific open-source project found solves this cleanly."** They either ignore it or sidestep it with LiDAR depth fusion. This is ranked **risk #2**, behind only egocentric accuracy, with the instruction to "budget real time for it."

The cleanest known pattern is from visionOS-land — [`DicyaninHandGesture`](https://github.com/hunterh37/DicyaninHandGesture) computes a scale-invariant deviation **normalized by hand span**, default threshold 0.15. The 2D equivalent is normalizing thumb–index pixel distance by a stable in-frame proxy for apparent hand size, recomputed every frame before thresholding.

**Alternatives considered.**

| Option | Verdict |
|---|---|
| Fixed normalized threshold (0.05) | Works at one distance only. Rejected as primary; useful as a baseline to beat in Phase 1 |
| Fixed physical threshold (~3cm) | Requires metric depth. Not available |
| **Denominator: `dist(wrist, middleMCP)`** | **Default.** One bone length, simple, tolerant of in-plane rotation. Risk: **depends on the wrist**, the joint most likely to be truncated at close range |
| **Denominator: 21-landmark bbox diagonal** | No single point of failure, degrades gracefully. But changes with *pose* as well as distance — closing the hand shrinks the box, which is the very signal we're isolating. Suspect this is the worst of the three |
| **Denominator: palm width across MCPs** | Nearly pose-invariant (MCPs barely move relative to each other) and **does not need the wrist**. Risk: smallest absolute distance ⇒ worst signal-to-noise from landmark jitter |
| LiDAR depth fusion | Not available |

**Consequences.**
- The threshold value is **unknown until Phase 1 measures it.** Every number in `GestureTuning` is a placeholder labelled as such.
- Phase 1 exists solely to produce this number and its noise band. It is not optional.
- **Recorded prediction:** if Phase 0 shows high wrist truncation, palm-width-across-MCPs wins. Written down now so Phase 1 tests a hypothesis rather than fishes.
- If no denominator produces non-overlapping distributions at a single distance, that is a **hard kill** — it means the 2D signal doesn't carry the information.
- Side benefit: because scale is driven by *delta* in `pinchRatio` since the gesture began, the same normalization makes the scale mechanic robust to mid-gesture hand drift.

---

## ADR-007 — Cube before coral

**Date:** 2026-08-08 · **Status:** Accepted

**Context.** The target asset is a coral model from Sketchfab, glb → usdz. A generated cube is the placeholder for every phase before the last.

**Alternatives considered.**
- **Use the real coral from Phase 3.** Rejected. Asset problems (wrong scale, off-center pivot, heavy geometry, material issues from the glb conversion) would be indistinguishable from placement, raycast or gesture problems. Every failure would need bisecting.
- **Use a textured cube.** Rejected. A plain untextured cube makes yaw hard to read — but that's what an asymmetric marker or debug axes are for, and those are cheaper than an asset pipeline.

**Consequences.**
- A cube's bounds and pivot are known exactly, so any misplacement is unambiguously a placement bug.
- Zero asset-pipeline work until Phase 6. glb→usdz conversion, licensing, and poly-count reduction are all deferred to one place.
- **Phase 6 is a real phase, not a formality.** The known risks it isolates: unexpected scale (coral arrives 40m tall or 4cm), off-center pivot (rotates around a point outside itself, which looks like a yaw bug), poly count dropping frame rate, and materials that survived the conversion badly.
- `ModelProvider` is the single file that changes. It should normalize bounds to a known size and report poly count.

---

## ADR-008 — Modern `DetectHumanHandPoseRequest`, not the legacy `VN*` API

**Date:** 2026-08-08 · **Status:** Accepted

**Context.** Two APIs coexist as of iOS 26: legacy `VNDetectHumanHandPoseRequest` → `VNHumanHandPoseObservation` (iOS 14+, still works), and modern `DetectHumanHandPoseRequest` → `HumanHandPoseObservation` (iOS 18+). The research says: **"Use this one."** Swift-only, async/await, `Sendable`, and it ships coordinate-conversion helpers (`NormalizedPoint.toImageCoordinates(from:imageSize:origin:)`) that remove the need to hand-roll the `1 - y` origin flip — which is coordinate gotcha #2.

**Consequences.**
- `Sendable` observations fit the background-queue architecture cleanly.
- One fewer place to get a sign wrong.
- Most sample code and blog posts online use the legacy API. Translating is easy; **their landmark constants are not trustworthy** — see below.
- ⚠️ **iOS 26 silently replaced the hand pose model.** WWDC25 session 272 @17:59: *"a smaller, modernized model... still detect 21 joints, but with improved accuracy, less memory usage, and less latency. Although the accuracy of the new model is improved, the joints are not in the same location as the previous model."* It shipped with **no new revision enum** — only `revision1` is exposed, so you cannot pin, A/B, or feature-detect the model version. Practical effect: any threshold constant copied from a pre-2025 source is measuring a different model. Measure our own.
- Most of the unverified items in the research (exact `VN*` deprecation annotations, ms benchmarks on A19) are moot for us — we're on the new API either way and will measure our own timings.

---

## ADR-009 — Phases 0–2 contain no ARKit, and are throwaway

**Date:** 2026-08-08 · **Status:** Accepted

**Context.** The six phases put all hand-tracking work (0–2) before any AR work (3), and keep them in separate apps until Phase 4. Phases 0–2 use a plain `AVCaptureSession`.

The reason is risk ordering. The research is unambiguous that **egocentric/close-range hand pose accuracy is risk #1, "completely unverified,"** with no Apple guidance, no benchmark, and no developer report for anything but third-person framing — and that the failure mode is binary (zero landmarks on truncation, not degraded landmarks). Its verdict: *"This is the #1 thing to test before writing any other code. It's cheap... Half a day of work de-risks the whole project."*

Every hour spent on ARKit before Phase 0 passes is an hour that might be worthless.

**Alternatives considered.**
- **Build the AR app first, add hands later.** Rejected — inverts the risk order.
- **Build one app throughout, with feature flags.** Rejected. The point of a throwaway is that it's throwaway; a shared target invites premature generalization and makes it emotionally expensive to delete.
- **Use `ARSession` in Phases 0–2 so the frame path is identical.** Rejected, but it's the closest call here, because it introduces a real seam (below).

**Consequences.**
- Phases 0–2 are cheap to delete, and are *meant* to be deleted. Do not refactor them for elegance or add tests.
- The gesture layer is developed against a simple camera feed, with fast iteration and no AR session lifecycle noise.
- Phase 3 independently proves plane detection works on the actual table and lighting, with pure touch input — so a Phase 4 failure is unambiguously about the *join*, not about either half.
- ⚠️ **The cost:** `ARFrame.capturedImage` is *always* native sensor orientation (landscape-right) and never rotates, whereas an `AVCaptureSession` buffer's orientation depends on connection configuration. **`CameraFeed` must be configured to match ARKit exactly**, or Phase 1's measured thresholds won't transfer. Mitigation: re-run an abbreviated Phase 1 sweep inside the AR app at Phase 4 and confirm the distributions match. Tracked as seam #2 in [`ARCHITECTURE.md`](ARCHITECTURE.md).

---

## ADR-010 — Yaw, not "Z rotation"

**Date:** 2026-08-08 · **Status:** Accepted

**Context.** The original brief said the gesture should control "Z rotation." In ARKit/RealityKit **Y is up and the ground is the X-Z plane.** Spinning an object like a lazy Susan on a table is rotation about **Y (yaw)**. Rotation about Z would tip the coral forward or backward.

**Decision.** The mechanic is yaw. The term "Z rotation" is retired from the project vocabulary.

```swift
entity.transform.rotation = simd_quatf(angle: yawRadians, axis: [0, 1, 0])
```

**Consequences.**
- `zRotation` must not appear in the codebase. Recorded in [`AGENTS.md`](AGENTS.md).
- Yaw is also what `installGestures`' `.rotation` recognizer produces (rotation about the surface normal), which makes it a valid reference implementation for the math — **though not a usable backend**, since those are `UIGestureRecognizer` subclasses wired to `UIView` touch delivery and cannot be fed hand-tracking deltas without subclassing.
- ⚠️ **Do not drive rotation with `move(to:duration:)`.** Quaternion slerp takes the short way around past 180°, so a small crossing produces a large visible snap in the wrong direction. Set `transform.rotation` directly per frame.

---

## ADR-011 — Throttle Vision to 15–20Hz on a background queue

**Date:** 2026-08-08 · **Status:** Accepted

**Context.** ARKit owns the camera; we consume its frames rather than opening a second capture session. Running the Vision request on every `ARFrame` on the session queue **will stall ARKit.**

The evidence cuts both ways. **For 60fps:** [ogoguel/realtimehand](https://github.com/ogoguel/realtimehand) (262★) runs the request synchronously per frame and shipped in the App Store app *Let's All Be Wizards!* — so it is possible. **Against:** ARHeadsetKit's author ran at 60fps, the phone got *"extremely warm in minutes,"* iOS throttled display refresh 60→30Hz, and he dropped to every 6th frame (~10Hz).

The research's own conclusion: *"gesture input doesn't need 60Hz. 15–20Hz inference with smoothing/hysteresis is plenty, and leaves ARKit's render loop untouched."* No published ms benchmark exists for the new iOS 26 model on A19, but with a smaller model on A19, inference cost is unlikely to be the bottleneck.

**Decision.** Serial background queue. Throttle to ~15–20Hz (`minInferenceInterval = 0.08s` ≈ 12.5Hz, or `frameCounter % N == 0` — either, as a named constant). `maximumHandCount = 1`. Drop frames rather than queue them. Release `ARFrame`s immediately.

**Consequences.**
- ARKit's render loop is untouched.
- We are not in a sealed cardboard enclosure, so the thermal picture is better than ARHeadsetKit's — but log `ProcessInfo.thermalState` anyway.
- ~15Hz means up to ~66ms of quantization on gesture onset. Combined with ~100ms hysteresis, that's within the 150ms latency budget in [`PRD.md`](PRD.md), but there is not much headroom. If latency feels bad, the throttle is the first knob.
- ⚠️ **Holding `ARFrame`s starves ARKit's buffer pool** and it starts dropping frames — which presents as bad tracking, not as a memory problem. `ARFrame` must never be stored in a property, array, or escaping closure.

---

## ADR-012 — Raw landmark math, not a Create ML classifier

**Date:** 2026-08-08 · **Status:** Accepted

**Context.** Apple's own trajectory pushes the other way: WWDC20 session 10653 introduced the raw landmark API, and **WWDC21 session 10039 pushed developers toward Create ML hand pose classifiers instead of raw landmark math.**

We're not taking that path, for three reasons.

1. **The vocabulary is one gesture.** Pinch. A classifier is overhead for a single binary signal that a distance ratio expresses directly.
2. **A classifier gives a label, not a magnitude.** Scale and yaw need continuous values — how open the pinch is, what angle the fingers make. That's the ratio and the angle, not a class.
3. ⚠️ **The iOS 26 model swap poisons pre-existing training.** Per WWDC25 session 272, the joints are in different locations than the previous model, and there is **no revision enum to pin against**. Any classifier trained pre-iOS-26 is silently miscalibrated. Training a fresh one is possible, but adds a data-collection burden to an experiment whose whole point is to move fast.

**Alternatives considered.** Create ML hand pose classifier (above); Create ML hand *action* classifier for temporal gestures (same objections, plus we want a state machine we can reason about, not a temporal black box); ManoMotion's built-in classification (ADR-001).

**Consequences.**
- Every threshold is explicit, inspectable, and tunable — which is exactly what Phases 1 and 2 need.
- No training data collection, no model file, no retraining when Apple swaps the model again.
- We hand-build the gesture lifecycle. Expected — the research notes Vision gives raw per-frame landmarks with no gesture lifecycle, and **most projects re-implement `UIGestureRecognizer`'s state machine (Possible → Began → Changed → Ended/Cancelled/Failed) by hand.**
- Design principles for that state machine come from Ken Pfeuffer's *Design Principles & Issues for Gaze and Pinch Interaction*: **minimalistic multimodal timing** (only one instant matters — thumb-index first contact; after that, commit to the drag regardless of what the signal does, explicitly to avoid Midas touch); **early/late triggers** (200–300ms of stable state before committing, echoing the 100ms hysteresis figure); **control-display ratio** (1:1 hand-to-object motion feels wrong at distance); and **drag & drop** — *"do not disengage a grabbed object if tracking is briefly lost mid-drag."* That last one is the grace period, and it is the fix for the flicker problem.

---

## ADR-013 — `ManipulationComponent` is visionOS-only — do not build on it

**Date:** 2026-08-08 · **Updated:** 2026-08-09 · **Status:** Accepted (resolved)

**Context.** `ManipulationComponent` (WWDC25, iOS/visionOS 26) is purpose-built for direct-manipulation pick-up / rotate / scale and auto-adds `CollisionComponent` + `InputTargetComponent` + `HoverEffectComponent`. If it works on iPhone, it is a **much more natural backend** than adapting touch gesture recognizers.

But: **all documentation describes it in visionOS hand-input terms, and the research could not confirm whether it is available on iOS.** It is listed under open questions as *"a 5-minute Xcode header check."*

**Decision.** Do not scaffold against it. Hand-rolled scale/yaw via `ManipulationTracker` + direct `transform.rotation` writes.

**Header check (2026-08-09, iPhoneOS 26.5 / XROS 26.5 SDK).** In `RealityFoundation.swiftinterface`:

```
@available(visionOS 26.0, *)
@available(macOS, unavailable)
@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(macCatalyst, unavailable)
public struct ManipulationComponent : RealityFoundation.Component
```

**Confirmed visionOS-only.** The type is present in the iOS SDK binary interface but marked `@available(iOS, unavailable)`. Phase 5 design is unchanged.

**Consequences.**
- Phase 5 assumes hand-rolled transform math, using `installGestures`' implementations as a math reference only.
- An agent must not generate `ManipulationComponent` code for this iPhone target. Recorded in [`AGENTS.md`](AGENTS.md).

---

## ADR-014 — AR glasses over USB-C — deferred, not rejected

**Date:** 2026-08-08 · **Status:** Deferred

**Context.** XREAL / VITURE / Rokid glasses are **optical see-through** — your real eyes see your real hands directly through the lens, with only graphics overlaid. That doesn't work around the passthrough problem; it **eliminates it entirely**, which makes it structurally better than the cardboard box (ADR-004).

All iPhone 15/16/17 support DisplayPort Alt Mode up to 4K60; VITURE explicitly sells iPhone USB-C packs and XREAL lists iPhone 17/16 support. And there's a finding worth acting on eventually: the vendor SDKs appear Unity/Android-centric, **but because the glasses register as a standard USB-C DisplayPort external display, a plain native Swift app can bypass the vendor SDK entirely** using Apple's `UIScreen` / `UIWindowScene` external-display APIs and render its own side-by-side stereo (these glasses commonly accept 3840×1080 SBS in 3D mode). Native Swift → true stereo glasses is plausible without Unity.

**Why deferred anyway.**
- **Cost**, on a project whose current hardware bill is zero.
- It's **a different architecture, not a rig swap**: the glasses have no cameras, so you still need a separate phone (desk or chest mounted) doing hand tracking, with the glasses as a HUD. "Phone IS your eyes" becomes "phone watches, glasses display." Arguably better — but it is a second system to build and debug.
- **It doesn't de-risk anything.** Phase 0's question — does hand detection survive this geometry — is identical either way. Glasses change only the display.

**Consequences.**
- Nothing in the codebase assumes an external display, stereo rendering, or head tracking.
- Revisit **only** if Phases 0–5 pass and the mechanic proves worth making immersive.
- If revisited, prototype the plain-`UIScreen`-bypass hypothesis before assuming a Unity lock-in.

---

## ADR-015 — Pinch ratio calibrated at a single fixed distance — cross-distance stability untested

**Date:** 2026-08-09 · **Status:** Accepted

**Context.** Phase 1 pinch calibration (TESTING.md Phase 1) specifies testing the pinchRatio threshold at three distances (30/50/70cm) to measure cross-distance drift, per the ±15% stability pass criterion. The actual working rig has the hand at a fixed, known distance from the camera (not variable), so cross-distance testing was deliberately skipped — only 40cm was captured and analyzed (phase1_b1/b2/b3/b4 CSVs, 2026-08-09).

**Decision.** Accept the single-distance calibration as sufficient for this project's fixed-distance rig. Threshold and hysteresis are calibrated for ~40cm only. Denominator choice: use palmWidth-across-MCPs (indexMCP↔littleMCP distance, `ratios.palmWidth` in PinchRatioCalculator.swift), not wristMCP — Phase 0 found wrist landmark confidence consistently weak (~0.5, highest truncation of any joint) across all tested distances, so it's a poor foundation for a ratio denominator even though single-distance separation looked comparable across all three candidates at 40cm (Cohen's d 2.5–2.8 for all three). Provisional threshold ≈5.9 (palmWidth ratio, midpoint of pinched/open means at 40cm from phase1_b1 data).

**Consequences.**
- The pinchRatio scale-invariance claim (that the ratio works across hand-to-camera distances) is unverified. If the rig's fixed distance ever changes, or a future version needs variable distance, this calibration must be redone with a real multi-distance sweep.
- Do not port this threshold to a different rig geometry without recalibrating.
- If revisited, follow the original TESTING.md Phase 1 protocol (30/50/70cm, 50 pinches each) properly, with the ground-truth toggle pressed by someone other than the hand being measured (self-toggling introduced label lag/tail contamination in the 40cm dataset).

---

## ADR-016 — Phase 3 (plane detection + touch placement) passed on informal verdict — no ruler/matrix data recorded

**Date:** 2026-08-09 · **Status:** Accepted

**Context.** docs/TESTING.md Phase 3 specifies four measured runs: Run A (10 cold starts, median time-to-first-plane ≤10s), Run B (10 physical markers, ruler-measured placement error, median ≤3cm), Run C (60s stationary + 60s-movement anchor drift check), Run D (surface matrix: bare/textured-mat/glossy/dim-light, pass/fail + timing per surface). Testing on 2026-08-09 covered these qualitatively rather than with the specified instrumentation: plane appeared quickly on non-glossy surfaces; placement looked accurate and stable with no drift after 60s on .existingPlaneGeometry; ceramic floor and patterned bedsheets failed to produce .existingPlaneGeometry but succeeded via .existingPlaneInfinite fallback (acceptable per pass criteria, same tier as .existingPlaneGeometry for the ≥80% raycast-tier threshold); no .estimatedPlane reliance observed. No ruler measurements were taken (Run B), no formal 10-cold-start timing (Run A), and Run D's dim-light condition was not tested.

**Decision.** Accept Phase 3 as passed based on this informal/visual verification. Proceed to Phase 4 (pinch replaces tap) without the missing ruler/timing data.

**Consequences.**
- Phase 3's exact placement-accuracy number (≤3cm target) is unverified — if placement feels visually "close enough" but is actually off by more, this won't surface until it's confusing to debug inside Phase 4's added complexity (hand tracking + AR running together).
- Dim-light surface behavior is untested; if a real-use lighting condition trends dark, plane detection reliability there is unknown.
- If placement accuracy becomes suspect at any later phase, come back and run Phase 3 Run B (ruler measurements) in isolation before assuming the bug is downstream.

---

## ADR-017 — HandProbe pinchRatio threshold (ADR-015, 5.9) did not transfer to CoralAR — re-derived to 1.98

**Date:** 2026-08-09 · **Status:** Accepted

**Context.** TESTING.md Phase 4 Run B (re-run an abbreviated Phase 1 sweep inside the AR app) was performed 2026-08-09, logging 759 labeled calibration rows (428 open, 331 pinched) to phase4_join_20260809_174233.csv, comparing CoralAR's `ARFrame.capturedImage`-sourced pinchRatio (palmWidth denominator) against the HandProbe/ADR-015 baseline (AVCaptureSession-sourced, threshold 5.9, calibrated at ~40cm).

Result: the whole distribution shifted down ~46-47% versus HandProbe (pinched mean 1.527→0.823, open mean 10.301→5.490) — consistent with ARFrame's 4:3 buffer vs AVCaptureSession's 16:9 producing different distance scaling in Vision's normalized coordinate space, the exact seam-#2 risk ARCHITECTURE.md flagged. This is far outside the ±10% transfer tolerance in TESTING.md's Phase 4 pass criteria. At the old threshold (5.9, enter at 5.4), 58.9% of open-hand frames read below the pinch-enter threshold — meaning an open hand would falsely trigger "pinch began" more than half the time. This was reported by the user as observed behavior: the cube sometimes places itself while the hand is open, not pinched.

Separation quality also degraded, not just shifted: Cohen's d dropped from 2.5–2.8 (HandProbe) to 1.55 (CoralAR), and the open-hand group's standard deviation is unusually high (≈73% of its own mean, vs a much tighter HandProbe hold) — likely because this calibration run was live/dynamic self-toggled labeling during normal hand movement, not an isolated static hold like HandProbe's b2/b3 blocks.

**Decision.** Mark the HandProbe/ADR-015 threshold (5.9) superseded for CoralAR. Re-derive pinchThreshold to 1.98 (midpoint of pinched-95th-percentile and open-5th-percentile from the calibration CSV) in CoralAR/Gesture/GestureTuning.swift. hysteresisBand left at 1.0 (unchanged) but marked provisional in the code comment — not re-derived from a clean static hold, carried over from ADR-015 as a placeholder. At the new threshold, the false-pinch rate on open-hand frames drops from 58.9% to 7.0% (still non-trivial, mitigated in practice by the 100ms hysteresisDuration requiring sustained readings, but not fully resolved).

**Consequences.**
- CoralAR and HandProbe now have independently calibrated thresholds; do not assume they should match, and do not port HandProbe threshold changes into CoralAR (or vice versa) without re-verifying on the actual buffer source.
- The residual 7% false-pinch rate at the new threshold means occasional spurious placements while the hand is open are still possible, especially during fast hand movement — this is a plausible explanation if that behavior is still observed after this fix.
- hysteresisBand is unverified — before trusting gesture reliability further, run a real static-hold calibration (mirroring HandProbe's b2/b3: ~10s held pinch, ~10s held open, no self-toggle lag) inside CoralAR and re-derive the band from actual noise, not carried-over HandProbe assumptions.
- Any future seam changes (different ARFrame resolution, different camera preset, portrait→landscape orientation change) should treat the pinchRatio threshold as unverified again until re-checked, per this ADR's evidence that buffer-source changes measurably shift the distribution.

**Addendum (2026-08-09, same day).** Re-verified with a proper static hold (phase4_join_20260809_180023.csv: one continuous 12.5s open block, one continuous 12.4s pinched block, no self-toggling mid-hold, per this ADR's own recommendation). Result: false-pinch rate at the 1.98 threshold is 0.0% (n=189 open frames), missed-pinch rate 4.3% (n=188 pinched frames, driven by a handful of single-frame tracking-glitch outliers up to ratio 63.7 that don't survive the 100ms hysteresis in practice — median pinched ratio 0.604 is a more representative center than the outlier-skewed mean of 1.607). Threshold and hysteresisBand confirmed as-is, no further change needed. The hysteresisBand-unverified caveat above is now resolved.

---

## ADR-018 — Mode disambiguation resolved — dominant-axis lock at first deadzone crossing, implemented

**Date:** 2026-08-09 · **Status:** Accepted

**Context.** Phase 5 (docs/STEPS.md, Prompt 9 in docs/PROMPTS.md) needed to resolve the open design question in PRD.md §6 / ARCHITECTURE.md §4: how to disambiguate scale vs yaw intent during a single continuous pinch hold. A prior review (recorded as the basis for the updated Prompt 9) selected dominant-axis lock at first deadzone crossing over two alternatives (per-frame dominant-axis — rejected for jitter given ADR-017's documented noise; separate gestures — rejected as requiring fresh calibration work for a second finger pair, and barred for two-hand approaches by maximumHandCount=1). This ADR records the as-built implementation and its deviations from the plan.

Also resolves ADR-013 (ManipulationComponent status): confirmed in the iOS 26.5 SDK, `ManipulationComponent` is `@available(visionOS 26.0, *)` / `@available(iOS, unavailable)` — visionOS-only, not available on iOS. The hand-rolled ManipulationTracker approach was the only option; ADR-013 is now closed, not just deferred.

Implementation shipped: mode-lock manipulation (CoralAR/Gesture/ManipulationTracker.swift, CoralAR/Gesture/YawAngleCalculator.swift), HUD mode indicator (—/SCALE/YAW), Phase 5 CSV logging, collision shape regeneration on scale-gesture end, direct per-frame yaw writes (not move(to:duration:)). All 10 new unit tests pass. CoralAR builds clean.

Deviations from the Prompt 9 plan:
- ManipulationTracker came out to ~180 lines, not the estimated ~60 — baseline-median computation, angle unwrapping, lock rebase logic, and result packing accounted for the difference. Not a scope problem, just an estimate miss.
- YawAngleCalculator and ManipulationTracker are shared into HandProbe via project.yml (not duplicated as a separate HandProbe copy) so HandProbeTests can import and test them directly.
- Tie-break rule for the rare case both scaleProgress and yawProgress cross 1.0 in the same frame: higher progress value wins; if exactly equal, scale wins by default.
- CSV format: Phase 4 columns kept as-is, Phase 5 fields appended (including the palm-axis yaw candidate column, yaw_palm_axis). File prefix is phase5_manip_ (not phase4_join_, since this is genuinely new logging, not a continuation). No separate elapsed_ms column was added — seconds_since_start (already present) is used instead.
- Scope-narrowed from the original prompt: only the first pinch in a session places a new object; subsequent pinches manipulate the existing one. A single continuous gesture that starts as a placement and transitions into manipulation within the same hold was not implemented — placement and manipulation are on separate pinch holds, not unified into one gesture lifecycle.
- Primary yaw control signal is thumb→index (as specified); the palm-axis (indexMCP→littleMCP) candidate is logged for comparison per the plan, but is not used as a fallback or blended in — it's data collection only at this point, no automatic source-switching logic was built.

**Decision.** Accept the implementation as-built, including the above deviations — none of them contradict the design intent, they're implementation details the plan didn't fully specify. Proceed to device testing (TESTING.md Phase 5 Runs A-F: scale targeting, yaw targeting, mode cross-talk, slerp check, collision-after-scale, control-feel/sensitivity tuning) before considering Phase 5 closed.

**Consequences.**
- The tie-break rule (higher-progress-wins, scale-wins-on-exact-tie) is untested against real device noise — if cross-talk (Run C) comes in high, this is one of the first things to revisit, since a bad tie-break could be silently flipping mode on borderline frames.
- The lack of same-gesture place→manipulate means the UX has an implicit two-step model (place, release, re-grab to manipulate) that wasn't explicitly decided as a UX choice — worth confirming this is actually the intended interaction before Phase 6, not just an implementation shortcut.
- yaw_palm_axis is being logged but nothing reads it yet — if Run B (yaw targeting) shows the thumb-index signal is noisy or unreliable, the palm-axis data is already being collected and can be analyzed retroactively without a new test run.
- scaleDeadzoneLog, yawDeadzoneRad, scaleSensitivity, yawSensitivity, and scaleModeExitThreshold are all still the provisional values from the Prompt 9 plan (0.22, 0.21, 1.0, 1.0, 3.5) — Run F is what's supposed to set their real values, not yet done.

---

## ADR-019 — Pick up and move, multi-object placement, and real object selection — built, two bugs found and fixed testing them

**Date:** 2026-08-10 · **Status:** Accepted

**Context.** Prompt 11 (docs/PROMPTS.md) was built: pick-up-and-move, triggered by which HUD demo mode is selected (Place/Adjust/Move), not by racing signals — Adjust's existing scale/yaw mode-lock (ADR-018) got zero changes, Move reads only the pinch point's raycast hit, absolute-from-grab. Multi-object placement followed (Place mode now adds objects instead of replacing — supersedes the "exactly one entity" non-goal in PRD.md, which was updated to reflect this). Real spatial selection followed that (SceneController.selectModel(at:) hit-tests the pinch point against every placed entity's CollisionComponent via ARView.entity(at:), replacing an interim "most-recently-touched" placeholder rule).

On-device testing after all three landed surfaced two real bugs, both found and fixed same day:

Bug 1 — objects jumping/floating after being placed, and drifting when the camera moved. Root cause was actually two separate things. First: reanchorModel() (added for Move, meant to swap the object onto a fresh anchor at move-end) called removeFromParent() without preserving world transform, then "preserved" the now-wrong transform onto the new anchor — this doubled every drag on release and added ~2.5cm of height on every single grab-release even with zero movement. Its own justification ("keeps the anchor tied to the tracked plane") was false — the original placement anchor (AnchorEntity(world:)) was never plane-relative to begin with, so the swap bought nothing. Deleted entirely rather than patched; moveModel() already converts through whatever the current parent is regardless of offset, so re-anchoring was never actually necessary. Second, separate cause of "moves with the camera": the HUD's "Adjust" button didn't actually force adjust mode — it fell through to a timing-based auto-decision (moveOrAdjustTrigger, keyed on regrabWindow) that returns Move whenever there's no recent prior gesture, which in practice was every deliberate grab. So users selecting "Adjust" were silently placed in Move the whole time, and Move correctly tracks the raycast hit under a screen point — so panning the camera while holding a grab looked exactly like broken anchoring, when the anchoring itself was fine.

Bug 2 — cubes not sitting flush on the surface. Separate and pre-existing, not caused by the Move/multi-object work. Two causes: (a) place() built the anchor from the raycast's full worldTransform including the hit plane's orientation, and on the .estimatedPlane raycast tier that normal can be an off-vertical guess, tilting the whole anchor; (b) the fixed 2.5cm base-lift offset didn't account for scale growing the box from its center, so scaling up sank the cube through the table and scaling down floated it.

Also fixed in the same pass: modelYaw was a single global field that leaked rotation state between objects (grabbing object B reused object A's stored yaw as its baseline) — now decoded per-object from each model's own transform, since every yaw write is a pure world-Y rotation (AGENTS.md) and is exactly invertible. And a nil-Vision-frame edge case that could leave a gesture's state machine stuck active (unable to time out via the grace period) was fixed so dropped frames properly feed an empty observation instead of early-returning past the state machine entirely.

**Decision.** 
1. All three HUD demo modes (Place/Adjust/Move) are now hard overrides — whichever is selected is the only thing that decides what a pinch does. No timing-based auto-switch runs on the live path anymore. The timing-based design (moveOrAdjustTrigger, regrabWindow, MoveTriggerTests) stays in the codebase unused — still considered the right shape for a future experience with no mode toggle, but calibrating regrabWindow against real device data is deferred until that experience actually gets built.
2. reanchorModel() is deleted, not fixed — the anchor-follows-the-object design it implemented was unnecessary in the first place.
3. Placement anchors are now position-only (identity rotation), gravity-aligned by construction regardless of raycast tier.
4. Scale compensates vertically for the object's own growth so its base stays put through any scale change.

**Consequences.**
- Automatic (no-toggle) Move-vs-Adjust disambiguation is explicitly unsolved and deferred — if a future build needs gesture-only mode switching without a HUD control, moveOrAdjustTrigger/regrabWindow need real on-device interval data before they can be trusted, per the same caveat ADR-018's follow-ups already established for other provisional constants this project has shipped.
- Multi-object selection has no fallback for a pinch that lands on nothing placed (no grab happens) — documented as deliberate (avoids a new uncalibrated distance threshold) but worth revisiting if missed grabs turn out to be common in practice.
- The reanchorModel() deletion means a placed object can sit at an arbitrarily large offset from its original anchor indefinitely after being moved — confirmed harmless (moveModel() converts through the current parent regardless of offset) but worth knowing if a future feature ever assumes anchor-proximity.
- Full day-to-day status of every gesture (not just this ADR's) lives in docs/GESTURE_LOG.md, which is the doc to check before testing, not this ADR.

---

## ADR-020 — Roaming handheld, not desk-stand

**Date:** 2026-08-12 · **Status:** Accepted

**Context.** ADR-004 chose a desk/tripod stand over a cardboard headset so Phase 0–5 could answer feasibility without stereo, nausea, or enclosure thermals. That was the right de-risking rig. Live use is not that rig: the user **walks with the phone** (roaming handheld) — one hand holds it, the other gestures in the rear-camera view, object on the phone screen. The app already works that way; there is no code fork.

ADR-004 listed handheld as the fallback and cited Nomtek's ergonomic awkwardness ("gestures with one hand in front of a device that is held in another"). That awkwardness is now the actual product geometry, and it is viable enough to keep.

**Decision.**
1. **Live use = roaming handheld.** Docs (README, PROJECT, AGENTS, GESTURES) describe that, not the desk stand.
2. **Headset rejection from ADR-004 still stands.** No cardboard box, no stereo, no external display, no head-tracking assumptions.
3. **Desk/tripod stand stays the calibration condition** for ADR-015/017 and any number that must be comparable to those CSVs. Roaming retunes are valid only if tagged as roaming — do not mix series.
4. **No code change.** Same binary. Orientation stays hardcoded `.right`. Thresholds stay as shipped until a roaming CSV says otherwise.

**Consequences.**
- Pinch threshold 1.98 and wave `waveProximityRadiusPt` 220pt were measured/tuned at a fixed desk distance. Roaming varies working distance; cross-distance stability (already open in ADR-015) is now the live risk, not a hypothetical.
- Purdue arm-fatigue mitigation (free hand resting on the table) does not apply while roaming. Expected, not a tracking bug.
- Do not "fix" the app back onto a stand. Do not add a second capture path or orientation-from-`UIDevice` because the user is walking.

---

## ADR-021 — Bystander-hand rejection: size + continuity gate, not chirality

**Date:** 2026-08-12 · **Status:** Accepted (revisit — thresholds uncalibrated)

**Context.** Roaming handheld use (ADR-020) puts the rear camera in public/shared spaces where a hand that isn't the user's can enter frame. `HandPoseDetector` requests `maximumHandCount = 1` and Vision hands back at most one `HumanHandPoseObservation`. Per Apple's own account of the underlying selection (WWDC20 session 10653), when the requested count is below what's detected, Vision keeps **the largest hand(s) in frame** — there is no documented confidence-based ranking (`observation.confidence` is reported to sit near 1.0 regardless), no ordering guarantee on the array, and no `boundingBox` property (must be derived from joint extents, which `handCoveragePct()` already does). Net effect: a bystander's hand that is bigger or closer to the lens than the user's own **silently replaces it** before any app code runs — nothing today rejects that swap.

`chirality` was considered as a filter and rejected: no `boundingBox`-equivalent reliability data exists for handheld rear-camera egocentric framing specifically, and multiple dev reports describe it flipping/misreporting due to image mirroring, independent of the project's own use case. Not a usable signal here.

No Apple API and no third-party prior art (checked: WWDC 2020/2021/2024 sessions, Vision docs, dev-forum and blog write-ups) implements bystander-vs-owner hand disambiguation by position or cross-frame identity — `DetectHumanHandPoseRequest` has no persistent hand ID. This is DIY territory with no reference implementation to copy.

**Decision.**
1. **Size gate.** Reject a frame (route it through the existing nil-frame/no-hand path, same grace/timeout handling already in place) if `handCoveragePct()` falls outside `tuning.handCoverageMin...handCoverageMax`. Catches a bystander's hand looming large near the lens, and a bystander hand small in the background.
2. **Continuity gate.** Track the last accepted hand's centroid (mean of confidence-gated joints, normalized coords). Reject a frame if the new centroid jumps further than `tuning.handJumpRejectRadius` in one frame — a same-hand frame-to-frame move should be small at 15–20Hz (ADR-011); a large jump is more likely Vision having switched which hand it's reporting.
3. **No chirality filter, no `maximumHandCount` bump.** Raising the count to compare two candidates ourselves would cost latency (Apple: pose is generated per detected hand, "will have a latency impact") for a ranking signal Vision doesn't document either — not worth it unless the two gates above prove insufficient in practice.
4. **Thresholds are placeholders**, not measured: `handCoverageMin = 0.5`, `handCoverageMax = 60.0`, `handJumpRejectRadius = 0.35`. Same status as this file's other un-derived constants (`regrabWindow`, `waveMinReversals`, etc.) — needs a real measurement pass, ideally against an actual second-hand-in-frame test, before trusting it in the field.

**Consequences.**
- A fast, large motion of the user's *own* hand (e.g. a big reach) can trip the continuity gate and get treated as "no hand" for a frame — same failure mode as any other single-frame gate, recoverable next frame since the gate re-locks on the first accepted centroid.
- Gate lives entirely in `handleVision()` (`ARSessionCoordinator.swift`) — no new files, no new dependency, reuses `handCoveragePct()`.
- Still no true depth/distance measurement (ADR-003 stands) — "size" here means apparent size in the 2D frame, same caveat as everywhere else in this project.

---

## ADR-022 — Peer-to-peer rooms as their own target, star topology, and a protocol seam to AR

**Date:** 2026-08-13 · **Status:** Superseded in part by [ADR-023](#adr-023--one-app-one-main-two-schemes) — **decision 1 (separate target) no longer holds.** Decisions 2–5 stand unchanged.

**Context.** Local multiplayer rooms (4-digit code, max 4 players, one host, home → lobby → in-session) needed building, with AR joining later. The hard requirement was that the networking layer must not know AR exists — no `ARKit` or `RealityKit` under `Networking/` — so that dropping AR in later touches nothing below the room layer.

**Decision.**

1. **A third app target, `CoralRooms`,** rather than folders inside `CoralAR`. `CoralAR` is already a full AR app whose `@main` starts an `ARSession`; adding the room screens there would have meant editing AR code (out of scope) and would have made two-instance Simulator verification impossible, since `ARWorldTrackingConfiguration` has no camera there. A separate target makes "the room layer does not depend on AR" mechanically true instead of a convention someone has to remember. Layout mirrors `CoralAR/`: `Networking/`, `Model/`, `Views/`, plus the app entry at the root.

2. **Star topology, not broadcast.** Two guests that both joined the host's `MCSession` are not guaranteed to be connected to each other. Guests transmit only to the host; the host re-sends to everyone but the original sender. A naive send-to-all-connected-peers looks correct at two players and silently drops traffic at three or four.

3. **Reliability encoded in the packet's tag byte.** Frame layout is `[tag][originLength][origin][body]`. The host relays a guest's frame byte-for-byte, so it needs the author's delivery guarantee out of the frame itself rather than from per-sender state it has no business owning. `origin` is in the frame for the same reason: `MCSession` reports the peer it received *from*, which for a relayed packet is the host, not the author.

4. **`ARPayloadChannel` is declared with no conformer.** `RoomSession` holds a `weak var arChannel` and routes opaque `Data` through it in both directions; outbound recipients are chosen by the room layer, so the star topology never leaks into AR code. `CoralAR` adopts it later with zero changes under `Networking/`.

5. **Occupancy rides in `discoveryInfo` alongside the room code.** A declined invitation is delivered as nothing at all — no callback, no error — so a full room would otherwise be indistinguishable from a wrong code until the join timed out. Publishing the player count lets the guest report "full" immediately; the host still declines invites, and still sends a `.roomFull` control message for the race where two invitations are accepted before either connection lands.

**Consequences.**

- Discovery state (advertising / browsing / rooms seen / matching code) is surfaced on-screen. A denied Local Network permission on a real device fails silently and permanently, and the Simulator inherits the Mac's grant and never prompts — these counters are the only evidence available. **This has not been exercised on a real device.**
- Every room gets a fresh `PeerTransport`: a disconnected `MCSession` is not documented as reusable. The peer-name suffix therefore changes per room, which is fine because roster identity is per-room.
- `NSBonjourServices` must list both `_coral-rooms._tcp` and `_coral-rooms._udp`, which has no `INFOPLIST_KEY_` equivalent — hence a hand-written `Info.plist` for this target only, generated from `project.yml`.
- The UI is a deliberate lo-fi wireframe: stock `Form`/`List`/`Section`, semantic colours, default spacing, no custom styles. It is placeholder work and is expected to be replaced.

---

## ADR-023 — One app, one `@main`, one scheme — rooms first

**Date:** 2026-08-13 · **Status:** Accepted · **Supersedes:** [ADR-022](#adr-022--peer-to-peer-rooms-as-their-own-target-star-topology-and-a-protocol-seam-to-ar) decision 1

**Context.** ADR-022 put the room layer in its own app target so that "the room layer does not depend on AR" was enforced by the target boundary. That worked for building and verifying rooms in isolation, but it left two installable apps and two `@main` entry points and no way to run the actual product — rooms leading into AR.

**Decision.** One app target, `CoralAR`, keeping bundle id `com.ada.ch5b.CoralAR`, one scheme, the stock `Debug`/`Release` configurations. `CoralRooms` is deleted and its sources move to top-level `Networking/`, `Model/` and `Views/`, with `CoralARApp.swift` and `Info.plist` at the repo root. `CoralARApp` is the only `@main`.

The app **always starts on the room flow**: Home → Lobby → Session, and AR is entered from the session screen. A single `private let startInARDirectly = false` on `CoralARApp` skips straight to AR when flipped — a development shortcut, one line, no build configuration behind it.

**Alternatives considered.**

| Option | Verdict |
|---|---|
| Two targets sharing one `@main` | Still two installable apps on the home screen, which is the thing being removed |
| Extra build configurations defining an `AR_ONLY` compilation condition, selected by a second scheme | Built, then reverted. It worked, but four configurations and two schemes is a lot of project machinery for "which screen opens first" — the cost is paid by every future reader of `project.yml`, not just the person who wanted the shortcut |
| Runtime toggle on the Home screen | Debug affordance shipping in the product |

**Consequences.**

- **The layering rule is no longer enforced by the compiler.** `Networking/` importing `ARKit` would now compile. It is enforced by folder discipline and a grep instead — that grep belongs in the checks for any change here. The rule currently holds: nothing under `Networking/` imports `ARKit`, `RealityKit`, `Vision` or `SceneKit`.
- **The app is landscape-only**, unchanged from the AR-only build. The room screens are stock `Form`s and render sideways without breaking, but they are cramped. Letting the app rotate would change AR's orientation assumptions (see the coordinate gotchas in [`AGENTS.md`](AGENTS.md)), which is out of scope here — flip `UISupportedInterfaceOrientations` in `project.yml` if the room screens turn out to matter more.
- `ARSessionCoordinator` is created by `ARRootView`, not at launch, so no camera and no world tracking until the player enters AR from the session screen.
- `Info.plist` is a checked-in file rather than `GENERATE_INFOPLIST_FILE`, unlike `HandProbe`. Forced, not chosen: `NSBonjourServices` is an array and no `INFOPLIST_KEY_NSBonjourServices` exists in Xcode 26.6. Its contents are generated from `project.yml`.
- The AR seam is still unwired: `RoomSession.arChannel` is `nil`, nothing conforms to `ARPayloadChannel`, and entering AR from a room gives every player their own independent scene. Multiplayer AR state sync is the next piece of work, and it needs no change under `Networking/`.
