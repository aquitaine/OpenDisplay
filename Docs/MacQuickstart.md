# macOS Quickstart (Claude Code on your Mac)

This repo's cross-platform core was built and tested on Linux; the **macOS app, providers,
rescue utility, CLI, and design system are built on a Mac**. Use this to pick up on macOS.

Pick up from branch **`claude/trusting-dirac-pewpub`** (PR #10). The cross-platform core has
42 passing tests; the Xcode targets are scaffolded (XcodeGen) and wired to an in-memory
`SimulatedDisplaySystem`, so the app runs before the real providers exist.

## Prerequisites
- **Xcode 16+** (Swift 6). Verify: `swift --version` → 6.x. If it shows 5.x, run
  `sudo xcode-select -s /Applications/Xcode.app`.
- **Homebrew** (used to install XcodeGen).

## Get it running (turnkey)
```sh
git fetch origin
git checkout claude/trusting-dirac-pewpub && git pull

make bootstrap        # verifies Swift 6 / Xcode
make test             # cross-platform core — expect 42/42 passing

make xcode            # installs XcodeGen via Homebrew, runs `xcodegen generate`
open OpenDisplay.xcodeproj
```
In Xcode, run the **OpenDisplay** scheme: a menu-bar app appears (no Dock icon — it's an
`LSUIElement` agent) showing three demo displays with a working **Reconnect All**.

Headless equivalents:
```sh
xcodebuild -scheme OpenDisplay build
xcodebuild -scheme OpenDisplay-PublicAPIOnly build   # public-API-only flavor (NFR-010)
xcodebuild -scheme opendisplay build
# then:
opendisplay list      # ● disp_builtin (main) / ● disp_studio / ○ disp_lg
opendisplay recover   # reconnects managed-offline displays
```

> The macOS sources (`Apps/`, `Providers/`, `Tools/`, `Packages/OpenDisplayDesignSystem`)
> were authored on Linux and have **not** been Xcode-compiled. Expect to fix a few
> compile issues on first build — that's the point of moving to the Mac.

## First M0 tasks (in order)
See the [PRD](PRD.md) §9–§10 and the architecture/recovery docs.
1. **CoreGraphicsProvider** — real display enumeration + a `TopologyObserving` event source;
   swap it into `Apps/OpenDisplay/Sources/AppModel.swift` in place of `SimulatedDisplaySystem`.
2. **ExperimentalLifecycleProvider** — logical disconnect/reconnect spike on Apple Silicon;
   wire into the app behind `#if !PUBLIC_API_ONLY`; verify the full `TopologyCoordinator` path
   (preflight → checkpoint → apply → verify → commit/rollback) on real hardware.
3. **Disk-backed, rescue-readable `CheckpointStore`** + the global Reconnect-All hotkey; finish
   `OpenDisplayRescue` end-to-end (reads the checkpoint independently of the main app).
4. **Design-system port** — components + the 11 menu-bar states from
   `Packages/OpenDisplayDesignSystem/reference/`.
5. **Hardware certification** — PRD §15, starting with the fault/recovery subset
   (T-006/T-007/T-008/T-017/T-021).

## Verification
`make test` → 42/42; `xcodebuild -scheme OpenDisplay build` and
`-scheme OpenDisplay-PublicAPIOnly build` succeed; the menu-bar app runs and Reconnect All
works; `opendisplay list`/`recover` print the expected output. The fault-injection + recovery
suite is the release gate (PRD §16.2).
