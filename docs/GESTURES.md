# GESTURES — state, tuning, and how to verify each mechanic

Living doc. Update every test session — new attempt, tuning change, or verdict flip gets a row. Not a replacement for [`DECISIONS.md`](DECISIONS.md) (ADRs are the permanent record of *why*); this is the day-to-day "what's live, what's the real number, how do I check it on device" tracker. This doc consolidates the former per-gesture status log, the gesture-track calibration-pass results, and the test-rig discipline that used to live in three separate files — those files no longer exist. See also [`ARCHITECTURE.md`](ARCHITECTURE.md), [`PROJECT.md`](PROJECT.md), [`AGENTS.md`](AGENTS.md), and [`../Measurements/`](../Measurements/) for the cited CSVs. **Where a source doc disagreed with the code, the code wins** — flagged inline below.

Status: cube prototype, not `coral.usdz`. The gesture track (Point/Carry/Rotate/Wave) is built on top of the original Place/Adjust/Move mechanics and has had a threshold-provenance pass (this doc); an on-device verification pass against the checklists in §4 is still outstanding.

---

## 1. Demo modes — HUD toggle, hard overrides, no auto-switch

`ARSessionCoordinator.DemoMode` has **six** cases, not three. Whichever is selected on the HUD is the *only* thing that decides what a pinch does — every mode is a hard override, and nothing on the live path runs a timing-based auto-switch behind it (`moveOrAdjustTrigger` still exists in `MoveController.swift` and is still unit-tested in `MoveTriggerTests`, but no call site on the live path invokes it — see §2.8's history for why that used to be silent and broken).

| Mode | Pinch does | Rotate on re-grab? | Point? | Wave? |
|---|---|---|---|---|
| **Place** | Every pinch adds a new object (accumulates, never grabs) | — | dead | dead |
| **Adjust** | First pinch places; later pinches on the object scale/yaw it (§2.2–2.4) | — | dead | dead |
| **Move** | First pinch places; later pinches on the object drag it (§2.8) | — | dead | dead |
| **Point** | Legacy pinch path is fully dead in this mode (no place/scale/move) | dead | ✅ dwell→popup (§2.9) | dead |
| **Carry** | Quick pinch (toggle) picks up/puts down; re-grab on an already-placed entity re-enters scale/yaw instead | ✅ (O1 stand-in) | dead | dead |
| **Sim** | Same carry toggle as above | ❌ re-grab always re-carries | dead | ✅ (§2.10) |

Place/Adjust/Move are the original mechanic set (ADR-018/019); Point/Carry/Sim are gesture-track stand-ins for a future flow-state machine (showcase / place-O1 / sim-with-wave) that doesn't exist yet — there's no phase/state gating them, the HUD picker is it. The former gesture log documented only Place/Adjust/Move as "all three live"; the calibration-pass results referred to a different subset ("Point / Carry / Sim"). Both were accurate about their own slice and incomplete about the other three — this table is the first place all six are documented together, straight from `DemoMode`'s own `allows*` properties.

---

## 2. Per-gesture status

### 2.1 Pinch to place

| | |
|---|---|
| **Motion** | Pinch (thumb+index) anywhere on a detected plane. Place mode: every pinch adds an object. Adjust/Move: first pinch places, later pinches grab. |
| **Status** | ✅ Working. Multi-object support — Place mode accumulates instead of replacing. |
| **Known limits** | `SceneController.selectModel(at:)` tries `ARView.entity(at:)` first, then nearest projected cube within `screenGrabRadiusPt` (220pt, same unit class as wave). Fat grab added 2026-08-12 — roaming Adjust/Move/Carry misses were pixel-perfect collision hits on a 5cm cube (pinch = thumb–index midpoint, often beside the mesh). Still nil if nothing is within 220pt. Multi-object: nearest wins. |
| **Flush-on-plane fixes** | Two separate pre-existing bugs, both fixed, neither caused by the Move/multi-object work: (1) `place()` used the raycast's full `worldTransform`, so on the `.estimatedPlane` tier a guessed off-vertical normal tilted the anchor and stood the cube up crooked — anchor now takes the hit's position only, identity rotation, gravity-aligned by construction (`applyYaw` writes an absolute world-Y rotation on the child, nothing wants the plane's yaw). (2) The 2.5cm base lift is fixed but scale grows the box about its centre, so scaling up sank it through the plane and scaling down floated it — `applyScale` now shifts y by the change in half-height (`ModelProvider.halfHeight`). |

### 2.2 Scale

| | |
|---|---|
| **Motion** | Pinch to grab, then open/close fingers. Open = bigger, close = smaller. |
| **Status** | ✅ Working |
| **History** | `scaleSensitivity` 1.0→0.5 (was slamming the clamp in ~130ms). Asymmetric `scaleShrinkSensitivity` 1.75 added — a settled-pinch baseline sits near the physical closing floor, so shrink needs a stronger multiplier than grow to reach comparable range. Settling window added so the baseline captures after the pinch stops closing, not mid-squeeze. |
| **Known limits** | Shrink range still slightly tighter than grow by design (physical floor, not fully eliminable). |
| **Tests** | `ManipulationTrackerTests`, `ManipulationTrackerSettlingTests`, `ManipulationTrackerDwellTests`. |

### 2.3 Rotate (yaw)

| | |
|---|---|
| **Motion** | Pinch to grab, then **slide hand left/right** (not a wrist twist). Live under Adjust (grab an existing object) and under Carry (re-grab an entity already put down once — §1). |
| **Status** | ✅ Working, current signal generation is horizontal slide |
| **History — three signal generations** | (1) thumbTip↔indexTip angle — coupled with scale's own vector, cross-talk unfixable by tuning. (2) wrist↔middleMCP angle — decoupled from scale, but *is* the rotation axis of a dial-turn motion itself, so it barely moved; also had an inverted aspect-ratio constant bug (fixed: after the `.right` swap the buffer is 1440×1920, so the correct factor is `width/height` = 1.333 — the reciprocal crushed the yaw axis). (3) **current**: horizontal screen-position of the pinch point, gain `horizontalSlideGain = 12.0`. Reuses the same raycast-tested point placement already computes — sidesteps the whole "measuring a short vector's angle" noise class. CSV column for the live signal is `horizontal_slide`; older files in `Measurements/` still header that column as `yaw_wrist_axis` (same value — rename only, no unit change). `unwrapYaw` is a plain delta accumulator, not ±π unwrap — `horizontalSlide` is not periodic; wrapping would alias fast slides. |
| **Known limits** | Gain is **measured-ish** (shipped + tuned in the original build, `GestureTuning`'s own comment still calls it provisional) — retune only if Carry re-grab yaw overshoots/undershoots targeting. Scope: rotate only exists inside Adjust's scale/yaw race, or Carry's `.carry`-only re-grab path — `.sim` never rotates (by design; O2/O3 tools are carried, not spun). |

### 2.4 Mode-lock (scale vs. rotate disambiguation)

| | |
|---|---|
| **Mechanism** | Dominant-axis race from grab — whichever deadzone (aperture-change vs. horizontal-slide) crosses first wins, locks for the hold (ADR-018). |
| **Status** | ✅ Working after the settling-window fix |
| **History** | Settling window added so grab-jitter doesn't win the race before real intent starts. Bug found and fixed: yaw accumulation was gated behind the same "armed" flag as the race, so rotation starting *during* the settle window (a natural grab-and-turn) was silently discarded — fixed by decoupling yaw accumulation (always runs) from the race start (waits for settle). Also: yaw baseline must arm independently of the ratio baseline — co-gating them stalled on lag ("stuck ambiguous"). |
| **Scope** | This race is within Adjust (or Carry's re-grab-rotate) only — Move/Carry-pickup are never in it; that's a HUD/routing decision, not a signal race (§1). |

### 2.5 Commit / release

| | |
|---|---|
| **Motion** | Hold the control signal still (~0.4s) → object freezes at current value ("✓" in HUD). Then open hand normally to release. |
| **Status** | ✅ Working (dwell-to-commit) |
| **History** | Original design conflated release with "keep opening fingers" (same direction as growing), so releasing always overshot to max scale. Dwell-to-commit decouples "I'm satisfied" (stillness) from "grow more" (motion). |

### 2.6 OK-sign pause/stop

| | |
|---|---|
| **Motion** | Thumb+index tight pinch + middle/ring/little extended — meant to force-commit instantly. |
| **Status** | ❌ Removed, not live |
| **History** | Fired almost instantly on ordinary scaling pinches (`okSignFingerExtendedRatio = 1.2` was an uncalibrated guess) — froze real scale gestures within ~50ms. `HandShapeClassifier.isOKSign` stays in the repo, unused. Needs real calibration data + a hold-duration gate before it's worth re-adding. |
| **Tests** | `HandShapeClassifierTests` covers the classifier logic (pinch-not-OK-sign, OK-sign-detected, open-hand-not-OK-sign) even though nothing calls it live. |

### 2.7 Grab highlight

| | |
|---|---|
| **What** | Object turns yellow while actively grabbed (material swap), reverts on release/cancel. |
| **Status** | ✅ Working |
| **History** | `HoverEffectComponent` (RealityKit's built-in highlight) confirmed available on iPhone, but only fires from RealityKit's own gaze/pointer input pipeline — this app's Vision-driven pinch gestures never touch that, so it would be a permanent no-op here. Manual material swap instead. |

### 2.8 Pick up and move (Move mode) / Carry toggle (Carry & Sim modes)

Two different mechanics that both end in "the object follows your hand," built at different times, both still live and gated by mode (§1) so they never race each other.

| | |
|---|---|
| **Move mode motion** | Select **Move** on the HUD, pinch and hold, drag — object follows the raycast hit under the pinch point every frame while the pinch is held. Absolute-from-grab, not accumulated deltas (`MoveController`), reusing the placement-preview raycast already computed every frame. |
| **Carry/Sim motion** | A **quick pinch** (began→ended under `carryToggleMaxDuration`, 0.7s) toggles pick-up/put-down (`CarryStateMachine`); once carried, the object follows the projected pinch point continuously — no need to keep fingers pinched — until the next quick pinch puts it down. A pinch held *longer* than the toggle window on a never-carried object does nothing at all (not a toggle, not a grab — `CarryStateMachineTests.testLongCycleDoesNothing`). Toggle target is latched at `.began` and never re-read at `.ended`. |
| **Status** | ✅ Both working |
| **Design** | Move/Carry split by *trigger*, not signal — pinch+drag = move (position); Adjust's scale/yaw race (`ManipulationTracker`) got zero changes. Rejected at design time: racing move against yaw (yaw's signal is a slice of move's own data) and an angle-based yaw as move's "orthogonal partner" (sliding your hand sideways rotates your forearm on this rig — not actually orthogonal). |
| **History — the toggle used to be silently broken** | Before demo modes were hard overrides, `.adjust` fell through to `moveOrAdjustTrigger(now:lastGestureEnd:regrabWindow:)` — quick re-pinch inside `regrabWindow` (0.4s) → Adjust, else → Move. With no prior gesture (or any gap over 0.4s) the decision was always Move, so picking "Adjust" on the HUD changed nothing observable and every deliberate grab landed on Move — reported as "I can't adjust without accidentally moving it." Now all modes are hard overrides; `moveOrAdjustTrigger`/`regrabWindow`/`MoveTriggerTests` stay in the tree (still the right shape for a future no-toggle build) but nothing calls the function on the live path. |
| **Bug found & fixed — the re-anchor doubling bug** | The initial Move build re-anchored the object onto a fresh `AnchorEntity` at the end of every move — `removeFromParent()` without preserving world transform, then "preserving" the now-wrong transform onto the new anchor — which doubled every drag and added ~2.5cm of height on every grab-release even with zero movement (reported as "jumping/floating"). The re-anchor's own justification ("keeps the anchor tied to the plane") was false — `place()`'s anchor was never plane-relative to begin with. **Deleted, not patched**; `moveModel()` already converts through whatever the current parent is, at any offset, so there was nothing to fix by re-anchoring. |
| **Bug found & fixed — global yaw leaking between objects** | `modelYaw` was a single global field; grabbing object B reused object A's stored rotation as B's baseline, snapping B's rotation on the first yaw frame after switching objects. Now decoded per-model from its own transform each time (`SceneController.modelYaw`) — safe because every yaw write is a pure world-Y `simd_quatf` (never `move(to:)`), so decoding back is exact. |
| **Bug found & fixed — grab-miss raycast fallback snap** | The grab-time raycast-miss fallback used to seed from the model's own position, causing a snap-under-fingertip the instant the raycast recovered. Now waits for a real hit before starting a move at all. |
| **Bug found & fixed — stuck-gesture nil-frame guard** | A nil Vision frame (the request threw) used to early-return before reaching `PinchStateMachine`, so an in-flight gesture never timed out — the state machine stayed `.active`, `MoveController.isActive` stayed true, and the next frame that arrived resumed the drag as if nothing happened. Nil frames now feed an empty observation so the grace period can cancel it. Rare in practice (a hand simply leaving frame returns an *empty* observation, not nil, which already cancelled correctly) but it's the exact failure mode of "the object resumed following me." Carry/Point/Wave all sit on this same nil-frame path for the same reason. |
| **Bug found & fixed — Adjust pinch self-cancel** | `endCarryIfActive()` ran every frame whenever `allowsCarry` was false — including Adjust. Adjust's scale/yaw uses the same shared `ManipulationTracker`, so pinch → `manipulation.begin` → same/next frame `handleCarryRouting` saw `isActive` and called `finishManipulation()` immediately. Reset is now edge-triggered on `demoMode` leaving Carry/Sim (`didSet`), not level-triggered per frame. Carry → Place mid-carry still drops `carriedEntity` / `moveController` / highlight once. |
| **Known limits** | Move is camera-relative by construction: it targets the raycast under a *screen* point, so panning the phone mid-move slides the object — expected inside a deliberate move, only read as a bug when Adjust was secretly entering Move. Targets whichever object the grab's hit-test resolves to (§2.1), correct per-object now. **Automatic (no-toggle) Move-vs-Adjust disambiguation is still unsolved** — deferred until a build genuinely needs gesture-only mode switching. |
| **Tests** | `MoveTriggerTests` (the retired trigger function, still exercised), `CarryStateMachineTests` (toggle latch + re-grab routing). |

### 2.9 Point-and-dwell (annotations)

| | |
|---|---|
| **Motion** | Point mode only. Extend the index finger (others curled, thumb clearly away from index — `HandShapeClassifier.isPointing`) and hold over an annotation marker for `pointDwellDuration` (0.4s) → popup fires. |
| **Status** | ✅ Working — one test annotation exists on the first-ever placed cube (`SceneController.addAnnotation`, cube-prototype scaffolding, not a real content system). |
| **Design** | A pinch beginning cancels any in-progress dwell outright — point and pinch/carry never run on the same target at once (`PointStateMachine`). Annotation hit: `entity(at:)` on `hitRadius = 0.035m` (Ø7cm) collision, then same `screenGrabRadiusPt` (220pt) nearest-marker fallback as Adjust. World `hitRadius` 0.022→0.035 after HIG floor was too tight at 30–40cm. |
| **Known limits** | `pointDwellDuration` (0.4s) and `pointFingerExtendedRatio` (1.2) are both unmeasured — see §3. Shape gate still drops dwell independently of hit radius. |
| **Tests** | `PointStateMachineTests` (dwell completion, early abandon, 2-frame grace survival, 10-frame timeout, pinch-cancels-dwell). |

### 2.10 Wave / stationary-hold (Sim mode only)

| | |
|---|---|
| **Motion** | Sim mode only. Wave the wrist near a placeholder target (projected top-face center of the active object) for `waveHoldDuration` (2.0s), **or** hold the wrist still near it for the same duration (stationary-hold fallback) — either fires `.waved`. |
| **Status** | ✅ Working as a recognizer; the target itself is scaffolding (a marker on the cube, not real dirt/pest content). |
| **⚠️ Known limit — the most surprising finding of the calibration pass** | `waveProximityRadiusPt` (220, defined in `ARSessionCoordinator+Wave.swift`, **not** in `GestureTuning.swift`) is a **screen-point radius**, not the originally intended 5–8cm world-space gate. It worked for the cube prototype on the desk-stand because the marker stayed roughly the same apparent size at a fixed working distance. **Roaming varies distance**, so apparent size changes — do not silently promote 220pt to a content-layer constant; replace with a world-space radius. |
| **History** | Proximity radius widened 130pt→220pt after on-device testing found wave silently stopped working once an object was placed and no longer glued to the hand — a stationary target needs more forgiveness than a carried one. Stationary-hold uses a **fixed start-of-run anchor** (not re-centered) — a sliding radius would treat slow drift as a hold. |
| **Known limits** | `waveMinAmplitude`, `waveMinReversals`, `waveProgressDecay` are all unmeasured plan placeholders (§3) — do not retune without real device data. |
| **Tests** | `WaveDetectorTests` — sustained wave fires once, sub-threshold duration doesn't fire, a 2-frame nil gap decays without hard-resetting, slow drift and carrying-speed translation never false-fire, stationary-hold fallback fires, cooldown suppresses immediate re-fire. |

---

## 3. Tuning constants — provenance

Every constant lives in `CoralAR/Gesture/GestureTuning.swift` unless noted otherwise. Provenance tags: **measured** — CSV-backed, filename cited. **ad-hoc** — direction confirmed on device, exact value not from a sweep. **placeholder** — never measured on this rig; carried from the original gesture-track plan (a dead document as of this pass — described here directly rather than cited). **not in tree** — no code yet (content-layer).

| Constant | Value | Provenance | Note |
|---|---|---|---|
| `pinchThreshold` | 1.98 | **measured** — ADR-017, `phase4_join_20260809_174233.csv` (759 rows) + static-hold confirm `…_180023.csv` | **Do not touch without a new ARFrame static-hold CSV.** |
| `hysteresisBand` | 1.0 | **measured** (confirmed by the same ADR-017 addendum static hold) | Keep. |
| `hitRadius` (`SceneController.addAnnotation`) | 0.035m (Ø7cm) | **ad-hoc** 0.022→0.035 | Collision volume for `entity(at:)`. Fat grab is `screenGrabRadiusPt`, not this. |
| `screenGrabRadiusPt` (`SceneController`, **not `GestureTuning`**) | 220pt | **ad-hoc** — same number as `waveProximityRadiusPt`; roaming Adjust/Point miss on pixel `entity(at:)` | Screen points, not world cm. Retune if multi-object false-grabs or still-misses. |
| `carryToggleMaxDuration` | 0.7s | **ad-hoc** 0.5→0.7 (0.5 too tight for a deliberate pick-up pinch) | Proper refine: log began→ended durations for ~20 toggles + ~20 grab-drags in Carry mode, pick the value that separates them. |
| `horizontalSlideGain` | 12.0 | **ad-hoc**, verging on measured — shipped and tuned during the original build, comment still calls it provisional | Re-touch only if Carry re-grab yaw overshoots/undershoots targeting. |
| `waveProximityRadiusPt` (`ARSessionCoordinator+Wave.swift`, **not `GestureTuning`**) | 220pt | **ad-hoc** 130→220; **unit mismatch** — screen points, not the intended 5–8cm world gate (§2.10) | Keep 220pt until a real hit volume exists; content layer must replace with a world-space radius. Apparent size changes more while roaming than on the desk-stand — do not treat 220pt as a content-layer constant. |
| `waveMinAmplitude` | 0.05 (norm. width frac.) | **placeholder** | Needs a real hand-span→normalized-x conversion at 30–40cm. Do not change until measured. |
| `waveMinReversals` | 3 (within `waveWindow=1.0s`) | **placeholder** | Measure reversals/s on deliberate waves vs. carry-drag false positives. |
| `waveHoldDuration` | 2.0s | **decided, unmeasured feel** | Keep unless demos feel slow; try 1.5 before redesigning. |
| `waveProgressDecay` | 2.5s | **placeholder** (mid-band pick) | Keep until gap-resume tests (already unit-tested for 2-frame gaps) say otherwise. |
| `pointDwellDuration` | 0.4s | **placeholder** | Same order of magnitude as `dwellDuration`; retune once real on-device annotation passes exist. |
| `waveStationaryRadius` | 0.02 | **placeholder** — half of `waveMinAmplitude`, so ordinary wave motion can't also read as a hold | Retune on device. |
| `okSignFingerExtendedRatio` | 1.2 | **placeholder**, unused live path (§2.6) | — |
| `pointFingerExtendedRatio` | 1.2 | **placeholder** — same starting value as OK-sign's ratio, separate knob so retuning one doesn't silently retune the other | — |
| `waveCooldownDuration` | 2.0s | **placeholder** — set equal to `waveHoldDuration` so a second wave needs a fresh deliberate gesture | — |
| `moveSmoothing` | 1.0 (no smoothing, 1:1 follow) | **unverified** whether 1:1 reads as jittery on device | First knob to revisit if Move/Carry following looks jumpy. |
| `regrabWindow` | 0.4s | **placeholder**; the function that reads it (`moveOrAdjustTrigger`) is dead on the live path (§2.8) | Needs real gesture-end-to-next-gesture-start interval data before any future no-toggle build trusts it. |
| Translation deadzone | — | **not in tree** | Move/Carry use absolute-from-grab 1:1 follow; add only if placed objects visibly creep while idle. |
| Dirt/pest counts, annotation fade band, onboarding stall timer | — | **not in tree** | Content-layer scope, out of scope for the cube prototype. |

### Pipeline & mode-lock lifecycle constants (state-machine internals, not per-gesture feel)

These don't show up in the per-gesture sections above because they're plumbing shared across every gesture, not a single mechanic's feel — but they're real `GestureTuning.swift` fields and belong in the provenance record too. New tag used here: **by design** — a deliberate engineering choice within a range the research/AGENTS.md/an ADR names, not a swept or CSV-derived number. **unrecorded** — no code comment, ADR, or CSV justifies this exact value; the honest answer is "nobody wrote down why."

| Constant | Value | Provenance | Note |
|---|---|---|---|
| `confidenceGate` | 0.3 | **by design** — chosen within the 0.3–0.5 band `AGENTS.md` specifies for landmark confidence; no code comment, no rig-specific sweep behind the exact number | If pinch reliability looks off before touching `pinchThreshold`, this is a candidate. |
| `inferenceInterval` | 0.066s (~15Hz) | **by design** — ADR-011's throttle decision (15–20Hz band, "gesture input doesn't need 60Hz"); not a per-rig measurement, no inference-cost benchmark exists for this model/device | ADR-011: ~66ms quantization plus ~100ms hysteresis leaves little headroom against the 150ms latency budget in `PRD.md`. |
| `hysteresisDuration` | 0.100s | **by design** — matches the "~100ms persistence" figure ADR-006/ADR-012 cite from external prior-art research, not independently measured on this rig | No code comment records this value; ADR-017 flags `hysteresisBand` as the untrusted half of the pinch pair, not this. |
| `gracePeriod` | 0.200s | **unrecorded** — implements Pfeuffer's "don't disengage on brief tracking loss" principle (ADR-012), but the 200ms figure itself has no code comment, ADR, or CSV behind it | The *existence* of a grace period is a design decision; the *duration* is not traced to any evidence. |
| `scaleDeadzoneLog` | 0.18 | **unrecorded** — drifted from ADR-018's recorded 0.22 with no comment, ADR update, or CSV explaining the new number | See the ADR-018 drift callout below — the one constant in this doc with no traceable origin at all. |
| `yawDeadzoneRad` | 0.35 | **ad-hoc** — drifted from ADR-018's recorded 0.21; the code comment gives a real reason (incidental wrist rotation during scale was winning the mode-lock race almost every time) even though no ADR/GESTURE_LOG entry was ever updated to match | See the ADR-018 drift callout below. |
| `yawSensitivity` | 1.0 | **placeholder** — Phase 5 provisional value, "set by targeting runs" (Run F) that never ran; unchanged from ADR-018's recorded 1.0 | Not drifted, just still unmeasured. |
| `scaleModeExitThreshold` | 3.5 | **placeholder** — same Phase 5 provisional group, unchanged from ADR-018's recorded 3.5 | — |
| `settleQuietLogDelta` | 0.06 | **measured** — `phase5_manip_20260809_23*.csv` (87 gestures, ~15Hz): median per-frame \|Δlog(ratio)\| falls 0.25→0.12 over the first ~150ms after Began, then to 0.02–0.03 by ~200–300ms; 0.06 sits inside that settling band | — |
| `settleTimeout` | 0.6s | **ad-hoc** — a fallback margin motivated by the same settling-window CSV above, not itself read off one specific data point | Arms the gesture anyway if the hand never goes quiet. |
| `dwellLogThreshold` | 0.05 | **placeholder** — code comment: "provisional, same order of magnitude as the deadzones above; retune alongside them once on-device data exists" | — |
| `dwellYawThreshold` | 0.05 | **placeholder** — same shared comment as `dwellLogThreshold` | — |
| `pinchEnterThreshold` / `pinchExitThreshold` | `pinchThreshold ∓ hysteresisBand/2` (≈1.48 / ≈2.48) | **measured** — pure computed functions of `pinchThreshold`/`hysteresisBand`, both ADR-017-backed | Named here for searchability; no independent provenance beyond what those two already have. |

**⚠️ ADR-018 is out of date for two of its five recorded constants.** ADR-018 (2026-08-09) states `scaleDeadzoneLog`/`yawDeadzoneRad`/`scaleSensitivity`/`yawSensitivity`/`scaleModeExitThreshold` "are all still the provisional values from the Prompt 9 plan (0.22, 0.21, 1.0, 1.0, 3.5)" pending a Run F that never happened. The live code has since moved on two of the five, with nothing recording when or why:

| Constant | ADR-018 (2026-08-09) | Live code | Recorded anywhere? |
|---|---|---|---|
| `scaleDeadzoneLog` | 0.22 | 0.18 | **No** — origin unrecorded |
| `yawDeadzoneRad` | 0.21 | 0.35 | In-code comment only (wrist rotation was winning the mode-lock race) — never promoted to an ADR or `GESTURE_LOG` entry |
| `scaleSensitivity` | 1.0 | 0.5 | Yes — §2.2 History (was slamming the clamp at 130ms) |
| `yawSensitivity` | 1.0 | 1.0 | unchanged |
| `scaleModeExitThreshold` | 3.5 | 3.5 | unchanged |

`scaleShrinkSensitivity` (1.75, §2.2) is a sixth constant in the same family, added after ADR-018 shipped — the ADR doesn't mention it because it didn't exist yet. **Treat ADR-018's numeric claim as historical, not current, for this group.** This is the one place in the project where an ADR is actively stale rather than authoritative. Do not backfill a reason for either drifted number — "changed after ADR-018, origin unrecorded" is the accurate tag for `scaleDeadzoneLog`; `yawDeadzoneRad` at least has its reasoning alive in the code comment, just never written up.

**0.7× (ultra-wide) lens — skipped, hard no.** `ARWorldTrackingConfiguration.supportedVideoFormats` only exposes `builtInWideAngleCamera` (1×) formats for world tracking; Apple's ultra-wide capture docs are written against `ARFaceTrackingConfiguration`, not world tracking, and forum consensus confirms no supported path to drive ultra-wide as ARKit's primary camera (Apple forum threads 712533, 765555). A multi-cam workaround would break the single-`ARFrame` pipeline this app is built on and is out of scope for a tuning pass. All calibration above is **1×-only**.

**Recommended changes from the last calibration pass: none.** Every ad-hoc and placeholder value above was kept as-is — nothing looked fundamentally unworkable from prior device feedback, and the pass's explicit rule was **do not invent numbers**: leave placeholders as placeholders until a real CSV exists, don't add deadzones/timers/fade-bands the content layer hasn't asked for yet. (`pointFingerExtendedRatio` and `waveCooldownDuration` appeared only in the calibration results' appendix, never in the gesture log — folded into §2.9/§2.10 above rather than kept as a separate leftover list; everything else in `GestureTuning.swift` is now accounted for somewhere in this doc.)

---

## 4. Rig, verification, and reporting

### 4.1 Rig discipline (fix this before measuring anything)

**Live use is roaming handheld** — walk with the phone, free hand in the rear-camera view, object on the phone screen. Same binary as the desk-stand build; no code fork (ADR-020).

**§3 numbers (ADR-015/017 pinch, etc.) came from a desk/tripod stand**, not from roaming: rear camera down-and-forward, ~45° tilt, eye-level; hand from behind/below at **30–40cm**; landscape (`landscapeRight`); palm generally toward camera; one table, one lighting setup, **one hand**, don't adjust the mount mid-run. A new number is only comparable to those CSVs if that mount is held constant. Roaming retunes are valid — tag the condition (`roaming` vs `desk-stand`) in the session note and filename; do not silently mix series.

Log `ProcessInfo.thermalState` on every row; **discard runs where it exceeds `.fair` mid-run** and note why.

### 4.2 Per-gesture on-device checklist (outstanding — this is the remaining human pass)

**Point (Point mode).** 20 deliberate points at the annotation marker, count dwell→popup successes. 20 deliberate mid-pinch/open-hand passes near the marker, count false popups (should be ~0 — shape gate). If miss rate > ~20% at 0.035m `hitRadius`, bump again; if false hits appear, tighten.

**Carry + rotate (Carry mode).** 20 short toggle pinches — all should pick up/put down (validates the 0.7s window). 10 deliberate long grab-drags (>0.7s) — must **not** toggle. After first put-down: re-pinch → yaw via horizontal slide; third pinch still rotates. First pickup before any put-down still carries (unchanged).

**Wave (Sim mode).** Wave ~2s near the target — `waveCount` in the HUD increments once. Stationary hold ~2s on target — also fires (fallback). Carry/drag across the table — must **not** fire. Pause mid-wave <1s and resume — progress should not hard-reset.

**Pinch enter/exit (any pinching mode).** Already ADR-017-backed. Only re-open if open-hand false-pinches return; then a new static-hold CSV, not a guess.

### 4.3 Reporting convention

At the end of a test session, append a dated entry: date, rig configuration, which checklist items were run and their CSV filenames if any, headline numbers against whatever pass criteria applied, pass/fail/pivot and the decision taken, and anything surprising. Update §2/§3 tables directly with row edits (status flips, provenance upgrades) rather than duplicating them here. **Failing a check is a valid outcome and gets written up with the same care as passing one** — an untested mechanic with no numbers is the actual failure mode to avoid.

---

## 5. See also

[`DECISIONS.md`](DECISIONS.md) ADR-015 (single-distance pinch calibration), ADR-017 (pinchRatio re-derivation, 5.9→1.98), ADR-018 (scale/yaw mode-lock, `ManipulationComponent` confirmed visionOS-only), ADR-019 (Move/multi-object/selection, the re-anchor and global-yaw bugs), ADR-020 (roaming handheld use; desk-stand was calibration only). Rig and hard constraints (no LiDAR, `.right` orientation, `displayTransform`, one hand) in [`AGENTS.md`](AGENTS.md). CSVs cited above live in [`../Measurements/`](../Measurements/).
