# opendisplay (CLI)

**macOS target** (Swift ArgumentParser). Scripts all supported get/set/toggle/scene/lifecycle
actions through the same `AutomationGateway` — and therefore the same identity, capability,
safety, transaction, verification, and audit path — as the UI (PRD §12, AUT-001..004/011).

- Stable selectors (`Packages/DisplayDomain/Selector.swift`); ambiguous selectors return
  candidates and perform no mutation.
- Machine-readable JSON via `Packages/AutomationSchema` (`ResultEnvelope`); documented exit codes.
- `--dry-run` for every multi-field or lifecycle mutation.

Proposed grammar (PRD §12.2):

```
opendisplay list [--state active|offline|all] [--json]
opendisplay get <selector> [field ...] [--json]
opendisplay set <selector> <field=value>... [--dry-run] [--json]
opendisplay connect|disconnect <selector> [--dry-run]
opendisplay blackout <selector> on|off|toggle
opendisplay scene list|show|apply|export|import <name> [--dry-run]
opendisplay recover all|checkpoint|safe-mode
opendisplay diagnose display|route|provider|bundle [selector]
```

Milestone: **M1**.

> Stub — Xcode/SPM executable target added on macOS.

## Sensor + streaming commands (Issue #34)

```
opendisplay lux [--json]      # current ambient-light reading, in lux
opendisplay lid [--json]      # lid open/closed state
opendisplay listen            # stream brightness/config events as line-delimited JSON
```

`lux` reads the built-in ambient light sensor directly (the same best-effort IOKit path Adaptive
Display's ambient mode falls back to — see `AmbientLight.swift`). `lid` derives open/closed from the
same two signals Adaptive Display already senses (`LidStatePolicy`): an active built-in panel, or a
readable ambient sensor, both mean the lid is open; neither means closed, best-effort. Both exit
non-zero with a message on stderr when the reading/state is unavailable (no sensor on this Mac, no
built-in panel to reason about, etc.) — nothing is printed to stdout in that case.

### `listen`

Streams one JSON object per line to stdout until interrupted with Ctrl-C (clean exit, no stack
trace). Output is line-buffered, so a piped consumer (`opendisplay listen | jq .` or `| tail -f`)
sees each event as it happens rather than batched at exit.

Two event kinds share one envelope (`ListenEvent` in `AutomationSchema`), distinguished by `event`.
`version` and `event` are on every line; the remaining keys are present only when that event kind
sets them (a `config` line has no brightness keys and vice versa):

```jsonc
// A live brightness change (menu, media key, another CLI invocation, or an App Intent).
{"version":1,"event":"brightness","timestamp":1737482921.5,"displayId":"cg:abc",
 "displayName":"Studio Display","level":0.62,"source":"mediaKey"}

// The display topology changed: hotplug, mode/resolution, rotation, mirror, or main display.
{"version":1,"event":"config","timestamp":1737482925.0,
 "displays":[{"id":"cg:abc","active":true,"main":true,"mode":"3840x2160@60"}]}
```

`brightness` events require **Broadcast OSD events** enabled in OpenDisplay's Settings (default
off) — `listen` prints a one-time note to stderr on startup when it's off, so brightness stays
silent but visibly explained rather than silently empty. `config` events need no setting; they come
from the same `CGDisplayRegisterReconfigurationCallback` source the app itself watches.

Out of scope for this pass: volume/mute OSD events (the `OSDBroadcast` channel carries them, but
`listen` only forwards `brightness` today — a natural follow-up `event` kind, not a schema change).
