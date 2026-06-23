# Changelog

All notable changes to OpenDisplay are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/). OpenDisplay is pre-1.0 (0.x); anything may
change until 1.0.

## [0.1.0] — 2026-06-23

First developer preview. The platform-independent safety core (domain models, state
machines, scene planner, `SafetyEngine`, serialized `TopologyCoordinator` with
checkpoint/rollback) is unit-tested (78 tests), and the macOS menu-bar app is functional
and verified on Apple Silicon hardware.

### Added
- Menu-bar app with a unified **brightness** slider (built-in via DisplayServices, external
  via DDC/CI, software-gamma fallback), **hardware controls** (contrast / volume / input /
  colour preset over DDC/CI), **mirroring**, **resolution / refresh / HiDPI** switching, a
  drag-to-arrange canvas, **per-display ICC colour profiles** (public ColorSync), **Black
  Out**, and **software dimming**.
- **Safe logical disconnect / reconnect** with an always-one-display-active guarantee,
  persisted managed-offline tracking, automatic fall-back to the built-in panel, and
  independent recovery (menu, the global ⌃⌥⌘R hotkey, and a separate `OpenDisplayRescue` app).
- **Scenes**: capture and re-apply display arrangements.
- `opendisplay` **CLI** and **Shortcuts/Siri** intents that drive the same audited,
  safety-checked command path as the UI.
- **Labs:** opt-in experimental display rotation through an isolated helper process — off by
  default and compiled out of the public-API / App Store build.

### Distribution
- Release builds are **Developer ID-signed, hardened-runtime, and notarized** by Apple, so
  the download opens with no Gatekeeper workaround. Reproducible via `make release-signed`
  (`scripts/release-signed.sh`).

### Performance
- Apple-Silicon optimisation pass: private SPI (DisplayServices), DDC/CI controller
  construction, ColorSync iteration, and EDID fingerprinting moved off the main thread;
  batched registry persistence (one write per topology event instead of one per display);
  cached display-mode enumeration in the detail pane; opt-in reconfiguration-callback
  registration that also closes a callback/deinit race; pruned DDC handle caches across
  reconnects. Removed a dead control-provider abstraction and other unused code.

### Foundations
- Project scaffolding: SPM monorepo with platform-independent domain packages
  (`DisplayDomain`, `ProviderInterfaces`, `SceneEngine`, `AutomationSchema`,
  `TopologyCore`) plus `SimulatorProvider`, and their unit tests.
- Safety core: lifecycle & transaction state machines, `SafetyEngine` (safe-surface and
  preflight rules), `IdentityScorer` (multi-signal confidence), and the serialized
  `TopologyCoordinator` with checkpoint/rollback.
- `SceneEngine` desired-state planner with deterministic, idempotent, safely-ordered diffs.
- Stable `AutomationSchema` JSON result envelope and selector grammar.
- Initial documentation (architecture, recovery model, decisions, PRD) and open-source
  governance (contributing, security, code of conduct, RFC and issue/PR templates).
- macOS target scaffolding for the app, rescue utility, CLI, providers, and design system.
- Local-first developer tooling: `Makefile` (`make bootstrap`/`build`/`test`/`lint`/`xcode`)
  and `scripts/bootstrap-swift.sh` to install a Swift 6 toolchain on Ubuntu / verify Xcode on macOS.
- Xcode project scaffolding via XcodeGen (`project.yml`, `scripts/generate-xcodeproj.sh`,
  `make xcode`): macOS app + public-API-only variant, rescue app, CLI, design-system and
  provider frameworks, with compile-ready stubs wired to the `SimulatorProvider`.

### Changed
- Hardened the disconnect transaction after review: `.blocked` preflights are non-bypassable
  (removed the `userOverride` escape hatch); the confirmation handler now defaults to *cancel*
  rather than silently approving `.needsConfirmation`; and verification now rolls back if any
  unrelated active display is unexpectedly lost, not only the target (PRD §9.2/§9.4).
- Verification is now **local-first**: removed the remote GitHub Actions CI workflow; run
  `make test` locally before pushing.
