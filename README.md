# Ch5B — Coral AR Placement Experiment

## Project

An experimental iOS AR app in which the rear camera watches the user's hands while the phone sits on a desk stand, and hand gestures place, scale, and yaw-rotate a 3D coral model on a real detected flat surface. Target device: iPhone 17 base (non-LiDAR). Stack: native Swift with ARKit, RealityKit, and Vision Framework for hand pose detection. This is a de-risking experiment to measure feasibility, not a product; the goal is a defensible yes/no answer reached in the first two weekends.

**Current phase:** 0

## Documentation

| Document | Purpose | When to read |
|---|---|---|
| [`RESEARCH.md`](docs/RESEARCH.md) | Hardware facts, feasibility analysis, and evidence | Start here if evaluating whether this is possible |
| [`PRD.md`](docs/PRD.md) | What the experiment is, what success looks like, pass thresholds | Before building; defines the end state |
| [`STEPS.md`](docs/STEPS.md) | Six build phases with acceptance criteria for each | Reference during development; phases are sequential |
| [`AGENTS.md`](docs/AGENTS.md) | Stack, versions, coding rules, and phase constraints | Before writing code |
| [`ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Intended system design and data flow | After understanding the scope; reference when structuring classes |
| [`DECISIONS.md`](docs/DECISIONS.md) | ADR-style log of all technical decisions with status | When evaluating trade-offs or reconsidering design choices |
| [`TESTING.md`](docs/TESTING.md) | How to validate each phase, test procedures, and pass criteria | At the start of each phase; defines what "done" means |
| [`PROMPTS.md`](docs/PROMPTS.md) | Ready-to-send prompts, one per phase, plus analysis and recurring prompts | Every time you start a phase; copy the matching prompt |
