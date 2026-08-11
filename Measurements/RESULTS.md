# RESULTS — Gesture-track calibration (Prompt G)

**Date:** 2026-08-11
**Phase / track:** Gesture build track (Point / Carry / Rotate / Wave), cube prototype — final gate before content-layer work
**Device:** iPhone 17 base (non-Pro), iOS 26
**Rig (from `docs/GESTURE_LOG.md` + `docs/TESTING.md` §0):** phone eye-level, ~45° tilt down, hand enters from behind/below, **30–40cm** working distance, landscapeRight, palm generally toward camera. Fixed mount / lighting / one hand — same discipline as Phase 0–5. Discard runs where `ProcessInfo.thermalState` exceeds `.fair`.

**This pass is inventory + feasibility + recommendation, not a fresh CSV sweep.** No new on-device measurement CSVs were produced in this session. Numbers below either cite existing ADR/CSV evidence, the D–F ad-hoc bumps already in the tree, or are explicitly flagged as still-unmeasured plan placeholders.

---

## 0.7x (ultra-wide) vs 1x (wide) — SKIPPED (hard no)

**Verdict:** do not run a 0.7x distance/confidence sweep. Per-lens tuning is N/A.

**Why:** `ARWorldTrackingConfiguration.supportedVideoFormats` only exposes `builtInWideAngleCamera` (1×) formats for world tracking. Apple's own `captureDeviceType` docs show selecting `builtInUltraWideCamera` against **`ARFaceTrackingConfiguration`**, not world tracking. Forum consensus for rear-camera world tracking / `ARSCNView` / RealityKit world sessions: no supported way to drive the ultra-wide as the ARKit primary camera ([thread 712533](https://developer.apple.com/forums/thread/712533), [thread 765555](https://developer.apple.com/forums/thread/765555)).

A multi-cam workaround (`AVCaptureMultiCamSession` on ultra-wide for Vision alongside ARKit's 1× session) would break the single-`ARFrame` pipeline this app is built on (ADR-002 / ADR-011 thermal budget) and is out of scope for a tuning pass.

All existing calibration (ADR-015 / ADR-017, `pinchThreshold = 1.98`) remains **1×-only**.

---

## Plan §4 threshold table vs live constants

Provenance tags (ADR-017 model):
- **measured** — CSV-backed, cited
- **ad-hoc** — direction confirmed on device between D–F, exact value not from a sweep
- **plan placeholder** — copied from plan §4 / §2, never measured on this rig
- **not in tree** — plan row has no code yet (content-layer)

| Plan §4 parameter | Plan start | Live value | Location | Provenance | Recommendation |
|---|---|---|---|---|---|
| Pinch enter | &lt; 2.5cm raw | ratio enter `1.98 − 0.5 = 1.48` | `GestureTuning.pinchEnterThreshold` | **measured** — ADR-017, `phase4_join_20260809_174233.csv` + static-hold confirm `…_180023.csv` | **Keep.** Do not touch without a new ARFrame static-hold CSV. |
| Pinch exit | &gt; 4.0cm raw | ratio exit `1.98 + 0.5 = 2.48` | `pinchExitThreshold` / `hysteresisBand = 1.0` | **measured** (threshold); band confirmed in ADR-017 addendum | **Keep.** |
| Annotation hit volume | ≥ 4.4cm @ 1m | `hitRadius = 0.035` m (Ø 7cm) | `SceneController.addAnnotation` | **ad-hoc** 0.022→0.035 | **Keep 0.035 as starting point.** Validate with a 20-trial point-mode miss/hit count at working distance before changing again. |
| Carry-toggle window | ≤ 0.5s | `carryToggleMaxDuration = 0.7` s | `GestureTuning` | **ad-hoc** 0.5→0.7 (0.5 too tight for deliberate pick-up) | **Keep 0.7.** Proper refine = log began→ended durations for ~20 toggles + ~20 grab-drags in Carry mode; pick the gap that separates them. |
| Translation deadzone | 2cm | — | — | **not in tree** | Move/Carry use absolute-from-grab follow (`moveSmoothing = 1.0`), no metric creep deadzone. Add only if placed objects visibly creep while idle. |
| Rotate yaw gain | 12.0 | `horizontalSlideGain = 12.0` | `GestureTuning` | **measured-ish** — shipped + tuned Phase 5 (`GESTURE_LOG` §3); still marked provisional in comment | **Keep.** Re-touch only if Carry-mode re-grab yaw overshoots/undershoots targeting. |
| Brush proximity gate | 5–8cm | `waveProximityRadiusPt = 220` pt | `ARSessionCoordinator+Wave` | **ad-hoc** 130→220; **unit mismatch** (screen points, not cm) | **Keep 220pt** until a real dirt-patch hit volume exists. Do not pretend it's 5–8cm. Content layer should replace with a world-space radius. |
| Wave stroke amplitude | ≥ 4–6cm | `waveMinAmplitude = 0.05` (norm. width frac.) | `GestureTuning` | **plan placeholder** | Needs a real hand-span → normalized-x conversion at 30–40cm. Do not change until measured. |
| Wave reversal rate | 1.5–3/s | `waveMinReversals = 3` in `waveWindow = 1.0` s | `GestureTuning` | **plan placeholder** | Same — measure reversals/s on deliberate waves vs carry-drag false positives. |
| Wave hold duration | 2.0s | `waveHoldDuration = 2.0` | `GestureTuning` | **decided** (plan), unmeasured feel | **Keep 2.0** unless demos feel slow; then try 1.5 before redesign. |
| Wave progress decay | 2–3s full | `waveProgressDecay = 2.5` | `GestureTuning` | **plan placeholder** (mid-band pick) | Keep until gap-resume tests say otherwise (Prompt E already unit-tests 2-frame gaps). |
| Dirt / pests per session | 3 each | — | — | **not in tree** (content) | Out of scope. |
| Annotation fade band | 60°→100° | — | — | **not in tree** | Out of scope until facing-angle UX ships. |
| Onboarding stall trigger | 10–15s | — | — | **not in tree** | No ghost-hand / stall timer in the cube prototype. Defer to content onboarding. |

### Related constants not in plan §4 (still flag)

| Constant | Value | Provenance |
|---|---|---|
| `pointDwellDuration` | 0.4s | plan §2 / matches `dwellDuration`; **plan placeholder** for annotation feel |
| `waveStationaryRadius` | 0.02 | half of `waveMinAmplitude` guess; **plan placeholder** |
| `waveCooldownDuration` | 2.0s | = hold duration, not in plan; **plan placeholder** |
| `okSignFingerExtendedRatio` | 1.2 | unused path; **plan placeholder** (GESTURE_LOG: OK-sign removed) |
| `moveSmoothing` | 1.0 | Carry 1:1 decision; **unverified** jitter on device |
| Rotate scope | `.carry` only | **by design** (Prompt G note) — `.sim` never rotates |

---

## Per-gesture short-pass checklist (still to run on device)

Reuse TESTING.md rig discipline. One hand, fixed mount, log thermal. Modes: Point / Carry / Sim.

### Point (Point mode)
1. 20 deliberate points at the yellow annotation marker — count dwell→popup successes.
2. 20 deliberate mid-pinch / open-hand near the marker — count false popups (should be ~0; shape gate).
3. If miss rate &gt; ~20% at 0.035m hitRadius, bump again; if false hits appear, tighten.

### Carry + rotate (Carry mode)
1. 20 short toggle pinches — all should pick up / put down (validates 0.7s window).
2. 10 deliberate long grab-drags (&gt;0.7s) — must **not** toggle.
3. After first put-down: re-pinch → yaw via horizontal slide; third pinch still rotates.
4. First-pickup before any put-down still carries (unchanged).

### Wave (Sim mode)
1. Wave ~2s near cube top — HUD `waveCount` increments once.
2. Stationary hold ~2s on target — also fires (fallback).
3. Carry/drag across table — must **not** fire.
4. Pause mid-wave &lt;1s and resume — progress should not hard-reset.

### Pinch enter/exit (any mode that pinches)
Already ADR-017-backed. Only re-open if open-hand false-pinches return; then new static-hold CSV, not a guess.

---

## Recommended constant changes from this pass

| Action | Constant | Change |
|---|---|---|
| None (keep) | `pinchThreshold` / `hysteresisBand` | 1.98 / 1.0 |
| None (keep pending validate) | `carryToggleMaxDuration` | 0.7 |
| None (keep pending validate) | `hitRadius` | 0.035 |
| None (keep pending validate) | `waveProximityRadiusPt` | 220 |
| None (keep) | `horizontalSlideGain` | 12.0 |
| None (keep) | `waveHoldDuration` | 2.0 |
| **Do not invent** | `waveMinAmplitude` / `waveMinReversals` / `waveProgressDecay` | leave plan placeholders until the checklist above produces numbers |
| **Do not add** | translation deadzone, stall timer, fade band | not needed until content layer asks |

**No gesture-file restructure.** Nothing in the threshold set looks fundamentally unworkable from prior device feedback; the three looser ad-hoc bumps already moved in the right direction.

---

## Pass / fail / pivot

| Item | Outcome |
|---|---|
| 0.7x lens comparison | **Skipped — hard no** (ARKit world tracking is 1×-only) |
| Threshold inventory + provenance flags | **Done** |
| Fresh on-device CSV sweep for Point/Carry/Wave | **Not run this session** — checklist above is the remaining human pass |
| Gesture redesign | **Not required** |

Surprising / important: brush proximity is still a **screen-point** radius, not the plan's 5–8cm world gate — fine for the cube prototype, must not silently become a content-layer constant without a unit conversion.
