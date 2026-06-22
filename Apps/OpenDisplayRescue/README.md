# OpenDisplay Rescue

**macOS target — independent, minimal-dependency, signed/notarized.** A standalone rescue
app + CLI that can reconnect managed-offline displays, disable auto-apply policies, restore a
checkpoint, and launch safe mode **even when the main app is corrupt, crashed, or displayed on
the very screen being removed** (PRD LIF-011, DIA-010, D-004).

Reads the rescue-readable `CheckpointStore` format directly. Its safety/restore logic reuses
`Packages/DisplayDomain` + `Packages/TopologyCore` and the `LifecycleProvider.recover(to:)`
contract. Rescue work always preempts ordinary queued operations.

Milestone: **M0 (proof) → M2 (shipped)**.

> Stub — Xcode target added on macOS. Process topology / IPC auth is open question Q-003.
