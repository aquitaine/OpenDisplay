# OpenDisplay — Batch 1 Issues (ready to file)

Six issues for the first build pass: **five quick wins** the audit confirmed have the most existing
scaffolding, plus **one safety-hardening item** the audit surfaced. Each is self-contained — paste as
a GitHub issue, or work from this file directly.

Target: **Apple Silicon only.** Line/symbol references are from the repo audit. Where a feature has a
private-SPI path, keep it behind the existing `#if !PUBLIC_API_ONLY` gate and `dlsym` resolution so
the public-API build still compiles and degrades gracefully.

Suggested order: **#1, #2 + #6 together, #3, #4, #5.** (#6 should land with or just before the
resolution slider in #2.)

---

## Issue 1 — Add DDC power control (VCP `0xD6`)

**Type:** feature · **Effort:** ~hours · **Risk:** low

**Current state.** The full DDC read/write/coalesce path exists (`DDCControl.swift`), but the `Feature`
enum has no `0xD6` case. Sibling controls (input `0x60`, color preset `0x14`) are already wired end to
end, so this is a copy of an established pattern.

**Acceptance criteria.**
- A `Feature`/VCP case for power mode (`0xD6`) is added to `DDCControl.swift`.
- `AppModel` exposes `setPowerMode(_:)` alongside `setInputSource` (`AppModel.swift:134`, `:806`).
- Menu item under the display's DDC controls (near `DisplayDetailView.swift:204`) offering **On /
  Standby / Off**.
- CLI verb `opendisplay ddc … power <on|standby|off>` mirroring the existing `ddc … input` verb.
- Sends are best-effort and never crash if the display NAKs or ignores the write.

**Implementation pointers.** Standard DPM values for `0xD6`: `0x01` On, `0x04` Off (DPMS), `0x05` Off
(hard). Exact accepted values vary by display — read them from the capabilities string where available
rather than assuming (ties into a future auto-config issue).

**Testing.** Send Standby/Off → panel powers down; send On → wakes (note: many displays can't be woken
over DDC once off — document and handle gracefully). Verify via read-back where the display supports it.

---

## Issue 2 — Replace the resolution dropdown with a slider

**Type:** feature (UI) · **Effort:** ~hours · **Risk:** low · **Companion:** #6

**Current state.** The backend is done — `CoreGraphicsProvider.swift:394 availableModes` returns one
mode per point-size, area-sorted, and `setMode` works. The UI renders a discrete `Menu`
(`DisplayDetailView.swift:85-99`), not a slider. Comments already assume a slider
(`AppModel.swift:633`), so this closes an intended-but-unfinished path.

**Acceptance criteria.**
- The resolution `Menu` in `DisplayDetailView.swift:85-99` is replaced by a `Slider` bound to the
  index into the area-sorted `availableModes`.
- Dragging the slider applies via `setMode`; the current mode is reflected as the slider position.
- The active stop's label shows resolution (and refresh / HiDPI where relevant).
- Single-mode displays hide or disable the slider (no dead control).

**Implementation pointers.** Pure UI/binding change; do not touch the provider. Index discipline must
match the area-sort so stops are monotonic.

**Testing.** Slider steps through every mode in order; selecting applies and lands on the correct mode;
verify the edge case of one-mode displays.

**Note.** Pair with #6 — a slider makes it trivial to slam through modes, so the timed auto-revert
safety gate should be in place when this ships. Commit-on-release + revert prompt.

---

## Issue 3 — Prevent display sleep while an external is connected

**Type:** feature · **Effort:** ~half day · **Risk:** low

**Current state.** No `IOPMAssertion` anywhere in the tree; `SettingsStore.swift` currently holds three
keys. Greenfield but small and self-contained.

**Acceptance criteria.**
- A new `SettingsStore` toggle (default off) + a menu item.
- While the toggle is on **and** ≥1 external display is present, hold an
  `IOPMAssertionCreateWithName` of type `kIOPMAssertionTypePreventUserIdleDisplaySleep`.
- The assertion is released when the last external is removed, or the toggle is turned off.
- No leaked assertions across connect/disconnect cycles or app relaunch.

**Implementation pointers.** Hook external-presence transitions in `observeTopologyChanges`
(`AppModel.swift:1071-1090`); store the assertion handle on the model; release symmetrically.

**Testing.** Enable + external connected → display doesn't idle-sleep; disconnect or disable → assertion
gone. Verify with `pmset -g assertions`.

---

## Issue 4 — `opendisplay://` URL-scheme automation

**Type:** feature · **Effort:** ~half day · **Risk:** low–medium (external trigger — see security note)

**Current state.** No `CFBundleURLTypes`, no `onOpenURL`, no HTTP listener. But a safe command surface
already exists and is reused by two front ends: the `opendisplay` CLI (`main.swift`:
list/disconnect/reconnect/recover/scene/brightness/ddc, `--json`) and App Intents/Siri
(`OpenDisplayIntents.swift`) — both routing through the same `CommandGateway`. This issue is just a
third front door onto that gateway.

**Acceptance criteria.**
- `CFBundleURLTypes` registered for `opendisplay://` in the app `Info.plist`.
- `.onOpenURL` parses the URL and maps it onto existing `CommandGateway` commands.
- Every action goes through the **same** safety-checked/audited path as the CLI (an audit entry
  appears).
- Malformed or unknown URLs are a logged no-op, never a crash.
- **Scope:** URL scheme only. The embedded HTTP listener is a separate later issue.

**Implementation pointers.** Mirror the CLI verb table (`main.swift`) in a small URL→command mapper;
reuse `CommandGateway` rather than re-implementing actions.

**Security note.** URL handlers can be invoked by any app or web link. Expose only the safe command
surface; anything destructive or arrangement-altering must require explicit in-app confirmation, not
fire silently from a URL. Do not accept arbitrary parameters that bypass the gateway's checks.

**Testing.** `open "opendisplay://reconnect-all"` (and a few others) trigger the action; a malformed URL
is ignored with a log line; confirm routing via the audit trail.

---

## Issue 5 — Auto-disconnect the built-in panel when an external connects

**Type:** feature · **Effort:** ~half day · **Risk:** low (mechanism + safety already exist)
**This is the project's original use case, made automatic.**

**Current state.** Only the fall-back exists: `enforceActiveSurfaceInvariant` fires when **0** displays
are active (the re-enable safety net), `AppModel.swift:1071-1090`. Nothing watches "external arrived →
turn off built-in." Manual disconnect, `setDisplayActive`, and the `SafetyEngine` are all in place.

**Acceptance criteria.**
- A policy toggle (default **off**) + menu item.
- When on, an external-arrival transition (detected in `observeTopologyChanges`) calls the existing
  `setDisplayActive(false)` on the **built-in**, routed through the gated
  `TopologyCoordinator`/`SafetyEngine` path.
- When the external later disappears, the built-in returns (the existing safety net already covers
  this — verify, don't duplicate).
- Connecting a **second** external does not re-trigger; turning the toggle off restores normal
  behavior.

**Implementation pointers.** Transition detection only — reuse `setDisplayActive(false)` and the
existing gated path; add the `SettingsStore` key. Do not add a new disconnect mechanism.

**Testing.** Toggle on + connect external → built-in turns off, external stays; disconnect external →
built-in returns; second external → no re-trigger; toggle off → no auto behavior.

---

## Issue 6 — Safety gate for arrangement-altering changes (timed auto-revert)

**Type:** safety hardening · **Effort:** ~0.5–1 day · **Risk:** low · **Recommended before/with #2**

**Why.** The audit found that only logical disconnect/reconnect is gated by the `SafetyEngine`.
**Set-main, mirror, and resolution changes alter the active arrangement but bypass it** — they're
applied directly (`CoreGraphicsProvider` / `DDCControl`). A bad resolution or mirror change can leave a
display unreadable while it's still technically "active," so it doesn't get the checkpoint/independent
-recovery guarantee that disconnect does. This contradicts the project's *safety-before-capability*
principle, and the incoming resolution slider (#2) makes it easy to trigger.

**Acceptance criteria.**
- Resolution, mirror, and set-main changes are wrapped in a checkpoint with a **macOS-style timed
  auto-revert**: apply → prompt "Keep these settings? Reverting in N seconds" → revert to the prior
  state unless confirmed.
- Revert restores the exact prior arrangement (mode/origin/mirror/main).
- The confirmation surface is reachable even if the *changed* display became unreadable (e.g. prompt
  shown on a still-good display, and/or confirmable via the existing global hotkey / rescue path).
- Consistent with the existing rotation marker/rollback pattern (`AppModel.swift:889`) — reuse it
  rather than inventing a parallel mechanism.

**Implementation pointers.** Extend the checkpoint/rollback approach rotation already uses; the
`SafetyEngine` + audit trail are the right home. Decide whether to route these ops through the gateway
or keep them direct-but-checkpointed — either is fine as long as the revert is independently reachable.

**Testing.** Apply an unsupported/blank resolution → it auto-reverts after the timeout without
confirmation; confirm within the window → it sticks; verify revert restores the prior arrangement
exactly; verify confirmability when the target display is unreadable.

---

## Not yet converted (rest of Tier 1 — say the word and I'll write these next)

DDC power's siblings **DDC auto-config** (parse capabilities string) · **EDID export** (raw
`IODisplayEDID` blob read + file export — currently only EDID-*derived* fields are read) · **favorite
resolutions** (pin/recall on top of `availableModes`) · **expand keyboard shortcuts** (the
`GlobalHotKey` Carbon class is reusable — generalize beyond the single Reconnect-All binding) ·
**native-looking OSD** + **notch-app integration API** · **networked TV/AVR control** (LG/Samsung/
Philips/Yamaha — the largest self-contained greenfield chunk) · **Night Shift for TVs**.
