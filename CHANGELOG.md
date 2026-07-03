# Changelog

All notable changes to OpenDisplay are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/). OpenDisplay is pre-1.0 (0.x); anything may
change until 1.0.

## [Unreleased]

### Added
- **Adaptive Display (Labs, opt-in):** transfer the built-in display's intelligence to external
  monitors. **Brightness sync** mirrors the built-in panel's ambient-light-driven brightness to
  the external's real backlight over DDC (learned offset from your manual tweaks, one-minute
  hands-off after a manual change, schedule-curve fallback with the lid closed). **Evening
  warmth** switches the monitor's hardware colour preset in the evening and back each morning —
  following macOS Night Shift's live state when readable (best effort, private CoreBrightness),
  otherwise a configurable schedule. The daytime preset is remembered and restored on quit,
  disable, next morning, and even across a crash or relaunch mid-evening. Adaptive changes are
  silent (no OSD) and never write to displays without working DDC.

## [0.3.0] — 2026-07-02

Third developer preview: keyboard media keys drive external-monitor hardware with a
native-style on-screen HUD, and the DDC/CI engine got substantially more robust — it now
identifies the right monitor by EDID identity and recovers replies other readers miss.
240 unit tests (up from 192); hardware paths attended-verified on Apple Silicon against a
Samsung ultrawide, including a full brightness write/read-back/restore round-trip.

### Added
- **Media keys (opt-in):** press the keyboard's brightness keys and OpenDisplay changes the
  *external monitor's real backlight* over DDC/CI — macOS-style 1/16 steps, ⇧⌥ fine steps,
  and a native-looking HUD drawn by the app. Target the display under the cursor, the main
  display, or the built-in. Needs Accessibility once; the app now shows the prompt when the
  feature is on, then arms itself the moment the grant lands — no relaunch.
- **More hardware controls:** sharpness and red/green/blue gain sliders appear automatically
  on monitors that answer them, alongside contrast and volume.
- **Raw VCP access in the CLI:** `opendisplay ddc <display> vcp 0xNN [value]` reads or writes
  ANY MCCS feature code — every control a monitor implements is reachable without a rebuild.
  Plus named features: `sharpness`, `red`, `green`, `blue`, and `mute` (accepts on/off).

### Changed
- **DDC binds to the right monitor by identity, not port order:** the display's EDID
  vendor/model/serial is scored against IORegistry attributes, so multi-monitor setups,
  docks, and identical panels get the correct I2C channel (order remains the fallback).
- **DDC reads recover misaligned replies:** wide reads with an in-buffer, checksum-validated
  frame scan — panels that prefix replies with stale bytes no longer read as "unsupported".
- **DDC transactions are truly serialized** (FIFO bus turnstile + paced inter-transaction
  gaps): concurrent slider drags and refreshes can never interleave on the I2C bus, and a
  lone write no longer pays a fixed trailing delay.
- **Fast menus on partial hardware:** features a panel repeatedly fails to answer are
  negatively cached (with a periodic recheck), instead of re-paying ~0.7s of retried I2C per
  absent control on every open.

### Fixed
- Hardware controls are rediscovered automatically on display reconfiguration and when a
  display's settings pane opens — a monitor whose DDC comes back (port switch, power-cycle)
  shows its controls without an app restart.
- Recovering from software dimming to hardware brightness lifts the leftover gamma dim, so
  the panel can't end up double-dimmed; Black Out is never overridden by background refreshes
  or colour-profile changes.
- Colour-mode menus offer the panel's advertised preset codes when capabilities are known,
  instead of guessing a contiguous range the monitor may ignore.
- CLI DDC writes validate their range (0–65535) instead of silently truncating; the
  capabilities read (`ddc … caps`) is documented as diagnostic-only — it can permanently
  wedge some monitors' DDC engines (observed on a Samsung HDMI port).

## [0.2.0] — 2026-06-24

Second developer preview. Two batches of display-management features land on top of the
0.1.0 safety core, plus a fix for Set-as-Main and a set of menu-bar UX fixes. The
platform-independent logic is unit-tested (192 tests, up from 78); hardware paths were
attended-verified on Apple Silicon.

### Added
- **Keep displays awake while an external is connected** — opt-in IOKit power assertion so
  the Mac/displays don't sleep while docked.
- **DDC power control** (VCP `0xD6`): put an external monitor into standby / wake it from
  the menu and CLI.
- **`opendisplay://` URL-scheme automation** — drive the same audited, safety-checked command
  path from URLs (confirmation-gated for destructive verbs).
- **Resolution slider** replacing the dropdown — scrub through the panel's modes by scale.
- **Timed auto-revert safety gate** for arrangement changes: a "Keep these display settings?"
  countdown that reverts on its own if you don't confirm.
- **Auto-disconnect the built-in** when an external connects (opt-in).
- **DDC capability detection** (VCP `0xF3`): controls are gated to what the panel actually
  reports it supports.
- **EDID retrieval / export** — parsed identity (manufacturer, product, serial descriptors,
  checksum, stable fingerprint) with a CLI `edid` export.
- **Favorite resolutions** — star the modes you use so they're one click away.
- **Display-config drift detection** — notice when a protected arrangement has been changed
  out from under you.
- **Configurable global hotkeys** — an expanded shortcut registry (cycle main display,
  brightness ±, reconnect-all) with a tolerant, forward-compatible settings format.
- **Connect / disconnect notifications** — optional banners when a display comes or goes.
- **One-click quit** — a power button in the menu header next to the gear.

### Fixed
- **Set-as-Main** targeted the wrong display: it computed the arrangement shift from a stale
  observation. It now re-resolves the target against a fresh snapshot before applying.
- **Menu pop-out mis-anchored** across multiple displays (SwiftUI `MenuBarExtra` opened on
  the wrong screen). Replaced with an AppKit `NSStatusItem` + `NSPopover` that anchors to the
  clicked screen and stays put when set-main relocates the primary display.
- **Settings wouldn't open** from the menu after the AppKit switch — the window is now owned
  directly by the app and reliably opens, activated and centered on the screen you're using.

### Changed
- **Quit now returns the Mac to a clean default**: reconnects any display the app turned off,
  lifts software dim/blackout, and drops the keep-awake assertion before the app exits
  (termination is deferred until the reconnect lands), rather than relying on the OS's
  process-exit auto-revert.

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
