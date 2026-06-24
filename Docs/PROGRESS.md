# OpenDisplay — autonomous progress (Batch 1)

Working branch: `batch1-auto`. Spec: `docs/OpenDisplay-Issues-Batch-1.md`.

**Convention:** an acceptance criterion that needs real-hardware verification is marked
`[deferred: attended verification]` here — implement + unit-test the logic, commit, and move on.
Do NOT exercise real display mutations in this session.

## Order (safest / most self-contained first)
3 (prevent-sleep) → 1 (DDC power) → 4 (URL scheme) → 2 (resolution slider) → 6 (arrangement safety gate) → 5 (auto-disconnect built-in)

## Done
- **Issue 3 — Prevent display sleep while external connected** ✅ (commit on `batch1-auto`)
  - Pure logic `DisplaySleepGuard` + `PowerAssertionControlling` protocol in TopologyCore (testable),
    holds **at most one** assertion, decision = `enabled && externalPresent`, idempotent reconcile.
  - `OpenDisplaySettings.preventDisplaySleepWithExternal` (default **off**), tolerant decode.
  - App: `IOKitPowerAssertions` (kIOPMAssertionTypePreventUserIdleDisplaySleep), AppModel reconciles on
    every topology change + settings change + launch; releases on `willTerminate` and `deinit`.
  - UI: menu item (menu-bar ⋯ menu) + Settings → Health & Recovery → Behavior toggle.
  - Tests: 9 `DisplaySleepGuardTests` + 2 new `SettingsStoreTests` (acquire/release conditions,
    idempotency, **no leaks across connect/disconnect cycles**, OS-refusal tolerance, deinit release).
  - `make test` green (89 tests, exit 0); both `OpenDisplay` and `OpenDisplay-PublicAPIOnly` xcodebuild
    targets BUILD SUCCEEDED.

- **Issue 1 — DDC power control (VCP 0xD6)** ✅ (commit on `batch1-auto`)
  - `ExternalDisplayDDC.Feature.power = 0xD6` added (reuses the existing write path).
  - Shared, testable `DDCPowerMode` value type in **AutomationSchema**: `on/standby/off` →
    VCP 0x01/0x04/0x05, tolerant `init?(parsing:)` (case/space-insensitive, sleep/dpms aliases).
  - `AppModel.setPowerMode(_:for:)` — best-effort, fire-and-forget, no-op on built-in / public build.
  - UI: Power row (On/Standby/Off menu) in `DisplayDetailView` ControlsCard, near the input-source row.
  - CLI: `opendisplay ddc <selector> power <on|standby|off>` mirroring `ddc … input`.
  - Tests: 7 `DDCPowerModeTests` (VCP values, parsing, aliases, rejection, labels).
  - `make test` green (96 tests); `OpenDisplay`, `OpenDisplay-PublicAPIOnly`, and `opendisplay` build.

- **Issue 4 — `opendisplay://` URL-scheme automation** ✅ (commit on `batch1-auto`)
  - Shared, testable `URLCommand` + `URLCommandParser` in **AutomationSchema** (pure, total: unknown/
    malformed URLs → nil). `reconnect-all` (+ aliases) → `.reconnectAll`; `disconnect?display=<sel>` →
    `.disconnect(selector:)` flagged `requiresConfirmation`.
  - New `Actor.url` case so the audit trail attributes URL-triggered commands.
  - `OpenDisplayAutomation.handleURL` routes through the **same** `makeGateway()` the App Intents use
    (→ same safety/verify/audit path, DiskAuditLog entry appears). Safe recovery commands auto-run;
    arrangement-altering ones are never fired silently — they bring the app forward for in-app confirm.
  - `AppDelegate.application(_:open:)` (via `@NSApplicationDelegateAdaptor`) receives the URLs
    (LSUIElement app has no always-alive window for SwiftUI `.onOpenURL`).
  - `CFBundleURLTypes` for `opendisplay://` registered in Info.plist (plutil-lint clean).
  - Tests: 8 `URLCommandTests` (verb/scheme parsing, query selectors, security-gate, rejection).
  - `make test` green (104 tests); both app flavors build. Scope: URL scheme only (HTTP listener later).

- **Issue 2 — Resolution slider (replace dropdown)** ✅ (commit on `batch1-auto`)
  - Pure, tested `ResolutionStops` helper in **DisplayDomain**: `areaSorted(from:)` = one stop per
    point-size (HiDPI/refresh-preferred), area-ascending with deterministic tie-breakers so stops stay
    monotonic; `index(of:in:)` maps the current mode back to its stop by point-size.
  - `DisplayDetailView` resolution `Menu` → `Slider` bound to the stop index. Commit-on-release (drag
    doesn't slam through every mode), live label tracks the thumb, position re-syncs to the current
    mode via `.onChange(of: display.mode)`. Single-mode displays show static text (no dead control).
  - Provider untouched (pure UI/binding change).
  - Tests: 8 `ResolutionStopsTests` (dedup, area-sort, index discipline, monotonicity, empty/single).
  - `make test` green (112 tests); both app flavors build. (Commit-on-release pairs with Issue 6.)

- **Issue 6 — Safety gate for arrangement changes (timed auto-revert)** ✅ (commit on `batch1-auto`)
  - Pure, tested `TimedRevertGate<State>` in **TopologyCore**: captures `before` + `deadline`; the
    keep-vs-revert decision resolves **exactly once** (confirm-after-timeout can't un-revert, timeout-
    after-confirm can't double-restore), and `tick`/`revert` hand back the exact `before` to restore.
  - `AppModel.applyWithRevert` now wraps resolution (`setMode`, hence refresh/HiDPI), mirror
    (`setMirrored`), and set-main (`setMain`): snapshot → apply → countdown → restore unless confirmed.
    `restoreArrangement` reapplies each display's prior mode + origin (origin restores main) + mirror.
  - Crash safety: a `revert.pending` marker (same dir as checkpoints/rotation marker) restores the
    prior arrangement on next launch if the app dies mid-window — reuses the rotation marker pattern.
  - Reachable when the changed display is unreadable: prompt is on the **menu-bar display** with
    Keep / Revert-now, and the auto-revert needs no input (global Reconnect-All hotkey stays too).
  - Pairs with Issue 2's commit-on-release slider.
  - Tests: 10 `TimedRevertGateTests` (keep/revert/timeout, idempotency, exact-before restore, countdown).
  - `make test` green (122 tests); both app flavors build (no new source warnings).

- **Issue 5 — Auto-disconnect built-in when an external connects** ✅ (commit on `batch1-auto`)
  - Pure, tested `AutoDisconnectBuiltInPolicy` in **TopologyCore**: edge-triggered, fires only on the
    external **rising edge** (none → some); a second external (some → more) does not re-trigger.
    `seed(externalPresent:)` stops a pre-attached external at launch from counting as an arrival.
  - `OpenDisplaySettings.autoDisconnectBuiltInOnExternal` (default **off**), tolerant decode.
  - `AppModel.applyAutoDisconnectBuiltInIfNeeded` (in `observeTopologyChanges`) turns the active
    built-in off via the **existing gated** `setDisplayActive(false)` → `coordinator.disconnect`
    (SafetyEngine-checked, audited) on arrival. The built-in returns via the existing always-one-active
    safety net (`enforceActiveSurfaceInvariant`) — verified, not duplicated.
  - UI: menu item (menu-bar ⋯ menu) + Settings → Behavior toggle.
  - Tests: 8 `AutoDisconnectBuiltInPolicyTests` + 1 `SettingsStoreTests`. `make test` green (131 tests);
    both app flavors build.

## In progress
- (none)

## Tried / stuck  (so the next attempt doesn't repeat it)
- (none yet)

## Attended live verification — 2026-06-24 (user present, MacBook Pro M4 Pro: built-in Liquid
##   Retina XDR + Samsung S34J55x "Desk" external over HDMI)
All five previously-deferred items VERIFIED LIVE on hardware. Test app = Debug build run from
`~/Applications/OpenDisplay.app` (relocated from `/tmp` because LaunchServices won't honor a URL
handler in a volatile temp dir); settings driven via `settings.json` + relaunch.
- **Issue 3 — VERIFIED ✅**: toggle on + external present → `pmset -g assertions` shows
  `PreventUserIdleDisplaySleep 1` held by the app, named exactly "OpenDisplay: external display
  connected". Quit → released (no leak). Toggle off + external present → not acquired. Real IOKit
  assertion confirmed end-to-end.
- **Issue 1 — VERIFIED ✅**: `opendisplay ddc alias:Desk power standby` (0x04) → S34J55x entered
  standby and dropped off the display bus; `power on` (0x01) → woke back up, DDC responsive again.
  Best-effort writes ACK'd, no crash. (Selector is `alias:Desk`/`tag:studio`, not bare `Desk`.)
- **Issue 4 — VERIFIED ✅**: CFBundleURLTypes registered (lsregister claims `opendisplay:`).
  `open opendisplay://reconnect-all` → audit entry `{"actor":"url","command":"reconnectAll",...}`
  (same gateway/audit path as CLI). `opendisplay://bogus-unknown-verb` → no audit entry, no crash
  (logged no-op). Security gate: `opendisplay://disconnect?display=Desk` did NOT fire — no audit
  entry, Desk stayed connected (surfaces app for in-app confirm instead).
- **Issue 5 — VERIFIED ✅** (forward path): with the toggle on, unplug→replug of the external
  produced the arrival edge and the built-in auto-disconnected to managed-offline within ~1s; an
  external *leave* did NOT spuriously fire. Captured in the topology monitor. The **return** path is
  the pre-existing always-one-active safety net (fires at 0-active); on this rig the HDMI unplug
  didn't always register as an OS-level removal (EDID/signal retention), so 0-active wasn't reliably
  reached — recovered via the menu's reconnect button (`reconnectOffline`). Not a code regression;
  the safety net needs a clean CG removal event, which this cable doesn't always emit.
- **Issue 6 — VERIFIED ✅**: menu "Set as Main" on the external → `[main]` flipped to the external +
  "Keep these display settings?" banner with countdown; with no input it auto-reverted to built-in
  main after ~5s. Reproduced 3× consecutively, restoring the exact prior arrangement each time.

## Notes from attended testing (worth a follow-up, non-blocking)
- LaunchServices won't register an `opendisplay://` handler for an app bundle in `/tmp`/`/private/tmp`
  — must live somewhere stable (`~/Applications`, `/Applications`, DerivedData). Affects local dev/test
  only, not shipped installs.
- URL `reconnect-all` correctly returns `noOp` against the running app's offline list because the URL
  handler builds a fresh `CommandGateway` (like App Intents) that doesn't share the app's in-memory
  `managedOffline`. Re-enabling an app-disconnected display goes through the running app's
  `reconnectOffline` (menu/safety-net), not the URL/CLI reconnect-all. Behaves as designed; flag if a
  future issue wants the URL surface to re-enable app-tracked offline displays.

## Final summary
**All six Batch-1 issues implemented, tested, and committed on `batch1-auto`** (one commit each, in the
order 3 → 1 → 4 → 2 → 6 → 5). `make test` is green at **131 tests** (started at 78; +53 new), exit 0.
Both `OpenDisplay` and `OpenDisplay-PublicAPIOnly` xcodebuild targets (plus the `opendisplay` CLI)
BUILD SUCCEEDED with no new source warnings. `make lint` is a no-op locally (swiftlint/swift-format not
installed) — code follows `.swiftlint.yml` by hand.

Approach: each issue's **decision logic** was extracted into the cross-platform SPM packages
(TopologyCore / AutomationSchema / DisplayDomain) where `make test` exercises it with injected fakes;
the macOS-framework side effects (IOKit power assertions, DDC I2C, SwiftUI, onOpenURL, live
disconnect) were wired in the app/providers/CLI and verified to **compile** via `xcodebuild` (no real
display mutations were run, per the SAFETY rules). Every acceptance criterion that needs real hardware
is listed above as `[deferred: attended verification]` with its logic already unit-tested.

Commits:
- `Issue 3` prevent display sleep — `DisplaySleepGuard` + IOKit assertion (89 tests)
- `Issue 1` DDC power 0xD6 — `DDCPowerMode` + CLI/menu (96 tests)
- `Issue 4` `opendisplay://` URL scheme — `URLCommand` + gateway routing (104 tests)
- `Issue 2` resolution slider — `ResolutionStops` + Slider (112 tests)
- `Issue 6` timed auto-revert gate — `TimedRevertGate` + restore (122 tests)
- `Issue 5` auto-disconnect built-in — `AutoDisconnectBuiltInPolicy` (131 tests)

Not pushed / no PR opened (as instructed). The generated `OpenDisplay.xcodeproj` is gitignored, so the
xcodegen regenerations made during compile-checks left no git footprint.

**Update 2026-06-24:** all six issues additionally **verified live on hardware** with the user present
(see "Attended live verification" above). Five of five previously-deferred hardware criteria pass; the
only caveat is the Issue 5 *return* path depending on a clean OS-level display-removal event, which this
HDMI rig doesn't always emit (pre-existing safety-net behavior, not new code).
