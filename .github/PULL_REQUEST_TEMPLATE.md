<!-- Thanks for contributing to OpenDisplay! Please complete this checklist. -->

## Summary

<!-- What does this change and why? Link the issue it closes. -->

Closes #

## Type of change

- [ ] Bug fix
- [ ] Feature
- [ ] Refactor / internal
- [ ] Docs
- [ ] Lifecycle / recovery / safety (requires threat & recovery review)

## Checklist

- [ ] **Clean-room:** this contribution is my original work, or its source and license are
      identified. No proprietary code, copied UI, copy, or assets.
- [ ] Tests added/updated (unit/state-machine for logic; hardware evidence for provider changes).
- [ ] `make test` passes locally (`swift test` green) and SwiftLint is clean. (No remote CI — local verification is the gate.)
- [ ] The **public-API-only** build still compiles with experimental providers absent (NFR-010).
- [ ] Docs updated where behavior changed.
- [ ] Commits are signed off (`git commit -s`, DCO).

## Safety & recovery

- [ ] This PR does **not** touch lifecycle, the transaction coordinator, checkpoints, the
      rescue path, startup, IPC, capture, update, or network.
- [ ] If it does: I have described new failure modes and how recovery stays guaranteed, and
      requested a threat & recovery review (RFC linked if applicable).
