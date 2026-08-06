#!/usr/bin/env bash
# Builds a Developer-ID-signed, notarized, stapled OpenDisplay.app, packages it as a zip that opens
# with no Gatekeeper warning (no `xattr` dance for users), and writes the Sparkle appcast that feeds
# in-app updates. Distribution channel is Developer ID + hardened runtime — NOT the App Store (the
# full app uses private frameworks; see D-007). Signs the bundle inside-out (Sparkle's helpers,
# frameworks, and the bundled CLI first, then the app) with a secure timestamp and the hardened
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
#   3. The Sparkle EdDSA signing key in your login keychain, whose public half is SUPublicEDKey in
#      Apps/OpenDisplay/Resources/Info.plist. See scripts/sparkle-setup.md — every update this script
#      publishes is signed with it, and an app in the field installs nothing that fails that check.
#
# Usage:
#   ./scripts/release-signed.sh                  # build → sign → notarize → staple → zip → appcast
#   NOTARIZE=0 ./scripts/release-signed.sh        # sign + zip only (skip notarization, for a dry run)
#   APPCAST=0 ./scripts/release-signed.sh         # skip the appcast (no Sparkle key on this machine)
#   PUBLISH=1 ./scripts/release-signed.sh         # also upload both assets to the release (needs gh)
#   RELEASE_TAG=v1.0.0 ./scripts/release-signed.sh  # tag the appcast's download URLs point at
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./scripts/release-signed.sh
#   NOTARY_PROFILE=my-profile ./scripts/release-signed.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-Release}"
NOTARIZE="${NOTARIZE:-1}"
APPCAST="${APPCAST:-1}"
PUBLISH="${PUBLISH:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-opendisplay-notary}"
ENTITLEMENTS="Apps/OpenDisplay/Resources/OpenDisplay.entitlements"
PROJECT_URL="https://github.com/aquitaine/OpenDisplay"
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
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
RELEASE_TAG="${RELEASE_TAG:-v$VERSION}"
echo "Version: $VERSION (release tag $RELEASE_TAG)"

# --- 2. Sign inside-out, hardened runtime + secure timestamp --------------------------------------
# Nested code is signed before the bundle that contains it, so each outer seal covers freshly-signed
# inner code. --options runtime = hardened runtime, which notarization requires everywhere.
sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"; }

# Sparkle ships an installer, a progress app, and two XPC services inside its framework. Xcode signs
# them when it embeds the framework, but they carry OUR identity and must be re-signed here whenever
# the outer seal is re-made — an unsigned or stale-signed helper fails notarization and, worse, is
# rejected at install time by Sparkle's own signature check.
SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
  echo "Signing Sparkle's nested helpers…"
  for version_dir in "$SPARKLE_FRAMEWORK"/Versions/*; do
    # Versions/Current is a symlink to the real version directory; signing through it would just
    # re-sign the same files under a second name.
    [ -L "$version_dir" ] && continue
    for nested in "$version_dir"/XPCServices/*.xpc "$version_dir"/Autoupdate "$version_dir"/Updater.app; do
      [ -e "$nested" ] || continue
      sign "$nested"
    done
  done
fi

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
else
  echo
  echo "⚠️  Signed but NOT notarized (NOTARIZE=0): $ZIP"
  echo "   Users would still hit Gatekeeper. Re-run without NOTARIZE=0 once credentials are stored."
fi

# --- 5. Sparkle appcast ---------------------------------------------------------------------------
# Last, deliberately: the EdDSA signature and length cover the exact bytes users download, and
# stapling rewrites the zip. Generating the appcast any earlier would sign a file that no longer
# exists.
if [ "$APPCAST" = "1" ]; then
  # The tool travels inside the resolved Sparkle package, so it is always the same version as the
  # framework we just embedded — no separately-installed copy to drift out of step.
  GENERATE_APPCAST=""
  if [ -n "${SPARKLE_BIN:-}" ]; then
    GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
  fi
  if [ ! -x "$GENERATE_APPCAST" ]; then
    GENERATE_APPCAST=$(find "$DD/SourcePackages/artifacts" -type f -name generate_appcast -perm -111 \
      2>/dev/null | head -1)
  fi
  if [ ! -x "$GENERATE_APPCAST" ]; then
    cat >&2 <<EOF
error: Sparkle's generate_appcast was not found under
  $DD/SourcePackages/artifacts
Resolve the Sparkle package once (open the project in Xcode, or run 'make xcode' and build), or point
SPARKLE_BIN at a directory holding the tool. Re-run with APPCAST=0 to skip the appcast entirely.
EOF
    exit 1
  fi

  # generate_appcast reads a DIRECTORY of archives and pairs each with a same-named release-notes
  # file. Staging a fresh directory keeps the feed to exactly this release: the appcast is published
  # as an asset of the newest release, and SUFeedURL resolves to that newest asset, so history in the
  # file would never be read.
  STAGE="$DIST/appcast-staging"
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  cp "$ZIP" "$STAGE/OpenDisplay.zip"

  # Release notes: this version's CHANGELOG section, which is what Sparkle shows in its update window.
  awk -v version="$VERSION" '
    $0 ~ "^## \\[" version "\\]" { capture = 1; next }
    capture && /^## \[/ { exit }
    capture { print }
  ' CHANGELOG.md > "$STAGE/OpenDisplay.md"
  if [ -s "$STAGE/OpenDisplay.md" ]; then
    echo "Release notes: CHANGELOG.md section for $VERSION"
  else
    echo "⚠️  No CHANGELOG.md section for $VERSION — the update will ship without release notes."
    rm -f "$STAGE/OpenDisplay.md"
  fi

  echo "Generating + signing the appcast…"
  "$GENERATE_APPCAST" \
    --download-url-prefix "$PROJECT_URL/releases/download/$RELEASE_TAG/" \
    --link "$PROJECT_URL" \
    --embed-release-notes \
    -o "$DIST/appcast.xml" \
    "$STAGE"
  rm -rf "$STAGE"
  echo "Appcast: $DIST/appcast.xml"
fi

# --- 6. Publish -----------------------------------------------------------------------------------
# Opt-in: uploads to an existing release rather than creating one, so cutting the release stays a
# deliberate act. Both assets go up together — an OpenDisplay.zip without its appcast.xml is a
# release nobody's app can see.
if [ "$PUBLISH" = "1" ]; then
  command -v gh >/dev/null 2>&1 || { echo "error: PUBLISH=1 needs the gh CLI." >&2; exit 1; }
  ASSETS=("$ZIP")
  if [ -f "$DIST/appcast.xml" ]; then
    ASSETS+=("$DIST/appcast.xml")
  fi
  echo "Uploading to release $RELEASE_TAG…"
  gh release upload "$RELEASE_TAG" "${ASSETS[@]}" --clobber
  echo "✅ Uploaded: ${ASSETS[*]}"
else
  echo
  echo "Next: attach both assets to the $RELEASE_TAG release —"
  echo "  gh release upload $RELEASE_TAG $ZIP $DIST/appcast.xml --clobber"
  echo "The appcast MUST accompany every release: SUFeedURL points at the newest release's copy, so a"
  echo "release published without it takes the update feed offline until the next one."
fi
