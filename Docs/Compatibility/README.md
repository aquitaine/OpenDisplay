# Compatibility

This directory will hold the **certified compatibility matrix**: which Mac/OS/display/route
combinations are certified, experimental, or unsupported for each capability — especially the
logical-disconnect lifecycle (PRD §15.4–15.5, §17.4).

Compatibility is established by our own instrumented hardware testing, not assumed from public
reports. Each lifecycle certification entry records: Mac model/chip, OS build, display model/
firmware, route (direct/dock/KVM/adapter), lid/power state, and the results of first-use,
repeat, wake, reboot, normal-quit, crash, provider-hang, route-loss, and Reconnect All tests,
plus at least one accessibility (keyboard/VoiceOver) recovery run.

Community results come in through the **Compatibility report** issue form; please redact
serials and other identifying data.

> Baseline: macOS 13 Ventura → macOS 26 Tahoe; Apple Silicon first; Intel best-effort and
> capability-gated. The signed compatibility/kill-switch dataset ships with each stable release.
