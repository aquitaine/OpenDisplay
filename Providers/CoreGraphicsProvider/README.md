# CoreGraphicsProvider

**macOS target.** Public display enumeration and configuration via Core Graphics:
enumerate endpoints, read/apply bounds, modes, mirror sets, and main display where supported
(PRD §10.3, TOP-001/002/003). Documented-API boundary; ships in every build flavor including
public-API-only.

Implements: the macOS source for `DisplayRegistry` observations and a `TopologyObserving`
event source feeding `TopologyCore`. Milestone: **M0/M1**.

> Stub — concrete implementation added on macOS in Xcode. It conforms to the protocols in
> `Packages/ProviderInterfaces`.
