# GESTURE_LOG — what's been tried, what works, what's live

Living doc. Update every test session — new attempt, tuning change, or verdict flip gets a row.
Not a replacement for `DECISIONS.md` (ADRs are the permanent record of *why*); this is the day-to-day
"what's the current state of each gesture" tracker.

**Demo mode toggle:** see HUD — Place / Adjust / Move, all three live and all three **hard overrides**. The selected mode is the only thing that decides what a pinch does; no timing-based auto-switch runs behind it.

---

## 1. Pinch to place

| | |
|---|---|
| **Motion** | Pinch (thumb+index) anywhere on a detected plane. In Place demo mode, every pinch adds a new object (no more clear-and-replace). In Adjust/Move demo modes, first pinch places; later pinches grab the active object instead. |
| **Status** | ✅ Working, Phase 3/4 verified. Multi-object support added — Place mode accumulates instead of replacing. |
| **Known limits** | Real spatial selection is live: `SceneController.selectModel(at:)` hit-tests the pinch point against every placed entity's `CollisionComponent` (`ARView.entity(at:)`) and that becomes the active object. Pinching where nothing's placed does nothing — no nearest-object fallback (rejected: needs a new, uncalibrated distance threshold; revisit if missed grabs turn out common at 30-40cm range). |
| **Flush-on-plane fixes** | Two separate causes of "the cube isn't sitting on the surface", both pre-existing, both fixed: (1) `place()` used the raycast's full `worldTransform` for the anchor, so on the `.estimatedPlane` tier a guessed, off-vertical normal tilted the whole anchor and stood the cube up crooked — the anchor now takes the hit's *position only*, identity rotation, gravity-aligned by construction (nothing wanted the plane's yaw: `applyYaw` writes an absolute world-Y rotation on the child). (2) The 2.5cm base lift is a fixed offset but scale grows the box about its centre, so scaling up drove the bottom through the plane and scaling down floated it — `applyScale` now shifts y by the change in half-height (`ModelProvider.halfHeight`). Neither was caused by the Move/multi-object work. |

## 2. Scale

| | |
|---|---|
| **Motion** | Pinch to grab (existing object), then open/close fingers. Open = bigger, close = smaller. |
| **Status** | ✅ Working |
| **History** | `scaleSensitivity` 1.0→0.5 (was slamming the clamp in ~130ms). Asymmetric `scaleShrinkSensitivity` 1.75 added — settled-pinch baseline sits near the physical closing floor, so shrink needed a stronger multiplier than grow to reach comparable range. Settling window added so the baseline captures after the pinch stops closing, not mid-squeeze. |
| **Known limits** | Shrink range still slightly tighter than grow by design (physical floor, not fully eliminable). |

## 3. Rotate (yaw)

| | |
|---|---|
| **Motion** | Pinch to grab, then **slide hand left/right** (not a wrist twist). |
| **Status** | ✅ Working, as of the horizontal-slide swap |
| **History** | Three signal generations, in order: (1) thumbTip↔indexTip angle — coupled with scale's own vector, cross-talk unfixable by tuning. (2) wrist↔middleMCP angle — decoupled from scale, but *is* the rotation axis of a dial-turn motion itself, so it barely moved; also had an inverted aspect-ratio constant bug (fixed, real bug, kept for the record). (3) **current**: horizontal screen-position of the pinch point, gain `horizontalSlideGain=12.0`. Reuses the same raycast-tested point placement already uses — sidesteps the whole "measuring a short vector's angle" noise class. |
| **Known limits** | Provisional gain, not yet calibrated against a real device sweep — retune if it feels off. |

## 4. Mode-lock (scale vs. rotate disambiguation)

| | |
|---|---|
| **Mechanism** | Dominant-axis race from grab — whichever deadzone (aperture-change vs. horizontal-slide) crosses first wins, locks for the hold. |
| **Status** | ✅ Working after the settling-window fix |
| **History** | Settling window added so grab-jitter doesn't win the race before real intent starts. Bug found and fixed: yaw accumulation was gated behind the same "armed" flag as the race, so rotation that started *during* the settle window (a natural grab-and-turn) was silently discarded — fixed by decoupling yaw accumulation (always runs) from the race start (waits for settle). |
| **Scope** | This race is *within* Adjust only (scale vs. yaw). Move is never in it — Move vs. Adjust is now the HUD toggle, full stop (see #8). |

## 5. Commit / release

| | |
|---|---|
| **Motion** | Hold the control signal still (~0.4s) → object freezes at current value ("✓" in HUD). Then open hand normally to release. |
| **Status** | ✅ Working (dwell-to-commit) |
| **History** | Original design had release conflated with "keep opening fingers" (same direction as growing), so releasing always overshot to max scale. Dwell-to-commit decouples "I'm satisfied" (stillness) from "grow more" (motion). |

## 6. OK-sign pause/stop

| | |
|---|---|
| **Motion** | Thumb+index tight pinch + middle/ring/little extended — meant to force-commit instantly. |
| **Status** | ❌ Removed, not live |
| **History** | Fired almost instantly on ordinary scaling pinches (uncalibrated finger-extension threshold, `1.2`, was a guess) — froze real scale gestures within ~50ms. Code (`HandShapeClassifier`) stays in the repo unused. Needs real calibration data + a hold-duration gate before it's worth re-adding. |

## 7. Grab highlight

| | |
|---|---|
| **What** | Cube turns yellow while actively grabbed (material swap), reverts on release/cancel. |
| **Status** | ✅ Working |
| **History** | `HoverEffectComponent` (RealityKit's built-in highlight) confirmed available on iPhone, but only fires from RealityKit's own gaze/pointer input pipeline — this app's gestures never touch that, so it'd be a no-op. Manual material swap instead. |

## 8. Pick up and move

| | |
|---|---|
| **Status** | ✅ Working — built per `PROMPTS.md` Prompt 11 |
| **Motion** | Select **Move** on the HUD, then pinch and drag — the object follows the raycast hit under the pinch point. In **Adjust** mode a pinch can never move anything, and vice versa. |
| **Design** | Split by *trigger*, not signal: pinch+drag = move (position, every frame, reuses the existing placement raycast, absolute-from-grab not accumulated deltas); adjust = today's scale/rotate race, untouched (`ManipulationTracker.swift` got zero changes). Rejected: racing move against yaw (yaw's signal *is* a slice of move's own data) and reviving angle-based yaw as move's "orthogonal partner" (sliding your hand sideways rotates your forearm on this rig — not actually orthogonal). |
| **Trigger: now the toggle, not timing** | Was: `moveOrAdjustTrigger(now:lastGestureEnd:regrabWindow:)` — quick re-pinch inside `regrabWindow` (0.4s) → Adjust, otherwise → Move. `.move` forced Move, but `.adjust` *fell through to that timing decision*, and with no prior gesture (or any gap over 0.4s) the decision is Move. So picking "Adjust" on the HUD changed nothing observable and every deliberate grab landed on Move — reported as "I can't adjust without accidentally moving it" and "the toggle doesn't do anything". Now all three modes are hard overrides; nothing calls `moveOrAdjustTrigger` on the live path. The function, `regrabWindow`, and `MoveTriggerTests` all stay — still the right shape for a future build with no toggle — but they don't silently run when the user has picked a mode. |
| **Known limits** | Move is camera-relative by construction: it targets the raycast under a *screen* point, so panning the phone while holding a move slides the object. That's expected inside a deliberate move; it only read as a bug when Adjust was secretly entering Move. Targets whichever object the grab's hit-test resolves to (see #1) — correct per-object now, not the whole scene. Automatic (no-toggle) Move-vs-Adjust disambiguation is still unsolved. |
| **Bug found & fixed** | The initial build re-anchored the object onto a fresh `AnchorEntity` at the end of every move — `removeFromParent()` without preserving world transform, then "preserving" the now-wrong transform onto the new anchor, doubled every drag and added ~2.5cm of height on every grab-release even with zero movement (the reported "jumping/floating"). The re-anchor step didn't do what its own comment claimed (place()'s anchor was never plane-relative to begin with) — deleted rather than patched. Also fixed in the same pass: `modelYaw` was a single global field that leaked between objects (grabbing object B reused object A's stored rotation as its baseline) — now decoded per-model from its own transform. And the grab-time raycast-miss fallback used to seed from the model's own position, causing a snap-under-fingertip the instant the raycast recovered — now waits for a real hit before starting a move at all. Re-verified after the next round of device testing: the re-anchor deletion and the per-model `modelYaw` decode are both clean, neither introduced anything new. |
| **Stuck-gesture guard** | A nil Vision frame (the request threw) used to early-return before reaching `PinchStateMachine`, so an in-flight gesture never timed out — the machine stayed `.active`, `MoveController.isActive` stayed true, and the next frame that arrived resumed the drag as if nothing happened. Nil frames now feed an empty observation so the grace period can cancel. Rare in practice (a hand simply leaving the view returns an *empty* frame, not nil, which already cancelled correctly) but it's the exact failure mode of "the cube resumed following me". |

---

## Rig, for reference

Phone eye-level, ~45° tilt down, hand enters from behind/below, 30-40cm working distance, landscape (landscapeRight), palm generally toward camera. Full diagram: [rig guide artifact](https://claude.ai/code/artifact/199427df-3a94-448d-8026-24019420914a).
