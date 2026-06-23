#!/usr/bin/env bash
# Build and test the platform-independent OpenDisplay packages.
# Works anywhere a Swift 6 toolchain is installed (macOS or Linux).
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v swift >/dev/null 2>&1; then
  echo "error: no Swift toolchain found."
  echo "  - macOS: install Xcode 16+ (Swift 6)."
  echo "  - Linux: install from https://www.swift.org/install/ or use the swift:6.0 container."
  exit 127
fi

swift --version
swift build
swift test --parallel
