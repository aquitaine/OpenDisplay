#!/usr/bin/env bash
# Generate OpenDisplay.xcodeproj from project.yml using XcodeGen (macOS).
# The generated project is not committed — run this whenever project.yml or the target
# source layout changes.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$(uname -s)" != "Darwin" ]; then
  echo "The Xcode project is macOS-only. On Linux, use 'make test' for the cross-platform core."
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing XcodeGen via Homebrew…"
    brew install xcodegen
  else
    echo "XcodeGen not found and Homebrew is unavailable."
    echo "Install it from https://github.com/yonaskolb/XcodeGen and re-run."
    exit 1
  fi
fi

xcodegen generate
echo
echo "✓ Generated OpenDisplay.xcodeproj"
echo "  open OpenDisplay.xcodeproj         # build & run the menu-bar app"
echo "  xcodebuild -scheme OpenDisplay build"
echo "  xcodebuild -scheme OpenDisplay-PublicAPIOnly build"
