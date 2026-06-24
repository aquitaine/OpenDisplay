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

## In progress
- (none)

## Tried / stuck  (so the next attempt doesn't repeat it)
- (none yet)

## Deferred to attended verification
- Issue 3: final `pmset -g assertions` confirmation with a real external attached `[deferred: attended
  verification]` — the create/hold/release lifecycle is fully unit-tested via the injected backend;
  only the live OS-assertion read needs hardware.

## Final summary
- (fill in when stopping)
