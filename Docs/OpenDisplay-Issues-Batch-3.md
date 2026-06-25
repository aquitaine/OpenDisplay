# OpenDisplay — Batch 3 Issues (native-looking OSD + media-key interception)

Two paired Tier-1 capabilities from the Feature-Parity-Map (§14 OSD, §1/§13 media keys), scoped against
the live `batch2` repo. They ship together on purpose: once OpenDisplay **intercepts** the brightness/
volume media keys it must *consume* them, which suppresses macOS's own HUD — so the app has to draw its
own. Media keys without an OSD feel broken; an OSD without media keys only fires on app/CLI changes.

Same rules as Batch 1/2:
- **Apple Silicon only.** Private-SPI paths stay behind `#if !PUBLIC_API_ONLY` + `dlsym`. (Nothing here
  needs private SPI — it's CGEventTap + AppKit + the existing control sinks.)
- **Clean-room.** "Native-looking" means matching *Apple's* system HUD conventions (segmented bar,
  SF Symbols glyphs, bottom-center placement) from public observation — **not** copying BetterDisplay's
  OSD layout, assets, or styles.
- **The gate per issue is `make test` green including new unit tests for that issue's pure logic.** Each
  issue extracts its decision/mapping/timing logic into a cross-platform SPM package and unit-tests it
  there; the macOS side effects (CGEventTap, NSPanel, DistributedNotificationCenter) are wired in the app
  and build-checked via `xcodebuild`. Anything needing a real keypress / Accessibility grant / on-screen
  render is `[deferred: attended verification]`.

**Package decisions (reuse existing targets, no new SPM packages):** media-key semantics + target
policy + OSD content/timing/style → **TopologyCore** (beside `NotificationPolicy`,
`KeyboardShortcutRegistry`) and **DisplayDomain** (the `OSDContent` value type beside `DisplayModels`);
the notch-app broadcast payload → **AutomationSchema** (beside `URLCommand` / `DDCPowerMode`).

**Suggested order (most-testable / least-live-verification first):**
**1 (media-key semantics + routing) → 2 (OSD content + timing) → 4 (OSD HUD window) → 3 (media-key tap)
→ 5 (styles + settings UI) → 6 (notch-app API).**

---

## ⚠️ Architectural decision — the first Accessibility (TCC) dependency

Today OpenDisplay requires **no** TCC permission for control: the one global hotkey uses Carbon
`RegisterEventHotKey`, which deliberately avoids Accessibility so recovery works when nothing is granted
(`GlobalHotKey.swift:6-8`). **Media-key interception is different** — capturing `NX_KEYTYPE_*` system-
defined events (and *consuming* them so the OS HUD doesn't also fire) needs an **active CGEventTap**,
which needs the **Accessibility** grant. This is the first permission OpenDisplay would ask for to power
a core control feature. Constraints this batch must honor:

- **Opt-in, default off.** A user who never enables media keys is never prompted (mirror the
  notifications pattern: request only on enable — `NotificationDelivery.requestAuthorization`).
- **Graceful when not granted.** Keys simply aren't intercepted; the OSD still works for app/CLI/Intent-
  driven changes; Settings shows a "Grant Accessibility…" affordance with live status.
- **Never in the recovery path.** Reconnect-All stays on Carbon with **no** Accessibility dependency.
  The event tap is a control convenience, not a safety mechanism.
- **The OSD itself needs no permission** — only key *interception* does. Issues 2/4/5/6 are useful even
  if a user never grants Accessibility.

---

## Issue 1 — Media-key semantics & display routing (pure logic)

**Type:** feature · **Effort:** ~half–1 day · **Risk:** low

**Current state.** `HotkeyAction` (`KeyboardShortcutRegistry.swift:5`) already has `brightnessUp/Down`,
but they're Carbon-only chords routed to `AppModel.adjustMainBrightness(by:)` (`AppModel.swift:1469`),
which **only ever targets the main display** and has **no volume actions**. There is no model for the
hardware media keys (F1/F2 brightness, F10–F12 volume/mute) or for *which* display a key should affect.

**Acceptance criteria.**
- A **pure** `MediaKey` mapping in **TopologyCore**: the macOS `NX_KEYTYPE_*` codes
  (`BRIGHTNESS_UP/DOWN`, `SOUND_UP/DOWN`, `MUTE`) → a semantic `MediaKeyAction`
  (`brightnessUp/Down`, `volumeUp/Down`, `muteToggle`), including the **fine-step modifier**
  (⇧⌥ → quarter-step, matching macOS's 1/16-vs-1/64 convention) → a step `delta`.
- A **pure** `MediaKeyTargetPolicy`: given the current displays, the cursor location, the main display,
  and a `MediaKeyTargetMode` setting (`underCursor` (default) / `mainDisplay` / `builtInAlways`), choose
  the **target display** and the **route** (brightness vs volume). Volume routes only to a display that
  reports DDC volume (VCP `0x62`); brightness routes via the existing native/DDC/software resolution.
- Single-display Macs always resolve to that display; an unreadable/asleep target is skipped (no crash).
- `adjustMainBrightness(by:)` is generalized to `adjustBrightness(by:for:)` so the existing Carbon
  `brightnessUp/Down` chords and the new media keys share one target-policy path.

**Testable logic (gate).** `MediaKeyTests` (every NX code → action, fine-step modifier math with
deterministic rounding, unknown code → nil) + `MediaKeyTargetPolicyTests` (under-cursor pick, main
fallback, single-display, volume gated on `0x62` capability via the Batch-2 `DDCCapabilities`, asleep-
target skip). Pure — no hardware.

**[deferred: attended verification]** none for this issue (logic only).

---

## Issue 2 — OSD content & presentation model (pure logic)

**Type:** feature · **Effort:** ~half–1 day · **Risk:** low

**Current state.** Nothing renders an on-screen display. Brightness/volume changes update caches
(`AppModel.brightness`, `ddcControlLevel`) and the menu sliders, silently.

**Acceptance criteria.**
- A **pure** `OSDContent` value type in **DisplayDomain**: `kind` (`brightness` / `volume` / `mute`),
  normalized `value` (0…1), the **16-segment fill count** (deterministic rounding), an SF-Symbol glyph
  name, and an optional percent label. Mute renders the speaker-slash glyph at the current level.
- A **pure** `OSDPresentationPolicy` in **TopologyCore**: coalesces rapid changes (a key-repeat or
  slider drag yields one updating HUD, not a stack), holds an **auto-hide** countdown (default ~1.2 s,
  refreshed on each change), and suppresses a no-op (value unchanged) — `decide(prev:event:now:) ->
  OSDDecision { show(content) | refresh | hide | ignore }`.
- An `OSDStyle` enum (`native` (default) / `minimal` / `classicTahoe`) selecting glyph set + segment
  rendering hints (the renderer in Issue 4/5 reads these; the enum + its mapping live here).

**Testable logic (gate).** `OSDContentTests` (segment math at 0 / 1 / boundaries with explicit rounding,
glyph + mute selection) + `OSDPresentationPolicyTests` (coalesce within window, refresh extends auto-hide,
no-op ignored, mute toggle). Pure — no AppKit.

**[deferred: attended verification]** none (logic only).

---

## Issue 4 — OSD HUD window (macOS)

**Type:** feature · **Effort:** ~1 day · **Risk:** low–medium

**Current state.** No HUD surface exists. The "pure policy + macOS-only delivery" split is already
established by Batch-2 #5 (`NotificationPolicy` + `NotificationDelivery.swift`) — mirror it.

**Acceptance criteria.**
- An `OSDHUDController` (macOS-only) owning a borderless, **non-activating** `NSPanel`
  (`.nonactivatingPanel`, `level = .statusBar`, ignores mouse, joins all Spaces) backed by an
  `NSVisualEffectView` (native blur) that renders an `OSDContent` using the existing
  **OpenDisplayDesignSystem** tokens (`Tokens.swift`, `MenuBarControls.swift`) for light/dark parity.
- The HUD appears on the **target display** (Issue 1's pick) — placed bottom-center by default — and
  fades in / auto-hides driven by `OSDPresentationPolicy` (Issue 2).
- It shows for brightness/volume changes from **any** source — media keys, the menu slider, the CLI,
  App Intents — by observing the AppModel control mutations (one funnel: route every brightness/volume
  set through a single `presentOSD(_:)` call).
- Public API only (no `#if !PUBLIC_API_ONLY` gate); compiles in the public-API-only flavor.

**Testable logic (gate).** Covered by Issue 2's `OSDContent`/`OSDPresentationPolicy` tests; the window
itself is view code.

**[deferred: attended verification]** the panel actually renders, placed on the right display, fades and
auto-hides, and never steals focus / never blocks clicks.

---

## Issue 3 — Media-key tap (macOS, Accessibility-gated)

**Type:** feature · **Effort:** ~1 day · **Risk:** medium (TCC permission + event consumption)

**Current state.** Carbon `GlobalHotKey` cannot see `NX_KEYTYPE_*` system-defined events (they're not
Carbon hotkeys). No event tap exists. See the architectural-decision note above.

**Acceptance criteria.**
- A `MediaKeyTap` (macOS-only) creating a `CGEventTap` for `NSEventType.systemDefined`
  (`kCGEventTapOptionDefault`, so events can be **consumed**), decoding the NX subtype/keycode, and —
  when interception is enabled and the key maps via Issue 1 — routing to the target display's
  `setBrightness` / `setHardwareControl(.volume,…)` / mute, then **swallowing** the event so macOS's own
  HUD does not also fire (OpenDisplay's OSD replaces it).
- New `OpenDisplaySettings.mediaKeyInterceptionEnabled` (default **off**) + `mediaKeyTargetMode`
  (default `underCursor`); tolerant decode.
- Accessibility handling: check `AXIsProcessTrusted()`; on enable, prompt once via
  `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`. When **not** trusted, the tap is
  a graceful no-op (keys pass through to the system unchanged) and Settings reflects "not granted".
- Tap lifecycle is clean: created on enable + grant, torn down on disable, re-armed if the tap is
  disabled by the system (`kCGEventTapDisabledByTimeout`). Never registered when the feature is off.
- **Recovery untouched:** Reconnect-All and all safety paths keep working with no Accessibility grant.

**Testable logic (gate).** The decode→action→target mapping is Issue 1 (fully unit-tested); this issue
is the OS plumbing on top.

**[deferred: attended verification]** Accessibility prompt + grant; a real F1/F2/volume keypress driving
the external's brightness/volume; confirmation the system HUD is suppressed (only OpenDisplay's shows);
pass-through behavior when the grant is absent.

---

## Issue 5 — OSD styles, placement & settings UI

**Type:** feature (UI) · **Effort:** ~half day · **Risk:** low

**Current state.** Issues 2/4 introduce `OSDStyle` + the HUD; nothing exposes them, and there's no UI to
enable media keys or surface the Accessibility status.

**Acceptance criteria.**
- `OpenDisplaySettings` gains `osdEnabled` (default **on**), `osdStyle` (default `native`),
  `osdPosition` (default `bottomCenter`); tolerant decode (missing → defaults, unknown ignored).
- Settings → Behavior gets: OSD on/off + style picker + position; "Media keys control displays" toggle
  (drives Issue 3) with a **live Accessibility status row** + "Open Accessibility settings…" deep-link
  and target-mode picker.
- Style selection flows through `OSDContent`/`OSDStyle` (Issue 2) into the renderer — `native` matches
  Apple's segmented HUD; `minimal` is a compact pill; `classicTahoe` is the pre-Tahoe look.

**Testable logic (gate).** `SettingsStore` round-trip for the new keys (incl. forward/back-compat) +
`OSDStyle`→content/glyph selection (Issue 2). Live styling = `[deferred]`.

**[deferred: attended verification]** each style/position rendered on screen.

---

## Issue 6 — External HUD / notch-app integration API

**Type:** feature · **Effort:** ~half day · **Risk:** low

**Current state.** No way for third-party notch apps (e.g. a notch HUD) to render OpenDisplay's
brightness/volume changes. The parity map (§14) calls for publishing OSD events so external HUDs can
subscribe.

**Acceptance criteria.**
- A **stable, Codable** `OSDBroadcast` payload in **AutomationSchema** (beside `URLCommand`): kind,
  value (0…1), display identity (`DisplayRecordID` + resolved name), source, timestamp — versioned and
  tolerant like the other schemas.
- A macOS-only publisher posts each OSD event via `DistributedNotificationCenter` under a documented
  name (`dev.opendisplay.osd`), gated by a new `publishOSDEventsEnabled` setting (default **off**).
- The payload schema + notification name are **documented** (a short `Docs/` note or README section) so
  notch apps can integrate; OpenDisplay's own OSD (Issue 4) can be suppressed when the user prefers an
  external HUD (style → `external`/off).

**Testable logic (gate).** `OSDBroadcastTests`: Codable round-trip, schema stability (unknown fields
ignored on decode), value clamping. Pure.

**[deferred: attended verification]** a second process actually receiving the distributed notification.

---

## Batch 3 — summary of new surface

| New pure type | Package | Tested by |
|---|---|---|
| `MediaKey` / `MediaKeyAction` / `MediaKeyTargetPolicy` / `MediaKeyTargetMode` | TopologyCore | `make test` |
| `OSDContent` | DisplayDomain | `make test` |
| `OSDPresentationPolicy` / `OSDStyle` | TopologyCore | `make test` |
| `OSDBroadcast` | AutomationSchema | `make test` |

| New macOS side-effect | File (new) | Verification |
|---|---|---|
| `MediaKeyTap` (CGEventTap, Accessibility-gated) | `Apps/OpenDisplay/Sources/MediaKeyTap.swift` | `[deferred]` |
| `OSDHUDController` (NSPanel + visual effect) | `Apps/OpenDisplay/Sources/OSDHUDController.swift` | `[deferred]` |
| OSD distributed-notification publisher | (in HUD controller or a small `OSDBroadcaster.swift`) | `[deferred]` |

New settings keys: `mediaKeyInterceptionEnabled` (off), `mediaKeyTargetMode` (underCursor), `osdEnabled`
(on), `osdStyle` (native), `osdPosition` (bottomCenter), `publishOSDEventsEnabled` (off).

Builds on: `KeyboardShortcutRegistry`/`HotkeyAction` (Batch-2 #4), `DDCCapabilities`/`ddcSupports`
(Batch-2 #1, gates volume), `NotificationPolicy`+`NotificationDelivery` (Batch-2 #5, the policy/delivery
pattern), `setBrightness`/`setHardwareControl(.volume)` sinks, and the OpenDisplayDesignSystem tokens.

**Estimated total: ~4–5 days.** Net new tests target ~40+ (keeping the per-issue `make test` gate).

---

## Progress

- **Issue 1 — Media-key semantics & routing** ✅ (pure logic)
  - `MediaKeyAction` + `NXKeyType` + `MediaKeyStep` + `MediaKeyTargetMode` + `MediaKeyTargetPolicy` in
    **TopologyCore** (`MediaKey.swift`). NX→action mapping, signed coarse/fine (1/16, 1/64) steps,
    target selection (under-cursor / main / built-in) with volume gated to DDC-audio-capable displays
    (built-in volume keys pass through). 13 tests (`MediaKeyTests` 5 + `MediaKeyTargetPolicyTests` 8).
- **Issue 2 — OSD content & presentation model** ✅ (pure logic)
  - `OSDContent` in **DisplayDomain** (`OSDContent.swift`): kind, clamped value, 16-segment fill
    (deterministic rounding), percent, SF-Symbol glyph. `OSDStyle`/`OSDPosition`/`OSDPresentationPolicy`
    in **TopologyCore** (`OSDPresentation.swift`): show/ignore + coalescing auto-hide deadline. 10 tests
    (`OSDContentTests` 4 + `OSDPresentationPolicyTests` 6).
- **Issue 4 — OSD HUD window** ✅ logic-tested; render `[deferred: attended verification]`
  - `OSDHUDController` (`OSDHUDController.swift`): borderless non-activating `NSPanel`, click-through,
    all-Spaces, `.regularMaterial` SwiftUI HUD (native square / minimal pill / classic), placed on the
    target display, coalescing auto-hide. Funnelled through `AppModel.presentOSD(...)`, called from
    `setBrightness` and `setHardwareControl(.volume)` so it fires for menu + media-key changes.
- **Issue 3 — Media-key tap** ✅ logic+wiring; live firing `[deferred: attended verification]`
  - `MediaKeyTap` (`MediaKeyTap.swift`): `CGEventTap` on `systemDefined` (active, so handled keys are
    consumed and the system HUD is suppressed); decodes NX subtype off the main-actor hop (CGEvent isn't
    Sendable) and dispatches Sendable values. Accessibility-gated (`AXIsProcessTrusted`, one-time prompt
    on enable), graceful no-op when not granted, re-arms on `tapDisabledBy*`. `AppModel.handleMediaKey`
    routes via Issue 1 to the brightness/volume sinks; `mediaKeyInterceptionEnabled` (default off) +
    `reconcileMediaKeyTap()`. Recovery path (Reconnect-All) stays Carbon, no Accessibility dependency.
- **Issue 5 — OSD styles, placement & settings UI** ✅ logic-tested; live styling `[deferred]`
  - `OpenDisplaySettings` gains `mediaKeyInterceptionEnabled`/`mediaKeyTargetMode`/`osdEnabled`/
    `osdStyle`/`osdPosition`/`publishOSDEventsEnabled` (tolerant decode); Settings → Health & Recovery →
    Behavior gains the OSD style/position pickers, the broadcast toggle, and the media-keys toggle with a
    live Accessibility status row + "Open Accessibility Settings…". +1 `SettingsStore` test.
- **Issue 6 — External HUD / notch-app integration API** ✅ logic-tested; cross-process receive `[deferred]`
  - `OSDBroadcast` in **AutomationSchema** (`OSDBroadcast.swift`): versioned, tolerant, string-only
    userInfo for `DistributedNotificationCenter` (`dev.opendisplay.osd`). `OSDBroadcaster` (app) publishes
    when `publishOSDEventsEnabled`. 6 tests (`OSDBroadcastTests`).

## Batch 3 — final summary
**All 6 issues implemented.** `make test` **192 → 222** (+30 new tests, 0 failures). All three Xcode
schemes — `OpenDisplay`, `OpenDisplay-PublicAPIOnly`, and the `opendisplay` CLI — **BUILD SUCCEEDED**,
no new source warnings. New pure logic, each unit-tested: `MediaKeyAction`/`MediaKeyTargetPolicy`/
`OSDStyle`/`OSDPresentationPolicy` (TopologyCore), `OSDContent` (DisplayDomain), `OSDBroadcast`
(AutomationSchema). macOS side effects (`MediaKeyTap` CGEventTap, `OSDHUDController` panel, distributed-
notification publish) are wired + build-checked; the interactive runtime parts are
`[deferred: attended verification]`:
- the Accessibility prompt/grant and a real F1/F2/volume keypress driving the target display,
- the system HUD being suppressed (only OpenDisplay's HUD shows), pass-through when not granted,
- each OSD style/position rendered on screen,
- a second process receiving the `dev.opendisplay.osd` broadcast.

Not committed/pushed (awaiting review). The generated `OpenDisplay.xcodeproj` is gitignored, so the
`make xcode` regen for the new files left no git footprint — but new source files do require
`xcodegen generate` before an Xcode build sees them.
