#!/usr/bin/env bash
# Builds a Developer-ID-signed, notarized, stapled OpenDisplay.app and packages it as a zip that
# opens with no Gatekeeper warning (no `xattr` dance for users). Distribution channel is Developer ID
# + hardened runtime — NOT the App Store (the full app uses private frameworks; see D-007). Signs the
# bundle inside-out (frameworks + helper first, then the app) with a secure timestamp and the hardened
# runtime, which is what notarization requires.
#
# Prerequisites (one-time, done by you — they need your Apple account and can't be scripted here):
#   1. A "Developer ID Application" certificate in your login keychain. Create it in
#      Xcode → Settings → Accounts → (your team) → Manage Certificates → + → Developer ID Application.
#      Confirm with:  security find-identity -v -p codesigning | grep "Developer ID Application"
#   2. Stored notarization credentials under a keychain profile (default name: opendisplay-notary):
#      xcrun notarytool store-credentials opendisplay-notary \
#        --apple-id "you@example.com" --team-id "YOURTEAMID" --password "app-specific-password"
#      (Generate the app-specific password at https://account.apple.com → Sign-In and Security.)
#
# Usage:
#   ./scripts/release-signed.sh                 # build → sign → notarize → staple → zip
#   NOTARIZE=0 ./scripts/release-signed.sh       # sign + zip only (skip notarization, for a dry run)
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./scripts/release-signed.sh
#   NOTARY_PROFILE=my-profile ./scripts/release-signed.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-Release}"
NOTARIZE="${NOTARIZE:-1}"
NOTARY_PROFILE="${NOTARY_PROFILE:-opendisplay-notary}"
ENTITLEMENTS="Apps/OpenDisplay/Resources/OpenDisplay.entitlements"
DIST="dist"

# --- 0. Resolve the signing identity --------------------------------------------------------------
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')
fi
if [ -z "$IDENTITY" ]; then
  cat >&2 <<'EOF'
error: no "Developer ID Application" signing identity found in the keychain.

Create one (one-time): Xcode → Settings → Accounts → your team → Manage Certificates
→ + → Developer ID Application. Then re-run this script. Verify with:
  security find-identity -v -p codesigning | grep "Developer ID Application"
EOF
  exit 1
fi
echo "Signing identity: $IDENTITY"

# --- 1. Build the Release app + bundle the helper -------------------------------------------------
CONFIG="$CONFIG" ./scripts/bundle-helper.sh "$CONFIG"

DD=$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/OpenDisplay-* | head -1)
APP="$DD/Build/Products/$CONFIG/OpenDisplay.app"
[ -d "$APP" ] || { echo "error: $APP not found" >&2; exit 1; }

# --- 2. Sign inside-out, hardened runtime + secure timestamp --------------------------------------
# Frameworks and the helper are signed first (no entitlements — they don't take the app's), then the
# main app last so its seal covers the freshly-signed nested code. --options runtime = hardened runtime.
sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"; }

echo "Signing embedded frameworks…"
for fw in "$APP"/Contents/Frameworks/*.framework; do
  [ -e "$fw" ] || continue
  sign "$fw"
done

if [ -x "$APP/Contents/Helpers/opendisplay" ]; then
  echo "Signing bundled helper…"
  sign "$APP/Contents/Helpers/opendisplay"
fi

echo "Signing the app…"
sign --entitlements "$ENTITLEMENTS" "$APP"

echo "Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP"

# --- 3. Package -----------------------------------------------------------------------------------
mkdir -p "$DIST"
ZIP="$DIST/OpenDisplay.zip"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
echo "Packaged: $ZIP"

# --- 4. Notarize + staple -------------------------------------------------------------------------
if [ "$NOTARIZE" = "1" ]; then
  echo "Submitting to Apple notary service (profile: $NOTARY_PROFILE)…"
  if ! xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait; then
    cat >&2 <<EOF
error: notarization failed. If this is a credentials problem, store them once with:
  xcrun notarytool store-credentials $NOTARY_PROFILE \\
    --apple-id "you@example.com" --team-id "YOURTEAMID" --password "app-specific-password"
For a rejection, inspect the log: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE
EOF
    exit 1
  fi
  echo "Stapling the notarization ticket…"
  xcrun stapler staple "$APP"
  # Re-zip so the distributed artifact carries the stapled ticket (works fully offline for users).
  rm -f "$ZIP"
  /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Gatekeeper assessment:"
  spctl -a -t exec -vvv "$APP" 2>&1 || true
  echo
  echo "✅ Notarized + stapled: $ZIP"
  echo "   Upload it to a GitHub release; users can open it with no quarantine workaround."
else
  echo
  echo "⚠️  Signed but NOT notarized (NOTARIZE=0): $ZIP"
  echo "   Users would still hit Gatekeeper. Re-run without NOTARIZE=0 once credentials are stored."
fi
