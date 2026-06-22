# Changelog

All notable changes to OpenDisplay are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/). OpenDisplay is pre-1.0 (0.x); anything may
change until 1.0.

## [Unreleased]

### Added
- Project scaffolding: SPM monorepo with platform-independent domain packages
  (`DisplayDomain`, `ProviderInterfaces`, `SceneEngine`, `AutomationSchema`,
  `TopologyCore`) plus `SimulatorProvider`, and their unit tests.
- Safety core: lifecycle & transaction state machines, `SafetyEngine` (safe-surface and
  preflight rules), `IdentityScorer` (multi-signal confidence), and the serialized
  `TopologyCoordinator` with checkpoint/rollback.
- `SceneEngine` desired-state planner with deterministic, idempotent, safely-ordered diffs.
- Stable `AutomationSchema` JSON result envelope and selector grammar.
- CI workflow running cross-platform domain tests on Linux and macOS.
- Initial documentation (architecture, recovery model, decisions, PRD) and open-source
  governance (contributing, security, code of conduct, RFC and issue/PR templates).
- macOS target scaffolding for the app, rescue utility, CLI, providers, and design system.
- Local-first developer tooling: `Makefile` (`make bootstrap`/`build`/`test`/`lint`) and
  `scripts/bootstrap-swift.sh` to install a Swift 6 toolchain on Ubuntu / verify Xcode on macOS.

### Changed
- Hardened the disconnect transaction after review: `.blocked` preflights are non-bypassable
  (removed the `userOverride` escape hatch); the confirmation handler now defaults to *cancel*
  rather than silently approving `.needsConfirmation`; and verification now rolls back if any
  unrelated active display is unexpectedly lost, not only the target (PRD §9.2/§9.4).
