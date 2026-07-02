#!/usr/bin/env bash
# PreToolUse(Bash) guard for unattended OpenDisplay runs.
# Blocks shell commands that would mutate REAL display state on this host
# (the same Mac the agent is running on). Logic must be verified via `make test`
# against the SimulatorProvider, never by yanking a live display.
#
# Hook contract: receives the tool-call JSON on stdin. Exit 2 = block the call
# (the stderr message is shown to Claude). Exit 0 = allow.
# NOTE: exit-code-2-blocks is the current Claude Code convention — confirm it
# against your installed version if you customize this.

payload="$(cat)"

if printf '%s' "$payload" | grep -Eiq \
  'opendisplay[^"]*(disconnect|reconnect|recover|scene[[:space:]]+apply|black[-_]?out)|displayplacer|cscreen|CGConfigureDisplay|SLSConfigureDisplay'; then
  echo "BLOCKED: refusing a real display-mutating command during an unattended run. \
Verify this behavior via 'make test' (SimulatorProvider) and non-destructive --json reads instead. (SAFETY rule.)" >&2
  exit 2
fi

exit 0
