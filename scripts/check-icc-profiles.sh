#!/usr/bin/env bash
# Read-only macOS integration check. Does not assign or reset any colour profile.
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/opendisplay-icc.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -parse-as-library Apps/OpenDisplay/Sources/ColorProfileService.swift \
  Tests/macOS/ColorProfileChecks.swift -o "$CHECK_DIR/icc-profiles"
"$CHECK_DIR/icc-profiles"
