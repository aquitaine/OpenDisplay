# OpenDisplay — Session Handover

**Last updated:** 2026-06-22 · **Branch:** `claude/trusting-dirac-pewpub` · **HEAD:** `3b9f74a`
· **PR:** #10 (open, ready for review) · **Repo:** `aquitaine/OpenDisplay`

## TL;DR
OpenDisplay is an open-source **macOS** display-management app (Swift 6, SwiftUI/AppKit,
actor-isolated coordinator, provider architecture). Headline feature: **safe logical display
disconnect/reconnect with independent recovery**. The platform-independent core is built and
**unit-tested (42/42)**; the macOS app/providers/CLI/rescue are **scaffolded but not yet
Xcode-compiled**. Pick up by building on a Mac, then start the **M0 safety spike**.

## ⚠️ Environment reality (the local-vs-remote confusion)
All work so far happened in a **Linux cloud container** (Claude Code on the web), **not on a
Mac**. That container has a Linux Swift 6.0.3 toolchain (runs `swift test`) but **no Xcode,
no SwiftUI/AppKit/CoreGraphics**. Consequences:
- The cross-platform packages are **verified** (compiled + tested on Linux Swift 6).
- The macOS-only sources (`Apps/`, `Providers/`, `Tools/`, `Packages/OpenDisplayDesignSystem`)
  were **authored but never compiled** — expect to fix a few first-build errors on the Mac.
- Nothing is on your Mac's disk yet; the code lives only in Git. **This new session should run
  on your Mac** (or a macOS environment) so it can use Xcode.

## Get the code (on your Mac)
```sh
cd ~/Developer                      # or wherever you keep projects
git clone https://github.com/aquitaine/OpenDisplay.git
cd OpenDisplay
git checkout claude/trusting-dirac-pewpub
```

## Build & run (on your Mac)
Full steps in `Docs/MacQuickstart.md`. Short version (needs Xcode 16+ / Swift 6 and Homebrew):
```sh
make bootstrap     # verifies Swift 6 / Xcode
make test          # cross-platform core — expect 42/42
make xcode         # installs XcodeGen via brew, runs `xcodegen generate`
open OpenDisplay.xcodeproj
```
Run the **OpenDisplay** scheme → menu-bar app (LSUIElement, no Dock icon) showing 3 demo
displays + working **Reconnect All**, backed by an in-memory `SimulatedDisplaySystem`.
Headless: `xcodebuild -scheme OpenDisplay build`, `-scheme OpenDisplay-PublicAPIOnly build`,
`-scheme opendisplay build` then `opendisplay list` / `opendisplay recover`.

## Current status
| Area | State |
|------|-------|
| Cross-platform core | ✅ implemented + **42 tests pass** (Swift 6.0.3) |
| Safety logic (SafetyEngine, TopologyCoordinator, state machines) | ✅ implemented + tested; Codex P1s fixed |
| Scene planner, identity scoring, selectors, result schema | ✅ implemented + tested |
| macOS app / providers / CLI / rescue / design system | 🟡 scaffolded, compile-ready stubs, **not Xcode-built** |
| Xcode project (XcodeGen `project.yml`) | ✅ present; generate with `make xcode` (not committed) |
| Remote CI | ❌ removed by design — local `make test` is the gate |
| Real display providers (CoreGraphics / lifecycle) | ⬜ not started — this is M0 |

## Repo layout (94 files)
```
Package.swift              SPM manifest — CROSS-PLATFORM core only (keep Linux-green)
project.yml                XcodeGen spec for the macOS targets (generates OpenDisplay.xcodeproj)
Makefile                   make bootstrap | test | xcode | lint | clean
Packages/
  DisplayDomain/           ✅ models, identity scoring, lifecycle+transaction state machines
  ProviderInterfaces/      ✅ provider protocols + typed failures
  SceneEngine/             ✅ desired-state scene diff/plan (idempotent, safely ordered)
  AutomationSchema/        ✅ stable JSON result envelope + selector grammar
  TopologyCore/            ✅ SafetyEngine + TopologyCoordinator + InMemoryCheckpointStore
  SimulatorProvider/       ✅ in-memory display system + fault injection (tests/previews)
  OpenDisplayDesignSystem/ 🟡 SwiftUI tokens stub + reference/ (the original design kit = source of truth)
Providers/                 🟡 CoreGraphics, DDC, NativeControl, Capture, ExperimentalLifecycle, VirtualDisplay (stubs)
Apps/OpenDisplay/          🟡 menu-bar app (OpenDisplayApp, AppModel, MenuBarView, SettingsView)
Apps/OpenDisplayRescue/    🟡 independent rescue app
Tools/opendisplay/         🟡 CLI (list/recover stub; ArgumentParser + full grammar in M1)
Docs/                      PRD.md (normative spec), Architecture/, Recovery/, Compatibility/, RFCs/, MacQuickstart.md
Tests/                     Fixtures/, HardwareLab/ (placeholders for M0+)
```
Tests live in `Packages/<Name>/Tests`. `make test` runs all 42.

## Architecture (1-minute version)
`DisplayRegistry` (observed truth, actor) → `TopologyCoordinator` (the **only** writer of
topology/lifecycle, actor) which runs every disconnect as a staged transaction:
**resolve → preflight (SafetyEngine) → checkpoint → confirm → apply (provider) → observe →
verify → commit/rollback.** Providers sit behind protocols (`ProviderInterfaces`); the
experimental lifecycle + virtual-display providers are separable and excluded from the
public-API-only build. Provider success ≠ product success — outcomes are verified or reported
`unverified`. Details: `Docs/Architecture/overview.md`, `Docs/Recovery/recovery.md`, PRD §9–§10.

## Key invariants (don't weaken without an RFC) — PRD §9.2
One active transaction at a time · no disconnect without an atomic checkpoint · never remove
the last safe recoverable display by default · success only after observed postconditions ·
Reconnect All preempts + works from an independent process · safe mode disables experimental
providers first.

## Decisions & open questions
- **Accepted:** Core/Labs split (D-001), Apple Silicon lifecycle baseline (D-002), disconnect
  is a transaction (D-003), standalone rescue utility (D-004), reconnect-on-quit default
  (D-005), no analytics (D-006), Developer ID signed/notarized distribution (D-007),
  public-API-only build path (D-008), stable IDs + scored fingerprints (D-009), verify-not-assume
  (D-010). Full list: `Docs/Architecture/decisions.md`.
- **Proposed/legal:** GPL-3.0-or-later (D-011), project name "OpenDisplay" (D-012).
- **Open (need you/legal):** certified OS/Mac matrix (Q-001), private-API/entitlement set
  (Q-002), rescue process topology/IPC (Q-003), default recovery hotkey (Q-004), license/SDK
  boundary (Q-005). The app/rescue entitlements currently set `app-sandbox = false` pending Q-002.

## GitHub
- **PR #10** open (ready for review). Codex left 3 P1s on `TopologyCoordinator` — all fixed in
  `b6ca341` (non-bypassable blocked preflights; fail-safe default confirm handler; verify "no
  unexpected endpoint lost").
- **Epics #1–#9** track the roadmap, labeled by milestone (`M0`…`M4`). NOTE: GitHub *milestone
  objects* couldn't be created via tooling — they're encoded as labels; create real milestones
  in the UI if you want them.
- **No remote CI** (removed). Verify locally with `make test` before pushing.

## What the new (Mac) session should do first — M0 safety spike
1. Build the scaffold (`make xcode` → run **OpenDisplay**); fix any first-build compile issues.
2. **CoreGraphicsProvider**: real display enumeration + a `TopologyObserving` event source;
   swap into `Apps/OpenDisplay/Sources/AppModel.swift` in place of `SimulatedDisplaySystem`.
3. **ExperimentalLifecycleProvider**: logical disconnect/reconnect spike on Apple Silicon;
   wire behind `#if !PUBLIC_API_ONLY`; verify the full coordinator path on real hardware.
4. Disk-backed, rescue-readable `CheckpointStore` + global Reconnect-All hotkey; finish the
   rescue app end-to-end.
5. Port design-system components + the 11 menu-bar states from
   `Packages/OpenDisplayDesignSystem/reference/`.
6. Hardware certification (PRD §15), fault/recovery subset first (T-006/007/008/017/021).

The detailed full-lifecycle plan is in the PRD (`Docs/PRD.md`) §19 and the architecture docs.

## Gotchas
- Keep `Package.swift` cross-platform (no macOS imports) so `make test` runs without Xcode.
  macOS code lives outside SPM target paths and is built only by Xcode.
- The generated `OpenDisplay.xcodeproj` is **git-ignored** — regenerate with `make xcode`.
- Provider files are guarded by `#if os(macOS)`; the CLI `main.swift` uses top-level `await`.
- On macOS, if `swift --version` shows 5.x, run `sudo xcode-select -s /Applications/Xcode.app`.

## Kickoff prompt for the new session (paste this)
> I'm continuing the OpenDisplay project on my Mac (Xcode 16, Apple Silicon). The repo is
> checked out on branch `claude/trusting-dirac-pewpub`. Read `Docs/HANDOVER.md` and
> `Docs/MacQuickstart.md`, then: run `make test` (expect 42/42), `make xcode`, build & run the
> OpenDisplay scheme, and fix any compile issues. After it runs, start the M0 safety spike —
> implement a real `CoreGraphicsProvider` (display enumeration + `TopologyObserving`) and wire
> it into `AppModel`. Verify with `make test` before any push.
