#!/usr/bin/env bash
# Deterministic fake-transport checks. Does not access displays or I2C services.
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/opendisplay-ddc.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  Providers/ExperimentalLifecycleProvider/Sources/DDCTransactionGate.swift \
  Tests/macOS/DDCCancellationChecks.swift -o "$CHECK_DIR/ddc-cancellation"
"$CHECK_DIR/ddc-cancellation"
