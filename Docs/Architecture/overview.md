# Architecture overview

This document summarizes how OpenDisplay is structured. The normative source is
[the PRD](../PRD.md) §10 (Technical architecture) and §9 (Safe display disconnection).

## Layering

```
UI (SwiftUI) / App Intents / CLI / local HTTP (1.x) / Rescue
                        │
                  CommandGateway / AutomationGateway   ← all external commands take the same
                        │                                 safety/verification/audit path
            TopologyCoordinator (actor)   ← single owner of every topology/lifecycle write
        ┌───────────────┼────────────────┐
   ScenePlanner     SafetyEngine     Activity/Audit
        └────────── Desired State ───────┘
                        │
              DisplayRegistry (actor)   ← single source of OBSERVED truth; topology generations
        IdentityResolver · CapabilityResolver
                        │
              ProviderRouter / ControlRouter
   ┌──────────┬──────────┬───────────┬──────────────┬───────────────────────┐
 CoreGraphics   DDC    NativeControl  Capture   ExperimentalLifecycle   VirtualDisplay
  Provider    Provider   Provider    Provider     (optional target)      (Labs target)
                        │
                  macOS + display hardware

Persistent: SettingsStore · CheckpointStore (rescue-readable) · HealthMarker ·
            DiagnosticsStore · Keychain · UpdateCompatibility · RecoveryService
```

## What lives where

| Layer | Packages / targets | Platform |
|-------|--------------------|----------|
| Domain (pure logic) | `DisplayDomain`, `ProviderInterfaces`, `SceneEngine`, `AutomationSchema`, `TopologyCore`, `SimulatorProvider` | cross-platform; `swift test` in CI |
| Concrete providers | `Providers/*` | macOS |
| Apps & tools | `Apps/OpenDisplay`, `Apps/OpenDisplayRescue`, `Tools/opendisplay` | macOS |
| Design system | `Packages/OpenDisplayDesignSystem` | macOS (SwiftUI) |

The split is deliberate: the safety-critical logic (identity scoring, the lifecycle &
transaction state machines, the safety engine, the scene planner) is **platform-independent
and fully unit-testable without hardware**. Concrete providers implement the protocols in
`ProviderInterfaces`; the coordinator only ever talks to protocols, so it can be exercised
end-to-end against `SimulatorProvider`.

## Concurrency & ownership

- `DisplayRegistry` (actor) owns normalized **observed** state and bumps the
  `TopologyGeneration` only after the topology stabilizes.
- `TopologyCoordinator` (actor) owns the **mutation queue**; at most one transaction is
  non-terminal at a time. Recovery preempts ordinary work.
- Providers are stateless where practical; per-route caches are versioned by topology
  generation.
- UI consumes immutable snapshots and submits commands — it never mutates domain models.

## Key invariants (enforced in `TopologyCore`)

1. At most one topology/lifecycle transaction is active.
2. No logical disconnect without an atomic last-known-safe checkpoint.
3. No default operation removes the last known-safe recoverable display.
4. A target below the destructive identity-confidence threshold is not mutated without
   explicit confirmation.
5. Success is reported only after observed postconditions; otherwise failed / unverified /
   degraded / rolled back.
6. Reconnect All preempts queued work and is reachable from an independent process.

See [the recovery model](../Recovery/recovery.md) for the disconnect transaction stages and
the recovery hierarchy.

## Build flavors

- **Core / full** — public APIs + hardware protocols + narrowly isolated experimental
  providers approved by maintainers.
- **Public-API-only** — documented Apple APIs + hardware/network protocols only; no
  private lifecycle/virtual/system-override provider. CI keeps this flavor green (NFR-010).
- **Labs** — opt-in, kill-switchable modules for unstable/undocumented behavior; never a
  Core startup or recovery dependency.
