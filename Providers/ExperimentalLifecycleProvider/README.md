# ExperimentalLifecycleProvider

**macOS target — optional, isolated.** The logical connect/disconnect mechanism. This is the
most safety-sensitive code in the project and is kept behind the `LifecycleProvider` protocol
(`Packages/ProviderInterfaces`) so it can be compiled, tested, disabled, kill-switched, or
**excluded entirely** from the public-API-only build (PRD §9.9, §10.9, OSS-02, D-001/D-008).

- Feature-flagged and runtime-probed; certified per OS/Mac family (Apple Silicon baseline).
- Never reports its own success — the `TopologyCoordinator` verifies postconditions.
- A `recover(to:)` path restores from a checkpoint with minimal dependencies.

Milestone: **M0 spike → M2**. The full transaction logic that drives this provider already
exists, platform-independently, in `Packages/TopologyCore` and is tested against
`SimulatorProvider`.

> Stub — concrete implementation added on macOS in Xcode after the M0 boundary memo (Q-002).
