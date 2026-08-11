# Gesture Build Prompts — Point / Carry / Rotate / Wave

Companion to `PROMPTS.md`, same format: one prompt per step, send in order, each assumes a coding
agent reading this repo fresh. Source plan: the merged architecture + UX doc (design decisions
below trace to `docs/DECISIONS.md` and `docs/GESTURE_LOG.md`, checked against those files before
this was written).

**Scope note:** this track runs on the cube prototype, alongside Phase 5. It does not renumber
`AGENTS.md`'s `CURRENT PHASE` line and does not block Phase 6 (real coral asset) — the two are
independent. Do not update `CURRENT PHASE` from this track.

**Decided, not open:** point-and-dwell (not literal tap), rotate via sequential re-grab (not a new
signal), rotate lives in the simulation flow only (not the showcase), 3 dirt patches / 3 pests per
session, 2.0s wave hold with a stationary-hold fallback. Don't re-litigate these inside a build
prompt — if a build finds one doesn't actually work on device, stop and report back rather than
silently picking a different design.

**Parallel safety:** Prompts B, C, and E touch disjoint files once Prompt A's skeleton lands, so
they can run as separate agents/sessions in parallel — in separate git worktrees if truly
simultaneous, or one after another in the same tree if not. Prompt D is **not** parallel-safe with
C — it edits the same file C creates, so it must run after C lands. Prompt F needs all four done.

---

## Prompt A — Setup commit (run first, alone)

> Read `docs/AGENTS.md`, `docs/DECISIONS.md` (especially ADR-018, ADR-019), and `docs/GESTURE_LOG.md`
> before doing anything. Also read the plan this implements — I'll paste it inline / attach it.
>
> Set up scaffolding only. No gesture logic yet. Specifically:
>
> 1. Empty skeleton files with just `struct`/`enum Event` shapes (no logic) for:
>    `CoralAR/Gesture/PointStateMachine.swift`, `CoralAR/Gesture/CarryStateMachine.swift`,
>    `CoralAR/Gesture/WaveDetector.swift`. Match the existing convention exactly — see
>    `PinchStateMachine.swift` for the shape: `Sendable` struct, `var tuning: GestureTuning`,
>    `mutating func process(...) -> [Event]`. No closures, no Combine, no ARKit/RealityKit imports
>    in `Gesture/`.
> 2. Empty extension files: `CoralAR/AR/ARSessionCoordinator+Point.swift`,
>    `CoralAR/AR/ARSessionCoordinator+Carry.swift`, `CoralAR/AR/ARSessionCoordinator+Wave.swift`.
> 3. Four stub dispatch lines in `ARSessionCoordinator.handleVision`, in this order, each calling
>    into the matching extension (bodies can be empty for now): pinch processing (existing) →
>    carry/rotate routing → point → wave. Also feed each new recognizer on the existing nil-frame
>    path (search for the current `guard let frame else` branch) — this is required now, not
>    deferred, since it's the easiest bug to ship later and forget.
> 4. Add all three new files to the `HandProbe` target's `sources:` list in `project.yml` (see
>    the existing entries for `ManipulationTracker.swift` / `MoveController.swift` as the pattern)
>    so `HandProbeTests` can `@testable import` them.
> 5. Four empty `// MARK: - <Gesture>` blocks in `GestureTuning.swift`, in this fixed order: Point,
>    Carry, Wave. (No Rotate block — rotate reuses `ManipulationTracker`'s existing tuning as-is.)
> 6. Four empty `XCTestCase` subclasses in `HandProbeTests/`: `PointStateMachineTests.swift`,
>    `CarryStateMachineTests.swift`, `WaveDetectorTests.swift`. One placeholder test each
>    (`XCTAssertTrue(true)`) so the suite has something to run.
> 7. Add `LandmarkFrame.indexTipPoint(confidenceGate:)` as a sibling to the existing
>    `pinchPoint(confidenceGate:)` — same guard shape, index fingertip instead of thumb/index
>    midpoint.
>
> Do not implement any gesture logic. This is pure scaffolding so four build steps can proceed
> without touching each other's files.

**Stop and test here.** Confirm before continuing:
- Project builds clean (`xcodebuild` or Xcode build, no warnings from the new empty files).
- `HandProbeTests` runs and the four placeholder tests pass.
- Every existing test (`PinchStateMachineTests`, `ManipulationTrackerTests`, etc.) still passes —
  scaffolding must not have touched anything live.
- Diff review: nothing outside the files listed above changed.

---

## Prompt B — Point-and-dwell → annotation popup

> Read `docs/AGENTS.md`, the plan's §2 (Point) and §3 (disambiguation, hitbox sizing), and
> `CoralAR/Gesture/PinchStateMachine.swift` for the state-machine convention to match.
>
> Implement `PointStateMachine`:
> - States: `idle → dwelling(target, since) → hovering(target)`. Dwell threshold ~400ms
>   (`tuning.pointDwellDuration`, add to the Point `// MARK` block in `GestureTuning.swift`).
> - Reuse the existing grace-period pattern from `PinchStateMachine` (`lastValidAt` +
>   `tuning.gracePeriod`) so one dropped Vision frame doesn't collapse a dwell in progress.
> - Events: `.hoverBegan(AnnotationID)`, `.hoverEnded(AnnotationID)`. Expose a live
>   `dwellProgress: Double` (0–1) for a filling-ring UI affordance.
> - A pinch beginning while dwelling cancels the dwell (`idle`) — point and carry never run
>   together on the same target.
>
> Add `isPointing(joints:)` to `HandShapeClassifier.swift`, next to the existing `isOKSign`: index
> extended (reuse the existing `isExtended` helper), middle/ring/little **not** extended, thumb
> away from index (reuse `PinchRatioCalculator`'s ratio — pointing requires being clearly *above*
> `tuning.pinchEnterThreshold`, not just below the pinch band).
>
> Add `SceneController.selectAnnotation(at:) -> AnnotationID?`, parallel to the existing
> `selectModel(at:)` collision hit-test — walk the parent chain the same way, but against a
> registered `[ObjectIdentifier: AnnotationID]` map instead of placed models. Annotation entities
> need a collision shape sized to at least ~4.4cm at the object's placement distance (see plan
> threshold table) even if the visible marker is smaller.
>
> On the cube prototype, add exactly one test annotation point on a visible cube face, wired to
> show a placeholder text popup on `.hoverBegan` and dismiss on `.hoverEnded`. This is just enough
> content to exercise the gesture, not a real annotation system.
>
> Wire it in `ARSessionCoordinator+Point.swift`, filling in the stub from Prompt A. Feed the
> index-fingertip viewport point (`LandmarkFrame.indexTipPoint`), not the pinch point.
>
> Write `PointStateMachineTests.swift` following `PinchStateMachineTests`' hand-written-array
> pattern: dwell completes → event; dwell abandoned early → no event; target lost 2 frames →
> survives (mirrors the existing drag-survives-dropped-frames test); target lost 10 frames →
> `.hoverEnded`; pinch begins mid-dwell → cancelled, no hover event.

**Stop and test here.** Confirm before continuing:
- `PointStateMachineTests` passes, all cases above covered.
- On device (or simulator with synthetic hand data if device isn't available yet): pointing at
  the test annotation for ~400ms shows the popup; pointing elsewhere or pinching cancels it.
- No regression in existing pinch/carry behavior — point runs in parallel with nothing yet, so
  this should be a pure addition.

---

## Prompt C — Carry: pinch-toggle pick up / place, with an indicator

> Read the plan's §2 (Carry) and `docs/DECISIONS.md` ADR-019 (existing pick-up-and-move
> behavior — this extends it, doesn't replace it).
>
> Implement `CarryStateMachine` as a toggle-latch consuming `PinchGestureEvent` (the existing
> `PinchStateMachine`'s output) — do not re-derive pinch detection.
> - `empty` + short pinch (under `tuning.carryToggleMaxDuration`, start ~0.5s) that began on a
>   target → `carrying(id)`, emits `.pickedUp(id)`.
> - `empty` + pinch over that duration, or `.cancelled` → stays `empty`, no event (a long pinch
>   is a grab, not a toggle).
> - `carrying(id)` + short pinch within the window → `empty`, emits `.putDown(id)`.
> - Expose exactly one piece of state: `carried: EntityID?`. No parallel boolean.
>
> Mirror this into `ARSessionCoordinator` as `@Published private(set) var carriedEntity: EntityID?`.
> Everything renderable derives from that one optional:
> - Reuse the existing `SceneController.setHighlighted(true/false)` call already used for
>   grab/manipulate — don't add a second highlight mechanism.
> - Add a contact shadow under the carried object if one doesn't already exist on this prototype;
>   it should tighten/darken as the object nears the surface.
> - `.pickedUp` → `moveController.begin(...)`; `.putDown` → `moveController.reset()`. Set
>   `tuning.moveSmoothing = 1.0` for the decided 1:1 follow (currently 0.5 — confirm this doesn't
>   make the follow visibly jittery on device; if it does, report back rather than silently
>   reverting).
>
> Wire it in `ARSessionCoordinator+Carry.swift`. Add `tuning.carryToggleMaxDuration` to the Carry
> `// MARK` block.
>
> Write `CarryStateMachineTests.swift` in `MoveTriggerTests`' pure-timestamp style: short cycle on
> a target → `.pickedUp`; long cycle → nothing; second short cycle → `.putDown`; `.cancelled`
> mid-pinch → no state change; pinch on empty space → nothing.

**Stop and test here.** Confirm before continuing:
- `CarryStateMachineTests` passes.
- On device: a quick pinch-release on the cube picks it up (highlight + shadow appear, object
  follows hand 1:1); a second quick pinch-release puts it down. A long hold-and-drag pinch
  behaves like today's existing grab, not a toggle.
- `docs/GESTURE_LOG.md`-listed bugs (re-anchor jump, per-model yaw leak) don't reappear — verify
  picking up a second object doesn't inherit state from the first.

---

## Prompt D — Rotate: route re-grab to the existing manipulator

> Depends on Prompt C being merged first — this edits `ARSessionCoordinator+Carry.swift`.
>
> **New finding from Prompt C, must be resolved as part of this prompt:** `handleCarryRouting`
> currently runs unconditionally every frame, regardless of the existing `demoMode`
> (Place/Adjust/Move) HUD toggle from ADR-019. On device, a pinch in Adjust or Move mode races
> the legacy `handleGestureEvent` flow against Carry over the same event — Carry sets up a
> pickup, then the legacy `.ended` handling calls `finishManipulation()` right after and undoes
> it. Rotate's re-grab routing would inherit the identical race if wired in blind. Fix required
> here, not deferred to Prompt F: give Carry/Rotate their own explicit `demoMode` case (e.g. add
> `.carry` to the existing enum) so `handleCarryRouting` — and this prompt's rotate routing —
> only run when that mode is selected, leaving the legacy Adjust/Move path untouched. This is a
> small, contained gating decision, not the full Prompt F gating table.
>
> Read the plan's rotate section and `docs/GESTURE_LOG.md` §3 (rotate signal history — do not
> revisit wrist-twist or slide-while-carrying, both are already-closed dead ends on this rig).
>
> No new gesture file. In `ARSessionCoordinator+Carry.swift`, add the routing rule: if a pinch
> begins on an entity that has been placed at least once before (i.e. `CarryStateMachine` has
> already emitted a `.putDown` for it), route that pinch to the existing `ManipulationTracker`
> instead of back into `CarryStateMachine`. `ManipulationTracker` already drives yaw from
> horizontal slide of the pinch point at `tuning.horizontalSlideGain` (12.0, already tuned) — do
> not change its internals.
>
> Track "has been placed before" as a small `Set<EntityID>` (or per-entity flag) at the coordinator
> level — this is the only new state in this prompt.
>
> No new tests needed — `ManipulationTrackerTests` already covers the yaw logic being reused. Add
> one small test (in `CarryStateMachineTests.swift` or a coordinator-level test if one exists)
> confirming a pinch on a never-placed entity goes to Carry, and a pinch on a previously-placed
> entity goes to rotate instead.

**Stop and test here.** Confirm before continuing:
- The routing test passes.
- On device: pick up the cube, place it, release. Pinch it again — it should now rotate (yaw)
  with horizontal slide instead of re-entering carry/follow. A *third* pinch (after releasing the
  rotate) should still rotate, not fall back to carry.
- Explicitly verify picking up and moving the cube to a **new** location still works normally
  before its first placement — this prompt should not change first-pickup behavior at all.

---

## Prompt E — Wave: proximity-gated trigger with a stationary-hold fallback

> Read the plan's §2 (Wave) and §3 (wave-while-pinched, proximity gating). This can run in
> parallel with B and C — independent files, and `WaveDetector` reads only wrist position, never
> finger shape, so it cannot be confused with carry/pinch state.
>
> Implement `WaveDetector`:
> - Reads `x: Double?` (normalized horizontal wrist position) + timestamp only. No pinch/hand-shape
>   input at all — this is what lets it run on a hand that's also mid-pinch.
> - Rolling buffer over `tuning.waveWindow` (~1.0s), copying `PinchRatioCalculator`'s
>   `RollingMinMax` age-based drop pattern.
> - States: `idle → waving(since) → cooldown(until)`. Enters `waving` when reversal count in the
>   window ≥ `tuning.waveMinReversals` (~3) at amplitude ≥ `tuning.waveMinAmplitude` (~4–6cm-
>   equivalent in normalized units — tune against real hand span). Fires `.waved` at
>   `tuning.waveHoldDuration = 2.0` (decided). Progress decays over `tuning.waveProgressDecay`
>   (2–3s) on a gap — never hard-resets to zero.
> - **Stationary-hold fallback**, decided in the plan: holding the wrist within
>   `tuning.waveStationaryRadius` of one point for the same 2.0s also fires `.waved`, via the same
>   progress/decay mechanism, not a second code path if you can avoid it — same timer, different
>   condition for what counts as "in progress."
> - Proximity gating (the brush-to-dirt-patch trigger) is content-layer, not part of this
>   recognizer — `WaveDetector` just detects wave/hold motion whenever the app tells it to run.
>   Don't hardcode a dirt-patch concept into the recognizer itself.
>
> On the cube prototype, add one placeholder target volume (e.g. a small marker on a cube face)
> that the app only listens to `WaveDetector` output near — enough to exercise the proximity-gate
> pattern without building real dirt-patch content.
>
> Wire it in `ARSessionCoordinator+Wave.swift`, reading wrist position every frame regardless of
> pinch state, and feed it on the nil-frame path per Prompt A's setup.
>
> Add wave tuning constants to the Wave `// MARK` block in `GestureTuning.swift`, each with a
> one-line comment on where the starting value came from (match the existing file's standard —
> every constant there explains its provenance).
>
> Write `WaveDetectorTests.swift` in `ManipulationTrackerSettlingTests`' explicit-clock style
> (`frame = 1.0/15.0`): synthetic 2s wave → fires once; 1s wave → no fire; wave with a 2-frame nil
> gap → still fires (decided gap tolerance); slow drift → never fires; carrying-speed lateral
> translation → never fires (this is the collision-avoidance check); stationary hold for 2s →
> fires via the fallback path; cooldown suppresses an immediate second fire.

**Stop and test here.** Confirm before continuing:
- `WaveDetectorTests` passes, all cases above covered, including the stationary-hold fallback.
- On device: waving near the placeholder target for ~2s fires the event; holding still on it for
  2s also fires it; carrying/dragging the cube across the table does **not** false-trigger it.
- Confirm progress doesn't hard-reset on a single dropped frame — pause mid-wave for under a
  second and resume; it should not restart from zero.

---

## Prompt F — Integration pass

> All of B, C, D, E should be merged before this runs.
>
> Read the plan's §1 (gesture gating table) and confirm the actual gating matches it on the cube
> prototype — there's no real showcase/simulation/quiz flow yet, so this is a synthetic check:
> pick two or three explicit "modes" on the cube prototype's existing demo HUD (or add one) that
> stand in for "showcase" and "sim, placed" states, and verify:
> - In a Point-only mode: pinch/carry, rotate, and wave never fire, even if you deliberately try
>   to trigger them.
> - In a Carry-only mode: point/dwell and wave never fire.
> - After first placement (rotate-eligible state): re-grab rotates, not carries; wave still works
>   independent of carry/rotate state (it should — wave reads wrist position only, per Prompt E).
>
> Also verify the full per-frame pipeline order from the plan (§2, "Per-frame pipeline order")
> matches what's actually in `handleVision` now — ratio → overlay → pinch → carry/rotate route →
> point → wave — and that all four new recognizers are still being fed on the nil-frame path (this
> is the one thing most likely to have drifted across four separate build steps — check it
> explicitly, don't assume Prompt A's stub survived unchanged).
>
> Report anything in the plan that didn't survive contact with the real pipeline order, rather
> than silently reconciling it.

**Stop and test here.** Confirm before continuing:
- All four gestures coexist on the cube prototype without cross-talk, per the gating table.
- Full existing test suite (all `HandProbeTests`) passes — this is the first point all five new
  types are in the tree together, and it's where a shared-file conflict from parallel builds
  (`GestureTuning.swift`, `handleVision`) would actually surface.
- Nil-frame / dropped-Vision-frame path confirmed to feed all four new recognizers, not just the
  original pinch machine.

---

## Prompt G — On-device calibration pass

> Read `docs/TESTING.md` for the rig-discipline conventions (fixed mount, fixed distance markers,
> fixed lighting, logged thermal state) — reuse that discipline here rather than inventing a new
> measurement protocol.
>
> Also fold in a 0.7x (ultra-wide) vs. 1x (wide) lens comparison here, not as a separate pass.
> Every existing calibration number (`pinchRatio` threshold 1.98, working-distance assumptions)
> was measured at 1x per ADR-015 — 0.7x changes FOV and distortion, which could shift all of it.
> A feasibility check (can `ARWorldTrackingConfiguration` even target the ultra-wide lens for
> world tracking at all) should already be resolved before this prompt runs; if it's a hard no,
> skip this paragraph entirely and note why. If 0.7x is viable, re-run the distance/confidence
> sweep at 0.7x alongside 1x and report whether thresholds diverge enough to need per-lens tuning.
>
> For each of the four gestures, run a short on-device pass against the plan's threshold table
> (§4) and report where the starting numbers need adjustment for this specific rig/lighting/hand:
> pinch enter/exit hysteresis, annotation hit volume, carry-toggle window, brush-proximity gate,
> wave amplitude/reversal-rate/hold-duration, onboarding stall trigger. Log whichever of these
> already have a `GestureTuning` constant with real device numbers behind it — palmWidth pinch
> ratio (1.98, per ADR-017) is the model to follow: don't leave a placeholder number un-flagged.
>
> This is a tuning pass, not a rebuild — report numbers and recommended constant changes, don't
> restructure any of the five gesture files unless a threshold turns out to be fundamentally
> unworkable (in which case stop and report rather than picking a new design solo).

**Stop here.** This is the last gate before any of this gets used inside a real annotation /
cleaning-sim / quiz flow — those are separate, content-layer work, not part of this track.
