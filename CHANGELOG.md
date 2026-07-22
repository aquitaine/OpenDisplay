# Changelog

All notable changes to OpenDisplay are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/). OpenDisplay is pre-1.0 (0.x); anything may
change until 1.0.

## [0.8.0] — 2026-07-23

The last row of the Lunar parity table: **every feature Lunar markets is now matched**.

### Added
- **XDR Brightness** (Labs, Issue #35) — drive the MacBook Pro's XDR panel past its 500-nit
  SDR cap. A compact sun badge at the end of the built-in's brightness row toggles a **2×
  boost**: a tiny extended-dynamic-range trigger makes macOS raise the physical backlight,
  and a gamma-table remap hands that raised range to your normal (SDR) content — the whole
  desktop gets genuinely brighter, hardware-verified around 1600 nits at the 3.2× internal
  ceiling. Public Metal/Core Graphics only (no private API), so it also works in the
  public-API-only build. Opt-in via Settings → Labs, session-only by design: quitting —
  or even crashing — always returns the panel to normal. Known trade-offs, stated in the
  UI: HDR content looks clipped while boosted, and sustained boost warms the panel.

### Fixed
- The app now enforces a **single running instance**: a second copy (a Debug build alongside
  the installed release, or several stale builds) exits immediately instead of fighting the
  first one for the gamma slot, DDC bus, settings file, hotkeys, and menu bar.

## [0.7.1] — 2026-07-22

A review-and-hardening pass over the whole codebase (no new features).

### Fixed
- **App Presets** no longer lose a display's saved baseline when it is unplugged while a preset
  is active: the restore stays owed and is paid back automatically when the display returns (or
  at the next launch), instead of stranding the re-plugged display at the preset's values. A
  display that *connects* while a preset is active is now governed immediately rather than
  waiting for the next app switch.
- **Settings file resilience**: one unreadable field (e.g. after a downgrade, or corruption) now
  falls back to that field's default instead of silently resetting every setting — including the
  FaceLight / app-preset / evening-preset restore ledgers — on the next save.
- Display identity: a "paired" record can no longer absorb an unrelated anonymous monitor; the
  pairing signal now requires corroborating evidence (serial, model, UUID, or registry path).
- Refresh-rate-only mode changes and 180° rotations now advance the topology generation instead
  of always sitting out the 2-second stabilization timeout.
- `opendisplay edid` on a Mac laptop no longer reports the built-in panel's EDID for an external
  display whose model number is unreadable.
- CLI: `favorite set <display> @2x` (no resolution) reports a usage error instead of crashing;
  `brightness` DDC writes round instead of truncate (0.29 wrote 28 but printed 29%).
- Clock Mode solar anchors queried just after midnight on a DST-transition day are no longer an
  hour off.
- Audit-log entries written concurrently by the app and CLI can no longer interleave mid-line.

### Changed
- Night Shift detection reuses one CoreBrightness client instead of opening a new connection
  every 5-second adaptive tick.

## [0.6.1] — 2026-07-21

### Fixed
- Pressing ⌘, (the standard macOS Settings shortcut) opened an empty stub window instead of the
  real Settings UI. The shortcut and the menu bar's gear now open the same Settings window
  (Displays / Arrange / Scenes / Health & Recovery / About), and repeated presses re-focus the
  existing window instead of spawning another.

## [0.7.0] — 2026-07-21

Wave 2 of the Lunar-parity work: Location Mode and App Presets. With these, every
Lunar-marketed feature except the XDR brightness unlock is matched.

### Added
- **Location Mode** (Issue #31) — brightness that follows the sun's real elevation at your
  location: a night floor below civil twilight (−6°), a linear ramp through dawn and dusk, and a
  full-brightness plateau once the sun is high (20°+). It slots into Adaptive Display as a
  fallback source below the live signals — the built-in mirror and the ambient-light sensor still
  win when available, an explicit Clock Mode schedule still outranks it, and manual tweaks teach
  it an offset exactly like sync mode. Great for lid-closed setups in rooms with natural light.
  The sun-elevation math extends 0.6.0's NOAA solar calculator (pure, deterministic, validated
  against an independent ephemeris algorithm within 0.5°); location is shared with Clock Mode
  (one-shot opt-in or manual latitude/longitude).
- **App Presets** (Issue #33) — per-app display presets: when a chosen app comes to the front,
  its preset (brightness, and optionally contrast and colour preset) applies to the target
  display — or all displays — and the prior state comes back when the app leaves. Switches are
  debounced (rapid ⌘-tabbing only commits the app you land on), writes go through the same
  silent, audited funnels as Adaptive Display (so they never trip the manual-change cooldown),
  and the pre-preset state is persisted *before* the first write — a crash or relaunch
  mid-preset restores your real settings, the same crash-safe ledger FaceLight uses.
  Precedence, documented and tested: FaceLight > App Presets > Clock Mode > Adaptive sync.

## [0.6.0] — 2026-07-21

The Lunar-parity feature batch: FaceLight, Clock Mode, input-switch hotkeys, and three new CLI
commands — plus an About section inside Settings.

### Added
- **FaceLight** (Issue #29) — turn the active monitor into a video-call fill light with one press:
  DDC brightness and contrast go to max and a warm, translucent, click-through overlay washes the
  screen (strong warm light with your call still legible underneath). Press again to restore the
  exact prior brightness, contrast, and overlay state. The restore ledger is persisted *before* the
  hardware writes land, so a crash or relaunch mid-FaceLight still puts the display back exactly as
  it was. Displays without DDC get the overlay-only version. Toggle from each display's card in the
  menu, or bind the new "Toggle FaceLight" global-hotkey action.
- **Input-switch hotkeys** (Issue #32) — assignable global hotkeys that jump a monitor straight to a
  specific input ("⌃⌥⌘2 → Desk, HDMI 2"), so KVM-style setups never need the menu. Configured in
  Settings; bindings target the display's persistent EDID identity, so they survive dock re-plugs
  and port reordering. The switch routes through the same audited command path as the UI and CLI,
  confirms on-screen via the OSD, and posts a notification instead of failing silently when the
  display is offline or rejects the switch.
- **CLI: `lux`, `listen`, `lid`** (Issue #34) — `opendisplay lux` prints the current ambient-light
  reading (with `--json`); `opendisplay lid` reports lid state; `opendisplay listen` streams
  brightness and display-topology events as line-delimited JSON until Ctrl-C, for scripting
  (`| jq`, tail-style automation). Schema documented in `Tools/opendisplay/README.md`.
- **About in Settings** — a new About section in the Settings sidebar (below Health & Recovery)
  showing the app version and build, a Check for Updates control, and project links — the same
  information as the About window, now one click away in Settings.
- **Clock Mode** (Issue #30) — a first-class, user-editable brightness schedule for external
  displays. Each schedule point is anchored either to a fixed clock time or to a solar event
  (sunrise, solar noon, sunset) with a per-anchor offset in minutes — so "70% thirty minutes
  before sunrise" tracks the season automatically. Three transition styles carry brightness between
  points: **instant** (step at the anchor), **30-min ramp** (ease in over the half-hour ending at
  the anchor), and **continuous** (glide across the whole gap). Transitions are silent — no OSD —
  like every other adaptive change.
  - **Solar math** is public-domain NOAA solar-position equations, computed as pure, deterministic
    logic in `TopologyCore` (`SolarCalculator`) and unit-tested against known city/date sunrise and
    sunset pairs (London, New York, Sydney) within a couple of minutes, plus polar-day/night and
    noon-symmetry invariants. Location comes from Core Location (one-shot, opt-in "Use current
    location") with a manual latitude/longitude fallback; with no location, solar anchors are
    skipped gracefully and time anchors still work.
  - **Precedence with Adaptive Display:** an explicit Clock Mode schedule outranks Adaptive
    Display's built-in mirror — enabling Clock Mode governs external brightness even when brightness
    sync is on. Adaptive warmth (colour preset) is orthogonal and unaffected. A manual brightness
    change still pauses the schedule for the cooldown, reusing the same quiet-write machinery, so
    the two never fight.
  - Settings gain a Clock Mode editor (add / edit / delete schedule points, choose the location)
    under Health & Recovery, consistent with the existing design.

## [0.5.1] — 2026-07-21

Patch release: a real About window and keyboard-accessibility fixes in the menu pop-out.

### Added
- **About window** — "About OpenDisplay" now opens a proper window instead of the bare
  system panel: the running version and build (selectable, for bug reports), a Check for
  Updates button, and links to the website, release notes, issue tracker, and license.
  Built with semantic fonts and VoiceOver labels.

### Fixed
- **No more surprise focus ring** — the menu pop-out no longer opens with a focus ring
  already drawn around the gear button. Keyboard focus is still one Tab away.
- **Tab now cycles forward through the whole pop-out** — forward Tab used to jump from
  the gear to the ··· button and stop there; only Shift-Tab could reach everything. Both
  directions now traverse every control and wrap around.

## [0.5.0] — 2026-07-20

Launch-prep feature release: a real update check, dimming that can go darker than gamma
alone, and a software colour-temperature control. 321 unit tests (up from 286).

### Added
- **Check for updates** — the menu row is live (it said "Soon"). A manual check asks GitHub
  for the newest release and, when one exists, shows its version badge and links to the
  release page. An automatic check runs at most once a day (default on, toggleable in
  Settings → Health & Recovery). Nothing is ever downloaded or installed automatically.
- **Overlay & combined dimming** — the Dimming card gains a method picker. *Gamma* is the
  original table scale (0.15 floor); *Overlay* is a black, click-through window at
  adjustable opacity; *Combined* stacks the overlay past the gamma floor — darker than
  either method alone, and still never fully black. The menu bar (and this app's menu)
  stay undimmed so the way back is always visible, overlays never appear in screenshots,
  and they vanish with the app — an overlay dim can't outlive a crash.
- **Colour temperature** — a warm/cool slider (2700–9300 K) in the Appearance card, applied
  through the display's gamma table with attenuation-only channel gains (no highlight
  clipping), snapping back to "Native" near 6500 K. Composes correctly with software
  dimming and software brightness — each remembers the other.

## [0.4.1] — 2026-07-19

Patch release: volume media keys now route by where your sound is actually playing.

### Fixed
- **Volume/mute keys follow the current sound output device** instead of the media-key
  target mode. When macOS sound output is a monitor with DDC audio, the keys drive that
  monitor's hardware volume (with the OSD); when sound plays anywhere else — built-in
  speakers, headphones, AirPods — the keys pass through to macOS untouched. Previously,
  with the target mode pointed at a DDC monitor, the keys could change the monitor's
  volume while audio played from the Mac's speakers. Brightness keys are unchanged and
  still follow the configured target mode; the Settings picker is relabelled to make the
  split explicit.

## [0.4.0] — 2026-07-03

Fourth developer preview: Adaptive Display brings macOS-grade brightness and warmth
intelligence to external monitors over DDC — sync to the built-in panel, read the ambient
light sensor directly when the built-in is off, or fall back to a schedule, plus Night-Shift-
following evening warmth. 271 unit tests (up from 240); adaptive paths attended-verified live
on a Samsung ultrawide end to end.

### Added
- **Adaptive Display (Labs, opt-in):** transfer the built-in display's intelligence to external
  monitors. **Brightness sync** mirrors the built-in panel's ambient-light-driven brightness to
  the external's real backlight over DDC (learned offset from your manual tweaks, one-minute
  hands-off after a manual change, schedule-curve fallback with the lid closed). **Evening
  warmth** switches the monitor's hardware colour preset in the evening and back each morning —
  following macOS Night Shift's live state when readable (best effort, private CoreBrightness),
  otherwise a configurable schedule. The daytime preset is remembered and restored on quit,
  disable, next morning, and even across a crash or relaunch mid-evening. Adaptive changes are
  silent (no OSD) and never write to displays without working DDC. With the built-in display
  turned OFF but the lid open (external-monitor-plus-Mac-keyboard setups), brightness reads the
  **ambient light sensor directly** — true light-driven dimming with no panel to mirror; only a
  closed lid (sensor covered) falls back to the schedule.
- Configurable day/night brightness levels and schedule times for the fallback curve.

### Fixed
- Local (non-release) builds now sign with a stable Developer ID identity instead of adhoc, so the
  macOS Accessibility grant the media-key tap needs survives a rebuild — the hardware brightness
  keys no longer silently stop working after the app is rebuilt. Notarized release builds were
  never affected.

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
