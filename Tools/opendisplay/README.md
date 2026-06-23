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
