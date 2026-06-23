# Hardware lab

Evidence and fixtures from real-hardware testing (PRD §15.4). Display management can't be
validated by unit tests alone; this is where the certification runs live.

- **Fixtures** (`../Fixtures`) — recorded Core Graphics / IORegistry event sequences (wake
  storms, reorder, route loss, mode invalidation, identical-monitor swaps) replayed against
  the coordinator and providers in integration-simulation tests.
- **Hardware matrix runs** — per-release evidence across the Mac/dock/KVM/display classes in
  PRD §15.4, including the 1,000-cycle endurance and fault-injection suites.
- **Certification records** feed `Docs/Compatibility/`.

The 30 critical scenarios (T-001…T-030, PRD §15.3) are tracked here and in the test suites;
the fault-injection + recovery subset is a release gate and must be 100% green.
