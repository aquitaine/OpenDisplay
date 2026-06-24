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

## In progress
- (none)

## Tried / stuck  (so the next attempt doesn't repeat it)
- (none yet)

## Deferred to attended verification
- Issue 3: final `pmset -g assertions` confirmation with a real external attached `[deferred: attended
  verification]` — the create/hold/release lifecycle is fully unit-tested via the injected backend;
  only the live OS-assertion read needs hardware.
- Issue 1: confirming a real panel actually powers down on Standby/Off and the wake-once-off behavior
  `[deferred: attended verification]` — VCP value mapping + token parsing are unit-tested; the I2C
  round-trip to a physical monitor needs hardware (and is intentionally not exercised in this session).
- Issue 4: live `open "opendisplay://reconnect-all"` end-to-end trigger `[deferred: attended
  verification]` — would run a real reconnect on this Mac (SAFETY: no real lifecycle mutations). Parser,
  command mapping, security/confirmation gate, and audit routing are all unit-tested / build-verified.

## Final summary
- (fill in when stopping)
