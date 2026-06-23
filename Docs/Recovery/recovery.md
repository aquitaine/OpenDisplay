# Recovery model

Recovery is a first-class product feature, not an afterthought. A display tool can remove
the surface that contains its own recovery UI, so recovery must work **independently of the
main app**. Normative source: [PRD](../PRD.md) §9.

## Disconnect transaction stages

Every logical disconnect runs through these staged steps (PRD §9.4), serialized by the
`TopologyCoordinator`:

1. **Resolve target** — persistent identity; refresh route & topology generation.
2. **Reconcile** — wait for prior topology events to stabilize.
3. **Preflight safety** — safe surface, identity threshold, OS/provider compatibility,
   recovery-service health (non-bypassable; see `SafetyEngine`).
4. **Checkpoint** — atomic snapshot of topology, modes, main/mirror, managed-offline set,
   recovery metadata, written **before** any provider call.
5. **Confirm** — first-use / elevated-risk countdown on a safe display, showing the target
   and the recovery shortcut.
6. **Apply** — invoke the provider with a transaction ID and deadline.
7. **Observe** — collect normalized OS events for this transaction.
8. **Verify** — target inactive/managed AND a safe surface remains active AND registry
   stable; otherwise roll back or mark degraded.
9. **Commit** — persist the managed-offline record, actor, reason, policy, verified state,
   and a new checkpoint.

## Recovery hierarchy

Ordered from least to most drastic (PRD §9.11). Earlier options are always preferred:

1. **Cancel** during the confirmation countdown.
2. **Undo** from the activity log while still reversible.
3. **Reconnect All** from the menu bar or a global hotkey.
4. **Automatic rollback** from the last-known-safe checkpoint.
5. **Standalone rescue utility / rescue CLI** (independent process).
6. **Safe-mode startup** via a modifier key or command.
7. **Selective reset** of lifecycle policies / provider cache.
8. **Documented manual removal** of login item / configuration (last resort).

> **P0 release rule:** any known path that can leave a supported default configuration
> without a usable recovery surface **blocks release**. A Labs label does not waive this.

## Safe surface

A safe surface is an active endpoint on which you can receive recovery feedback and invoke
recovery. The default rule requires a local active display that is **not** in the target
set, **not** expected to vanish from lid/power policy, **not** mirrored or blacked-out, and
has a stable identity. The current main being the target is a special case: the main /
recovery role must move to a verified safe display before the target is removed.

## States are never conflated

`Black Out`, `Monitor Sleep/Power`, `Logical Disconnect`, `Reconnect`, and physical unplug
are distinct concepts throughout the code, copy, and APIs. A display's full state is
`reachability × presentation overlay × monitor power` (see
`DisplayDomain/LifecycleState.swift`). The product never claims that logical disconnect
frees a hardware pipeline, bypasses display-count limits, or emulates cable removal.
