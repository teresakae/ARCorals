# Ch5B — Coral AR Placement Experiment

## Project

An experimental iOS AR app for **roaming handheld use**: the user walks with the phone, the rear camera watches the free hand, and hand gestures place, scale, yaw-rotate and carry a 3D object on a real detected flat surface. (Early de-risking and pinch calibration used a desk/tripod stand; that rig is not how the app is used. Same binary, no code fork.) Target device: iPhone 17 base (non-LiDAR). Stack: native Swift with ARKit, RealityKit and the Vision framework for hand pose detection. This is a de-risking experiment to measure feasibility, not a product — the goal is a defensible yes/no answer.

**Status:** the original build phases 0–5 are complete and verified. Phase 6 (swapping the cube placeholder for a real `coral.usdz`) was never built; work moved instead to a gesture track — Point, Carry, Rotate and Wave — built on the cube prototype. The content layer has not started. A **local peer-to-peer room layer** (4-digit code, up to 4 players, one host) was added alongside it and is what the app now opens on; it does not yet share any AR state. See [`PROJECT.md`](docs/PROJECT.md) for scope, [`GESTURES.md`](docs/GESTURES.md) for per-gesture state, and [`ARCHITECTURE.md`](docs/ARCHITECTURE.md) §8 for the room layer.

## Layout

One app target, `CoralAR`, one `@main`. It opens on the room screens and AR is entered from the session screen.

| Path | What |
|---|---|
| `CoralARApp.swift` | The `@main`. Opens `RoomFlowView`; a one-line `startInARDirectly` skips to AR |
| `Info.plist` | Camera, local-network and Bonjour keys. **Generated from `project.yml` — edit there** |
| `Networking/` | Peer-to-peer transport, discovery, packet framing. Imports no ARKit/RealityKit |
| `Model/` | Room state, roster, wire protocol, and the `ARPayloadChannel` seam |
| `Views/` | Placeholder SwiftUI room screens |
| `CoralAR/` | The AR pipeline — hand pose, gestures, placement |
| `HandProbe/` | Throwaway measurement harness, its own target |

`project.yml` is the source of truth for the Xcode project. After editing it, run `xcodegen generate`.

## Documentation

| Document | Purpose | When to read |
|---|---|---|
| [`PROJECT.md`](docs/PROJECT.md) | What the experiment is, what it answered, non-goals, prior art, live risks | Start here — scope and why this is built the way it is |
| [`AGENTS.md`](docs/AGENTS.md) | Stack, hard constraints, coordinate gotchas, known traps, performance rules | Before writing any code |
| [`ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Module breakdown, data flow, concurrency model, fragile seams | When structuring or changing code |
| [`GESTURES.md`](docs/GESTURES.md) | Per-gesture status and history, tuning constants with provenance, on-device checklists | Every test session — check before re-tuning anything |
| [`DECISIONS.md`](docs/DECISIONS.md) | ADR log of every technical decision, including the rejected options | Before reconsidering a design choice or proposing an alternative |

`Measurements/` holds the CSV logs pulled off the device. They are the evidence behind the calibrated constants — ADRs cite them by filename.
