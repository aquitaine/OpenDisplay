#!/usr/bin/env bash
# Bundles the `opendisplay` CLI into OpenDisplay.app/Contents/Helpers so the experimental rotation
# backend can run it as an isolated helper process. The CLI is a Swift `tool` target that cannot be
# built inside the app's own Xcode build (its module outputs conflict with the app's), so we build it
# as a separate invocation and copy the product into the bundle.
#
# Usage: scripts/bundle-helper.sh [Debug|Release]
set -euo pipefail
CONFIG="${1:-Debug}"
cd "$(dirname "$0")/.."

[ -d OpenDisplay.xcodeproj ] || make xcode

echo "Building OpenDisplay.app ($CONFIG)…"
xcodebuild -project OpenDisplay.xcodeproj -scheme OpenDisplay -configuration "$CONFIG" -destination 'platform=macOS' build >/dev/null
echo "Building opendisplay CLI ($CONFIG)…"
xcodebuild -project OpenDisplay.xcodeproj -scheme opendisplay -configuration "$CONFIG" -destination 'platform=macOS' build >/dev/null

DD=$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/OpenDisplay-* | head -1)
PRODUCTS="$DD/Build/Products/$CONFIG"
APP="$PRODUCTS/OpenDisplay.app"
CLI="$PRODUCTS/opendisplay"

[ -d "$APP" ] || { echo "error: $APP not found" >&2; exit 1; }
[ -x "$CLI" ] || { echo "error: opendisplay CLI not found at $CLI" >&2; exit 1; }

mkdir -p "$APP/Contents/Helpers"
cp -f "$CLI" "$APP/Contents/Helpers/opendisplay"
echo "Bundled: $APP/Contents/Helpers/opendisplay"
