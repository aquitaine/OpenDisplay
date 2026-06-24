# OpenDisplay — Batch 2 Issues (rest of Tier 1)

Six more Tier-1 wins from the Feature-Parity-Map, scoped against the live repo. Same rules as Batch 1:
**Apple Silicon only**; private-SPI paths stay behind `#if !PUBLIC_API_ONLY` + `dlsym`; clean-room (no
BetterDisplay). The **gate per issue is `make test` green including new unit tests for that issue's pure
logic** — so each issue extracts its decision/parsing logic into a cross-platform SPM package and
unit-tests it there; the macOS-framework side effects are wired in the app/providers/CLI and
build-checked via `xcodebuild`. Hardware-only criteria are `[deferred: attended verification]`.

Package decisions (reuse existing targets, no new SPM packages): DDC capabilities parser →
**AutomationSchema** (beside `DDCPowerMode`); EDID parser → **DisplayDomain** (beside the identity
types); favorites / shortcuts / notifications / drift → **TopologyCore** + **DisplayDomain**.

Suggested order (most-testable / least-live-verification first):
**1 (DDC auto-config) → 2 (EDID export) → 3 (favorite resolutions) → 6 (config protection) →
4 (keyboard shortcuts) → 5 (notifications).**

---

## Issue 1 — DDC capabilities / auto-config (VCP `0xF3`)

**Type:** feature · **Effort:** ~half–1 day · **Risk:** low

**Current state.** `ExternalDisplayDDC` (`Providers/ExperimentalLifecycleProvider/Sources/DDCControl.swift`)
reads/writes VCP features but *guesses* which a monitor supports and their value ranges. The MCCS
capabilities request (VCP `0xF3`) is never sent or parsed, so the menu/CLI offer controls a panel may
not support. Batch-1 #1 (DDC power) already noted "read accepted values from the capabilities string."

**Acceptance criteria.**
- A **pure** MCCS capabilities-string parser in **AutomationSchema** decodes the `0xF3` response (e.g.
  `(vcp(10 12 60(01 03 11) 14(05 08) D6(01 04 05))…)`) into a `DDCCapabilities` value: the set of
  supported VCP codes, and for discrete features their allowed value lists.
- Tolerant + total: malformed/partial strings return `nil` (or a best-effort partial), never crash.
- `ExternalDisplayDDC.readCapabilities() async -> DDCCapabilities?` sends `0xF3` (chunked read per MCCS),
  assembles the string, and delegates to the parser.
- `AppModel` caches capabilities per external display and uses them to filter what the UI/CLI offer:
  contrast/volume/input/color-preset shown only when their VCP code is advertised (fail-open: if no
  capabilities, offer everything as today).
- CLI `opendisplay ddc <selector> caps` prints the discovered capabilities (and `—` when unsupported).
- Writes are unchanged and remain best-effort (capabilities are advisory only — never block a write).

**Testable logic (gate).** `DDCCapabilities` + `parse(_:)` in AutomationSchema, with `DDCCapabilitiesTests`
over valid strings (simple, nested discrete values, `vcp(...)` wrapper, extra `model`/`mccs_ver` tags),
malformed strings (unbalanced parens, non-hex, truncated), and edge cases (empty, duplicate codes).

**[deferred: attended verification]** the live `0xF3` round-trip to a real monitor (I2C read).

---

## Issue 2 — EDID retrieval / export

**Type:** feature · **Effort:** ~1 day · **Risk:** low

**Current state.** Only CG-derived fields are read (`CGDisplayVendor/Model/SerialNumber`, screen size) in
`CoreGraphicsProvider.fingerprint(for:)`; the raw EDID blob (`IORegistry` `IODisplayEDID`/`kIODisplayEDID`)
is never fetched and there's no EDID byte-parser or export.

**Acceptance criteria.**
- A **pure** EDID parser in **DisplayDomain** decodes the 128-byte base block (+ detects/parses CEA
  extension blocks): manufacturer 3-letter ID, product code, serial, week/year, EDID version, basic
  display params, and the four 18-byte descriptors (monitor name `0xFC`, serial `0xFF`, range `0xFD`,
  detailed timing). Validates the header magic + checksum.
- Total/tolerant: truncated/garbled/bad-checksum input returns a partial result or `nil`, never crashes.
- `CoreGraphicsProvider` reads the raw EDID from IORegistry (gated `#if !PUBLIC_API_ONLY` if the key
  needs SPI) and feeds the parser; falls back to CG-derived fields when absent.
- App/CLI can **export** the EDID: raw `.bin` and a human-readable `.txt` (manufacturer/model/serial/
  timings/flags). Serial is hashed by default (privacy), with an opt-in raw export.
- `opendisplay edid <selector> [--out <path>]` prints/export the parsed EDID.

**Testable logic (gate).** `EDID` model + `EDID.parse(_ bytes:)` in DisplayDomain, with `EDIDTests` over
several real sample blocks (built-in + a couple externals, 128 and 256 byte), descriptor variants
(`0xFC/0xFF/0xFD`), and malformed/short/bad-checksum inputs.

**[deferred: attended verification]** reading a real panel's IORegistry EDID + the export file contents.

---

## Issue 3 — Favorite resolutions

**Type:** feature (UI) · **Effort:** ~1 day · **Risk:** low · **Builds on:** Batch-1 #2 (`ResolutionStops`)

**Current state.** `ResolutionStops` (DisplayDomain) gives the area-sorted stops; the slider lives in
`DisplayDetailView`. There's no way to pin/recall preferred modes.

**Acceptance criteria.**
- A **pure** `FavoriteResolutions` value type in **DisplayDomain**: add/remove/contains a mode (keyed by
  `pointWidth×pointHeight@refreshHz`+HiDPI), and a `merged(favorites:stops:)` that lists favorites first
  (stable order) then the area-sorted stops, deduped.
- `DiskFavoritesStore` in **TopologyCore** persists `favorites.json` in Application Support, keyed by
  **stable display identity** (`DisplayRecordID`) so favorites survive reconnects; missing/corrupt file →
  empty (graceful).
- A star/pin affordance per resolution in `DisplayDetailView` toggles a favorite; favorites surface at
  the top of the resolution control.
- CLI `opendisplay favorite <list|set|unset> <selector> [mode]`.

**Testable logic (gate).** `FavoriteResolutions` (add/remove/contains/merge ordering + dedup) in
DisplayDomain, and `DiskFavoritesStore` round-trip/missing/corrupt tests in TopologyCore.

---

## Issue 6 — Display-config protection (drift detect → restore)  *(safety-hardening)*

**Type:** safety-hardening · **Effort:** ~1 day · **Risk:** low · **Builds on:** Batch-1 #6, scenes, checkpoints

**Current state.** `TimedRevertGate`, `DiskCheckpointStore`, `SceneRecorder.capture`/`ScenePlanner.plan`,
and `restoreArrangement` exist. Missing: a way to mark the current arrangement "protected" and detect
when it drifts (another app/hotplug changed origins/main/mode/mirror) so it can be restored.

**Acceptance criteria.**
- A **pure** `DisplayConfigDrifter` in **TopologyCore**: `detectDrift(protected:current:) -> DriftAnalysis`
  comparing two `TopologySnapshot`s record-by-record for origin / mode / main / mirror / active-set
  changes (and disconnect / unexpected hotplug). Output is a typed change list.
- A `ProtectedConfig` (Codable) capturing the protected snapshot + timestamp; persisted via the
  checkpoint store under its own key.
- A restore plan: feed the protected snapshot to the existing `ScenePlanner.plan` to get the minimal
  ops to restore it (reuse the engine; no new one).
- **Scope: pure logic + persistence only** this issue. Wiring drift→confirm→auto-restore into the live
  topology loop is a follow-up (keeps it safe + testable now).

**Testable logic (gate).** `DisplayConfigDrifterTests` over: identical (no drift), origin moved, mode
changed, mirror toggled, main reassigned, external offline, unexpected hotplug; plus restore-plan
generation. No hardware needed — pure snapshot logic.

---

## Issue 4 — Expanded keyboard shortcuts (configurable global-hotkey registry)

**Type:** feature · **Effort:** ~1 day · **Risk:** low

**Current state.** `GlobalHotKey.swift` is a single hardcoded chord (⌃⌥⌘R → Reconnect-All) via Carbon
`RegisterEventHotKey` (no Accessibility perm). `SettingsStore` has only a `reconnectAllHotkeyEnabled`
bool. No binding model.

**Acceptance criteria.**
- A **pure** `KeyboardShortcutRegistry` + `HotkeyAction` enum in **TopologyCore**: bindings map
  `(keyCode, modifiers)` → action (reconnect-all, set-main-toggle, brightness ±, …) with defaults,
  conflict detection (same combo → two actions), and Codable round-trip.
- `OpenDisplaySettings` gains `hotkeyBindings`; tolerant decode (missing → defaults, unknown keys ignored).
- `GlobalHotKey` is generalized to register an arbitrary `(keyCode, modifiers, handler)`; `AppModel`
  registers all enabled bindings from the registry at launch.
- **Scope:** configurable global *hotkeys* (Carbon). Low-level media-key (F1/F2/volume) interception is a
  harder follow-up — note it, don't build it.

**Testable logic (gate).** `KeyboardShortcutRegistryTests`: combo↔action mapping, defaults fallback,
conflict detection, Codable round-trip incl. forward/backward compat; plus `SettingsStore` round-trip.

**[deferred: attended verification]** that the registered chords actually fire in the running app.

---

## Issue 5 — Display notifications

**Type:** feature · **Effort:** ~1 day · **Risk:** low

**Current state.** `AppModel.observeTopologyChanges` already sees every hotplug/change; nothing surfaces
them to the user. No `UNUserNotificationCenter` use.

**Acceptance criteria.**
- A **pure** `NotificationPolicy` in **TopologyCore**: given prior+current snapshots, settings, and the
  last-notified timestamps, decide `(shouldNotify, title, body)` for external connected/disconnected,
  built-in auto-disconnected, arrangement reverted — with a short **dedup window** and name resolution
  (alias → model → record id).
- `OpenDisplaySettings.displayNotificationsEnabled` (default **off**), tolerant decode.
- `AppModel.observeTopologyChanges` feeds the policy and posts via `UNUserNotificationCenter`
  (authorization requested once at launch). Delivery is macOS-only (`#if os(macOS)`), never compiled
  into the test target.

**Testable logic (gate).** `NotificationPolicyTests`: each transition, dedup within the window, "settings
off → never", and text/name resolution; plus the `SettingsStore` toggle round-trip.

**[deferred: attended verification]** the actual notification banners + the one-time auth prompt.

---

## Progress

- **Issue 1 — DDC capabilities / auto-config** ✅ (commit on `batch2`)
  - Pure `DDCCapabilities` + `parse(_:)` in **AutomationSchema** (vcp-block parser, tolerant/total).
    11 `DDCCapabilitiesTests` (valid/nested/realistic/case/malformed/unbalanced/dup/whitespace).
  - `ExternalDisplayDDC.readCapabilitiesString()` — VCP 0xF3 chunked read + assemble.
  - `AppModel`: `ddcCapabilities` cache, `refreshCapabilities`, `ddcSupports` (fail-open),
    `refreshHardwareControls` now gates by capabilities. CLI: `opendisplay ddc <sel> caps`.
  - `make test` green (143); `OpenDisplay`, `OpenDisplay-PublicAPIOnly`, `opendisplay` all build.
  - **VERIFIED LIVE** on the S34J55x (read-only): real caps string parsed; 0x62/volume correctly
    absent (no speakers) → volume control would be hidden. The 0xF3 read works on real hardware.
- **Issue 2 — EDID retrieval / export** ✅ (commit on `batch2`)
  - Pure `EDID` + `parse(_:)` in **DisplayDomain**: 128-byte base block (manufacturer/product/serial/
    week/year/version/size/gamma), the 4 descriptors (monitor name 0xFC, serial 0xFF, range, detailed
    timing), checksum + extension count, and a deterministic `stableHash` (FNV-1a). Tolerant: bad
    header/short → nil; bad checksum still parses but flags. 9 `EDIDTests`.
  - `EDIDReader` (CoreGraphicsProvider, public IOKit): walks the IORegistry service plane for the raw
    `EDID` blob, matched to the display by product code. CLI: `opendisplay edid <sel> [--out <path.bin>]`.
  - `make test` green (152); both app flavors + CLI build.
  - **VERIFIED LIVE** on the S34J55x (read-only): parsed model "S34J55x", serial "H4ZN401101",
    week 17/2020, 3440×1440, 80×33cm, valid checksum, 1 extension; `--out` wrote the correct 256-byte blob.
