# OpenDisplay

Open-source display management for macOS.

OpenDisplay gives predictable, **safe** control over multiple displays: a stable
registry and topology model, scenes (desired-state snapshots), brightness/audio/input
controls over native and DDC routes, and — its defining capability — **safe logical
display disconnect/reconnect with independent recovery**. You can remove a supported
display from the active desktop without unplugging it, and always get it back, even if
the disconnected screen was the one showing the app.

> **Status: pre-1.0, in active bring-up.** The product, architecture, and scope are
> defined in the [PRD](Docs/PRD.md). The platform-independent core (domain models,
> state machines, scene planner, safety engine, automation schema) ships with unit
> tests, and the macOS app is functional and verified on Apple Silicon hardware:
> a menu-bar UI with live **brightness** (built-in via DisplayServices, external via
> DDC/CI), **hardware controls** (contrast/volume over DDC), **mirroring**, **display
> modes** (resolution / refresh rate / HiDPI), **software dimming** (gamma, any
> display), **scenes**, and **safe logical disconnect** with an always-one-display-active
> guarantee and an automatic fall-back to the built-in panel. The rescue utility, the
> `opendisplay` CLI, and Shortcuts/Siri intents drive the same safety-checked, audited path.

> Functional reference only: BetterDisplay. OpenDisplay is an independent, clean-room
> project — no BetterDisplay name, assets, copy, UI cloning, or proprietary code. It is
> not affiliated with or endorsed by BetterDisplay.

## Principles

- **Safety before capability** — a feature that can make the desktop unreachable is
  incomplete until recovery is independently usable.
- **Observed state ≠ desired state** — we record what macOS reports, what you want, and
  who changed it.
- **Verify, do not assume** — a provider call is not success; outcomes are verified via
  OS events / read-back, or reported as `unverified`.
- **Open by default, risky by consent** — experimental system behavior is opt-in,
  reversible **Labs**, and never a dependency of normal startup or recovery.

## Repository layout

```
Apps/OpenDisplay            Menu-bar + settings app (SwiftUI/AppKit)        [macOS, Xcode]
Apps/OpenDisplayRescue      Independent signed rescue app + CLI             [macOS, Xcode]
Tools/opendisplay           Automation CLI                                  [macOS]
Packages/DisplayDomain      Models, identity scoring, state machines        [cross-platform] ✅ tested
Packages/ProviderInterfaces Provider protocols + typed failures            [cross-platform] ✅
Packages/SceneEngine        Desired-state scenes: diff/plan/idempotency     [cross-platform] ✅ tested
Packages/AutomationSchema   Stable JSON result/selector schema              [cross-platform] ✅ tested
Packages/TopologyCore       SafetyEngine + transaction coordinator          [cross-platform] ✅ tested
Packages/SimulatorProvider  In-memory provider for tests/previews           [cross-platform] ✅
Packages/OpenDisplayDesignSystem  SwiftUI port of the design kit            [macOS]
Providers/*                 CoreGraphics, DDC, NativeControl, Capture,
                            ExperimentalLifecycle (optional), VirtualDisplay (Labs)  [macOS]
Docs/                       Architecture, Recovery, Compatibility, RFCs, ADRs, PRD
Tests/                      Fixtures + hardware-lab evidence
```

## Building & testing

Local-first: the platform-independent core builds and tests anywhere a **Swift 6**
toolchain is installed (macOS Xcode 16+ or Linux).

```sh
make bootstrap   # ensure a Swift 6 toolchain (installs it on Ubuntu; checks Xcode on macOS)
make test        # swift build && swift test --parallel   (42 unit/state-machine tests)
make lint        # SwiftLint, if installed
```

`make` with no target runs the tests. See `make help` for all targets. (`./scripts/test.sh`
also works if you prefer not to use make.) There is **no remote CI** — local `make test` is
the verification gate.

### Building the macOS app (on a Mac)

The app, rescue utility, CLI, design system, and providers are macOS targets generated from
[`project.yml`](project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen). The
generated `OpenDisplay.xcodeproj` is **not committed** — regenerate it locally:

```sh
make xcode                 # installs XcodeGen if needed, runs `xcodegen generate`
open OpenDisplay.xcodeproj  # build & run the OpenDisplay menu-bar app
# or headless:
xcodebuild -scheme OpenDisplay build
xcodebuild -scheme OpenDisplay-PublicAPIOnly build   # public-API-only flavor (NFR-010)
```

The app runs immediately against the in-memory `SimulatedDisplaySystem`; the real
`CoreGraphicsProvider`/`ExperimentalLifecycleProvider` land in the M0 spike. All macOS targets
depend on the cross-platform packages through the protocols in `ProviderInterfaces`.

## Documentation

- [Product Requirements Document](Docs/PRD.md) — the normative spec.
- [macOS Quickstart](Docs/MacQuickstart.md) — build & run the app on a Mac.
- [Architecture overview](Docs/Architecture/overview.md)
- [Recovery model](Docs/Recovery/recovery.md)
- [Architecture decisions](Docs/Architecture/decisions.md)
- [Contributing](CONTRIBUTING.md) · [Security policy](SECURITY.md) · [Code of conduct](CODE_OF_CONDUCT.md)

## Roadmap

Delivery is milestone-based: **M0** safety spike → **M1** developer preview → **M2**
alpha → **M3** beta / Core 1.0 → **M4** Core 1.x, with **Labs** as a parallel gated
track. See the [milestones](https://github.com/aquitaine/opendisplay/milestones) and
the architecture docs.

## License

GPL-3.0-or-later (see [LICENSE](LICENSE)). A separately packaged provider/automation SDK
may adopt a permissive license in the future, subject to maintainer and legal review.
