**OPENDISPLAY**

Product Requirements  
Document

An open-source macOS display-management platform

|     |     |     |
|-----|-----|-----|

|     | **Primary product promise** Reliable control of multiple displays with safe, reversible display disconnection, strong recovery, and open governance. The design is clean-room and functionally inspired by publicly documented display-management workflows; it is not affiliated with or endorsed by BetterDisplay. |
|-----|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

**DRAFT v1.0**

Prepared: 21 June 2026

Status: Product and technical baseline for discovery, architecture, and delivery planning

Audience: Product, macOS engineering, design, QA, security, legal, and open-source maintainers

**Working name only.** “OpenDisplay” requires trademark and package-identifier clearance before public use.

# Document control

| **Field**          | **Definition**                                                                                                                                    |
|--------------------|---------------------------------------------------------------------------------------------------------------------------------------------------|
| Document owner     | Product lead / founding maintainer                                                                                                                |
| Technical owner    | macOS platform lead                                                                                                                               |
| Decision authority | Maintainer council for product scope; security owner for recovery-critical changes                                                                |
| Status             | Draft baseline                                                                                                                                    |
| Version            | 1.0                                                                                                                                               |
| Date               | 21 June 2026                                                                                                                                      |
| Target release     | Core 1.0, followed by Core 1.x and opt-in Labs                                                                                                    |
| Primary platforms  | macOS 13 Ventura through macOS 26 Tahoe; Apple Silicon first                                                                                      |
| License direction  | GPL-3.0-or-later for the application and recovery stack; Apache-2.0 or MIT for a separately packaged SDK, subject to legal review                 |
| Research method    | Clean-room synthesis of public product pages, documentation, release notes, issue reports, Apple documentation, and adjacent open-source projects |

## Approval record

| **Role**             | **Name** | **Decision** | **Date** |
|----------------------|----------|--------------|----------|
| Product              | TBD      | Pending      | —        |
| Engineering          | TBD      | Pending      | —        |
| Security             | TBD      | Pending      | —        |
| Design/accessibility | TBD      | Pending      | —        |
| Legal/open-source    | TBD      | Pending      | —        |

## How to use this PRD

This document establishes product intent, scope, user outcomes, functional and non-functional requirements, safety rules, architecture boundaries, release stages, acceptance gates, and research provenance. It deliberately separates Core features from Labs features that may rely on undocumented macOS behavior. Requirement IDs are normative. Narrative sections explain rationale and implementation constraints but do not override explicit acceptance criteria.

|     | **Normative language** “Shall” indicates a release requirement. “Should” indicates a committed target that may be deferred only through an explicit product decision. “Could” indicates optional scope. “Experimental” does not relax safety, recovery, privacy, or transparency requirements. |
|-----|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# Contents

| **1**  | [<u>Executive summary</u>](#executive-summary)                                                                       |
|--------|----------------------------------------------------------------------------------------------------------------------|
| **2**  | [<u>Product principles and clean-room boundary</u>](#product-principles-and-clean-room-boundary)                     |
| **3**  | [<u>Problem, opportunity, and users</u>](#problem-opportunity-and-users)                                             |
| **4**  | [<u>Goals, success definition, and non-goals</u>](#goals)                                                            |
| **5**  | [<u>Scope and release model</u>](#scope-and-release-model)                                                           |
| **6**  | [<u>Research synthesis</u>](#research-synthesis)                                                                     |
| **7**  | [<u>Reference feature inventory and proposed disposition</u>](#reference-feature-inventory-and-proposed-disposition) |
| **8**  | [<u>Product experience and core workflows</u>](#product-experience-and-core-workflows)                               |
| **9**  | [<u>Safe display disconnection subsystem</u>](#safe-display-disconnection-subsystem)                                 |
| **10** | [<u>Technical architecture</u>](#technical-architecture)                                                             |
| **11** | [<u>Detailed requirements</u>](#detailed-requirements)                                                               |
| **12** | [<u>Automation and integration contract</u>](#automation-and-integration-contract)                                   |
| **13** | [<u>Data, configuration, and migration</u>](#data-configuration-and-migration)                                       |
| **14** | [<u>Security, privacy, and permissions</u>](#security-privacy-and-permissions)                                       |
| **15** | [<u>Quality, test strategy, and hardware matrix</u>](#quality-test-strategy-and-hardware-matrix)                     |
| **16** | [<u>Success metrics and release gates</u>](#success-metrics-and-release-gates)                                       |
| **17** | [<u>Distribution and update strategy</u>](#distribution-and-update-strategy)                                         |
| **18** | [<u>Open-source governance and licensing</u>](#open-source-governance-and-licensing)                                 |
| **19** | [<u>Delivery roadmap</u>](#delivery-roadmap)                                                                         |
| **20** | [<u>Risk register</u>](#risk-register)                                                                               |
| **21** | [<u>Decision log and open questions</u>](#decision-log-and-open-questions)                                           |
| **22** | [<u>Sources and research notes</u>](#sources-and-research-notes)                                                     |
| **23** | [<u>Glossary</u>](#glossary)                                                                                         |

|     | **Navigation note** The contents links are clickable in Word-compatible readers. Requirement and feature tables use stable IDs for issue tracking and traceability. |
|-----|---------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 1. Executive summary

OpenDisplay is an independently designed, open-source macOS display-management application for people who need predictable control over multiple displays. Its defining capability is safe display lifecycle management: the user can logically disconnect and reconnect supported displays without physically unplugging them, while retaining emergency recovery even when the display containing the app is removed from the active desktop.

|     | **Recommended product strategy** Ship a dependable Core before pursuing feature parity at the system-override layer. Core 1.0 should make multi-display identity, topology, scenes, DDC/software controls, automation, disconnect/reconnect, diagnostics, and recovery trustworthy. HiDPI overrides, virtual displays, EDID/system overrides, forced HDR/XDR behavior, and streaming belong in opt-in Labs. |
|-----|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

## Product thesis

macOS exposes useful public display APIs, but advanced users still experience fragile identities, inconsistent wake behavior, limited external-monitor controls, and no unified way to describe a desired multi-display state. Existing utilities often solve one slice—DDC, placement, virtual displays, or brightness—while a full platform must coordinate them as one stateful system. OpenDisplay will treat the desktop as a reconciled topology with explicit desired state, transactional changes, verified outcomes, and independent recovery.

## Primary outcomes

- **Control many displays.** One consistent registry, topology view, scene model, and automation surface for built-in, external, wireless, virtual, active, and remembered-offline endpoints.

- **Disconnect without fear.** Logical disconnect is a guarded transaction with identity confidence, safe-surface preflight, checkpoint, verification, rollback, and Reconnect All.

- **Automate predictably.** Stable selectors, idempotent scenes, dry-run planning, App Intents, CLI, and later authenticated local HTTP integration.

- **Stay open and inspectable.** Source, architecture, recovery logic, schemas, SBOM, release provenance, and issue decisions are public.

- **Degrade honestly.** Unsupported behavior is explained by OS, hardware, route, permission, build flavor, or safety policy; the app never reports false success.

## Core 1.0 definition

Core 1.0 is complete when a user can install a signed/notarized build, identify and organize multiple displays, save and apply scenes, control supported brightness/audio/input routes, logically disconnect and reconnect supported Apple Silicon displays with automatic recovery, automate common actions, export diagnostics, and recover through safe mode or a standalone rescue utility. No Labs feature is required for Core stability or startup.

## Key product decisions

| **Decision**         | **Baseline**                                                                                                                    |
|----------------------|---------------------------------------------------------------------------------------------------------------------------------|
| Implementation       | Swift 6, SwiftUI plus AppKit where needed; actor-isolated state coordinator; provider interfaces around OS/hardware mechanisms. |
| Distribution         | Direct Developer ID signed and notarized releases; optional public-API-only build later.                                        |
| License direction    | Strong copyleft for the application/recovery stack; permissive license for a separately packaged SDK, subject to counsel.       |
| Telemetry            | None by default. Opt-in diagnostics and crash reporting only, with preview/redaction.                                           |
| Disconnect semantics | Four explicit actions: Black Out, Monitor Sleep/Power, Logical Disconnect, Reconnect.                                           |
| Safety model         | No destructive lifecycle action bypasses preflight, transaction serialization, verification, or recovery.                       |
| Compatibility        | Apple Silicon first; Intel best-effort and capability-gated; macOS 13 through current macOS 26 baseline.                        |
| Branding             | No BetterDisplay name, iconography, copy, UI cloning, or proprietary implementation reuse.                                      |

## What this document does not assert

- It does not assert that all publicly advertised reference features can be implemented using public APIs.

- It does not promise that logical disconnect is equivalent to cable removal, releases a GPU display pipeline, or increases a Mac model's supported display count.

- It does not treat public issue reports as prevalence data; they are design inputs and failure examples.

- It does not approve a final project name, license, entitlement set, or use of any third-party code without legal and technical review.

# 2. Product principles and clean-room boundary

## 2.1 Product principles

| **Principle**                       | **Application**                                                                                                            |
|-------------------------------------|----------------------------------------------------------------------------------------------------------------------------|
| Safety before capability            | A feature that can make the desktop unreachable is incomplete until recovery is independently usable.                      |
| Observed state is not desired state | The product must record what macOS/hardware currently reports, what the user wants, and which actor changed it.            |
| Stable identity over transient IDs  | A display ID is an observation, not an identity. Persistent behavior uses multi-signal fingerprints and user confirmation. |
| One coordinator owns topology       | UI, rules, Shortcuts, CLI, HTTP, and recovery requests converge on the same planner, queue, safety checks, and audit log.  |
| Verify, do not assume               | A provider call is not success. Operations are verified through OS events, read-back, or an explicit unverified result.    |
| Capability is contextual            | Support depends on Mac, OS, display, cable, adapter, dock/KVM, route, permission, build flavor, and policy.                |
| Open by default, risky by consent   | Source and behavior are inspectable; experimental system changes are opt-in and clearly reversible.                        |
| No false equivalence                | Black Out, monitor power, logical disconnect, and physical unplug are separate concepts throughout product copy and APIs.  |

## 2.2 Clean-room implementation policy

The project may study public behavior, public documentation, user reports, and legally usable open-source implementations to understand the problem space. It shall not copy BetterDisplay's proprietary executable, assets, strings, screenshots, internal structure, trade dress, or non-public behavior obtained through prohibited means. Feature names that are generic descriptions may be used when necessary, but product information architecture and interface design must be independently created.

- **Allowed inputs.** Public websites, public wiki pages, release notes, public issue reports, Apple's public documentation, observable OS behavior, and dependencies with compatible verified licenses.

- **Disallowed inputs.** Decompiled proprietary implementation, extracted private assets, copied UI layouts or marketing copy, confidential information, or code with unknown/incompatible provenance.

- **Contribution rule.** Every nontrivial contribution must be the contributor's original work or identify the upstream source and license. Maintainers may request provenance notes.

- **Naming rule.** Use a distinct project name, bundle identifier, icon, website, terminology hierarchy, and visual identity. Include a non-affiliation statement where comparison is discussed.

- **Compatibility language.** Describe functional outcomes and supported environments; do not imply drop-in identity or endorsement by the reference product.

|     | **Legal review gate** Before public launch, counsel should review trademark clearance, license choice, contributor terms, use of undocumented APIs, distribution representations, and any code inspired by public repositories whose license or provenance is unclear. |
|-----|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

## 2.3 Build-flavor boundary

| **Flavor**      | **Permitted implementation**                                                                                                             | **Expected capability**                                                                                                                  |
|-----------------|------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------|
| Core / full     | Public APIs, compatible open-source libraries, hardware protocols, and narrowly isolated experimental providers approved by maintainers. | Full Core feature set including guarded logical disconnect where supported.                                                              |
| Public-API-only | Documented Apple APIs and hardware/network protocols only.                                                                               | Topology, modes where public, DDC/software controls, scenes, capture, automation; no private lifecycle/virtual/system-override provider. |
| Labs            | Opt-in modules for unstable or undocumented behavior with separate compatibility flags.                                                  | HiDPI/custom-mode overrides, virtual endpoints, EDID/system overrides, forced HDR/XDR, advanced redirection/streaming.                   |

# 3. Problem, opportunity, and users

## 3.1 Problem statement

People with more than one display often manage a coupled system: display identity, placement, main-display assignment, mirroring, mode and refresh, brightness, audio, input source, profiles, sleep/wake, docking, and automation. macOS can change parts of this state after wake, reconnect, cable-route changes, or OS updates. Hardware protocols add another layer: the same monitor may expose DDC directly but not through a dock or KVM. A logical disconnect is particularly risky because it can remove the very screen needed to reverse the action.

## 3.2 Opportunity

An open-source product can make this domain inspectable and community-testable while consolidating capabilities that are currently spread across system settings and specialized tools. The differentiator is not the number of toggles. It is a trustworthy state and recovery model: stable identity, capability reasoning, transactional scene application, verifiable provider outcomes, and an emergency path that does not depend on the main UI.

## 3.3 Jobs to be done

- When I dock or undock, restore the intended arrangement, modes, controls, and active displays without flicker or manual cleanup.

- When a display should not participate in the desktop, remove it logically and make recovery obvious even if I chose the wrong screen.

- When I use identical monitors or change ports, keep my names, positions, and policies attached to the correct physical device.

- When a monitor or dock cannot perform an action, tell me whether the limitation is the OS, display, route, permission, or safety policy.

- When I automate my workspace, provide stable selectors, predictable errors, dry runs, and idempotent commands.

- When an update or experiment fails, start safely, reconnect displays, and give me a diagnostic record of what happened.

## 3.4 Personas

| **Persona**                 | **Context**                                                                | **Primary needs**                                                                             |
|-----------------------------|----------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| Multi-display professional  | Uses 2-6 external displays, docks, and changing workspaces.                | One-click scenes, predictable identity, safe disconnect, mode/layout protection.              |
| Laptop clamshell user       | Moves between desk, meeting room, and mobile use.                          | Auto-disconnect/reconnect built-in display, clear lid and power behavior.                     |
| Creative/HDR user           | Needs accurate profiles, HDR/XDR control, and consistent brightness.       | Profiles, nits-aware controls, guardrails against clipping or washout.                        |
| Developer/automator         | Wants reproducible setup from scripts, Shortcuts, and CI-like checks.      | Stable selectors, CLI/HTTP/App Intents, idempotent commands, machine-readable output.         |
| Accessibility/eye-care user | Needs reduced brightness, color filters, and predictable keyboard control. | Software dimming, filter profiles, Night Shift support, no inaccessible recovery path.        |
| Remote/headless operator    | Runs a Mac without a permanently attached physical monitor.                | Virtual display lifecycle, persistent scenes, remote-safe recovery, clear unsupported states. |
| IT/power user               | Supports varied Mac models, monitors, docks, and KVMs.                     | Diagnostics bundle, capability explanations, reversible settings, documented compatibility.   |

## 3.5 Representative usage environments

| **Environment** | **Typical topology**                                             | **Critical concerns**                                             |
|-----------------|------------------------------------------------------------------|-------------------------------------------------------------------|
| Laptop desk     | Built-in + 1-3 external via dock/KVM                             | Built-in auto-disconnect, DDC route changes, wake reconciliation. |
| Studio          | 2-6 direct or docked displays, HDR/reference display             | Profiles, HDR guardrails, consistent brightness, mode protection. |
| Presentation    | Built-in + projector/TV + capture/teleprompter                   | Fast scenes, mirroring, input switch, privacy, recovery.          |
| Remote/headless | No permanent physical display; optional virtual/headless adapter | Safe startup, remote-resilient modes, no black-screen loop.       |
| Hot desk        | Frequent unknown monitors and docks                              | Capability scan, no destructive default policy, portable scenes.  |
| Lab/IT support  | Many Macs, OS versions, adapters, and identical panels           | Diagnostics, deterministic test fixtures, compatibility database. |

# 4. Goals, success definition, and non-goals

## 4.1 Goals

1\. Deliver the safest practical logical display disconnect/reconnect experience on supported Macs, with independent recovery.

2\. Manage at least eight active or remembered displays without identity, ordering, or automation ambiguity.

3\. Unify topology, modes, controls, profiles, scenes, rules, and diagnostics in one consistent state model.

4\. Expose stable, documented automation through CLI and App Intents in Core 1.0; add authenticated local HTTP/event integrations in Core 1.x.

5\. Make unsupported states and experimental mechanisms transparent, capability-gated, and testable.

6\. Publish source, schemas, architecture decisions, security policy, release provenance, and contributor governance.

7\. Maintain a useful public-API-only build path even when the full build contains isolated experimental providers.

## 4.2 Success definition

The product succeeds when users can move among common multi-display workspaces without repeatedly opening System Settings, and when a failed display action produces a recoverable, explainable state rather than a black-screen incident. For Core 1.0, safety and predictability outweigh breadth: a smaller verified capability set is preferred to a broad set of unverified toggles.

## 4.3 Non-goals

- Replicating BetterDisplay's source code, brand, visual design, exact information architecture, licensing model, or every feature at launch.

- Circumventing Mac hardware limits, Digital Rights Management, HDCP, enterprise controls, or security protections.

- Guaranteeing DDC through every dock, KVM, adapter, cable, or monitor firmware.

- Claiming logical disconnect is a physical cable disconnect or that it always frees GPU/display-controller resources.

- Providing medical treatment or health claims through PWM, dithering, color, or brightness features.

- Supporting arbitrary remote internet control by default; network interfaces remain local and opt-in.

- Making Labs features prerequisites for normal startup, recovery, scene storage, or basic display controls.

- Supporting pre-macOS 13 in the initial maintained release line.

## 4.4 Prioritization rules

| **Priority** | **Meaning**                                          | **Decision rule**                                                  |
|--------------|------------------------------------------------------|--------------------------------------------------------------------|
| P0 / Must    | Required for Core release or safety.                 | No release with an unmet P0 unless scope is explicitly removed.    |
| P1 / Should  | High-value, committed target.                        | May defer only with documented impact and compatibility path.      |
| P2 / Could   | Optional enhancement.                                | Schedule after Core reliability and maintenance capacity.          |
| Labs         | Experimental, system-sensitive, or evidence-limited. | Opt-in, kill-switchable, and never part of Core safety dependency. |

# 5. Scope and release model

## 5.1 Compatibility target

| **Dimension**     | **Target**                                                                       | **Product implication**                                                                     |
|-------------------|----------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| Operating systems | macOS 13 Ventura through current macOS 26 Tahoe                                  | Core build; behavior gated by runtime capability tests. Reassess minimum after telemetry.   |
| Architectures     | Apple Silicon first; Intel best-effort                                           | Logical disconnect and some lifecycle features may be unavailable or experimental on Intel. |
| Display count     | At least 8 active/remembered displays; design for 16                             | Includes built-in, external, virtual, Sidecar, AirPlay, and offline remembered devices.     |
| Connections       | USB-C/Thunderbolt, HDMI, DisplayPort, docks, KVMs, network-controlled displays   | Per-route capability matrix; no assumption that DDC passes through.                         |
| Display classes   | Built-in, external, HDR/XDR, TVs, projectors, headless dongles, virtual displays | Features exposed only when safe and supported.                                              |
| Distribution      | Direct signed/notarized package; optional public-API-only flavor                 | App Store distribution is not the baseline for experimental lifecycle features.             |

## 5.2 Release rings

| **Ring**          | **Audience**                 | **Behavior**                                                                               |
|-------------------|------------------------------|--------------------------------------------------------------------------------------------|
| Canary            | Maintainers and hardware lab | Experimental providers enabled only by explicit developer flags; full diagnostics.         |
| Preview           | Technical contributors       | Core defaults; Labs opt-in; rapid compatibility flags and rollback.                        |
| Beta              | Broader volunteers           | Signed/notarized; migration supported; opt-in telemetry; known-issue list.                 |
| Stable            | General users                | Only certified OS/hardware combinations auto-enable lifecycle providers.                   |
| LTS consideration | Organizations/power users    | Security and compatibility fixes for selected stable branch if maintainer capacity allows. |

## 5.3 Core 1.0 scope

- Display registry, persistent identity, aliases/tags, topology model, capability explanations, and detailed display inspector.

- Safe logical disconnect/reconnect on certified Apple Silicon configurations, Black Out, monitor sleep/power where supported, Reconnect All, safe mode, and rescue utility.

- Layout, main display, mirroring, resolution/refresh/rotation, favorites, property protection, and scenes with preview and rollback.

- Native/DDC/software brightness, volume/mute/contrast/input where supported, keyboard routing, OSD, groups, sync, and rate limiting.

- Menu-bar UI, full settings window, accessibility baseline, CLI, App Intents/Shortcuts, export/import, logs, and diagnostics bundle.

- Direct signed/notarized open-source distribution, SBOM, contributor docs, security policy, and reproducible release metadata.

## 5.4 Deferred to Core 1.x

- Authenticated local HTTP API, event subscriptions, URL scheme, advanced rules, and plugin SDK.

- Nits-aware sync, richer color controls, SDR/HDR profile rules, network display/receiver providers.

- ScreenCaptureKit picture-in-picture, zoom, screenshots, and teleprompter rendering.

- UI-scale matching, window placement policies, and richer layout adaptation.

## 5.5 Labs scope

- Custom/flexible HiDPI and custom mode/system parameter overrides.

- Virtual displays, arbitrary headless resolutions, virtual HDR/refresh, and persistence.

- EDID/configuration overrides, encoding/range/chroma manipulation, forced HDR/XDR upscaling.

- Local streaming, display redirection, rotated Sidecar workarounds, and PWM/dithering mitigation experiments.

|     | **Scope guardrail** A Labs feature may graduate only after it has a provider contract, compatibility matrix, safe-mode bypass, diagnostics, automated fault tests, user documentation, and no open P0/P1 recovery defect. |
|-----|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 6. Research synthesis

## 6.1 Method

Research reviewed the reference product's public website, public GitHub materials, feature matrix, integration documentation, specialist wiki pages, current release information, representative public issue reports, Apple's display/capture/distribution guidance, and adjacent open-source display utilities. The purpose was to map user-visible outcomes and failure modes, not to infer or reproduce proprietary internals. Sources are listed in Section 22.

## 6.2 Findings that shape the product

| **Finding**                    | **Implication**                                                                                                                                                                                                                                                   | **Evidence**               |
|--------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------|
| Feature breadth                | The reference product is a display-management platform, not merely a brightness utility. Public materials span topology, modes, DDC, software image controls, HDR/XDR, virtual displays, streaming, automation, layout protection, diagnostics, and recovery.     | \[S01-S09\]                |
| Disconnect semantics           | Users use the word disconnect for several different outcomes: remove a display from the macOS topology, turn the monitor panel off, black out the image while retaining topology, or emulate physical unplug. The product must name these separately.             | \[S01, S03, S19-S22\]      |
| Identity is unstable           | Transient display IDs may change across reconnection, wake, ports, docks, or identical monitor swaps. Automation needs a multi-signal identity model and confidence scoring, not a single numeric ID.                                                             | \[S04, S12, S20, S24\]     |
| Wake is a reconciliation event | macOS and hardware may independently reconnect, reorder, or alter modes after sleep. The app should wait for topology to stabilize, reconcile observed state, and then apply policy once rather than repeatedly fighting the system.                              | \[S20-S26, S29-S30\]       |
| DDC is transport-dependent     | A monitor can support DDC while a dock, adapter, KVM, or cable blocks it. Capability detection must be per route, degradable, and explain failures without treating the whole display as unsupported.                                                             | \[S03, S10-S11, S23, S27\] |
| Recovery is a product feature  | A display tool can remove the surface that contains its own recovery UI. Safe mode, reconnect-all, rollback checkpoints, startup bypass, keyboard recovery, and a standalone rescue utility are first-class requirements.                                         | \[S07, S19-S22, S31\]      |
| Distribution affects scope     | Public Core Graphics and ScreenCaptureKit cover many features, but some lifecycle, virtual-display, and system-override behavior may require undocumented interfaces. A direct, signed, notarized build and a public-API-only build should be planned separately. | \[S14-S18\]                |
| Clean-room is mandatory        | Open source does not permit copying proprietary code, assets, text, brand identity, or distinctive UI. The project should reproduce user outcomes through independently authored designs and documented public observations.                                      | \[S01-S04, S16\]           |

## 6.3 Representative reports and design response

| **Observed report**                                                       | **Product response**                                                                                                           | **Source**  |
|---------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------|-------------|
| Logical disconnect may target the last or primary surface.                | Treat disconnect as recovery-critical; block unsafe defaults and require safe-surface verification.                            | \[S19\]     |
| macOS may reconnect or reorder displays after sleep.                      | Use a debounced wake reconciliation generation and protected desired state rather than immediate repeated writes.              | \[S20\]     |
| Intel configurations can present blank screens after disconnect/wake.     | Apple Silicon is the certified baseline; Intel lifecycle provider remains unavailable or experimental until separately proven. | \[S21\]     |
| Aggressive disconnect may not survive reboot as users expect.             | Define persistence as an explicit policy with health delay and bypass; never imply OS-level permanence.                        | \[S22\]     |
| DDC may work directly but fail through a hub.                             | Probe and cache capabilities per route; report transport failure separately from monitor support.                              | \[S23\]     |
| Modes can differ after reconnect.                                         | Resolve modes by properties, refresh capabilities after topology events, and reject stale identifiers.                         | \[S24\]     |
| Wake can trigger crashes or repeated instability.                         | Serialize operations, bound retries, maintain a circuit breaker, and preserve a pre-wake checkpoint.                           | \[S25\]     |
| Reconnect All may not wake Sidecar.                                       | Use endpoint-specific semantics and per-target result reporting; never return blanket success.                                 | \[S26\]     |
| Power controls buried in UI reduce utility.                               | Expose safe quick actions in root menu, hotkeys, and automation while retaining clear semantics.                               | \[S27\]     |
| Rapid XDR/brightness changes can produce visual corruption.               | Rate-limit/coalesce writes, enforce safe ranges, verify where possible, and provide profile rollback.                          | \[S28\]     |
| Virtual display sleep can move windows or fail to reconnect.              | Virtual lifecycle requires explicit window/sleep policy, separate persistence, and safe-mode bypass.                           | \[S29-S30\] |
| Severe startup/WindowServer incidents are possible in this problem class. | Independent rescue utility, health marker, startup bypass, and conservative OS compatibility flags are release requirements.   | \[S31\]     |

## 6.4 Interpretation limits

- Public issue reports demonstrate possible failure modes; they do not establish frequency, root cause, or current unresolved status.

- Feature descriptions establish user-visible intent but not the implementation method, entitlement set, or reliability guarantees.

- Apple documentation describes supported public interfaces; absence of a public API does not prove impossibility, but it changes distribution and maintenance risk.

- Compatibility must be established by our own instrumented hardware testing for each Mac/OS/route/provider combination.

# 7. Reference feature inventory and proposed disposition

The following inventory translates publicly described reference capabilities into independently specified product outcomes. It is a planning map, not a promise of identical implementation or behavior. “Required” means part of the stated release scope; “Capability-gated” means exposed only when the current environment can support and verify it; “Labs” means opt-in and system-sensitive.

| **Capability domain**                       | **Items** | **Release distribution**                                     |
|---------------------------------------------|-----------|--------------------------------------------------------------|
| Display lifecycle and topology              | 16        | Core 1.0: 14, Core 1.x: 1, Labs: 1                           |
| Modes, scaling, and geometry                | 16        | Core 1.0: 7, Core 1.x: 4, Labs: 5                            |
| Brightness, audio, color, and input         | 23        | Core 1.0: 12, Core 1.x: 7, Core read; Labs write: 1, Labs: 3 |
| Virtual displays, capture, and presentation | 11        | Labs: 6, Core 1.x: 5                                         |
| Automation and integrations                 | 12        | Core 1.0: 7, Core 1.x: 5                                     |
| Diagnostics, configuration, and recovery    | 12        | Core 1.0: 11, Labs: 1                                        |
| User experience and accessibility           | 10        | Core 1.0: 10                                                 |
| Open-source platform and distribution       | 8         | Core 1.0: 6, Core 1.x: 2                                     |

|     | **Traceability convention** Feature IDs describe product capabilities. Detailed requirement IDs in Section 11 define testable behavior. Source markers such as \[S01\] refer to the source register in Section 22. |
|-----|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

## Display lifecycle and topology

Feature inventory: Display lifecycle and topology

| **ID** | **Capability**                    | **Independently specified outcome**                                                                   | **Target** | **Disposition**            | **Evidence**               |
|--------|-----------------------------------|-------------------------------------------------------------------------------------------------------|------------|----------------------------|----------------------------|
| LIF-01 | Enumerate all display endpoints   | Show built-in, external, virtual, Sidecar/AirPlay, mirrored, disconnected/remembered endpoints.       | Core 1.0   | Required                   | \[S01-S04\]                |
| LIF-02 | Stable human-readable naming      | Custom names/tags and consistent menu ordering.                                                       | Core 1.0   | Required                   | \[S03-S04\]                |
| LIF-03 | Logical disconnect                | Remove a supported display from the active macOS display topology without unplugging it.              | Core 1.0   | Experimental provider      | \[S01-S04, S19-S22\]       |
| LIF-04 | Logical reconnect                 | Return a managed-offline display to the active topology.                                              | Core 1.0   | Experimental provider      | \[S01-S04, S19-S22\]       |
| LIF-05 | Reconnect All                     | One action to reconnect every display placed offline by the app.                                      | Core 1.0   | Safety-critical            | \[S07, S19-S22, S26\]      |
| LIF-06 | Black Out                         | Render black while the display remains active in layout; optional cursor suppression.                 | Core 1.0   | Public/low risk            | \[S03\]                    |
| LIF-07 | Monitor sleep/power               | Send DDC or network power/sleep command while topology may remain active.                             | Core 1.0   | Hardware-dependent         | \[S03, S10-S11, S23, S27\] |
| LIF-08 | Built-in display automation       | Disconnect or reconnect the MacBook panel based on external display, lid, power, or scene conditions. | Core 1.0   | Guarded rules              | \[S01-S03\]                |
| LIF-09 | Persistent managed-offline policy | Reapply an opt-in disconnect policy after login/reboot once health checks pass.                       | Core 1.x   | Opt-in only                | \[S22\]                    |
| LIF-10 | Main display selection            | Assign main display and protect it from system reordering.                                            | Core 1.0   | Required                   | \[S01-S04, S20\]           |
| LIF-11 | Mirroring topology                | Create, break, and inspect mirror sets; choose source and targets.                                    | Core 1.0   | Public APIs where possible | \[S01-S04\]                |
| LIF-12 | Display groups                    | Group displays for synchronized controls and scene application.                                       | Core 1.0   | Required                   | \[S01-S03\]                |
| LIF-13 | Layout and anchors                | Set relative coordinates, align edges, preserve gaps, and anchor important displays.                  | Core 1.0   | Required                   | \[S01-S03, S12\]           |
| LIF-14 | Layout protection                 | Observe topology drift and restore protected placement/main/mirror properties.                        | Core 1.0   | Debounced                  | \[S01-S03, S20\]           |
| LIF-15 | Display redirection               | Present one display's contents on another endpoint.                                                   | Labs       | Research                   | \[S01-S03\]                |
| LIF-16 | Physical-unplug semantics         | Detect cable removal and explain that software cannot generally sever the physical link.              | Core 1.0   | Explicit non-goal          | Product requirement        |

## Modes, scaling, and geometry

Feature inventory: Modes, scaling, and geometry

| **ID** | **Capability**                 | **Independently specified outcome**                                                 | **Target** | **Disposition**               | **Evidence**        |
|--------|--------------------------------|-------------------------------------------------------------------------------------|------------|-------------------------------|---------------------|
| MOD-01 | Resolution selection           | List and apply available resolutions with logical and pixel dimensions.             | Core 1.0   | Required                      | \[S01-S05, S12\]    |
| MOD-02 | Favorite modes                 | Pin resolutions/refresh combinations for menu and keyboard access.                  | Core 1.0   | Required                      | \[S01-S04\]         |
| MOD-03 | Resolution slider              | Continuous-feeling UI over discrete supported modes.                                | Core 1.x   | Convenience                   | \[S01-S03\]         |
| MOD-04 | HiDPI mode visibility          | Expose HiDPI/non-HiDPI status and filter mode lists.                                | Core 1.0   | Required                      | \[S03-S05\]         |
| MOD-05 | Flexible HiDPI scaling         | Offer additional scaled desktop sizes on compatible systems.                        | Labs       | Undocumented/system-sensitive | \[S01-S05\]         |
| MOD-06 | Custom resolutions             | Create or expose custom mode entries where technically possible.                    | Labs       | High risk                     | \[S01-S05\]         |
| MOD-07 | Arbitrary headless resolutions | Provide custom dimensions for headless/virtual workflows.                           | Labs       | Depends on virtual provider   | \[S01-S05\]         |
| MOD-08 | Refresh rate                   | Select fixed refresh rates and report current/maximum rate.                         | Core 1.0   | Required                      | \[S01-S04\]         |
| MOD-09 | Variable refresh rate          | Expose VRR status and supported ranges; allow protected selection where available.  | Core 1.x   | Capability-gated              | \[S01-S04\]         |
| MOD-10 | Bit depth and pixel format     | Report/apply depth and encoding choices where supported.                            | Core 1.x   | Capability-gated              | \[S01-S04\]         |
| MOD-11 | Rotation                       | Apply 0/90/180/270-degree rotation to supported displays.                           | Core 1.0   | Required                      | \[S01-S04, S12\]    |
| MOD-12 | Rotated Sidecar                | Allow or emulate rotation for Sidecar-oriented workflows.                           | Labs       | Research                      | \[S01-S03\]         |
| MOD-13 | UI-scale matching              | Calculate matching apparent UI size across displays with different density.         | Core 1.x   | Differentiator                | \[S01-S03\]         |
| MOD-14 | Geometry presets               | Support TV lower-half, off-center, overscan-safe, and custom viewport arrangements. | Labs       | Niche/system-sensitive        | \[S01-S03\]         |
| MOD-15 | Mode protection                | Restore protected resolution, refresh, rotation, HDR, and profile after drift.      | Core 1.0   | Required                      | \[S01-S03\]         |
| MOD-16 | Mode diff preview              | Show current versus proposed geometry before applying a scene.                      | Core 1.0   | OpenDisplay enhancement       | Product requirement |

## Brightness, audio, color, and input

Feature inventory: Brightness, audio, color, and input

| **ID** | **Capability**               | **Independently specified outcome**                                                             | **Target**            | **Disposition**                | **Evidence**              |
|--------|------------------------------|-------------------------------------------------------------------------------------------------|-----------------------|--------------------------------|---------------------------|
| CTL-01 | Native brightness            | Control Apple/native display brightness through supported system interfaces.                    | Core 1.0              | Required                       | \[S01-S03, S10\]          |
| CTL-02 | DDC brightness               | Control external monitor backlight over DDC/CI.                                                 | Core 1.0              | Hardware/route-dependent       | \[S01-S03, S10-S11, S23\] |
| CTL-03 | Software dimming             | Apply a software overlay/gamma/Metal dimmer below hardware minimum.                             | Core 1.0              | Required                       | \[S01-S03, S10\]          |
| CTL-04 | Combined brightness curve    | Seamlessly combine hardware and software ranges with calibrated transitions.                    | Core 1.x              | Quality feature                | \[S01-S03, S10\]          |
| CTL-05 | Volume and mute              | Control display audio volume/mute through native or DDC routes.                                 | Core 1.0              | Capability-gated               | \[S01-S03, S10\]          |
| CTL-06 | Contrast                     | Read/write DDC contrast when supported.                                                         | Core 1.0              | Capability-gated               | \[S01-S03, S10-S11\]      |
| CTL-07 | Color channels and presets   | Control RGB gain, color temperature, picture modes, or vendor presets when available.           | Core 1.x              | Capability-gated               | \[S01-S03\]               |
| CTL-08 | Keyboard media keys          | Route brightness and volume keys to the display under pointer, focus, main display, or a group. | Core 1.0              | Required                       | \[S01-S04, S10\]          |
| CTL-09 | Custom on-screen display     | Show native-looking feedback for brightness, volume, input, and scene changes.                  | Core 1.0              | Required                       | \[S01-S03, S10\]          |
| CTL-10 | Control synchronization      | Synchronize brightness/volume/color across a group with per-display offsets.                    | Core 1.0              | Required                       | \[S01-S03, S10\]          |
| CTL-11 | Nits-aware synchronization   | Map controls by measured/declared luminance rather than percentage.                             | Core 1.x              | Advanced                       | \[S01-S03\]               |
| CTL-12 | Input source switching       | Read/write DDC input source and expose named inputs.                                            | Core 1.0              | Capability-gated               | \[S01-S04, S10-S11\]      |
| CTL-13 | DDC auto-configuration       | Probe VCP support, delays, verification, and route stability.                                   | Core 1.0              | Required                       | \[S01-S03, S23\]          |
| CTL-14 | Network display control      | Adapters for supported LG/Samsung/Philips displays and receivers.                               | Core 1.x              | Plugin/provider                | \[S01-S03\]               |
| CTL-15 | Night Shift on televisions   | Extend or coordinate Night Shift-like behavior on displays not handled by macOS.                | Core 1.x              | Best effort                    | \[S01-S03\]               |
| CTL-16 | Color profile selection      | List, apply, and protect ICC/display profiles.                                                  | Core 1.0              | Required                       | \[S01-S03\]               |
| CTL-17 | SDR/HDR profile automation   | Switch profiles based on dynamic range state or content workflow.                               | Core 1.x              | Advanced                       | \[S01-S03, S06\]          |
| CTL-18 | HDR toggle/force             | Expose HDR state and, in Labs, attempt forced HDR modes where feasible.                         | Core read; Labs write | Risk-gated                     | \[S01-S03, S06\]          |
| CTL-19 | XDR/HDR brightness expansion | Provide guarded extra-brightness workflows on compatible displays.                              | Labs                  | Thermal/visual safety          | \[S01-S03, S06, S28\]     |
| CTL-20 | Encoding/range/chroma        | Inspect and, where possible, influence RGB/YCbCr, full/limited range, and chroma.               | Labs                  | System-sensitive               | \[S01-S04\]               |
| CTL-21 | Image filters                | Per-display dimming, grayscale, inversion, tint, white balance, and accessibility filters.      | Core 1.x              | Metal/overlay pipeline         | \[S01-S03, S09\]          |
| CTL-22 | PWM/dithering mitigation     | Provide carefully worded eye-care modes and diagnostics without medical claims.                 | Labs                  | Evidence-limited               | \[S01-S03, S09\]          |
| CTL-23 | Control rate limiting        | Coalesce rapid writes and rollback unsafe color/HDR transitions.                                | Core 1.0              | OpenDisplay safety enhancement | \[S28\]                   |

## Virtual displays, capture, and presentation

Feature inventory: Virtual displays, capture, and presentation

| **ID** | **Capability**                | **Independently specified outcome**                                          | **Target** | **Disposition**               | **Evidence**         |
|--------|-------------------------------|------------------------------------------------------------------------------|------------|-------------------------------|----------------------|
| VIR-01 | Virtual display creation      | Create software display endpoints with configurable size and density.        | Labs       | Undocumented/system-sensitive | \[S01-S04, S29-S30\] |
| VIR-02 | Multiple virtual displays     | Create and manage more than one virtual endpoint subject to system limits.   | Labs       | Capability-gated              | \[S01-S03\]          |
| VIR-03 | Virtual refresh and HDR       | Configure refresh rate, color depth, and HDR flags where supported.          | Labs       | Research                      | \[S01-S03\]          |
| VIR-04 | Virtual lifecycle persistence | Reconnect named virtual displays after login/wake using safe policies.       | Labs       | Recovery required             | \[S29-S30\]          |
| VIR-05 | Picture in picture            | Preview any display in a resizable always-on-top window.                     | Core 1.x   | ScreenCaptureKit              | \[S01-S03, S15\]     |
| VIR-06 | Display zoom                  | Zoom/pan a selected display or region for accessibility and inspection.      | Core 1.x   | ScreenCaptureKit              | \[S01-S03, S15\]     |
| VIR-07 | Screenshots                   | Capture full display or selected region with privacy-aware exclusions.       | Core 1.x   | ScreenCaptureKit              | \[S01-S03, S15\]     |
| VIR-08 | Local streaming               | Stream a display to another local endpoint or browser with explicit consent. | Labs       | Security-sensitive            | \[S01-S03, S15\]     |
| VIR-09 | Headless workspace            | Maintain usable remote resolutions when no physical monitor is connected.    | Labs       | Virtual provider              | \[S01-S05\]          |
| VIR-10 | Teleprompter/mirror mode      | Mirror, flip, or present text/video for teleprompter workflows.              | Core 1.x   | Capture/render pipeline       | \[S01-S03\]          |
| VIR-11 | Cursor and window policy      | Define whether windows/cursor move when virtual displays sleep or reconnect. | Core 1.x   | Required before virtual GA    | \[S29-S30\]          |

## Automation and integrations

Feature inventory: Automation and integrations

| **ID** | **Capability**            | **Independently specified outcome**                                                                | **Target** | **Disposition**         | **Evidence**        |
|--------|---------------------------|----------------------------------------------------------------------------------------------------|------------|-------------------------|---------------------|
| AUT-01 | Command-line interface    | Script all supported get/set/toggle/scene/lifecycle actions.                                       | Core 1.0   | Required                | \[S04, S12\]        |
| AUT-02 | Stable display selectors  | Address by tag, UUID, fingerprint, name, vendor/product/serial, topology, pointer, focus, or main. | Core 1.0   | Required                | \[S04\]             |
| AUT-03 | Machine-readable output   | JSON output with stable schema, exit codes, warnings, and capability reasons.                      | Core 1.0   | OpenDisplay enhancement | Product requirement |
| AUT-04 | URL scheme                | Invoke safe actions from launchers and automations.                                                | Core 1.x   | Opt-in                  | \[S04\]             |
| AUT-05 | Local HTTP API            | Loopback server for authenticated control and event subscription.                                  | Core 1.x   | Opt-in/security-gated   | \[S04\]             |
| AUT-06 | Distributed notifications | Publish and consume local process events where appropriate.                                        | Core 1.x   | Compatibility           | \[S04\]             |
| AUT-07 | App Intents and Shortcuts | Expose scenes and common controls to Shortcuts, Spotlight, and Siri surfaces.                      | Core 1.0   | Required                | \[S01-S04\]         |
| AUT-08 | Global shortcuts          | Bind display, group, scene, brightness, input, and emergency recovery actions.                     | Core 1.0   | Required                | \[S01-S04\]         |
| AUT-09 | Events and rules          | Trigger actions on connect/disconnect, wake, lid, power source, focus, time, and app launch.       | Core 1.x   | Rule engine             | \[S01-S04\]         |
| AUT-10 | Idempotent scene apply    | Repeatedly applying the same desired state should not flicker or reorder unnecessarily.            | Core 1.0   | Required                | Product requirement |
| AUT-11 | Dry run and diff          | Return planned operations, risks, and unsupported fields without applying.                         | Core 1.0   | Safety enhancement      | Product requirement |
| AUT-12 | Shell and webhook hooks   | Run user-approved local commands or webhooks around scene transitions.                             | Core 1.x   | Sandboxed/explicit      | \[S01-S04\]         |

## Diagnostics, configuration, and recovery

Feature inventory: Diagnostics, configuration, and recovery

| **ID** | **Capability**                   | **Independently specified outcome**                                                          | **Target** | **Disposition** | **Evidence**        |
|--------|----------------------------------|----------------------------------------------------------------------------------------------|------------|-----------------|---------------------|
| DIA-01 | Detailed display inspector       | Show IDs, fingerprints, connection route, mode, color, HDR, DDC, and topology state.         | Core 1.0   | Required        | \[S01-S04\]         |
| DIA-02 | EDID viewer/export               | Parse and export EDID where available; flag inconsistent or missing values.                  | Core 1.0   | Required        | \[S01-S04\]         |
| DIA-03 | Configuration and EDID overrides | Manage advanced overrides with backup, validation, and reboot warnings.                      | Labs       | High risk       | \[S01-S03\]         |
| DIA-04 | Capability explanation           | For every disabled control, explain OS, hardware, route, permission, or policy reason.       | Core 1.0   | Required        | Product requirement |
| DIA-05 | Configuration export/import      | Portable, versioned settings with secrets excluded by default.                               | Core 1.0   | Required        | \[S08\]             |
| DIA-06 | Safe mode                        | Launch with all experimental providers and auto-apply policies disabled.                     | Core 1.0   | Safety-critical | \[S07\]             |
| DIA-07 | Reset and selective reset        | Reset rules, scenes, display identities, DDC cache, or all settings.                         | Core 1.0   | Required        | \[S07\]             |
| DIA-08 | Last-known-safe checkpoint       | Persist topology, modes, and policies before risky operations.                               | Core 1.0   | Safety-critical | \[S19-S22, S31\]    |
| DIA-09 | Automatic rollback               | Restore checkpoint when verification or watchdog fails.                                      | Core 1.0   | Safety-critical | \[S19-S22, S31\]    |
| DIA-10 | Standalone rescue utility        | Independent small app/CLI to reconnect displays and disable startup policies.                | Core 1.0   | Safety-critical | Product requirement |
| DIA-11 | Diagnostics bundle               | Redacted logs, topology timeline, capability probes, crash state, and config schema version. | Core 1.0   | Required        | \[S23-S26\]         |
| DIA-12 | Health and circuit breaker       | Disable a failing provider after bounded failures and surface recovery guidance.             | Core 1.0   | Required        | Product requirement |

## User experience and accessibility

Feature inventory: User experience and accessibility

| **ID** | **Capability**               | **Independently specified outcome**                                                                 | **Target** | **Disposition** | **Evidence**        |
|--------|------------------------------|-----------------------------------------------------------------------------------------------------|------------|-----------------|---------------------|
| UX-01  | Menu-bar first UI            | Fast access to displays, favorites, scenes, and emergency recovery.                                 | Core 1.0   | Required        | \[S01-S03, S27\]    |
| UX-02  | Full settings window         | Topology map, display details, controls, scenes, automation, and diagnostics.                       | Core 1.0   | Required        | Product requirement |
| UX-03  | Per-display cards            | Consistent cards with identity, connection state, mode, brightness, audio, and quick actions.       | Core 1.0   | Required        | Product requirement |
| UX-04  | Reorder displays in menus    | User-defined menu order independent of transient system order.                                      | Core 1.0   | Required        | \[S01-S03\]         |
| UX-05  | Favorites and recent actions | Pin modes, inputs, scenes, and controls; show undoable recent actions.                              | Core 1.0   | Required        | \[S01-S03\]         |
| UX-06  | Risk labels                  | Mark public, hardware-dependent, experimental, and restart-required actions.                        | Core 1.0   | Required        | Product requirement |
| UX-07  | Accessibility                | VoiceOver labels, keyboard navigation, sufficient contrast, reduced motion, and nonvisual recovery. | Core 1.0   | Required        | Product requirement |
| UX-08  | Localization-ready copy      | String catalog, pluralization, and no layout assumptions based on English length.                   | Core 1.0   | Required        | Product requirement |
| UX-09  | Onboarding capability scan   | Explain permissions, DDC routes, experimental features, and recovery before first use.              | Core 1.0   | Required        | Product requirement |
| UX-10  | Undo and activity log        | Undo recent reversible changes and inspect what changed, why, and by which trigger.                 | Core 1.0   | Required        | Product requirement |

## Open-source platform and distribution

Feature inventory: Open-source platform and distribution

| **ID** | **Capability**                | **Independently specified outcome**                                                      | **Target** | **Disposition** | **Evidence**        |
|--------|-------------------------------|------------------------------------------------------------------------------------------|------------|-----------------|---------------------|
| OSS-01 | Clean-room implementation     | Independently authored code, copy, UI, icons, and architecture.                          | Core 1.0   | Mandatory       | \[S01-S04, S16\]    |
| OSS-02 | Provider architecture         | Separate public, hardware, and experimental implementations behind capability contracts. | Core 1.0   | Mandatory       | Product requirement |
| OSS-03 | Public-API-only build         | Compile/package a reduced feature build without undocumented interfaces.                 | Core 1.x   | Strategic       | \[S14-S18\]         |
| OSS-04 | Signed and notarized releases | Reproducible release process with Developer ID signing and notarization.                 | Core 1.0   | Mandatory       | \[S17-S18\]         |
| OSS-05 | Software bill of materials    | Publish dependencies, licenses, checksums, provenance, and security policy.              | Core 1.0   | Mandatory       | Product requirement |
| OSS-06 | Plugin SDK                    | Document provider interfaces for DDC, network control, and future hardware adapters.     | Core 1.x   | Extension point | Product requirement |
| OSS-07 | Contributor governance        | DCO/CLA decision, code of conduct, issue templates, RFCs, and maintainer policy.         | Core 1.0   | Mandatory       | Product requirement |
| OSS-08 | Privacy-first operation       | No analytics by default; opt-in diagnostics; local control endpoints only by default.    | Core 1.0   | Mandatory       | Product requirement |

# 8. Product experience and core workflows

## 8.1 Information architecture

| **Surface**        | **Purpose**                      | **Required contents**                                                                                                       |
|--------------------|----------------------------------|-----------------------------------------------------------------------------------------------------------------------------|
| Menu-bar root      | Immediate control and recovery   | Reconnect All; current scene; display cards; favorite brightness/modes/inputs; Black Out; logical disconnect; health badge. |
| Topology workspace | Visual multi-display management  | Active/offline endpoints, arrangement, main display, mirrors, identity confidence, scene preview, protected properties.     |
| Display detail     | Per-endpoint configuration       | Identity, route, mode, controls, profiles, lifecycle policy, automation tags, capability reasons, diagnostics.              |
| Scenes             | Desired-state authoring          | Required/optional members, topology, modes, controls, lifecycle, triggers, dry run, history, export.                        |
| Automation         | External and event control       | Shortcuts/App Intents, CLI examples, hotkeys, rules, API status, tokens, audit log.                                         |
| Health & recovery  | Prevent and repair unsafe states | Managed-offline list, pending transaction, provider health, Reconnect All, safe mode, restore checkpoint, support bundle.   |
| Labs               | Explicit experimental opt-in     | Compatibility warnings, provider flags, recovery acknowledgement, kill switches, diagnostics.                               |

## 8.2 Display card anatomy

- **Identity.** Alias, display class, model, fingerprint confidence, route, and current reachability.

- **State.** Active, Blacked Out, monitor power unknown/asleep, managed offline, system absent, reconnecting, degraded, or error.

- **Mode.** Logical/pixel size, HiDPI, refresh/VRR, rotation, HDR, profile, and main/mirror role.

- **Controls.** Brightness provider, volume/mute, contrast, input, synchronized-group membership, and verification state.

- **Quick actions.** Favorite mode, input, scene, Black Out, monitor sleep, logical disconnect/reconnect, details.

- **Safety.** Risk badge, capability reason, last checkpoint, last action actor, and direct recovery action.

## 8.3 Onboarding flow

| **Step**        | **User experience**                                                                | **System behavior / acceptance**                                             |
|-----------------|------------------------------------------------------------------------------------|------------------------------------------------------------------------------|
| 1\. Welcome     | Explain that Core is open source and that some advanced features are experimental. | No permission prompt or topology mutation.                                   |
| 2\. Scan        | Show discovered displays and connection routes.                                    | Registry and capability resolver run; slow DDC probes are asynchronous.      |
| 3\. Name        | Offer aliases/tags, especially for identical displays.                             | Identity evidence and confidence are visible.                                |
| 4\. Permissions | Request only permissions for selected features.                                    | Core topology/DDC remains usable without capture permission.                 |
| 5\. Recovery    | Teach Reconnect All hotkey and rescue utility before enabling logical disconnect.  | User confirms they can invoke keyboard recovery.                             |
| 6\. Test        | Optional first-disconnect test with countdown and automatic reconnect.             | Creates checkpoint, verifies transition, and records route-specific consent. |
| 7\. Scene       | Offer a starter scene from current state.                                          | Scene is a desired-state snapshot with optional controls.                    |

## 8.4 Primary workflow: disconnect one display

1\. User opens the display card and chooses Logical Disconnect. The action is visually distinct from Black Out and Monitor Sleep.

2\. The planner resolves the target identity, shows confidence and topology impact, and checks for a safe visible/recoverable surface.

3\. For first use or elevated risk, the app shows a countdown confirmation with the Reconnect All hotkey and a Cancel button on a safe display.

4\. The coordinator writes a last-known-safe checkpoint and marks the transaction in progress.

5\. The lifecycle provider performs the platform-specific request; the registry observes resulting display events.

6\. The verifier confirms the target is inactive, at least one safe surface remains, and topology has stabilized.

7\. On success, the target becomes Managed Offline with actor, timestamp, policy, and Reconnect action. On failure, rollback begins automatically.

## 8.5 Primary workflow: scene transition

| **Phase**        | **Planner behavior**                                                       | **User feedback**                                                               |
|------------------|----------------------------------------------------------------------------|---------------------------------------------------------------------------------|
| Resolve          | Resolve required/optional displays and capabilities using stable identity. | Missing/ambiguous targets shown before mutation.                                |
| Diff             | Compare observed state with desired fields; omit satisfied operations.     | Preview groups normal, hardware-dependent, experimental, and unsupported steps. |
| Checkpoint       | Persist topology-critical state and transaction plan.                      | Activity item shows pending scene and Cancel when safe.                         |
| Establish safety | Connect destination displays and confirm a safe surface.                   | Status identifies which display is being prepared.                              |
| Apply topology   | Main/mirror/layout/modes through ordered transactions.                     | Minimal OSD; no unnecessary intermediate states.                                |
| Apply controls   | Brightness/audio/input/profile with rate limits and optional verification. | Per-field warnings do not masquerade as full success.                           |
| Retire displays  | Disconnect only after the destination is verified.                         | Countdown used when policy/risk requires.                                       |
| Commit           | Record verified state and transaction result.                              | Scene shows Applied, Applied with warnings, or Rolled back.                     |

## 8.6 Wake and dock reconciliation

Wake is treated as a new topology generation. The app records events but does not immediately fight each one. After a quiet/stability window, it refreshes capabilities, reconciles identities, compares observed state with applicable protected state and rules, produces one plan, and applies it through the transaction coordinator. Repeated OS events extend the stabilization window up to a bound; repeated failures open a circuit breaker and stop writes.

## 8.7 Failure experience

| **Failure**                      | **Immediate response**                                                            | **Recovery surface**                                                              |
|----------------------------------|-----------------------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| Target did not disconnect        | Report provider timeout/failure; no false success.                                | Retry, change provider policy, diagnostics.                                       |
| Safe display disappeared         | Abort remaining steps and run rollback/reconnect.                                 | Full-screen recovery banner/OSD on any available surface; hotkey/rescue.          |
| Identity became ambiguous        | Pause before mutation.                                                            | Candidate selection with evidence; remember explicit pairing.                     |
| DDC route stopped responding     | Stop repeated writes; mark route degraded.                                        | Use software fallback where valid; show cable/dock guidance.                      |
| Mode unavailable after reconnect | Reject stale mode and select no automatic substitute unless scene policy permits. | Show closest supported alternatives.                                              |
| App terminated mid-transaction   | Health marker remains unclean.                                                    | Next launch enters recovery-first flow; rescue utility can restore independently. |

## 8.8 Accessibility-critical behavior

- Reconnect All has a configurable global shortcut with a non-conflicting default and an accessible spoken confirmation.

- The recovery path does not depend on color, pointer placement, animation, or the display that was disconnected.

- Topology diagrams have a complete list/table representation with the same controls and relationships.

- Countdowns support extended duration and do not auto-focus a control on a display about to disappear.

- OSD announcements can be routed to VoiceOver and suppressed visually; reduced motion avoids topology animation.

- No filter, dimmer, Black Out overlay, or PIP window may obscure or intercept the emergency recovery command.

# 9. Safe display disconnection subsystem

Logical display disconnection is the product's highest-risk capability and its primary differentiator. It must be implemented as a lifecycle subsystem with explicit semantics, invariants, provider isolation, transactional verification, and independent recovery—not as a direct button-to-private-API call.

## 9.1 Semantic model

| **User action**           | **Topology participation**                                     | **Panel/link behavior**                                 | **Window behavior**                                         | **Risk**                     |
|---------------------------|----------------------------------------------------------------|---------------------------------------------------------|-------------------------------------------------------------|------------------------------|
| Black Out                 | Display remains active.                                        | Black overlay or render path; panel may remain powered. | Windows normally remain.                                    | Low to medium.               |
| Monitor Sleep / Power Off | Usually remains active unless hardware/system also removes it. | DDC/network command; result may be unverified.          | Windows normally remain; monitor may wake from OS activity. | Medium / hardware-dependent. |
| Logical Disconnect        | Display is removed from active macOS topology when supported.  | Physical link may remain; panel behavior varies.        | Windows may be moved by macOS or policy.                    | High / recovery-critical.    |
| Reconnect                 | Managed-offline endpoint is requested back into topology.      | Physical/wireless endpoint must still be available.     | Layout/mode may require restoration.                        | Medium.                      |
| Physical unplug           | OS observes link removal.                                      | Cable/link is physically removed.                       | macOS decides window handling.                              | Outside app control.         |

## 9.2 Safety invariants

1\. At most one topology/lifecycle transaction is active.

2\. No logical disconnect starts without a complete last-known-safe checkpoint.

3\. No default operation may intentionally remove the last known-safe recoverable display.

4\. A target below the destructive identity-confidence threshold is not mutated without explicit confirmation.

5\. Success is reported only after postconditions are observed; otherwise the result is failed, unverified, degraded, or rolled back.

6\. Reconnect All always preempts ordinary queued work and is available from an independent process.

7\. Safe mode disables experimental providers and all automatic lifecycle policies before they can run.

8\. Persistent managed-offline policy runs only after health checks and can be bypassed at startup.

9\. Normal quit reconnects app-managed displays unless the user explicitly chose persistence.

10\. Provider failure is bounded; circuit breakers prevent repeated destabilizing calls.

11\. A display may be system-absent, managed-offline, or monitor-powered-off; these states are never conflated.

12\. The product never promises to free a hardware pipeline, bypass the Mac's display-count limit, or emulate cable removal.

## 9.3 Lifecycle state model

Reachability:  
systemAbsent -\> discoveredInactive -\> active  
\| \|  
v v  
managedOffline \<- disconnecting  
\| \|  
v v  
reconnecting -----\> active  
  
Presentation overlays (orthogonal):  
visible \| blackedOut \| dimmed \| filtered  
  
Monitor power observation (orthogonal):  
unknown \| awake \| sleepRequested \| asleepVerified \| powerFailed  
  
Transaction:  
idle -\> resolving -\> preflight -\> checkpointed -\> applying  
-\> observing -\> verifying -\> committed  
-\> rollingBack -\> recovered \| degraded \| failed

The state model intentionally separates topology, presentation, and monitor power. A display can be active but blacked out, active while its panel is asleep, or managed offline while the physical monitor remains powered. Orthogonal states prevent UI and automation from claiming the wrong outcome.

## 9.4 Disconnect transaction

| **Stage**        | **Required work**                                                                                               | **Failure response**                                              |
|------------------|-----------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------|
| Resolve target   | Use persistent identity; refresh current route and topology generation.                                         | Return ambiguous/not found; no mutation.                          |
| Reconcile        | Wait for any prior topology events to stabilize and refresh observed state.                                     | Timeout to busy/degraded; no mutation.                            |
| Preflight safety | Safe surface, identity threshold, OS/provider compatibility, recovery service health, pending policy conflicts. | Block or require elevated timed override.                         |
| Checkpoint       | Atomic snapshot of topology, modes, main/mirror, protected fields, managed-offline set, and recovery metadata.  | Block; no provider call.                                          |
| Confirm          | First-use/risk countdown on a safe display; show target and recovery key.                                       | Cancel cleanly.                                                   |
| Apply            | Invoke provider through coordinator with transaction ID and deadline.                                           | Begin rollback if any uncertainty can affect reachability.        |
| Observe          | Collect normalized OS events; suppress policy loops for this transaction.                                       | Continue to bounded verification or rollback.                     |
| Verify           | Target inactive/managed, safe surface active, registry stable, no unexpected endpoints lost.                    | Rollback or mark degraded with emergency recovery.                |
| Commit           | Persist managed-offline record, actor, reason, policy, verified state, and new checkpoint.                      | If persistence fails, restore or surface recovery-critical error. |

## 9.5 Pseudocode contract

func disconnect(targetSelector, actor, options) async -\> LifecycleResult {  
return await topologyCoordinator.exclusiveTransaction(kind: .disconnect) { tx in  
let target = try await registry.resolve(targetSelector, minimumConfidence: options.threshold)  
try await stabilizer.awaitStableGeneration()  
let preflight = try await safety.preflightDisconnect(target, recoveryHealth: rescue.health)  
try preflight.requireAllowed(options.userOverride)  
  
let checkpoint = try await checkpoints.writeAtomic(currentState, tx.id)  
if preflight.needsConfirmation {  
try await confirmation.countdown(on: preflight.safeSurface, recoveryShortcut: rescue.shortcut)  
}  
  
do {  
try await lifecycleProvider.disconnect(target, deadline: options.deadline)  
let observed = try await registry.awaitTopologyChange(correlatedWith: tx.id)  
try verifier.requireDisconnected(target, in: observed)  
try verifier.requireSafeSurface(in: observed)  
try await managedOfflineStore.commit(target, actor, options.policy, tx.id)  
return .committed(tx.id, verification: .verified)  
} catch {  
let recovery = await rollback.restore(checkpoint, priority: .emergency)  
return LifecycleResult.from(error, recovery)  
}  
}  
}

## 9.6 Safe-surface determination

A safe surface is an active endpoint on which the user can receive recovery feedback and invoke recovery, or a separately verified remote/control surface explicitly configured by the user. The default rule requires a local active display that is not part of the disconnect target set, is not expected to vanish because of lid/power policy, and has a stable identity. Remote/headless overrides are advanced and must verify the rescue utility, remote session, and startup bypass before allowing the last local surface to be disconnected.

| **Signal**                                                 | **Effect on safe-surface score**                                     |
|------------------------------------------------------------|----------------------------------------------------------------------|
| Active, visible, non-mirrored display with stable identity | Strong positive.                                                     |
| Built-in panel with lid open                               | Positive; may be preferred recovery surface.                         |
| External display on same hub/KVM as target                 | Lower confidence because route may fail together.                    |
| Display scheduled for a later scene disconnect             | Not safe for the transaction.                                        |
| Blacked out or filtered                                    | Potentially safe only if recovery bypass removes overlays.           |
| Sidecar/AirPlay                                            | Provider-specific; not assumed safe without connection verification. |
| Remote session/virtual display                             | Advanced override only; requires independent recovery proof.         |
| Current main display is target                             | Requires moving recovery UI/main designation before apply.           |

## 9.7 Reconnect strategy

- **Normal reconnect.** Resolve the remembered endpoint and invoke the corresponding provider; wait for an active registry record before restoring modes/layout.

- **Reconnect All.** Prioritize physical/built-in endpoints, attempt every managed-offline record independently, then refresh Sidecar/AirPlay/virtual providers with explicit per-target results.

- **Wake reconciliation.** Trust observed state first. If macOS already reconnected a managed-offline display, decide whether policy should disconnect it only after stabilization and safety checks.

- **Startup recovery.** On unclean health marker or bypass key, do not reapply offline policies; reconnect first, then present a recovery summary.

- **Normal quit.** Reconnect managed-offline endpoints unless persistent policy was explicitly approved; record any endpoint that could not be restored.

## 9.8 Persistence and aggressive policy

Persistent disconnect is not an OS guarantee. It is a desired-state policy that the application may reapply after login, wake, or reconnect. It is disabled by default, configured per display, and evaluated only after the main app and rescue service have both reported healthy, topology has stabilized, and a safe surface exists. A startup modifier, rescue command, or unclean shutdown suppresses it. Policies must include cooldowns and maximum attempts to prevent reconnect/disconnect loops.

## 9.9 Provider contract

| **Method / property**        | **Contract**                                                                                                     |
|------------------------------|------------------------------------------------------------------------------------------------------------------|
| probe(environment)           | Returns supported/unsupported/unknown, reason, risk level, OS range, and health. Must not mutate.                |
| disconnect(target, deadline) | Requests logical removal. Must be cancellation-aware and emit structured progress; cannot report success itself. |
| reconnect(target, deadline)  | Requests reactivation. Must tolerate already-active state and be idempotent.                                     |
| reconnectAll(candidates)     | Optional optimized route; coordinator still verifies each target.                                                |
| recover(checkpoint)          | Best-effort emergency restoration path usable with minimal app dependencies.                                     |
| failure semantics            | Typed: unsupported, denied, ambiguous, busy, timeout, provider error, OS rejected, partial, unknown.             |
| telemetry/logging            | No private user content; include provider version, OS build, target pseudonymous ID, timings, and result.        |
| isolation                    | No UI or automation layer may call provider internals directly.                                                  |

## 9.10 Edge-case policy

| **Scenario**                        | **Required policy**                                                                                                       |
|-------------------------------------|---------------------------------------------------------------------------------------------------------------------------|
| Disconnect current main display     | Move recovery UI and, where appropriate, main role to a verified safe display before disconnect.                          |
| Disconnect all selected displays    | Reject by default; advanced override only with independently verified remote recovery.                                    |
| Lid closes during transaction       | Pause/abort and reconcile; never assume built-in panel remains a safe surface.                                            |
| Dock disappears mid-transaction     | Abort remaining operations, refresh route/capabilities, reconnect available endpoints, and enter degraded recovery state. |
| Identical monitor ambiguity         | Block destructive operation until explicit physical pairing/confirmation.                                                 |
| Target already absent               | Return idempotent no-op only if it is already managed offline; otherwise distinguish system absence.                      |
| OS reconnects target immediately    | Do not loop. Apply cooldown, record policy conflict, and require manual decision or bounded retry.                        |
| Mode list changes after reconnect   | Refresh modes; resolve favorites by properties; do not apply stale mode handles.                                          |
| Provider hangs                      | Deadline, cancellation, separate watchdog, circuit breaker, and rescue priority.                                          |
| App update changes provider support | Disable incompatible persistent policy before first launch and explain migration.                                         |

## 9.11 Recovery hierarchy

1\. Cancel in confirmation countdown.

2\. Undo from activity item while the transaction remains reversible.

3\. Reconnect All from menu bar or global hotkey.

4\. Automatic rollback from checkpoint.

5\. Standalone rescue utility or rescue CLI.

6\. Safe-mode startup using modifier key or command.

7\. Selective reset of lifecycle policies/provider cache.

8\. Documented manual removal of login item/configuration as last resort.

|     | **P0 release rule** Any known path that can leave a supported default configuration without a usable recovery surface blocks release. A Labs label does not waive this rule. |
|-----|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 10. Technical architecture

## 10.1 Architectural style

The recommended implementation is a Swift 6 macOS application using SwiftUI for most interface surfaces and AppKit for mature menu-bar, window, keyboard, and display integrations. State-changing operations flow through actor-isolated domain services. Platform mechanisms live behind provider protocols so public APIs, DDC, network control, and experimental lifecycle code can be compiled, tested, disabled, or replaced independently.

## 10.2 Logical component map

UI / App Intents / CLI / local API / rescue  
\|  
Command Gateway  
\|  
TopologyCoordinator (actor)  
+------------+-------------+  
\| \| \|  
ScenePlanner SafetyEngine Activity/Audit  
\| \| \|  
+------ Desired State -----+  
\|  
DisplayRegistry (actor)  
observed state + identity + capability  
\|  
Provider Router / CapabilityResolver  
+--------+--------+--------+---------+  
CoreGraphics DDC Native Capture Experimental  
Provider Provider Control Provider Lifecycle/Virtual  
\|  
macOS + display hardware  
  
Persistent services: SettingsStore, CheckpointStore, HealthMarker,  
DiagnosticsStore, Keychain, UpdateCompatibility, RecoveryService.

## 10.3 Components and responsibilities

| **Component**                 | **Responsibility**                                                                                 | **Boundary**                                      |
|-------------------------------|----------------------------------------------------------------------------------------------------|---------------------------------------------------|
| AppShell                      | Menu bar, windows, lifecycle, safe-mode bootstrap, dependency composition.                         | No direct display mutation.                       |
| DisplayRegistry               | Normalize OS events, maintain active/offline records, observed state, topology generations.        | Single source of observed display truth.          |
| IdentityResolver              | Compute fingerprints/confidence, handle identical monitors, aliases, pairing, selector resolution. | No destructive choice on ambiguity.               |
| CapabilityResolver            | Combine OS, Mac, display, route, permission, build flavor, provider health, and policy.            | Every unavailable feature has a reason.           |
| TopologyCoordinator           | Serialize transactions, prioritize recovery, manage deadlines/cancellation, correlate events.      | Only owner of topology/lifecycle writes.          |
| SafetyEngine                  | Safe-surface checks, risk score, confirmation policy, last-display rules.                          | Cannot be bypassed by automation.                 |
| ScenePlanner                  | Diff desired/observed state, order operations, classify required/optional, generate dry run.       | Idempotent and deterministic.                     |
| CoreGraphicsProvider          | Public display enumeration/configuration, bounds, modes, mirror/main operations where supported.   | Documented API boundary.                          |
| ControlRouter                 | Select native/DDC/software/network providers and map ranges.                                       | Exposes verification/fallback.                    |
| DDCProvider                   | Route probing, VCP commands, timing, read-back, raw diagnostics.                                   | Per-route health and rate limit.                  |
| CaptureProvider               | ScreenCaptureKit PIP/zoom/screenshot sessions and permission state.                                | No capture until explicit action.                 |
| ExperimentalLifecycleProvider | Logical connect/disconnect mechanisms isolated from Core.                                          | Feature-flagged, kill-switchable, runtime-probed. |
| VirtualDisplayProvider        | Labs virtual endpoint lifecycle and configuration.                                                 | Absent from Core dependency graph.                |
| RecoveryService               | Reconnect All, checkpoint restore, startup bypass, rescue IPC.                                     | Minimal dependency set; emergency priority.       |
| SettingsStore                 | Versioned settings/scenes/rules with atomic write, backup, import/export.                          | No secrets.                                       |
| CheckpointStore               | Small atomic last-known-safe records and transaction health marker.                                | Readable by rescue utility.                       |
| DiagnosticsService            | Structured logs, topology timeline, bundle redaction, provider health.                             | No raw serials/tokens by default.                 |
| AutomationGateway             | CLI/App Intents/URL/HTTP command normalization and typed results.                                  | Same safety/coordinator path as UI.               |

## 10.4 State ownership and concurrency

- DisplayRegistry is an actor that owns normalized observed state and increments a topology generation after stabilization.

- TopologyCoordinator is an actor that owns the mutation queue. Emergency recovery has higher priority than scenes, rules, or external requests.

- Providers are stateless where practical; any per-route caches are actor-isolated and versioned by topology generation.

- UI views consume immutable snapshots and submit commands; they do not mutate domain models.

- OS callback threads enqueue raw events quickly; normalization, debouncing, and identity reconciliation occur off the callback path.

- Every transaction has a UUID/correlation ID, actor, reason, deadline, checkpoint ID, and event suppression scope.

## 10.5 Display identity model

| **Signal**                         | **Use**                                                  | **Caveat**                                                      |
|------------------------------------|----------------------------------------------------------|-----------------------------------------------------------------|
| User alias / explicit pairing      | Highest-level durable intent.                            | Must not silently move to another physical device.              |
| EDID serial/hash                   | Strong physical identity when valid.                     | Missing, duplicated, changed by adapters, or privacy-sensitive. |
| Vendor/product/model/year/week     | Model-family evidence.                                   | Insufficient for identical units.                               |
| IORegistry path / transport        | Route and port context.                                  | Changes across docks/ports and OS versions.                     |
| Physical dimensions                | Supporting evidence and scale calculations.              | Often rounded or incorrect.                                     |
| Current topology/relative position | Disambiguates identical monitors in a stable desk setup. | Not identity by itself.                                         |
| CG UUID/display ID                 | Current-session addressing.                              | May change or switch; never sole persistent key.                |
| User tags                          | Automation grouping.                                     | May intentionally match multiple displays.                      |

The resolver stores a stable internal DisplayRecord ID and links observations through scored evidence. Destructive selector resolution requires one high-confidence candidate; read-only queries may return multiple candidates. When evidence conflicts, the system marks the record Uncertain and preserves both candidates until the user resolves them.

## 10.6 Capability model

CapabilityDecision {  
capability: LogicalDisconnect \| DDCBrightness \| HDRWrite \| ...  
status: supported \| unsupported \| unknown \| degraded \| disabledByPolicy  
verification: verified \| readBackUnavailable \| notApplicable  
risk: normal \| hardwareDependent \| experimental \| recoveryCritical  
provider: identifier?  
reasons: \[OSVersion, Architecture, DisplayClass, Route, Permission,  
BuildFlavor, ProviderHealth, UserPolicy, SafetyPolicy\]  
validForTopologyGeneration: UInt64  
}

## 10.7 Scene planning and operation order

1\. Resolve identities and capabilities against one topology generation.

2\. Validate required displays and fields; produce a dry-run diff.

3\. Create checkpoint and suppress conflicting rules for the transaction scope.

4\. Reconnect destination displays and wait for registry stabilization.

5\. Establish safe surface and recovery UI location.

6\. Apply mirror/main/layout changes using public atomic configuration where possible.

7\. Refresh mode lists and apply modes/rotation/profile with verification.

8\. Apply controls, inputs, brightness, filters, and network commands with rate limits.

9\. Disconnect retiring displays only after destination postconditions pass.

10\. Commit desired state, activity result, and new last-known-safe checkpoint.

## 10.8 Storage model

| **Store**           | **Contents**                                                               | **Properties**                                      |
|---------------------|----------------------------------------------------------------------------|-----------------------------------------------------|
| Settings            | Preferences, UI state, feature flags, provider policies.                   | Versioned JSON/PropertyList; atomic write; backups. |
| Display records     | Stable IDs, aliases, tags, fingerprints, route history, pairing decisions. | Sensitive fields hashed/redacted on export.         |
| Scenes/rules        | Desired-state documents, selectors, triggers, priority, cooldown.          | Human-reviewable, versioned, import diff.           |
| Checkpoints         | Minimal topology and recovery state for recent risky transaction.          | Atomic, bounded, rescue-readable, no secrets.       |
| Activity/logs       | Transactions, events, provider health, errors, timings.                    | Structured, rotating, redaction levels.             |
| Keychain            | API tokens and network credentials.                                        | Never exported by default or logged.                |
| Compatibility flags | OS/build/provider certifications and kill switches.                        | Signed release data; conservative defaults.         |

## 10.9 Public/private API isolation

The experimental lifecycle and virtual-display modules must be separable build targets with narrow protocol surfaces. Core models may refer to capability concepts but not to private symbols or implementation types. CI shall compile and test a public-API-only flavor. On an unrecognized major OS build, persistent experimental policy is disabled until compatibility is explicitly enabled by a signed release configuration or the user opts into Labs.

# 11. Detailed requirements

These requirements are the normative backlog baseline. Acceptance criteria are intentionally testable and should be linked to implementation issues and automated/manual evidence. Release labels indicate the earliest intended delivery; Labs requirements remain subject to opt-in and compatibility gating.

| **Requirement domain**                   | **Count** | **Priority mix**              | **Release mix**                    |
|------------------------------------------|-----------|-------------------------------|------------------------------------|
| Display registry and identity            | 12        | Must: 11, Should: 1           | Core 1.0: 12                       |
| Safe display lifecycle                   | 22        | Must: 21, Should: 1           | Core 1.0: 21, Core 1.x: 1          |
| Topology, modes, and scenes              | 18        | Must: 14, Should: 3, Could: 1 | Core 1.0: 16, Core 1.x: 2          |
| Controls, DDC, color, and audio          | 14        | Must: 11, Should: 2, Could: 1 | Core 1.0: 10, Labs: 2, Core 1.x: 2 |
| Virtual display and capture              | 8         | Must: 4, Should: 3, Could: 1  | Labs: 5, Core 1.x: 3               |
| Automation and APIs                      | 12        | Must: 9, Should: 3            | Core 1.0: 7, Core 1.x: 5           |
| Recovery, diagnostics, and configuration | 12        | Must: 9, Should: 3            | Core 1.0: 10, Labs: 1, Core 1.x: 1 |
| User experience and accessibility        | 10        | Must: 7, Should: 3            | Core 1.0: 10                       |
| Non-functional requirements              | 16        | Must: 13, Should: 3           | Core 1.0: 16                       |

|     | **Release interpretation** Core 1.0 requirements are part of the first stable release unless removed by an explicit scope decision. Core 1.x requirements are follow-on commitments. Labs requirements define the minimum quality bar for experimentation; they are not permission to ship unsafe behavior. |
|-----|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

## Display registry and identity

Normative requirements: Display registry and identity

| **ID**  | **Requirement**                     | **System shall…**                                                                                                                                         | **Acceptance criterion**                                                                                                                        | **Priority** | **Release** |
|---------|-------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------|--------------|-------------|
| REG-001 | Discover active displays            | The system shall enumerate built-in, external, virtual, Sidecar/AirPlay, mirror members, and headless endpoints exposed by the OS.                        | A topology snapshot appears within 2 seconds of app readiness and matches Core Graphics/System Settings for all test fixtures.                  | Must         | Core 1.0    |
| REG-002 | Track topology events               | The registry shall publish ordered add, remove, mode, bounds, mirror, main-display, and sleep/wake changes.                                               | A recorded test sequence produces one normalized event stream with no duplicate stable-state events.                                            | Must         | Core 1.0    |
| REG-003 | Create persistent fingerprints      | Each display shall receive a fingerprint derived from available EDID, vendor/product, serial, transport, IORegistry, physical size, and topology signals. | A display reconnected to the same or another port resolves to its prior record when confidence exceeds the configured threshold.                | Must         | Core 1.0    |
| REG-004 | Handle identical monitors           | The identity engine shall distinguish identical models using serial, route/topology, user aliases, and explicit pairing.                                  | Two same-model monitors can be assigned persistent left/right identities and remain correct across ten reconnect cycles in the certified setup. | Must         | Core 1.0    |
| REG-005 | Expose confidence and provenance    | Every identity resolution shall expose confidence, matched signals, conflicting signals, and whether user confirmation is required.                       | Diagnostics and API output contain a score and evidence set; destructive actions are blocked below the safety threshold.                        | Must         | Core 1.0    |
| REG-006 | Remember offline devices            | The registry shall retain approved display records after disconnect and mark current reachability separately from desired policy.                         | A managed-offline display remains selectable for reconnect and scene planning after app restart.                                                | Must         | Core 1.0    |
| REG-007 | Support aliases and tags            | Users shall set unique display aliases and multiple automation tags.                                                                                      | Aliases appear in all UI/API surfaces and tags resolve deterministically or return an ambiguity error.                                          | Must         | Core 1.0    |
| REG-008 | Compute per-route capabilities      | Capabilities shall be evaluated for the current Mac, OS, display, port, adapter, dock, and policy combination.                                            | Moving a monitor from direct USB-C to a non-DDC dock updates the control availability and explanation without changing its user identity.       | Must         | Core 1.0    |
| REG-009 | Separate observed and desired state | The model shall retain observed OS/hardware state, user-desired state, policy source, and last verified state.                                            | Diagnostics can explain whether a value came from macOS, a scene, a rule, a user action, or recovery.                                           | Must         | Core 1.0    |
| REG-010 | Resolve conflicts explicitly        | Ambiguous selectors or competing policies shall never silently choose a destructive target.                                                               | CLI/API returns a typed conflict with candidates; UI requests confirmation or policy precedence.                                                | Must         | Core 1.0    |
| REG-011 | Version display records             | Persisted records shall use a migratable schema with atomic writes and backup.                                                                            | Upgrade and downgrade fixtures preserve aliases/scenes or fail safely with a readable migration report.                                         | Must         | Core 1.0    |
| REG-012 | Export registry diagnostics         | The app shall export a redacted machine-readable registry snapshot.                                                                                       | Export includes fingerprints with salted/redacted sensitive fields, capability reasons, and schema version.                                     | Should       | Core 1.0    |

## Safe display lifecycle

Normative requirements: Safe display lifecycle

| **ID**  | **Requirement**                     | **System shall…**                                                                                                                                       | **Acceptance criterion**                                                                                                                    | **Priority** | **Release** |
|---------|-------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------|--------------|-------------|
| LIF-001 | Name lifecycle operations precisely | The product shall expose separate actions for Black Out, Monitor Sleep/Power, Logical Disconnect, and Reconnect.                                        | No UI or API labels use these terms interchangeably; help text states topology impact for each.                                             | Must         | Core 1.0    |
| LIF-002 | Serialize lifecycle changes         | All logical connect/disconnect operations shall run through a single topology transaction coordinator.                                                  | Concurrent UI, rule, and CLI requests are queued, coalesced, or rejected with a busy result; no overlapping provider calls occur.           | Must         | Core 1.0    |
| LIF-003 | Preflight a safe visible surface    | Before logical disconnect, the app shall verify that at least one known-safe visible or recoverable surface remains.                                    | Disconnect is blocked when it would remove the last safe surface unless the user completes an advanced, timed, explicit override.           | Must         | Core 1.0    |
| LIF-004 | Preflight identity confidence       | A destructive lifecycle action shall require target identity above a configurable confidence threshold.                                                 | A low-confidence identical-monitor fixture cannot be disconnected without explicit target confirmation.                                     | Must         | Core 1.0    |
| LIF-005 | Create an atomic checkpoint         | The coordinator shall write a last-known-safe topology checkpoint before invoking an experimental lifecycle provider.                                   | Power loss after checkpoint creation leaves either the prior complete checkpoint or the new complete checkpoint, never partial data.        | Must         | Core 1.0    |
| LIF-006 | Provide first-use confirmation      | The first disconnect for each display/route shall present a countdown with Cancel and explain the recovery hotkey.                                      | Cancel during the countdown performs no provider action; acceptance records route-specific consent.                                         | Must         | Core 1.0    |
| LIF-007 | Verify postconditions               | After provider invocation, the coordinator shall observe system events and verify target state, safe-surface state, and topology stability.             | An operation is not reported successful until verified; timeout results in rollback or a degraded-state warning.                            | Must         | Core 1.0    |
| LIF-008 | Rollback failed disconnects         | A failed or unsafe transition shall restore the checkpoint using the most reliable available provider path.                                             | Injected failures at every transaction stage return the certified fixture to a usable display within the recovery objective.                | Must         | Core 1.0    |
| LIF-009 | Reconnect all managed displays      | Reconnect All shall attempt every display marked managed-offline, then reconcile results individually.                                                  | One failing display does not prevent attempts for others; UI and JSON list success/failure per target.                                      | Must         | Core 1.0    |
| LIF-010 | Keep emergency recovery omnipresent | Reconnect All shall be accessible from menu-bar root, global keyboard shortcut, CLI, and rescue utility.                                                | Recovery can be invoked without opening the main settings window and without using a pointer.                                               | Must         | Core 1.0    |
| LIF-011 | Ship independent rescue utility     | A minimal signed helper shall reconnect managed displays, disable auto-apply policies, and launch the app in safe mode.                                 | The helper operates when the main app configuration is corrupt or the main app crashes on launch.                                           | Must         | Core 1.0    |
| LIF-012 | Restore on normal quit by default   | Normal quit shall reconnect displays managed offline unless the user enabled an advanced persistent policy.                                             | Default quit on all certified fixtures leaves no display intentionally offline.                                                             | Must         | Core 1.0    |
| LIF-013 | Recover after unclean exit          | A startup health marker shall detect crash/termination during a lifecycle transaction and offer or perform safe restoration.                            | Killing the app at each transaction stage results in safe-mode startup and checkpoint recovery.                                             | Must         | Core 1.0    |
| LIF-014 | Reconcile wake once                 | After wake, the app shall debounce display events until topology is stable, then apply lifecycle policy at most once per stabilization generation.      | Wake storms do not cause repeated disconnect/reconnect loops; logs identify the single reconciliation decision.                             | Must         | Core 1.0    |
| LIF-015 | Guard persistent disconnect         | Persistent/aggressive disconnect shall be per-display, off by default, require a healthy startup window, and be bypassable by holding a documented key. | Reboot with bypass key prevents all experimental auto-actions; persistent policy never runs before rescue services are ready.               | Must         | Core 1.x    |
| LIF-016 | Automate built-in panel safely      | Built-in display rules shall account for external safe surface, lid state, AC power, and current session.                                               | Removing the last external display reconnects the built-in panel before the external endpoint becomes unavailable when the platform allows. | Must         | Core 1.0    |
| LIF-017 | Protect the last/iMac display       | The app shall identify configurations where the target may be the only recoverable local surface and increase confirmation/deny unsafe action.          | Certified last-display and iMac fixtures cannot enter an unrecoverable black-screen state using default settings.                           | Must         | Core 1.0    |
| LIF-018 | Implement Black Out reversibly      | Black Out shall be reversible locally and by recovery hotkey, without changing layout or moving windows unless explicitly configured.                   | Window positions and active topology remain unchanged over a Black Out cycle.                                                               | Must         | Core 1.0    |
| LIF-019 | Implement monitor power honestly    | DDC/network sleep shall report sent, verified, unverified, unsupported, or failed; it shall not claim logical disconnect.                               | A route that blocks DDC shows unverified/failed and retains the display in topology.                                                        | Must         | Core 1.0    |
| LIF-020 | Explain physical link limits        | The UI shall state that software generally cannot emulate cable removal, free a hardware display pipeline, or exceed platform display-count limits.     | Help and action details contain this limitation; no marketing text promises otherwise.                                                      | Must         | Core 1.0    |
| LIF-021 | Treat Sidecar/AirPlay separately    | Wireless/continuity endpoints shall use provider-specific connect/reconnect semantics and shall not be assumed equivalent to physical displays.         | Reconnect All reports unsupported or delegated behavior for Sidecar/AirPlay instead of false success.                                       | Should       | Core 1.0    |
| LIF-022 | Expose managed-offline status       | Every offline record shall show who disconnected it, when, why, desired reconnect policy, and last failure.                                             | UI and API expose the complete status for troubleshooting.                                                                                  | Must         | Core 1.0    |

## Topology, modes, and scenes

Normative requirements: Topology, modes, and scenes

| **ID**  | **Requirement**               | **System shall…**                                                                                                                     | **Acceptance criterion**                                                                                                  | **Priority** | **Release** |
|---------|-------------------------------|---------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------|--------------|-------------|
| TOP-001 | Read complete topology        | The app shall model bounds, scale, rotation, main display, mirror sets, active mode, refresh, HDR, profile, and connection state.     | The topology model round-trips certified fixture state to JSON without loss of supported fields.                          | Must         | Core 1.0    |
| TOP-002 | Apply layout atomically       | A layout change shall use one Core Graphics configuration transaction where supported.                                                | A multi-display move presents no observable intermediate overlap in event logs and completes or rolls back as one change. | Must         | Core 1.0    |
| TOP-003 | Set main display              | Users and scenes shall select the main display using stable identity.                                                                 | After apply and one wake cycle, the selected display remains main when protection is enabled.                             | Must         | Core 1.0    |
| TOP-004 | Manage mirrors                | The app shall create/remove mirror sets and validate source/target compatibility.                                                     | Unsupported mirror requests fail before changing topology; valid requests survive export/import.                          | Must         | Core 1.0    |
| TOP-005 | Apply modes safely            | Mode changes shall verify width, height, HiDPI flag, refresh, depth, and rotation against current capability.                         | An unavailable mode is rejected with alternatives; no stale mode ID is applied after reconnect.                           | Must         | Core 1.0    |
| TOP-006 | Pin favorite modes            | Users shall mark named mode combinations and invoke them from menu, shortcut, scene, or CLI.                                          | Favorites resolve by properties rather than transient mode IDs and warn when no current equivalent exists.                | Should       | Core 1.0    |
| TOP-007 | Protect selected properties   | Users shall independently protect layout, main display, mode, rotation, HDR, refresh, and profile.                                    | Changing an unprotected field does not trigger restoration; changing a protected field does after the debounce window.    | Must         | Core 1.0    |
| TOP-008 | Debounce restoration          | Protection shall wait for topology stabilization and use bounded retries/circuit breaking.                                            | A deliberately unsupported state does not cause an infinite restore loop or persistent flicker.                           | Must         | Core 1.0    |
| TOP-009 | Define anchors                | Scenes may position displays relative to an anchor with edge/center alignment and gaps.                                               | Scenes adapt when an optional display is absent while preserving anchor-relative placement.                               | Should       | Core 1.0    |
| TOP-010 | Model desired state scenes    | A scene shall contain optional display membership, topology, modes, controls, profiles, and lifecycle policy.                         | A scene can omit fields; omitted fields remain unchanged during apply.                                                    | Must         | Core 1.0    |
| TOP-011 | Preview scene diff            | Before manual application, the UI shall show target resolution, operations, unsupported fields, and risk level.                       | Preview uses the same planner as execution and matches the resulting transaction log.                                     | Must         | Core 1.0    |
| TOP-012 | Order scene operations safely | The planner shall connect needed displays before layout/mode changes and disconnect targets only after a safe surface is established. | A desk-to-mobile fixture never disconnects the current safe display before the destination surface is verified.           | Must         | Core 1.0    |
| TOP-013 | Make scene apply idempotent   | Applying an already-satisfied scene shall produce no unnecessary provider calls.                                                      | Second apply on a stable fixture yields zero topology writes and zero visible flicker.                                    | Must         | Core 1.0    |
| TOP-014 | Support partial availability  | Scenes shall declare required and optional displays and a policy for missing capabilities.                                            | Required-missing blocks before mutation; optional-missing continues and reports a warning.                                | Must         | Core 1.0    |
| TOP-015 | Rollback scene failure        | A scene transaction shall roll back topology-critical fields when a required step fails.                                              | Fault injection at each required step returns the system to checkpoint or a documented safe degraded state.               | Must         | Core 1.0    |
| TOP-016 | Export/import scenes          | Scenes shall serialize to a documented, versioned, reviewable format.                                                                 | Round-trip preserves all non-secret fields; imports validate selectors and show a diff before commit.                     | Must         | Core 1.0    |
| TOP-017 | Separate window movement      | Window repositioning shall be opt-in and isolated from display topology changes.                                                      | Applying a scene with window policy disabled never moves application windows.                                             | Should       | Core 1.x    |
| TOP-018 | Provide UI scale suggestions  | The app shall calculate suggested modes that approximate equal physical UI size across selected displays.                             | Recommendation includes assumptions and never auto-applies without confirmation.                                          | Could        | Core 1.x    |

## Controls, DDC, color, and audio

Normative requirements: Controls, DDC, color, and audio

| **ID**  | **Requirement**                          | **System shall…**                                                                                                                                  | **Acceptance criterion**                                                                                          | **Priority** | **Release** |
|---------|------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------|--------------|-------------|
| CTL-001 | Probe DDC per route                      | The app shall probe DDC/CI availability, VCP support, timing, and verification behavior for the current connection route.                          | Diagnostics distinguish display support from transport failure and cache results with expiry.                     | Must         | Core 1.0    |
| CTL-002 | Control brightness through best provider | Brightness shall select native, DDC, software, or combined providers according to capability and user policy.                                      | The UI displays the active provider and fallback; provider changes do not produce large visible jumps.            | Must         | Core 1.0    |
| CTL-003 | Control volume/mute/contrast             | Supported DDC/native values shall expose read/write ranges and verification state.                                                                 | Controls are hidden or disabled with reason when unavailable; writes respect the device's actual range.           | Must         | Core 1.0    |
| CTL-004 | Switch inputs safely                     | Input switching shall use named values, optional read-back, and configurable delay before dependent scene steps.                                   | A scene waits for the configured route stabilization or reports unverified transition.                            | Must         | Core 1.0    |
| CTL-005 | Normalize control ranges                 | Provider-specific ranges shall map to a consistent 0-100 user scale while preserving raw values for diagnostics.                                   | Round-trip error stays within one UI step for certified monitors.                                                 | Must         | Core 1.0    |
| CTL-006 | Rate-limit writes                        | Slider, key repeat, automation, and synchronization writes shall be coalesced and bounded per device/provider.                                     | A 100-event burst generates no more than the configured safe provider call rate and converges to the final value. | Must         | Core 1.0    |
| CTL-007 | Synchronize groups                       | Group control shall map one source value to members with per-display curve, min/max, and offset.                                                   | Mixed native/DDC/software group converges within tolerance without recursive event loops.                         | Must         | Core 1.0    |
| CTL-008 | Route media keys                         | Brightness and volume keys shall target main, pointer, focused-window, fixed display, or group policy.                                             | Each routing mode passes keyboard-only tests and shows an identifying OSD.                                        | Must         | Core 1.0    |
| CTL-009 | Select and protect profiles              | Users/scenes shall select color profiles and optionally protect them.                                                                              | Profile is restored after a simulated system drift and not restored when protection is disabled.                  | Must         | Core 1.0    |
| CTL-010 | Guard HDR/XDR changes                    | High dynamic range and brightness expansion writes shall be capability-gated, rate-limited, reversible, and clearly experimental where applicable. | Rapid-change and crash tests do not leave a certified display washed out after recovery.                          | Must         | Labs        |
| CTL-011 | Provide image filters                    | Software filters shall declare capture/overlay limitations and be removable through safe mode/recovery.                                            | Filters never obscure the Reconnect All recovery surface and are disabled in safe mode.                           | Should       | Core 1.x    |
| CTL-012 | Support network providers                | Network-controlled devices shall use opt-in provider plugins with explicit discovery and credentials handling.                                     | Credentials remain in Keychain; disabling a plugin removes network listeners and discovery.                       | Could        | Core 1.x    |
| CTL-013 | Expose raw diagnostics                   | Advanced users shall inspect raw DDC VCP codes, provider responses, and timing without enabling arbitrary unsafe writes by default.                | Diagnostics are read-only unless an advanced developer flag is enabled.                                           | Should       | Core 1.0    |
| CTL-014 | Avoid medical claims                     | Eye-care features shall describe technical effects and uncertainty without diagnosing or promising health outcomes.                                | Copy review finds no medical efficacy claim; links distinguish user preference from established evidence.         | Must         | Labs        |

## Virtual display and capture

Normative requirements: Virtual display and capture

| **ID**  | **Requirement**                        | **System shall…**                                                                                                     | **Acceptance criterion**                                                                                     | **Priority** | **Release** |
|---------|----------------------------------------|-----------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------|--------------|-------------|
| VIR-001 | Gate virtual displays behind Labs      | Virtual display creation shall be disabled by default and isolated behind a provider/capability contract.             | Core build operates fully with the provider absent; Labs opt-in includes recovery notice.                    | Must         | Labs        |
| VIR-002 | Create named virtual endpoints         | Users shall create a virtual display with name, logical/pixel size, scale, and optional refresh/HDR parameters.       | On supported fixtures, the endpoint appears in registry and can be discarded/recreated by stable virtual ID. | Should       | Labs        |
| VIR-003 | Persist virtual intent safely          | Persistence shall wait for app health and topology stabilization and shall be bypassed by safe-mode startup.          | A corrupt virtual definition cannot create a startup loop; invalid entries are quarantined.                  | Must         | Labs        |
| VIR-004 | Preview displays with ScreenCaptureKit | PIP/zoom shall use public capture APIs and request only required permissions.                                         | Permission denial leaves topology features functional and provides a direct explanation.                     | Should       | Core 1.x    |
| VIR-005 | Protect captured privacy               | Capture UI shall show an active indicator, honor system exclusions, and stop streams on lock/logout.                  | Automated lock test terminates all capture sessions within the defined objective.                            | Must         | Core 1.x    |
| VIR-006 | Control PIP behavior                   | Users shall choose always-on-top, aspect fit/fill, pointer visibility, click-through, and target display/region.      | Settings persist per PIP preset and keyboard control remains possible.                                       | Could        | Core 1.x    |
| VIR-007 | Define virtual sleep policy            | Users shall choose whether windows move, display reconnects, or state remains offline after sleep.                    | Each policy produces documented behavior in sleep/wake integration tests.                                    | Should       | Labs        |
| VIR-008 | Secure local streaming                 | Streaming shall be off by default, bind locally by default, require authentication, and show active-session controls. | A network scan finds no listener until enabled; unauthenticated requests fail.                               | Must         | Labs        |

## Automation and APIs

Normative requirements: Automation and APIs

| **ID**  | **Requirement**                  | **System shall…**                                                                                                                      | **Acceptance criterion**                                                                                    | **Priority** | **Release** |
|---------|----------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------|--------------|-------------|
| AUT-001 | Provide a stable CLI             | The CLI shall implement list/get/set/toggle/scene/connect/disconnect/recover/diagnose with documented exit codes.                      | Golden tests validate syntax, stdout JSON, stderr warnings, and idempotency across releases.                | Must         | Core 1.0    |
| AUT-002 | Use stable selectors             | CLI/API selectors shall support fingerprint ID, alias, tag, name with disambiguation, vendor/product/serial, main, pointer, and focus. | Ambiguous selectors return candidates and no mutation.                                                      | Must         | Core 1.0    |
| AUT-003 | Support dry run                  | Every multi-field or lifecycle mutation shall offer a dry-run plan.                                                                    | Dry run performs zero writes and returns operation order, risks, permissions, and unsupported fields.       | Must         | Core 1.0    |
| AUT-004 | Return typed results             | Automation surfaces shall return per-field success, failure, warning, verification state, and transaction ID.                          | Callers can distinguish unsupported, permission denied, ambiguous, timeout, rollback, and provider failure. | Must         | Core 1.0    |
| AUT-005 | Expose App Intents               | Common actions and scenes shall be available through App Intents with parameterized display selectors.                                 | Shortcuts can list scenes, apply a scene, adjust brightness, switch input, and invoke Reconnect All.        | Must         | Core 1.0    |
| AUT-006 | Secure URL actions               | The URL scheme shall limit destructive actions or require a confirmation/token policy.                                                 | A crafted untrusted URL cannot silently disconnect the last safe display.                                   | Must         | Core 1.x    |
| AUT-007 | Secure HTTP API                  | The optional HTTP server shall bind to loopback by default and require a random bearer token.                                          | Requests without token fail; tokens rotate; no secret is included in diagnostics export.                    | Must         | Core 1.x    |
| AUT-008 | Publish events                   | Clients shall subscribe to normalized topology, state, transaction, and recovery events.                                               | Event payloads include monotonic sequence, schema version, source, and correlation ID.                      | Should       | Core 1.x    |
| AUT-009 | Evaluate rules deterministically | Rules shall have explicit priority, cooldown, conditions, and conflict resolution.                                                     | Given the same event/state fixture, rule evaluation produces the same ordered action plan.                  | Should       | Core 1.x    |
| AUT-010 | Audit automation                 | Every automated mutation shall be logged with actor, selector resolution, policy, and result.                                          | Activity log can answer what changed a display and how to undo it.                                          | Must         | Core 1.0    |
| AUT-011 | Rate-limit external callers      | CLI/API/HTTP requests shall share coordinator limits and cannot bypass safety checks.                                                  | A request flood does not exceed provider rate limits or starve Reconnect All.                               | Must         | Core 1.0    |
| AUT-012 | Maintain backward compatibility  | Documented API fields shall follow semantic versioning and deprecation windows.                                                        | Compatibility tests run against the prior two minor client schemas.                                         | Should       | Core 1.x    |

## Recovery, diagnostics, and configuration

Normative requirements: Recovery, diagnostics, and configuration

| **ID**  | **Requirement**                    | **System shall…**                                                                                                                 | **Acceptance criterion**                                                                                             | **Priority** | **Release** |
|---------|------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|--------------|-------------|
| DIA-001 | Launch in safe mode                | Safe mode shall disable experimental providers, auto-apply rules, persistent disconnect, filters, and virtual recreation.         | Holding the startup bypass key or using the rescue utility reaches a usable safe-mode UI on every certified fixture. | Must         | Core 1.0    |
| DIA-002 | Offer selective reset              | Users shall reset display identity, DDC cache, rules, scenes, providers, or all settings.                                         | Each reset previews affected objects and leaves unrelated settings untouched.                                        | Must         | Core 1.0    |
| DIA-003 | Write structured logs              | Logs shall include transaction ID, topology generation, provider, state transitions, timing, and redaction level.                 | A failing integration test can be reconstructed from the diagnostics bundle without personal content.                | Must         | Core 1.0    |
| DIA-004 | Build a topology timeline          | Diagnostics shall retain a bounded sequence of normalized display events around wake, connect, and failure.                       | Timeline displays stable timestamps and causal transaction IDs.                                                      | Should       | Core 1.0    |
| DIA-005 | Generate a redacted support bundle | The bundle shall include versions, hardware class, capability matrix, settings schema, logs, and crash metadata with user review. | Default export removes usernames, window titles, IPs, serials, and tokens or hashes them consistently.               | Must         | Core 1.0    |
| DIA-006 | Show actionable capability reasons | Disabled features shall explain missing OS support, route, hardware, permission, build flavor, or safety policy.                  | At least 95% of disabled controls in test fixtures have a non-generic reason code and remediation.                   | Must         | Core 1.0    |
| DIA-007 | Detect provider health             | Each provider shall expose probe, health, version, failure count, and circuit-breaker state.                                      | Three bounded failures in a configured window disable the provider and present recovery without repeated writes.     | Must         | Core 1.0    |
| DIA-008 | Back up risky configuration        | Before EDID/system override changes, the app shall export current state and require explicit restart/recovery acknowledgement.    | A failed override install can be removed by rescue flow with documented commands.                                    | Must         | Labs        |
| DIA-009 | Validate imports                   | Imported settings shall be schema-validated, show a diff, exclude secrets, and quarantine unknown experimental fields.            | Malformed imports perform no partial write and produce line/item-level errors.                                       | Must         | Core 1.0    |
| DIA-010 | Support reproducible bug reports   | The app shall create a correlation ID and optional minimal reproduction script from an activity segment.                          | Maintainers can attach logs and steps without requiring users to disclose full configuration.                        | Should       | Core 1.x    |
| DIA-011 | Protect secrets                    | HTTP tokens, network credentials, and signing material shall never enter plain settings or logs.                                  | Static and dynamic scans find no plaintext secret in exported configuration or bundle.                               | Must         | Core 1.0    |
| DIA-012 | Provide in-app health summary      | A dashboard shall show unsafe pending states, managed-offline displays, circuit breakers, permissions, and update compatibility.  | A user can reach all active remediation actions from the health summary.                                             | Should       | Core 1.0    |

## User experience and accessibility

Normative requirements: User experience and accessibility

| **ID** | **Requirement**                   | **System shall…**                                                                                                                                           | **Acceptance criterion**                                                                                                     | **Priority** | **Release** |
|--------|-----------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------|--------------|-------------|
| UX-001 | Provide a fast menu-bar surface   | The root menu shall show Reconnect All, scenes, and display cards without deep navigation.                                                                  | Reconnect All is one menu level or less; common brightness and mode actions are reachable within two levels.                 | Must         | Core 1.0    |
| UX-002 | Provide a topology workspace      | The settings app shall visualize arrangement, main display, mirrors, active/offline state, and identity confidence.                                         | Keyboard and VoiceOver users can inspect and change the same supported topology fields.                                      | Must         | Core 1.0    |
| UX-003 | Use risk-aware copy               | Actions shall carry Normal, Hardware-dependent, Experimental, Restart-required, or Recovery-critical labels.                                                | Usability test participants correctly predict topology impact of each lifecycle action at the target rate.                   | Must         | Core 1.0    |
| UX-004 | Make dangerous actions reversible | The UI shall offer Undo where technically safe and always provide the next recovery action after failure.                                                   | Activity rows show Undo/Recover or explain why neither is possible.                                                          | Must         | Core 1.0    |
| UX-005 | Meet accessibility baseline       | The app shall support VoiceOver, full keyboard navigation, reduced motion, sufficient contrast, Dynamic Type-equivalent scaling, and non-color status cues. | Automated audit passes and manual VoiceOver workflow covers onboarding, disconnect, reconnect, scene apply, and diagnostics. | Must         | Core 1.0    |
| UX-006 | Avoid trapping focus off-screen   | After topology changes, key windows shall be moved to a verified active display when needed.                                                                | The main/recovery window remains reachable after disconnecting the display that previously contained it.                     | Must         | Core 1.0    |
| UX-007 | Show concise OSD feedback         | Brightness, volume, input, mode, and scene actions shall show target and result without obscuring critical UI.                                              | OSD identifies the display/group and disappears or persists according to accessibility preference.                           | Should       | Core 1.0    |
| UX-008 | Support localization              | All user-facing strings shall use localization resources and layouts shall tolerate at least 40% expansion.                                                 | Pseudo-localization produces no clipping in all core screens.                                                                | Should       | Core 1.0    |
| UX-009 | Explain permissions in context    | Screen recording, accessibility, automation, network, and login-item permissions shall be requested only when a feature needs them.                         | Fresh install can use core topology/DDC features without granting unrelated capture permission.                              | Must         | Core 1.0    |
| UX-010 | Provide contextual help           | Each advanced feature shall link to a local help page with behavior, compatibility, risk, and recovery.                                                     | Help remains accessible offline and matches the installed app version.                                                       | Should       | Core 1.0    |

## Non-functional requirements

Normative requirements: Non-functional requirements

| **ID**  | **Requirement**         | **System shall…**                                                                                                        | **Acceptance criterion**                                                                                            | **Priority** | **Release** |
|---------|-------------------------|--------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|--------------|-------------|
| NFR-001 | Startup performance     | Menu-bar status and registry shall become usable quickly without blocking on slow DDC probes.                            | p95 time to usable is \<=2.0 seconds on supported Apple Silicon baseline; DDC probes continue asynchronously.       | Must         | Core 1.0    |
| NFR-002 | Interaction latency     | Common UI actions shall acknowledge immediately and complete within provider-specific budgets.                           | UI feedback \<=100 ms; p95 native control \<=250 ms; DDC completion budget documented per route.                    | Should       | Core 1.0    |
| NFR-003 | Topology convergence    | After the last OS display event, registry state shall converge within a bounded stabilization window.                    | p95 stable snapshot \<=2 seconds after normal connect/wake event storms on certified fixtures.                      | Must         | Core 1.0    |
| NFR-004 | Recovery objective      | A failed lifecycle transaction shall restore a usable safe surface rapidly.                                              | Automated fault tests achieve usable recovery within 10 seconds p95 where the OS/provider remains responsive.       | Must         | Core 1.0    |
| NFR-005 | Crash-free operation    | Core paths shall meet a defined crash-free-session target before 1.0.                                                    | \>=99.9% crash-free sessions in opt-in beta telemetry or equivalent test evidence; zero known P0 recovery defects.  | Must         | Core 1.0    |
| NFR-006 | Resource use            | Idle monitoring shall have low CPU, memory, wakeups, and energy impact.                                                  | Baseline idle \<=0.5% CPU average, \<=150 MB memory, and no busy polling on reference hardware.                     | Should       | Core 1.0    |
| NFR-007 | Security                | The project shall use least privilege, hardened runtime where compatible, Keychain for secrets, and dependency scanning. | Threat model reviewed; high/critical dependency findings block release; local endpoints require authentication.     | Must         | Core 1.0    |
| NFR-008 | Privacy                 | No analytics, display serial collection, capture, or network listener shall activate by default.                         | Fresh-install network/capture audit shows zero unexpected outbound traffic or capture session.                      | Must         | Core 1.0    |
| NFR-009 | Accessibility quality   | Accessibility is a release gate, not a post-1.0 enhancement.                                                             | Core workflows pass manual VoiceOver and keyboard testing on each supported major OS.                               | Must         | Core 1.0    |
| NFR-010 | Compatibility isolation | Experimental code shall not be required for Core compilation or startup.                                                 | Public-API-only CI build passes all applicable tests with experimental modules absent.                              | Must         | Core 1.0    |
| NFR-011 | Reproducible builds     | Release artifacts shall be traceable to tagged source, dependency lockfiles, checksums, and SBOM.                        | Two clean build environments produce functionally equivalent artifacts; release publishes provenance and checksums. | Should       | Core 1.0    |
| NFR-012 | Update safety           | Updates shall preserve recovery paths and detect OS/build incompatibility before auto-enabling experimental providers.   | On a new major macOS version, experimental auto-apply defaults off until compatibility is explicitly approved.      | Must         | Core 1.0    |
| NFR-013 | Testability             | Core logic shall be dependency-injected and runnable against simulated topology/provider fixtures.                       | State machine, planner, identity, and rules achieve agreed coverage and deterministic replay tests.                 | Must         | Core 1.0    |
| NFR-014 | Documentation           | User, recovery, API, architecture, and contribution documentation shall ship with each release.                          | Release checklist blocks if docs or schema references are stale.                                                    | Must         | Core 1.0    |
| NFR-015 | Maintainability         | Provider boundaries and state transitions shall be explicit, logged, and reviewed through RFCs.                          | No UI component directly calls private/system provider APIs; architecture lint/tests enforce dependency direction.  | Must         | Core 1.0    |
| NFR-016 | License compliance      | Every dependency and contribution shall have recorded provenance and compatible licensing.                               | Automated license scan and human review pass before release; unknown license blocks inclusion.                      | Must         | Core 1.0    |

# 12. Automation and integration contract

## 12.1 Design requirements

- Every external command enters through AutomationGateway and uses the same identity, capability, safety, transaction, verification, and audit path as the UI.

- Selectors are stable and explicit. Ambiguity is an error for mutation; read-only queries may return a candidate set.

- Commands are idempotent where the requested end state is already satisfied.

- Machine-readable output is the default for scripting; human-readable output remains available.

- Dry run is supported for scenes, multi-field updates, and lifecycle actions.

- The API distinguishes unsupported, disabled-by-policy, denied, ambiguous, timeout, failed, partial, rolled-back, and unverified results.

## 12.2 Proposed CLI grammar

opendisplay list \[--state active\|offline\|all\] \[--json\]  
opendisplay get \<selector\> \[field ...\] \[--json\]  
opendisplay set \<selector\> \<field=value\>... \[--dry-run\] \[--json\]  
opendisplay connect \<selector\> \[--dry-run\] \[--json\]  
opendisplay disconnect \<selector\> \[--confirm-policy interactive\|preapproved\] \[--dry-run\]  
opendisplay blackout \<selector\> on\|off\|toggle  
opendisplay power \<selector\> on\|off\|sleep  
opendisplay scene list\|show\|apply\|export\|import \<name-or-id\> \[--dry-run\]  
opendisplay recover all\|checkpoint\|safe-mode \[--json\]  
opendisplay diagnose display\|route\|provider\|bundle \[selector\]

## 12.3 Selector contract

| **Selector**       | **Example**                       | **Mutation rule**                                                    |
|--------------------|-----------------------------------|----------------------------------------------------------------------|
| Stable internal ID | id:disp_01J…                      | Preferred exact selector.                                            |
| Alias              | alias:DeskLeft                    | Must resolve uniquely.                                               |
| Tag                | tag:studio                        | May target a set; destructive set operations require explicit --all. |
| Fingerprint fields | vendor:610 product:12345 serial:… | Evidence is normalized; sensitive values may be hashed.              |
| Name/model         | name:"LG HDR 4K"                  | Ambiguity returns candidates.                                        |
| Role               | main, builtin, pointer, focus     | Resolved at transaction start and recorded.                          |
| State              | state:managedOffline              | Set selector; explicit confirmation for lifecycle mutations.         |
| Topology           | leftOf:alias:Center               | Read/query aid; not sole persistent identity.                        |

## 12.4 Result envelope

{  
"schemaVersion": "1.0",  
"transactionId": "A4D0…",  
"status": "committed \| partial \| rolledBack \| failed \| noOp",  
"actor": "cli",  
"requestedAt": "2026-06-21T12:00:00Z",  
"topologyGeneration": 419,  
"targets": \[{  
"displayId": "disp_01J…",  
"alias": "DeskLeft",  
"identityConfidence": 0.98,  
"operations": \[{  
"field": "lifecycle.connected",  
"requested": false,  
"observed": false,  
"verification": "verified",  
"provider": "experimentalLifecycle.v1",  
"warnings": \[\]  
}\]  
}\],  
"recovery": {"checkpointId": "cp\_…", "available": true},  
"errors": \[\]  
}

## 12.5 App Intents baseline

| **Intent**         | **Parameters**                          | **Result**                                    |
|--------------------|-----------------------------------------|-----------------------------------------------|
| Apply Scene        | Scene; optional dry run                 | Applied / warnings / failed.                  |
| Set Brightness     | Display/group; value; relative/absolute | Provider and verified/unverified state.       |
| Set Volume / Mute  | Display/group; value/action             | Per-target outcome.                           |
| Switch Input       | Display; named input                    | Sent/verified/unverified.                     |
| Set Favorite Mode  | Display; favorite                       | Applied or unavailable with alternatives.     |
| Black Out          | Display/group; on/off/toggle            | Current overlay state.                        |
| Logical Disconnect | Display; confirmation policy            | May require foreground confirmation.          |
| Reconnect          | Display                                 | Verified active or endpoint-specific failure. |
| Reconnect All      | None                                    | Per-target recovery result.                   |
| Get Display State  | Display selector                        | Structured display summary.                   |

## 12.6 Local HTTP and event API

Core 1.x may expose a loopback-only HTTP API using the same command/result schemas. It is disabled by default, requires a randomly generated bearer token stored in Keychain, supports token rotation, binds to 127.0.0.1/::1 unless the user explicitly enables LAN access, and never permits last-safe-display disconnect without a preapproved safety policy. Server-sent events or WebSocket events may publish normalized state and transaction updates with sequence numbers and schema versions.

## 12.7 API stability

- Semantic version the external schema separately from the application.

- Additive fields are permitted in minor versions; clients must ignore unknown fields.

- Breaking field/semantic changes require a major schema version and migration guide.

- Document deprecation at least two minor releases before removal where security does not require immediate change.

- Golden fixtures for the prior two minor versions run in CI.

# 13. Data, configuration, and migration

## 13.1 Primary entities

| **Entity**           | **Key fields**                                                                | **Notes**                                       |
|----------------------|-------------------------------------------------------------------------------|-------------------------------------------------|
| DisplayRecord        | stableID, alias, tags, fingerprints, route history, pairing, lastSeen         | Persists across active/offline observations.    |
| DisplayObservation   | CG IDs/UUID, IO path, active/bounds/mode, mirror/main, HDR/profile, timestamp | Immutable snapshot tied to topology generation. |
| CapabilitySnapshot   | capability, status, reasons, provider, verification, generation               | Invalidated by route/OS/provider changes.       |
| Scene                | ID, name, member selectors, required/optional flags, desired fields, policy   | Fields are optional and independently applied.  |
| Rule                 | event, conditions, priority, cooldown, scene/actions, enabled                 | Deterministic conflict handling.                |
| ManagedOfflineRecord | displayID, actor, reason, time, provider, persistence policy                  | Distinct from system absence.                   |
| Checkpoint           | topology, modes, roles, managed-offline set, transaction metadata             | Minimal and rescue-readable.                    |
| Transaction          | ID, actor, plan, stages, results, checkpoint, timestamps                      | Append-only activity record.                    |
| ProviderHealth       | provider, environment key, status, failures, breaker, last probe              | Controls capability decisions.                  |

## 13.2 Scene document example

{  
"schemaVersion": "1.0",  
"id": "scene_studio",  
"name": "Studio",  
"members": \[  
{"selector": "alias:Center", "required": true},  
{"selector": "alias:Left", "required": true},  
{"selector": "builtin", "required": false}  
\],  
"desired": {  
"Center": {  
"connected": true,  
"main": true,  
"position": {"x": 0, "y": 0},  
"mode": {"width": 3008, "height": 1692, "hiDPI": true, "refreshHz": 60},  
"brightness": 62,  
"profile": "Studio SDR"  
},  
"Left": {  
"connected": true,  
"position": {"relativeTo": "Center", "edge": "left", "gap": 0},  
"rotation": 90,  
"brightness": 54  
},  
"builtin": {"connected": false}  
},  
"policy": {  
"missingOptional": "continue",  
"unsupportedField": "warn",  
"windowPlacement": "unchanged",  
"rollbackOnRequiredFailure": true  
}  
}

## 13.3 Configuration principles

- Use versioned, human-reviewable formats for scenes, rules, display aliases, and export bundles.

- Use atomic replace, fsync-equivalent durability where practical, and rotating backups for settings and checkpoints.

- Store secrets only in Keychain and reference them by opaque ID.

- Keep display serials and network identifiers out of default exports; use salted hashes when correlation is needed.

- Do not persist transient display IDs as the sole selector.

- Validate imported documents before any write and show a semantic diff.

## 13.4 Migration strategy

1\. Read the current schema version and create an immutable backup.

2\. Run pure, deterministic migration steps in order; each step produces a validation report.

3\. Resolve deprecated selector forms to stable display records where confidence is sufficient.

4\. Quarantine unknown experimental fields rather than silently discarding them.

5\. Write the new document atomically and retain the previous version for rollback.

6\. On failure, start with Core defaults and present an import/recovery screen; do not apply automatic display policies.

## 13.5 Export profiles

| **Profile**       | **Included**                                                                      | **Excluded/default redaction**                                          |
|-------------------|-----------------------------------------------------------------------------------|-------------------------------------------------------------------------|
| Portable settings | Preferences, scenes, rules, aliases/tags, safe feature flags.                     | Secrets, raw serials, logs, crash data.                                 |
| Support bundle    | Versions, capability matrix, redacted topology timeline, logs, transaction state. | Tokens, credentials, usernames, window titles, captures.                |
| Developer bundle  | Support bundle plus raw provider diagnostics with explicit preview.               | Still excludes secrets; sensitive identifiers require separate consent. |
| Recovery snapshot | Checkpoint and lifecycle policy needed by rescue utility.                         | No general settings or credentials.                                     |

# 14. Security, privacy, and permissions

## 14.1 Threat model summary

| **Threat**                         | **Asset / consequence**                    | **Control**                                                                             |
|------------------------------------|--------------------------------------------|-----------------------------------------------------------------------------------------|
| Malicious local automation request | Disconnect/alter user's displays.          | Authenticated gateway, loopback default, safety checks, rate limits, audit.             |
| Compromised provider/dependency    | Arbitrary code or unstable display writes. | Minimal dependencies, sandbox where feasible, SBOM, review, signing, isolation.         |
| Leaked display/network identifiers | Device/user fingerprinting.                | Local-only storage, hash/redact exports, no analytics by default.                       |
| Capture without clear consent      | Screen content exposure.                   | On-demand permission, active indicator, session controls, stop on lock/logout.          |
| Update incompatibility             | Black screen/startup loop.                 | Signed updates, OS compatibility flags, safe-mode migration, experimental defaults off. |
| Corrupt settings/import            | Unsafe auto-apply.                         | Schema validation, atomic writes, backup, quarantine, recovery-first startup.           |
| Stolen API token                   | Local/remote control.                      | Keychain, scoped/rotatable token, LAN off by default, audit and revoke.                 |
| Supply-chain tampering             | Malicious release.                         | Protected branches, reproducible metadata, checksums, notarization, provenance/SBOM.    |

## 14.2 Permission model

| **Permission / capability** | **When requested**                                                                | **Features affected**                  | **Behavior when denied**                                 |
|-----------------------------|-----------------------------------------------------------------------------------|----------------------------------------|----------------------------------------------------------|
| Screen Recording            | Only when starting PIP/zoom/screenshot/stream.                                    | Capture features.                      | Topology, controls, scenes, lifecycle remain functional. |
| Accessibility               | Only for optional window placement or advanced key routing if required.           | Window movement / selected automation. | No window movement; display features remain functional.  |
| Automation / App Intents    | When user enables Shortcuts/integrations.                                         | External workflows.                    | In-app and CLI remain available according to platform.   |
| Local Network               | Only for explicitly enabled network providers or LAN API.                         | TV/receiver plugins, LAN control.      | Providers unavailable with reason.                       |
| Login item / helper         | When enabling startup policies or recovery service.                               | Persistent policy, early recovery.     | No auto-apply; manual app functions remain.              |
| Administrator privilege     | Avoid in Core; request only if a specific Labs override cannot operate otherwise. | System overrides.                      | Feature remains unavailable; no blanket privilege.       |

## 14.3 Privacy defaults

- No analytics, crash upload, network discovery, HTTP listener, screen capture, or LAN access on fresh install.

- Opt-in diagnostics show exactly what will be sent and allow local save instead of upload.

- Display serials, EDID, topology, connected-device names, and network addresses are treated as potentially identifying.

- Logs record pseudonymous stable IDs; raw identifiers are available only in an advanced local diagnostic view.

- The application does not collect screen contents for ordinary display management.

- Credentials live in Keychain and are never included in exported settings or support bundles.

## 14.4 Secure development requirements

- Threat model and security review for lifecycle provider, rescue IPC, update channel, and local API before 1.0.

- Dependency pinning, automated vulnerability/license scanning, secret scanning, signed commits/tags where practical, protected release workflow.

- Hardened runtime and least entitlements for each binary, balanced against documented compatibility needs.

- Fuzz/schema tests for imports and API payloads; strict bounds and timeouts for DDC/network protocol parsing.

- Security advisory process, private reporting channel, supported-version policy, and coordinated disclosure.

|     | **Experimental API warning** Use of undocumented system interfaces increases compatibility and review risk. Such code must be narrowly isolated, auditable, kill-switchable, and excluded from the public-API-only build. It must not bypass macOS security controls. |
|-----|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 15. Quality, test strategy, and hardware matrix

## 15.1 Quality strategy

Display management cannot be validated by unit tests alone. The test program combines deterministic model/state-machine tests, provider contract tests, simulated OS event replay, integration tests on real hardware, fault injection, sleep/wake/reboot endurance, accessibility testing, and release-ring evidence. Every high-risk lifecycle change must be tested against recovery, not only success.

## 15.2 Test layers

| **Layer**              | **Scope**                                                             | **Examples**                                                    |
|------------------------|-----------------------------------------------------------------------|-----------------------------------------------------------------|
| Unit                   | Pure identity, capability, planner, rules, schema, range mapping.     | Ambiguity, scene diff, ordering, migrations, DDC normalization. |
| State-machine/model    | Lifecycle and transaction invariants under generated events/failures. | No last-safe loss; rollback; circuit breaker; idempotency.      |
| Provider contract      | Mock and real provider behavior against typed semantics.              | Timeouts, cancellation, unsupported, partial, read-back.        |
| Integration simulation | Recorded Core Graphics/IO events and virtual fixtures.                | Wake storms, reorder, route changes, mode invalidation.         |
| Real hardware          | Certified Mac/display/dock/KVM matrix.                                | Disconnect, DDC, modes, HDR, identical displays, sleep/wake.    |
| Endurance              | Repeated connect/disconnect, wake, reboot, scene cycles.              | 1,000-cycle lab runs; memory/handle leaks; state drift.         |
| Fault injection        | Crash/kill/hang/corrupt storage at every transaction stage.           | Recovery objective and startup bypass.                          |
| Accessibility/UX       | VoiceOver, keyboard, reduced motion, pseudo-localization.             | Complete disconnect/reconnect and recovery workflows.           |
| Security/privacy       | Threat tests, endpoint auth, secret/redaction scans.                  | Unauthorized HTTP, bundle redaction, capture session lifecycle. |

## 15.3 Critical scenarios

| **ID** | **Scenario**                         | **Fixture**                                        | **Expected result**                                                                |
|--------|--------------------------------------|----------------------------------------------------|------------------------------------------------------------------------------------|
| T-001  | First logical disconnect             | Apple Silicon laptop + one external; built-in open | Disconnect external; countdown; verify built-in remains; reconnect.                |
| T-002  | Disconnect built-in safely           | Laptop + verified external                         | Move recovery UI, disconnect built-in, reconnect on external loss.                 |
| T-003  | Block last safe display              | Single active local display                        | Attempt logical disconnect; default path is blocked.                               |
| T-004  | Disconnect current main              | Two active displays                                | Main role/recovery UI moves before target is removed.                              |
| T-005  | Multi-target scene                   | Three displays                                     | Connect destination, apply layout/modes, disconnect retiring target in safe order. |
| T-006  | Failure after checkpoint             | Injected provider error                            | Automatic rollback restores usable surface.                                        |
| T-007  | App kill at every state              | Fault injection                                    | Next launch detects unclean marker and enters recovery-first mode.                 |
| T-008  | Provider hang                        | Injected non-returning call                        | Deadline/watchdog fires; recovery command preempts queue.                          |
| T-009  | Wake reconnect storm                 | Scripted event burst                               | One stabilized reconciliation plan; no oscillation.                                |
| T-010  | OS reconnects managed-offline target | Wake/reconnect fixture                             | Cooldown prevents loop; policy conflict is logged.                                 |
| T-011  | Identical monitors swap ports        | Two same-model displays                            | No destructive action until confidence/pairing is sufficient.                      |
| T-012  | DDC direct vs hub                    | Same monitor, two routes                           | Capability changes per route; identity remains stable.                             |
| T-013  | DDC write unverified                 | Monitor without read-back                          | Result is unverified, never verified success.                                      |
| T-014  | Rapid brightness key repeat          | 100 events                                         | Writes coalesce and converge to final value within rate limit.                     |
| T-015  | Mode list changes                    | Reconnect with different available modes           | Favorite resolves by properties or returns closest alternatives.                   |
| T-016  | Sidecar reconnect                    | Sidecar endpoint                                   | Per-target unsupported/delegated result; no blanket success.                       |
| T-017  | Safe-mode startup                    | Startup modifier / rescue utility                  | No auto-rules, filters, virtual recreation, or experimental provider calls.        |
| T-018  | Persistent policy after clean reboot | Approved display policy                            | Runs only after health and stable topology; bypass key suppresses.                 |
| T-019  | Persistent policy after crash        | Unclean marker                                     | Policy does not run; recovery summary appears.                                     |
| T-020  | Normal quit                          | Managed-offline display                            | Default quit reconnects; failures are reported.                                    |
| T-021  | Filter/Black Out recovery            | Overlay active                                     | Recovery hotkey bypasses/removes overlay and remains usable.                       |
| T-022  | Capture permission denied            | PIP requested                                      | Capture fails contextually; topology/control features remain usable.               |
| T-023  | HTTP unauthorized                    | Local server enabled                               | Missing/invalid token rejected; destructive action cannot run.                     |
| T-024  | Import malformed scene               | Invalid schema/selector                            | No partial write; precise errors and diff.                                         |
| T-025  | New major macOS build                | Uncertified OS fixture                             | Experimental persistent providers default off.                                     |
| T-026  | Public-API-only build                | Experimental modules absent                        | App compiles, starts, and passes all applicable Core tests.                        |
| T-027  | VoiceOver disconnect/reconnect       | Keyboard-only + VoiceOver                          | Complete workflow and recovery without pointer or visual color cue.                |
| T-028  | Pseudo-localization                  | 40% expanded strings                               | No clipping or inaccessible controls.                                              |
| T-029  | Support bundle redaction             | Fixture with usernames/serials/tokens              | Export contains no raw sensitive fields.                                           |
| T-030  | Route disappears mid-scene           | Unplug dock during apply                           | Abort, reconcile, recover, and log degraded outcome.                               |

## 15.4 Hardware lab matrix

| **Class**                   | **Representative hardware**                              | **Coverage**                                          | **Cadence**             |
|-----------------------------|----------------------------------------------------------|-------------------------------------------------------|-------------------------|
| Apple Silicon baseline      | MacBook Air/Pro M1-M4 class                              | Built-in + direct USB-C/DP external                   | Every stable release    |
| Apple Silicon multi-display | Mac mini/Studio and Pro/Max/Ultra class                  | 2-6 displays, mixed direct/dock                       | Every stable release    |
| HDMI path                   | Mac with built-in HDMI                                   | HDMI monitor/TV; DDC where available                  | Every stable release    |
| Thunderbolt dock            | At least two mainstream dock chipsets                    | Dual external displays; route changes                 | Every stable release    |
| USB-C dock / hub            | At least two non-Thunderbolt hubs                        | DDC blocked/partial fixtures                          | Every stable release    |
| KVM                         | At least one DDC-pass and one DDC-blocking route         | Identity and capability changes                       | Beta/stable             |
| Identical monitors          | Two identical serial-capable and serial-missing fixtures | Identity confidence and pairing                       | Every stable release    |
| HDR/XDR                     | Apple XDR-capable built-in plus external HDR             | Core read; Labs writes                                | Labs-certified releases |
| TV/receiver                 | HDMI TV and optional network receiver                    | Input, range, Night Shift-like/filter tests           | Core 1.x                |
| Sidecar/AirPlay             | Supported iPad / receiver                                | Endpoint-specific lifecycle results                   | Beta/stable             |
| Headless                    | No physical display or headless adapter                  | Safe startup/recovery; Labs virtual                   | Labs                    |
| Intel regression            | One Intel laptop and one Intel desktop where available   | Core public controls; lifecycle disabled/experimental | Best-effort             |

## 15.5 OS matrix

| **OS**           | **Core public APIs**           | **Lifecycle provider**                                | **Labs**                        | **Release policy**                               |
|------------------|--------------------------------|-------------------------------------------------------|---------------------------------|--------------------------------------------------|
| macOS 13 Ventura | Full targeted Core subset.     | Certify selected Apple Silicon combinations.          | Limited; provider-specific.     | Regression on every stable release.              |
| macOS 14 Sonoma  | Full targeted Core subset.     | Certify selected Apple Silicon combinations.          | Provider-specific.              | Regression on every stable release.              |
| macOS 15 Sequoia | Full targeted Core subset.     | Primary certification.                                | Provider-specific.              | Regression on every stable release.              |
| macOS 26 Tahoe   | Current primary certification. | Enable only after explicit evidence per build family. | Off by default until certified. | Fast compatibility response.                     |
| Future major     | Public-API discovery mode.     | Persistent/experimental auto-enable off.              | Off by default.                 | Preview ring first; compatibility flag required. |

## 15.6 Release defect policy

| **Severity** | **Definition**                                                                                                           | **Release rule**                                        |
|--------------|--------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------|
| P0           | Unrecoverable/no-visible-display state, data/security compromise, startup loop on supported default.                     | Blocks every release; revoke/kill-switch if discovered. |
| P1           | Major topology corruption, repeated crash/wake loop, wrong-display destructive action, recovery failure with workaround. | Blocks stable; must have owner and verified fix.        |
| P2           | Incorrect control/mode, partial scene failure, degraded route diagnostics.                                               | May ship with documented workaround and bounded impact. |
| P3           | Cosmetic, copy, minor performance, noncritical compatibility issue.                                                      | Triaged normally.                                       |

## 15.7 Evidence required for lifecycle certification

- Mac model/chip, OS build, display model/firmware, route, adapter/dock/KVM, lid/power state, and mirror/main topology recorded.

- Successful first-use, repeat, wake, reboot, normal quit, crash, provider hang, route loss, and Reconnect All tests.

- At least one accessibility recovery run without pointer/visual dependency.

- No open P0/P1 defect and no unexplained topology drift after endurance run.

- Provider version and kill-switch entry published in compatibility data.

# 16. Success metrics and release gates

## 16.1 North-star outcome

A multi-display workspace reaches and stays in the user's intended state, and any failed high-risk transition returns to a usable state without physical intervention.

## 16.2 Product and reliability metrics

| **Metric**                      | **Definition**                                                                    | **Core 1.0 target**                                              |
|---------------------------------|-----------------------------------------------------------------------------------|------------------------------------------------------------------|
| Verified lifecycle success      | Logical disconnect/reconnect transactions committed with verified postconditions. | \>=99.5% in certified lab combinations; publish per environment. |
| Automatic recovery success      | Failed lifecycle tests restored to usable safe surface within objective.          | 100% in release-gate fault suite.                                |
| Wrong-target destructive action | Lifecycle operation applied to unintended display.                                | Zero known occurrences; P0.                                      |
| Topology convergence            | Time from last OS event to stable registry generation.                            | p95 \<=2 seconds in certified normal scenarios.                  |
| Scene idempotency               | Second apply produces no unnecessary topology writes.                             | \>=99% of stable-scene fixtures.                                 |
| DDC truthfulness                | UI/API verification label matches read-back capability/outcome.                   | 100% contract tests.                                             |
| Crash-free sessions             | Sessions without unexpected termination.                                          | \>=99.9% beta evidence or equivalent test confidence.            |
| Recovery discoverability        | Users can identify and invoke Reconnect All in study.                             | \>=95% after onboarding; \>=90% without reminder.                |
| Disabled-feature explanation    | Unavailable controls with specific reason/remediation.                            | \>=95% across hardware matrix.                                   |
| Accessibility completion        | Core workflow completion via keyboard/VoiceOver.                                  | 100% scripted/manual release checklist.                          |

## 16.3 Go/no-go gates for Core 1.0

1\. All Must / Core 1.0 requirements are implemented or explicitly removed through an approved scope change.

2\. No open P0 or P1 defect in certified configurations.

3\. Reconnect All, safe mode, rescue utility, checkpoint rollback, and unclean-startup recovery pass the full fault suite.

4\. Public-API-only build compiles and passes applicable Core tests.

5\. Signed/notarized artifacts, update path, checksums, SBOM, privacy/security documentation, and source tag are ready.

6\. Hardware/OS compatibility table identifies certified, experimental, and unsupported combinations.

7\. VoiceOver/keyboard, pseudo-localization, and support-bundle redaction release checks pass.

8\. Legal review of project name, license, dependencies, contribution terms, and experimental distribution language is complete.

## 16.4 Telemetry policy for measuring targets

Targets should be measured primarily through the hardware lab and opt-in beta diagnostics. Any telemetry must be disabled by default, documented in source, previewable, and designed without raw display serials, screen content, usernames, or network credentials. A local metrics dashboard should work even when the user never shares data.

# 17. Distribution and update strategy

## 17.1 Baseline distribution

The full build should be distributed directly as a Developer ID signed and notarized application. The website/repository should publish checksums, source tag, SBOM, release notes, compatibility changes, and recovery instructions. The Mac App Store is not the baseline because advanced lifecycle/system features may rely on behavior incompatible with store review or sandbox constraints; this must be validated rather than assumed.

## 17.2 Artifact set

| **Artifact**                 | **Purpose**                                                           | **Release requirement**                                                    |
|------------------------------|-----------------------------------------------------------------------|----------------------------------------------------------------------------|
| OpenDisplay.app              | Menu-bar and settings application.                                    | Signed, notarized, hardened/runtime reviewed.                              |
| OpenDisplay Rescue.app / CLI | Independent reconnect, safe mode, policy disable, checkpoint restore. | Minimal dependencies; signed/notarized; included and separately invocable. |
| opendisplay CLI              | Automation and diagnostics.                                           | Stable schema; codesigned; optional symlink/install helper.                |
| Public-API-only build        | Reduced-risk/community distribution flavor.                           | Same source tag; explicit capability differences.                          |
| Source archive/tag           | Reproducible source for release.                                      | Signed tag, dependency locks, license notices.                             |
| SBOM/provenance/checksums    | Supply-chain verification.                                            | Published with every stable release.                                       |

## 17.3 Update behavior

- Verify signature and update manifest; never replace the rescue path without a successful staged health check.

- Before migration, write backup and checkpoint; after update, first launch suppresses persistent experimental policy until compatibility and health pass.

- On a newly detected major macOS build, experimental persistent providers default off unless explicitly certified.

- Support rollback to the prior application version and configuration schema where practical.

- Release notes call out display-lifecycle provider changes prominently and include recovery instructions.

## 17.4 Compatibility kill switches

The app should ship a signed compatibility dataset keyed by OS build family, architecture, provider version, and known route/display constraints. A remote update may disable a dangerous provider only if the user opted into compatibility updates; the payload must be transparent, signed, cached, and auditable. Core offline operation remains available. A kill switch may disable auto-apply but should preserve manual Reconnect All/recovery where safe.

# 18. Open-source governance and licensing

## 18.1 License recommendation

The user's stated goal is to keep the product open source. The working recommendation is GPL-3.0-or-later for the application, lifecycle coordinator, and recovery stack so distributed derivatives of those components remain open. A separately packaged provider/automation SDK may use Apache-2.0 or MIT to encourage integrations, provided the boundary does not undermine the project's goals. This is a product recommendation, not legal advice; dependency compatibility, contributor expectations, app distribution, and any use of private APIs require counsel and community review.

## 18.2 Governance baseline

| **Mechanism**         | **Baseline**                                                                                                                    |
|-----------------------|---------------------------------------------------------------------------------------------------------------------------------|
| Maintainer council    | At least two maintainers for release/security decisions; documented succession and inactive-maintainer policy.                  |
| RFC process           | Required for provider interfaces, lifecycle invariants, schema/API breaking changes, telemetry, licensing, and Labs graduation. |
| DCO or CLA            | Choose before external contributions; document rationale and contribution provenance expectations.                              |
| Code of conduct       | Adopt and enforce with named response team.                                                                                     |
| Security policy       | Private reporting channel, supported versions, severity policy, coordinated disclosure.                                         |
| Release policy        | Protected tags/branches, two-person review for recovery-critical code, signed artifacts and provenance.                         |
| Compatibility reports | Template captures Mac/OS/display/route and redacts identifying data.                                                            |
| Decision log          | Public ADRs/RFC outcomes; link code changes to requirements and tests.                                                          |

## 18.3 Repository structure

/  
Apps/OpenDisplay  
Apps/OpenDisplayRescue  
Tools/opendisplay  
Packages/DisplayDomain  
Packages/DisplayRegistry  
Packages/TopologyCoordinator  
Packages/SceneEngine  
Packages/AutomationSchema  
Providers/CoreGraphicsProvider  
Providers/DDCProvider  
Providers/NativeControlProvider  
Providers/CaptureProvider  
Providers/ExperimentalLifecycleProvider \# optional target  
Providers/VirtualDisplayProvider \# Labs target  
Docs/Architecture  
Docs/Recovery  
Docs/Compatibility  
Docs/RFCs  
Tests/Fixtures  
Tests/HardwareLab

## 18.4 Contribution gates

- Original-work/provenance attestation and license scan.

- No proprietary assets, copied interface text, or reverse-engineered code of unclear legality.

- Unit/state-machine tests for logic; hardware evidence for provider changes.

- Threat/recovery review for any lifecycle, startup, IPC, capture, update, or network change.

- Public-API-only build remains green unless an RFC intentionally changes scope.

- Documentation and compatibility data updated with behavior changes.

# 19. Delivery roadmap

## 19.1 Milestones

| **Milestone**         | **Indicative duration** | **Exit outcome**                                                                                                                                    |
|-----------------------|-------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------|
| M0: Technical spike   | 4-6 weeks               | Enumerate topology; prove safe logical connect/disconnect on supported Apple Silicon; DDC probe; recovery hotkey; public/private API boundary memo. |
| M1: Developer preview | 8-10 weeks              | Registry, identities, basic menu-bar UI, connect/disconnect transaction, layout/mode controls, CLI, diagnostics.                                    |
| M2: Alpha             | 8 weeks                 | Scenes, groups, DDC/software controls, wake reconciliation, rescue utility, signed/notarized builds, migration tests.                               |
| M3: Beta / Core 1.0   | 8-12 weeks              | App Intents, stable APIs, accessibility pass, hardware lab matrix, localization foundation, contributor docs.                                       |
| M4: Core 1.x          | Ongoing                 | Color/profile automation, sync, ScreenCaptureKit zoom/PIP, richer network controls.                                                                 |
| Labs                  | Parallel, gated         | HiDPI overrides, EDID/system overrides, HDR/XDR upscaling, virtual displays, streaming. Never block Core stability.                                 |

## 19.2 Technical spike deliverables

1\. Public/private API boundary memo with prototypes for enumeration, modes/layout, logical connect/disconnect, and virtual endpoints.

2\. Lifecycle provider protocol plus a simulator provider that exercises every result and fault state.

3\. Recovery proof: independent Reconnect All, startup bypass, checkpoint format, and kill-at-every-stage tests.

4\. Identity proof for identical monitors, port changes, and transient display IDs.

5\. DDC route probe on direct, dock, and KVM fixtures with verified/unverified semantics.

6\. Signed/notarized prototype and entitlement/distribution assessment.

7\. Initial hardware/OS certification table and explicit unsupported cases.

## 19.3 Suggested workstreams

| **Workstream**     | **First deliverables**                                                           | **Dependencies**          |
|--------------------|----------------------------------------------------------------------------------|---------------------------|
| Domain/state       | Display models, identity, capability, transaction state machine, scene schema.   | None; starts first.       |
| Public platform    | Core Graphics provider, event normalization, mode/layout operations.             | Domain/state.             |
| Lifecycle/recovery | Experimental provider spike, safety engine, checkpoints, rescue utility.         | Domain + public platform. |
| Controls           | Native/DDC/software providers, rate limiting, keyboard/OSD.                      | Registry/capability.      |
| Product/design     | Menu-bar, topology workspace, onboarding, risk language, accessibility.          | Domain snapshots.         |
| Automation         | CLI schema, App Intents, dry run, typed results.                                 | Coordinator/planner.      |
| Quality/lab        | Simulator, event replay, hardware fixtures, fault injection, compatibility data. | Begins with domain.       |
| Security/release   | Threat model, signing/notarization, SBOM, update and governance.                 | Cross-cutting.            |

## 19.4 Staffing assumption

A credible Core 1.0 requires at least one senior macOS/platform engineer, one additional Swift engineer, product/design capacity with accessibility expertise, and dedicated QA/hardware-lab ownership. Security/release/legal support can be fractional but must be scheduled before architecture lock and public beta. A smaller volunteer team should reduce scope rather than compress recovery and test work.

# 20. Risk register

| **ID** | **Severity** | **Risk**                                                                  | **Mitigation**                                                                                                                  |
|--------|--------------|---------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------|
| R-01   | Critical     | Logical disconnect leaves the user with no visible display.               | Preflight safe-surface rule, countdown confirmation, atomic checkpoint, auto rollback, Reconnect All hotkey and rescue utility. |
| R-02   | Critical     | Private or undocumented macOS behavior breaks after an OS update.         | Provider abstraction, runtime probing, feature flags, staged releases, public-API-only fallback.                                |
| R-03   | High         | Display identity mismatch applies a scene to the wrong identical monitor. | Confidence score, topology context, user-confirmed aliases, destructive-action threshold, visible dry run.                      |
| R-04   | High         | Wake/reconnect loops cause flicker or WindowServer instability.           | Debounced topology stabilizer, single-owner transaction queue, bounded retries, circuit breaker.                                |
| R-05   | High         | DDC commands fail through a hub or KVM and appear to succeed.             | Read-back verification where available, route-specific capability cache, explicit unverified status.                            |
| R-06   | High         | Rapid HDR/XDR or brightness writes produce washed-out or unsafe output.   | Rate limiting, coalescing, safe ranges, profile rollback, confirmation for high-risk modes.                                     |
| R-07   | High         | App crash while displays are managed offline prevents recovery.           | Independent launch agent/rescue binary, startup health marker, restore-on-unclean-exit policy.                                  |
| R-08   | Medium       | Scene application moves windows unexpectedly or disrupts presentations.   | Preview diff, window-move opt-in, per-app exclusions, transactional ordering.                                                   |
| R-09   | Medium       | Open-source contributors accidentally introduce copied assets or code.    | DCO/CLA policy, clean-room contribution guide, provenance review, trademark and license checks.                                 |
| R-10   | Medium       | Automation endpoint is abused by another local process.                   | Loopback only by default, random bearer token, opt-in server, origin restrictions, audit log.                                   |
| R-11   | Medium       | Configuration migration corrupts settings.                                | Versioned schema, atomic writes, backups, import validation, downgrade-safe export.                                             |
| R-12   | Medium       | Capability labels promise physical unplug or additional GPU pipelines.    | Precise UX wording; never claim hardware link removal or increased display-count limits.                                        |

## 20.1 Risk review cadence

- Review P0/P1 risks at every lifecycle/provider change and before each release ring promotion.

- Link each mitigation to an owner, test, compatibility flag, and recovery action.

- Treat new macOS major versions, new experimental provider mechanisms, and update-system changes as automatic risk reviews.

- Public issue reports should be triaged into reproducible environments rather than counted as prevalence.

# 21. Decision log and open questions

## 21.1 Decision log

| **ID** | **Decision**                                                | **Status** | **Rationale**                                                                                  |
|--------|-------------------------------------------------------------|------------|------------------------------------------------------------------------------------------------|
| D-001  | Use a Core/Labs product split.                              | Accepted   | Prevents experimental system mechanisms from becoming a dependency of normal startup/recovery. |
| D-002  | Apple Silicon is the certified lifecycle baseline.          | Accepted   | Public evidence and failure reports indicate materially different Intel behavior.              |
| D-003  | Logical disconnect is a transaction, not a direct command.  | Accepted   | Required for preflight, checkpoint, verification, rollback, and audit.                         |
| D-004  | Ship a standalone rescue utility.                           | Accepted   | The main app/UI may be unavailable or displayed on the target being removed.                   |
| D-005  | Normal quit reconnects managed-offline displays by default. | Accepted   | Conservative recovery expectation; persistence remains explicit.                               |
| D-006  | No analytics by default.                                    | Accepted   | Consistent with open-source trust and display/capture sensitivity.                             |
| D-007  | Direct signed/notarized distribution is the baseline.       | Accepted   | Advanced lifecycle capabilities may not be compatible with App Store constraints.              |
| D-008  | Maintain a public-API-only build path.                      | Accepted   | Reduces platform/legal risk and preserves a stable subset.                                     |
| D-009  | Use stable internal IDs and scored fingerprint evidence.    | Accepted   | Transient display IDs and identical hardware make single-key identity unsafe.                  |
| D-010  | Provider call success is not product success.               | Accepted   | All applicable operations require observation/read-back or explicit unverified status.         |
| D-011  | Working license direction is GPL-3.0-or-later for the app.  | Proposed   | Strong copyleft supports the user's open-source goal; counsel/community approval required.     |
| D-012  | Working project name is OpenDisplay.                        | Proposed   | Useful internal label only; trademark/package clearance required.                              |

## 21.2 Open questions

| **ID** | **Question**                                                                                                        | **Resolution method**                   | **Owner**               |
|--------|---------------------------------------------------------------------------------------------------------------------|-----------------------------------------|-------------------------|
| Q-001  | Which exact macOS versions and Mac models can be certified for logical disconnect in Core 1.0?                      | Technical spike + hardware lab evidence | Architecture lead       |
| Q-002  | What undocumented interfaces, entitlements, or signing constraints are required by each lifecycle/virtual provider? | Legal/technical boundary memo           | Platform lead + counsel |
| Q-003  | Should the rescue component be a separate app, launch agent, login item, privileged helper, or combination?         | Threat model and failure injection      | Security + platform     |
| Q-004  | What is the safest default recovery shortcut with minimal conflict across layouts/accessibility tools?              | User study and system conflict scan     | Design/accessibility    |
| Q-005  | Should strong copyleft apply to all modules, or should providers/SDK have separate licenses?                        | Community and legal review              | Maintainer council      |
| Q-006  | What compatibility data, if any, may be collected opt-in without exposing display serials or personal topology?     | Privacy design                          | Security/privacy        |
| Q-007  | Can a public-API-only flavor share one bundle or must it be a separate distribution/package ID?                     | Build and signing spike                 | Release engineering     |
| Q-008  | What is the minimum supported Intel scope, and how prominently should unavailable lifecycle behavior be shown?      | Regression evidence                     | Product + QA            |
| Q-009  | Which scene fields are atomic requirements versus best-effort controls?                                             | Planner RFC                             | Product + architecture  |
| Q-010  | How should window placement integrate without requiring Accessibility permission for users who do not need it?      | UX/API spike                            | Design + platform       |
| Q-011  | Which network display vendors are maintainable as first-party providers versus community plugins?                   | Provider SDK RFC                        | Maintainers             |
| Q-012  | What criteria graduate a Labs feature to Core?                                                                      | Governance RFC                          | Maintainer council      |

## 21.3 Decisions required before architecture lock

- Certifiable lifecycle provider scope by OS/architecture and whether it can ship in the main process.

- Rescue process topology, IPC authentication, startup order, and login-item behavior.

- Final license, contributor agreement/DCO, project name, bundle identifiers, and trademark position.

- Scene atomicity policy and which control failures are warnings versus rollback triggers.

- Public-API-only build packaging and shared source boundaries.

## 21.4 Decisions required before public beta

- Default recovery hotkey, onboarding test, and accessibility evidence.

- Compatibility dataset publication format and emergency kill-switch policy.

- Opt-in diagnostics data model and support upload mechanism, if any.

- Supported Intel scope and Labs graduation criteria.

- Update framework, rollback behavior, and minimum supported-version policy.

# 22. Sources and research notes

Sources were accessed on 21 June 2026. Product and issue sources are used to identify publicly described outcomes and representative failure modes. They do not authorize copying proprietary implementation or establish defect prevalence. Apple sources define public platform and distribution guidance. Adjacent open-source projects are references only; code reuse requires a separate license and provenance review.

| **ID** | **Source**                                                 | **Research use**                                                                                                             | **Link**                                                                                                           |
|--------|------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------|
| S01    | BetterDisplay product website                              | Official feature overview and positioning                                                                                    | [<u>Open</u>](https://betterdisplay.pro/)                                                                          |
| S02    | BetterDisplay GitHub repository                            | Compatibility notes, release history, feature documentation index                                                            | [<u>Open</u>](https://github.com/waydabber/BetterDisplay)                                                          |
| S03    | BetterDisplay free and Pro feature matrix                  | Detailed public feature inventory                                                                                            | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/wiki/List-of-free-and-Pro-features)                       |
| S04    | BetterDisplay integration features and CLI                 | CLI, URL, HTTP, notifications, selectors, actions, and display addressing                                                    | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/wiki/Integration-features%2C-CLI)                         |
| S05    | Fully scalable HiDPI desktop                               | Flexible scaling behavior and compatibility                                                                                  | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/wiki/Fully-scalable-HiDPI-desktop)                        |
| S06    | XDR and HDR brightness upscaling                           | HDR/XDR brightness behavior and presets                                                                                      | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/wiki/XDR-and-HDR-brightness-upscaling)                    |
| S07    | Safe mode, app reset, and removal                          | Recovery paths and emergency startup                                                                                         | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/wiki/Safe-mode%2C-app-reset%2C-app-removal)               |
| S08    | Export and import app settings                             | Configuration portability                                                                                                    | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/wiki/Export-and-import-app-settings)                      |
| S09    | Eye care: prevent PWM and/or temporal dithering            | Accessibility and eye-care controls                                                                                          | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/wiki/Eye-care%3A-prevent-PWM-and-or-temporal-dithering)   |
| S10    | MonitorControl                                             | Open-source DDC, software control, keyboard, OSD, and sync reference                                                         | [<u>Open</u>](https://github.com/MonitorControl/MonitorControl)                                                    |
| S11    | m1ddc                                                      | Open-source Apple Silicon DDC control reference                                                                              | [<u>Open</u>](https://github.com/waydabber/m1ddc)                                                                  |
| S12    | displayplacer                                              | Open-source display layout and mode automation reference                                                                     | [<u>Open</u>](https://github.com/jakehilborn/displayplacer)                                                        |
| S13    | InternalDisplayOff                                         | Public implementation report for logical display enable/disable and recovery concepts; license must be verified before reuse | [<u>Open</u>](https://github.com/RonaldPark89/InternalDisplayOff)                                                  |
| S14    | Apple Quartz Display Services                              | Public Core Graphics APIs for display enumeration and configuration                                                          | [<u>Open</u>](https://developer.apple.com/documentation/coregraphics/quartz-display-services)                      |
| S15    | Apple ScreenCaptureKit                                     | Public capture framework for screen preview, zoom, and picture-in-picture features                                           | [<u>Open</u>](https://developer.apple.com/documentation/screencapturekit)                                          |
| S16    | Apple App Review Guidelines                                | Public API and copycat restrictions; distribution implications                                                               | [<u>Open</u>](https://developer.apple.com/app-store/review/guidelines/)                                            |
| S17    | Apple: Notarizing macOS software before distribution       | Notarization requirements for direct distribution                                                                            | [<u>Open</u>](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)    |
| S18    | Apple: Distributing your app for beta testing and releases | Distribution, signing, and release guidance                                                                                  | [<u>Open</u>](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases) |
| S19    | BetterDisplay issue \#1396                                 | User report: logical disconnect safety and last-display concerns                                                             | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/issues/1396)                                              |
| S20    | BetterDisplay issue \#1413                                 | User report: macOS reconnecting displays after sleep and main-display protection                                             | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/issues/1413)                                              |
| S21    | BetterDisplay issue \#1809                                 | User report: Intel blank screens after disconnect and wake recovery                                                          | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/issues/1809)                                              |
| S22    | BetterDisplay issue \#5227                                 | User report: persistent/aggressive disconnect behavior across reboot                                                         | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/issues/5227)                                              |
| S23    | BetterDisplay issue \#4909                                 | User report: DDC succeeds directly but fails through a hub                                                                   | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/issues/4909)                                              |
| S24    | BetterDisplay issue \#2046                                 | User report: mode availability changes after reconnect                                                                       | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/issues/2046)                                              |
| S25    | BetterDisplay issue \#2362                                 | User report: crash or instability after wake                                                                                 | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/issues/2362)                                              |
| S26    | BetterDisplay issue \#4737                                 | User report: reconnect-all semantics do not necessarily wake Sidecar                                                         | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/issues/4737)                                              |
| S27    | BetterDisplay issue \#1372                                 | User report: need faster access to DDC power control                                                                         | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/issues/1372)                                              |
| S28    | BetterDisplay issue \#5234                                 | User report: rapid XDR/brightness changes can produce visual corruption                                                      | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/issues/5234)                                              |
| S29    | BetterDisplay issue \#76                                   | User report: virtual display sleep and window movement behavior                                                              | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/issues/76)                                                |
| S30    | BetterDisplay issue \#13                                   | User report: reconnecting virtual displays after sleep                                                                       | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/issues/13)                                                |
| S31    | BetterDisplay issue \#2627                                 | User report: severe startup/WindowServer recovery scenario                                                                   | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/issues/2627)                                              |
| S32    | BetterDisplay releases                                     | Current release cadence and compatibility evidence                                                                           | [<u>Open</u>](https://github.com/waydabber/BetterDisplay/releases)                                                 |

## 22.1 Source interpretation rules

- Reference product sources support the feature inventory and compatibility hypotheses, not implementation claims.

- Issue reports are cited as examples that a failure can occur; engineering must reproduce and characterize behavior independently.

- Apple documentation is authoritative for documented APIs and distribution guidance, but actual OS behavior still requires testing.

- Open-source repositories may be studied and, where licenses permit, reused with attribution and compliance; unknown-license code is not reused.

- All source-dependent statements should be refreshed before implementation planning if material time has passed or macOS has changed.

# 23. Glossary

| **Term**                  | **Definition**                                                                                                                  |
|---------------------------|---------------------------------------------------------------------------------------------------------------------------------|
| Active display            | An endpoint currently participating in the macOS display topology.                                                              |
| Black Out                 | A reversible presentation state that displays black while the endpoint normally remains active.                                 |
| Capability decision       | A contextual supported/unsupported/degraded result with provider, reasons, risk, and verification metadata.                     |
| Checkpoint                | An atomic last-known-safe record used to restore topology and lifecycle state.                                                  |
| Clean-room implementation | Independent design based on lawful public observations without copying proprietary implementation or assets.                    |
| Core                      | Stable product scope whose startup and recovery do not depend on Labs modules.                                                  |
| DDC/CI                    | Display Data Channel Command Interface, commonly used to control monitor brightness, input, contrast, and audio.                |
| Desired state             | The topology, controls, modes, or policies the user or scene intends.                                                           |
| Display fingerprint       | A scored set of identity signals used to associate observations with a persistent display record.                               |
| Display pipeline          | Hardware/OS capacity used to drive displays; logical disconnect does not necessarily free it.                                   |
| EDID                      | Extended Display Identification Data provided by many displays or adapters.                                                     |
| Experimental provider     | An isolated implementation that uses unstable or undocumented behavior and is feature-flagged.                                  |
| HiDPI                     | A scaled mode where multiple physical pixels represent a logical UI pixel for sharper rendering.                                |
| Identity confidence       | The score/evidence indicating how reliably an observed endpoint maps to a persistent display.                                   |
| Labs                      | Opt-in modules for unstable, system-sensitive, or evidence-limited features.                                                    |
| Logical disconnect        | Removing a supported display from active macOS topology without physically unplugging it.                                       |
| Managed offline           | A remembered display that OpenDisplay intentionally placed offline and can attempt to reconnect.                                |
| Mirror set                | A source and one or more displays presenting equivalent desktop content.                                                        |
| Monitor Sleep/Power       | A hardware/network request to sleep or power a monitor; topology may remain active.                                             |
| Observed state            | What macOS and providers currently report, independent of the user's desired state.                                             |
| Provider                  | A module that implements a capability through public APIs, native controls, DDC, network protocols, or experimental mechanisms. |
| Public-API-only build     | A product flavor compiled without undocumented/private system providers.                                                        |
| Reconnect All             | Emergency action that attempts every app-managed offline display and reports per-target results.                                |
| Recovery surface          | A verified endpoint or control channel from which the user can see feedback and invoke recovery.                                |
| Route                     | The physical/logical path from Mac to display, including port, adapter, dock, KVM, and protocol.                                |
| Scene                     | A named partial desired state for displays, topology, modes, controls, profiles, and lifecycle.                                 |
| Selector                  | A stable expression used by automation to resolve one or more display records.                                                  |
| System absent             | A display not currently observed by macOS and not necessarily disconnected by OpenDisplay.                                      |
| Topology generation       | A stable version number for the normalized set and relationships of observed displays.                                          |
| Transaction coordinator   | The single serialized owner of display mutations, verification, rollback, and audit.                                            |
| Unverified result         | A provider request was sent but the resulting hardware/system state could not be read back conclusively.                        |
| Virtual display           | A software-created display endpoint used for headless, capture, streaming, or workspace workflows.                              |
| VRR                       | Variable refresh rate.                                                                                                          |
| XDR/HDR                   | Extended/high dynamic range display modes that can expose higher luminance and wider range.                                     |

## PRD completion checklist

| **Area**       | **Baseline in this document**                                                                             |
|----------------|-----------------------------------------------------------------------------------------------------------|
| Product intent | Problem, personas, jobs, principles, goals, non-goals, and success definition.                            |
| Scope          | Core 1.0, Core 1.x, Labs, compatibility, and release rings.                                               |
| Feature map    | 108 public/reference-derived capability items with disposition.                                           |
| Requirements   | 124 normative functional and non-functional requirements with acceptance criteria.                        |
| Safety         | Disconnect semantics, invariants, transaction, recovery hierarchy, edge cases, and provider contract.     |
| Architecture   | Components, state ownership, identity, capabilities, planning, storage, and isolation.                    |
| Quality        | 30 critical scenarios, hardware/OS matrix, fault testing, accessibility, security, and release gates.     |
| Delivery       | Distribution, updates, governance, licensing direction, milestones, risks, decisions, and open questions. |
| Research       | 32 public sources with interpretation limits and traceability markers.                                    |

|     | **Next governance action** Convert accepted Core 1.0 requirements into tracked epics and test cases, then run the M0 technical spike before committing to a public release date. The spike must prove recovery and provider isolation before broad feature work. |
|-----|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
