# Architecture decision records

Accepted and proposed decisions carried from the [PRD](../PRD.md) §21 decision log. New
significant decisions are added here (newest first) and, when they change provider
interfaces, lifecycle invariants, schema/API, telemetry, licensing, or Labs graduation,
must go through an [RFC](../RFCs/0000-template.md).

| ID | Decision | Status | Rationale |
|----|----------|--------|-----------|
| D-001 | Core / Labs product split | Accepted | Keeps experimental system mechanisms out of normal startup & recovery. |
| D-002 | Apple Silicon is the certified lifecycle baseline | Accepted | Public evidence shows materially different Intel behavior. |
| D-003 | Logical disconnect is a transaction, not a direct command | Accepted | Enables preflight, checkpoint, verification, rollback, audit. |
| D-004 | Ship a standalone rescue utility | Accepted | The main UI may be on the very display being removed. |
| D-005 | Normal quit reconnects managed-offline displays by default | Accepted | Conservative recovery expectation; persistence stays explicit. |
| D-006 | No analytics by default | Accepted | Open-source trust; display/capture sensitivity. |
| D-007 | Direct signed/notarized distribution is the baseline | Accepted | Advanced lifecycle features may not fit App Store constraints. |
| D-008 | Maintain a public-API-only build path | Accepted | Reduces platform/legal risk; preserves a stable subset. |
| D-009 | Stable internal IDs + scored fingerprint evidence | Accepted | Transient display IDs and identical hardware make single-key identity unsafe. |
| D-010 | Provider call success is not product success | Accepted | All applicable operations require observation/read-back or an explicit `unverified` result. |
| D-011 | Working license direction is GPL-3.0-or-later for the app | Proposed | Strong copyleft supports the open-source goal; counsel/community approval required. |
| D-012 | Working project name is "OpenDisplay" | Proposed | Internal label only; trademark/package-identifier clearance required. |

## How decisions map to code

- D-003 / D-010 → `Packages/TopologyCore` (`TopologyCoordinator`, `SafetyEngine`) and the
  transaction state machine in `Packages/DisplayDomain/LifecycleState.swift`.
- D-009 → `Packages/DisplayDomain/Identity.swift` (`IdentityScorer`, confidence threshold).
- D-001 / D-008 → provider isolation behind `Packages/ProviderInterfaces`; the
  experimental lifecycle and virtual-display providers are separable targets absent from
  the public-API-only flavor.
- D-004 → `Apps/OpenDisplayRescue` reads the `CheckpointStore` format independently.

## Open questions (need owners / legal)

Q-001 certified OS/Mac matrix · Q-002 private-API/entitlement set · Q-003 rescue process
topology · Q-004 default recovery hotkey · Q-005 license/SDK boundary. See PRD §21.2.
