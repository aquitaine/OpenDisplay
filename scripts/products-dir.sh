#!/usr/bin/env bash
# Prints the Build/Products/<CONFIG> directory Xcode uses for THIS checkout's OpenDisplay project.
# Usage: scripts/products-dir.sh [Debug|Release]
set -euo pipefail
CONFIG="${1:-Debug}"
cd "$(dirname "$0")/.."
xcodebuild -project OpenDisplay.xcodeproj -scheme OpenDisplay -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '$1 ~ /^ *BUILT_PRODUCTS_DIR$/ { print $2; exit }'
