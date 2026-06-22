# OpenDisplay (app)

**macOS app target** (SwiftUI + AppKit). The menu-bar popover (primary surface) and the
settings window, built from `Packages/OpenDisplayDesignSystem`. Hosts the dependency
composition root: `DisplayRegistry`, `TopologyCoordinator`, providers, stores, and the
`RecoveryService` (Reconnect All + global hotkey).

Surfaces (PRD §8.1): menu-bar root, topology workspace, display detail, scenes, automation,
health & recovery, Labs. The UI consumes immutable snapshots and submits commands through the
command gateway — it never mutates domain state directly.

Milestone: **M1 (menu-bar + connect/disconnect) → M3 (Core 1.0)**.

> Stub — Xcode app target added on macOS. Logic lives in the cross-platform packages.
