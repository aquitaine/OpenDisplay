# DDCProvider

**macOS target.** DDC/CI control over external monitors: per-route VCP probing, brightness/
contrast/volume/input commands, timing, and read-back verification (PRD CTL-001..006/012/013).
Capability is **per route** — a monitor may support DDC directly but not through a dock/KVM —
so transport failure is reported separately from display support, and unverifiable writes are
reported `unverified` (never success).

Implements: `ControlProvider`. Milestone: **M1/M2**.

> Stub — concrete implementation added on macOS in Xcode.
