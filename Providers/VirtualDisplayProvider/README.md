# VirtualDisplayProvider

**macOS target — Labs only.** Software-created display endpoints (headless, capture, Sidecar
targets) with configurable size/density and an explicit sleep/window policy (PRD VIR-001..003/
007). Disabled by default, absent from the Core dependency graph, bypassable by safe mode; a
corrupt virtual definition must never create a startup loop.

Implements: a `VirtualDisplayProvider` protocol. Milestone: **Labs (parallel, gated)**.

> Stub — concrete implementation added on macOS in Xcode.
