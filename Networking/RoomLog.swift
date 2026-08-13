import os

/// Room events are low-frequency — connect, roster change, phase change — so unlike the
/// per-frame AR path in `CoralAR` they can be logged unconditionally. `Logger` rather than
/// `print`, per AGENTS.md's performance rules.
nonisolated let roomLog = Logger(subsystem: "com.ada.ch5b.CoralAR", category: "rooms")
