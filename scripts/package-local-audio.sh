#!/bin/bash
# Package an already-built app without signing identities or upstream auto-updates.
set -euo pipefail
products="${1:?Pass Xcode Build/Products/Debug or Release}"
destination="${2:?Pass an output directory outside the source tree}"
app="$destination/OpenDisplay.app"
if [[ -e "$app" ]]; then
    echo "Destination already exists: $app" >&2
    exit 1
fi
mkdir -p "$destination"
ditto "$products/OpenDisplay.app" "$app"
python3 - "$app/Contents/Info.plist" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as source:
    info = plistlib.load(source)
info.update(CFBundleIdentifier='dev.opendisplay.app', CFBundleVersion='33',
            CFBundleDisplayName='OpenDisplay', OpenDisplayAudioRevision='9-physical-audio-return',
            OpenDisplayDisableUpdates=True)
with open(path, 'wb') as target:
    plistlib.dump(info, target)
PY
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$destination/OpenDisplay-Audio-Fix-9.zip"
