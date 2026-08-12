# PROJECT — Coral AR Placement Experiment

**Type:** de-risking experiment, not a product.
**See also:** [`DECISIONS.md`](DECISIONS.md) (why, ADR log) · [`ARCHITECTURE.md`](ARCHITECTURE.md) (how, module/data-flow) · [`GESTURES.md`](GESTURES.md) (per-gesture status, tuning constants, provenance, device checklists) · [`AGENTS.md`](AGENTS.md) (coding rules/traps for AI agents).

## 1. What this is

**Use is roaming handheld:** the user walks with the phone; the **rear camera** watches the free hand; hand gestures place, scale, yaw-rotate, and carry a 3D object on a real detected horizontal plane, rendered on the phone's own screen. Early de-risking and pinch calibration used a desk/tripod stand (ADR-004); that is not the live use case. The same app works as-is while roaming — no code fork (ADR-020). Device: iPhone 17 base, no LiDAR, iOS 26. Native Swift — ARKit + RealityKit via `ARView` + Vision `DetectHumanHandPoseRequest`. All hand input is 2D landmarks + an ARKit raycast; there is no hand depth (ADR-003).

The deliverable was never an app — it's a defensible yes/no on "does camera-based hand-gesture manipulation of AR objects work well enough to build on, on hardware already owned?" **The answer is yes, empirically**, for the mechanics built so far. No maintained open-source project was found doing this, and the two closest precedents both abandoned hand gestures and retreated (§8). This project re-ran that experiment deliberately, with tighter scope, because two of their three failure causes — LiDAR-dependent depth fusion, headset thermals/nausea — were designed out from the start (ADR-003, ADR-004).

## 2. Problem statement

Placing and manipulating AR objects on iPhone today means touching the screen — that works, and Nomtek shipped exactly that after evaluating everything else (§8), but one hand then holds the phone and the other pokes glass. The question: can the 2D hand landmarks Vision already gives us, plus an ARKit raycast, drive place/scale/yaw/carry well enough to feel like manipulation rather than fighting the machine, on a non-LiDAR iPhone, **while roaming** — one hand holding the phone, the other gesturing in the rear-camera view? (Nomtek named that ergonomic awkwardness and retreated to touch; this experiment keeps the gestures. Desk-stand was the original de-risking rig, not the use case — ADR-004 / ADR-020.)

## 3. The three questions this answered

1. **Does hand detection survive the camera geometry?** The failure mode of this model class is binary — zero landmarks, not degraded ones, on wrist truncation or palm occlusion. **Confirmed viable** first on the desk-stand de-risking rig (camera looks down at hands on a table — a better case than egocentric/headset framing; ADR-004), then **confirmed again while roaming** with the same binary, no code change (ADR-020).
2. **Can pinch be detected reliably without a fixed pixel threshold?** Raw 2D thumb–index distance scales with distance-to-camera; no iPhone-Vision project had solved this cleanly. **Confirmed viable** with a scale-invariant `pinchRatio` (ADR-006), recalibrated when it didn't transfer as-is from the throwaway prototype into the real app (ADR-017), then verified at 0% false-pinch / ~4% missed-pinch on a clean static hold (ADR-017 addendum).
3. **Does ARKit's world tracking hold up when hands fill the frame?** **Confirmed viable** — no VIO drift was found; what initially looked like anchor drift in testing turned out to be a mode-selection bug (Move vs. Adjust), not tracking (ADR-019).

## 4. Being tested / not being tested

| Being tested | Not being tested |
|---|---|
| Hand landmark availability while roaming (free hand in rear-camera view, phone handheld) | Anything head-/chest-mounted or headset-based |
| Whether a scale-invariant pinch ratio produces a separable threshold | Metric 3D hand position, `estimatedDepthData`, hand-size depth heuristics |
| Gesture lifecycle robustness (hysteresis, grace period, dropped frames) | Gesture classification beyond geometric pinch/dwell/wave (no Create ML) |
| Plane detection viability on the actual table, without LiDAR | Plane detection across arbitrary surfaces/lighting |
| Place / scale / yaw / carry as distinct, learnable mechanics | Whether a real coral `.usdz` behaves like the cube (untested — Phase 6 never built) |
| Whether ARKit VIO degrades with hands in frame | Content: dirt, pests, quiz, real coral annotations (not started) |

One-hand only: `maximumHandCount = 1`. Two-handed gestures are not in scope.

## 5. Non-goals

Still true: multiplayer/shared sessions, persistence across relaunch, headset/VR-box/AR-glasses rigs (ADR-004, ADR-014), App Store shipping polish, real occlusion of the object by the hand (LiDAR-only, ADR-005), two-handed gestures, metric hand depth, Create ML gesture classifiers (ADR-012), and robustness across arbitrary surfaces/lighting (some real surfaces still fail plane detection, ADR-016).

**No longer non-goals — since built:** multi-object placement, and picking up/moving an already-placed object (the "Carry" gesture). Both were explicitly out of scope in the original PRD and were built as part of the gesture build track (ADR-019).

## 6. Status

- **Phases 0–5 (original plan): complete and verified.** Detection viability, pinch calibration, gesture state machine, ARKit plane detection, pinch-replaces-tap, scale + yaw all passed.
- **Phase 6 (swap the cube for a real `coral.usdz`): never built.** No `.usdz` exists in the repo; `ModelProvider` still generates a cube. Anything describing Phase 6 as done is wrong.
- **Gesture build track (built on the cube prototype):** Point (dwell → annotation), Carry (pinch-toggle pick up/place), Rotate (re-grab yaw), Wave (proximity-gated brush). Has had a calibration/provenance pass; an on-device verification checklist is still outstanding — see [`GESTURES.md`](GESTURES.md) for current per-gesture state and tuning values, not here.
- **Content layer** (dirt, pests, quiz, real coral annotations): not started.
- The phase-gating system itself is being retired from the docs; this file intentionally carries no phase counter.

The old hard-kill/pivot criteria are dead weight now that the mechanic survived — but one is still worth carrying forward to the content layer: if a real `coral.usdz` (unlike the cube) makes placement/scale/collision behave differently enough that the built gestures stop feeling controllable, that's a reason to fix the asset (ADR-007), not to reopen the gesture mechanics.

## 7. Mechanics (as designed; see `GESTURES.md` for as-built tuning)

**Place** — raycast from the pinch midpoint (`thumbTip`/`indexTip`) to the plane; the ray passes through the hand deliberately (ADR-003). ≥8/10 placements within 5cm of intent was the original target.

**Scale** — driven by delta in `pinchRatio` since the hold began, not its absolute value, so it tolerates the hand drifting nearer/further mid-gesture. Applied to the child `ModelEntity`, never the anchor. ≥8/10 within ±20% of a target size.

**Rotate (yaw)** — yaw about `[0,1,0]` (ADR-010), written directly per frame, never via `move(to:duration:)` (slerp takes the long way past 180°). ≥8/10 within ±15° of a marked target. ⚠️ The signal changed during the build: the original design read the 2D thumbTip→indexTip angle, and **that approach was abandoned** — as built, yaw is driven by the horizontal screen position of the pinch point. See `GESTURES.md` for the three signal generations and why the first two failed.

**Mode disambiguation** (scale vs. yaw from the same held pinch) was an open design question in the original PRD. **Resolved**: dominant-axis lock at first deadzone crossing, implemented and passing its unit tests (ADR-018).

**Carry / multi-object** — a pinch resolves to whichever placed entity `SceneController.selectModel(at:)` picks (`entity(at:)` then nearest within `screenGrabRadiusPt`); a pinch with nothing in radius does nothing. Superseded the original "exactly one entity, no translation" non-goal (ADR-019).

## 8. Prior art (read before re-deriving any of this)

No maintained open-source project does what this repo does. Two postmortems are worth reading in full: **philipturner's [ARHeadsetKit](https://github.com/philipturner/ARHeadsetKit)** (archived June 2024) built almost exactly this idea on a cardboard headset, hit imprecise hand reconstruction and 60fps thermal throttling, and retreated to a flat 2D holographic UI panel instead of grabbing 3D objects. **Nomtek's ["Choosing a Hand Gesture-Based Input Method"](https://www.nomtek.com/blog/hand-gesture-input-method-mobile-app)** evaluated ARKit body tracking, MediaPipe, MRTK, and ManoMotion for a commercial handheld-AR installation and shipped with the plain touchscreen instead. The one shipped consumer app doing anything close, **[realtimehand](https://github.com/ogoguel/realtimehand)**-powered *Let's All Be Wizards!*, requires LiDAR (unavailable here) and reviewers describe its gestures as "a bit finicky" — for a low-precision novelty effect, not precision manipulation. This project's rig and scope decisions (ADR-001 through ADR-005) exist specifically to avoid the failure causes these three hit.

## 9. Risks — still live

- **Ergonomics / arm fatigue.** Purdue CHI'17: unsupported mid-air gestures cost meaningfully more time/energy/exertion than a keyboard. Desk-stand de-risking let the free hand rest on the table; **roaming does not** — one hand holds the phone, the other gestures mid-air. Never measured for the longer content-layer interactions (dwell-based Point, quiz). Worth re-checking once content exists.
- **Plane detection degrades on some real surfaces.** A ceramic floor and patterned bedsheets never produced `.existingPlaneGeometry` and were carried by the `.existingPlaneInfinite` fallback tier instead; dim light was never tested at all, and the ≤3cm placement-accuracy target was accepted on a visual verdict rather than ruler measurement (ADR-016). Relevant wherever the content layer gets used outside the tested table and lighting.
- **Automatic mode disambiguation without a HUD toggle is unsolved.** Current builds hard-select Place/Adjust/Move from the HUD; a future gesture-only version would need real device data to calibrate a timing-based auto-switch (ADR-019).

Dropped as answered: egocentric hand-pose accuracy (Phase 0 passed), pinch scale-invariance (ADR-006/015/017), no-LiDAR as a blocker (scoped around, ADR-003/005), cardboard-rig viability (rejected, not attempted, ADR-004), ARKit VIO-vs-hands-in-frame (Phase 4 passed; ADR-019), `ManipulationComponent` iOS availability (confirmed visionOS-only, ADR-013).

## 10. Open questions — still open

- **`estimatedDepthData` buffer resolution and metric error at 30–60cm** — never measured; still the first thing to try if a future feature genuinely needs hand depth, before LiDAR (ADR-003).
- **Cross-distance stability of the pinch-ratio threshold** — calibrated at a single fixed distance on the desk-stand (ADR-015/017). Roaming varies working distance; untested whether 1.98 still separates pinch from open hand off that mount.

Dropped as answered by ADRs or shipped code: `VN*` deprecation annotations and A19 inference benchmarks (moot — on the modern API either way, ADR-008), passthrough latency (moot — headset rejected, ADR-004), ManoMotion pricing (moot — Unity path rejected, ADR-001).

## 11. Key sources

- [WWDC25 session 272 — hand pose model update](https://developer.apple.com/videos/play/wwdc2025/272/?time=1079)
- [philipturner — first-affordable-ar-headset](https://github.com/philipturner/first-affordable-ar-headset)
- [Nomtek — Choosing a Hand Gesture-Based Input Method](https://www.nomtek.com/blog/hand-gesture-input-method-mobile-app)
- [Pfeuffer — Design Principles & Issues for Gaze and Pinch Interaction](https://medium.com/antaeus-ar/design-principles-issues-for-gaze-and-pinch-interaction-a95e251169ae)
- [Purdue CHI'17 — Dispelling the Gorilla Arm Syndrome](https://link.springer.com/chapter/10.1007/978-3-319-57987-0_41)
- Apple forum threads: [665274 (orientation)](https://developer.apple.com/forums/thread/665274) · [733648 (collision shape scale)](https://developer.apple.com/forums/thread/733648) · [803595 (no revision enum)](https://developer.apple.com/forums/thread/803595)
