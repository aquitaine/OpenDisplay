# Contributing to OpenDisplay

Thanks for your interest. OpenDisplay is a **clean-room**, safety-first, open-source macOS
project. Please read this before opening a PR.

## Clean-room rule (important)

OpenDisplay is functionally inspired by publicly documented display-management workflows but
is **not** affiliated with BetterDisplay. Do **not** contribute:

- decompiled or reverse-engineered proprietary code,
- copied UI layouts, marketing copy, icons, screenshots, or trade dress,
- code with unknown or incompatible license/provenance.

Every nontrivial contribution must be **your original work**, or it must identify the
upstream source and its license. Maintainers may ask for provenance notes.

## Developer Certificate of Origin (DCO)

Sign off every commit (`git commit -s`) to certify the DCO. Your `Signed-off-by:` line
asserts you have the right to submit the work under the project license.

## Getting started

```sh
make bootstrap   # ensure a Swift 6 toolchain (installs on Ubuntu; checks Xcode on macOS)
make test        # builds & runs the cross-platform test suite (Swift 6, macOS or Linux)
```

The macOS app, providers, rescue utility, CLI, and SwiftUI design system require **Xcode
16+** (generate the project with `make xcode`). New safety/state logic should land in the
cross-platform packages with unit tests so it can be verified locally with `make test`,
no hardware needed.

## What every PR needs

- A linked issue and a clear summary.
- **Tests:** unit/state-machine tests for logic; for provider changes, hardware evidence
  (Mac model/chip, OS build, route, display) per the compatibility report form.
- **Verify locally before pushing:** `make test` green; SwiftLint clean; the
  **public-API-only** build still compiles (no experimental-provider deps). There is no
  remote CI — local verification is the gate.
- Docs updated when behavior changes.
- The PR checklist completed (see the pull request template).

## Changes that need extra review

Any change to **lifecycle, the transaction coordinator, checkpoints, the rescue path,
startup, IPC, capture, update, or network** requires a **threat & recovery review**, and
typically an [RFC](Docs/RFCs/0000-template.md). The same applies to provider interfaces,
schema/API breaking changes, telemetry, licensing, and Labs → Core graduation.

## Safety expectations

- Never weaken a §9.2 invariant without an accepted RFC.
- A provider call is not success — verify postconditions or report `unverified`.
- No feature may obscure or intercept the emergency recovery command.

## Code style

Swift 6, 4-space indentation, `swift-format`/SwiftLint configs in the repo root. Prefer
value types and dependency injection so logic stays testable against `SimulatorProvider`.

By contributing, you agree your contributions are licensed under the project license
(GPL-3.0-or-later) and you abide by the [Code of Conduct](CODE_OF_CONDUCT.md).
