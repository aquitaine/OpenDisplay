# Sparkle update signing — one-time setup

OpenDisplay updates itself with [Sparkle 2](https://sparkle-project.org). Every update is verified
twice before it runs: against the project's EdDSA (ed25519) signing key, and against the Developer ID
code signature of the app that is already installed. This file covers the key half — the part that
lives outside the repository and can't be regenerated from it.

## What is already wired up

| Piece | Where | Value |
|---|---|---|
| Feed | `Apps/OpenDisplay/Resources/Info.plist` → `SUFeedURL` | `https://github.com/aquitaine/OpenDisplay/releases/latest/download/appcast.xml` |
| Public key | `Apps/OpenDisplay/Resources/Info.plist` → `SUPublicEDKey` | `G9aQchK8B0eqrXhKwKWat4SRCR/XboPdgpmfuHrBnuE=` |
| Private key | maintainer's **login keychain** (account `ed25519`) | never on disk, never in the repo |
| Framework | `project.yml` → `packages.Sparkle` | resolved by SwiftPM, embedded in the app |
| Appcast | produced by `scripts/release-signed.sh`, uploaded beside `OpenDisplay.zip` | one item, signed |

The feed URL uses GitHub's `releases/latest/download/<asset>` redirect, so it always resolves to the
newest release's `appcast.xml` and never has to be re-pointed at a new tag.

## Generating the key (only on a new machine, or to rotate)

The key already exists in the maintainer's login keychain — **running `generate_keys` again will not
overwrite it**, it prints the existing public key instead. You only need this section to set up a
second machine or to deliberately rotate.

```sh
# The tools travel inside the resolved Sparkle package, so they always match the embedded framework.
DD=$(ls -dt ~/Library/Developer/Xcode/DerivedData/OpenDisplay-* | head -1)
SPARKLE_BIN="$DD/SourcePackages/artifacts/sparkle/Sparkle/bin"

"$SPARKLE_BIN/generate_keys"        # creates the keypair, stores the private half in the keychain
"$SPARKLE_BIN/generate_keys" -p     # prints just the public key, for checking against Info.plist
```

`generate_keys` prints the `SUPublicEDKey` value to paste into
`Apps/OpenDisplay/Resources/Info.plist`. Confirm the embedded key matches the machine you release
from before cutting a release:

```sh
diff <("$SPARKLE_BIN/generate_keys" -p) \
     <(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" Apps/OpenDisplay/Resources/Info.plist)
```

To move the key to another machine, export and import it — never commit the exported file, and delete
it once imported:

```sh
"$SPARKLE_BIN/generate_keys" -x sparkle-private-key.txt   # on the machine that has the key
"$SPARKLE_BIN/generate_keys" -f sparkle-private-key.txt   # on the machine that needs it
rm -P sparkle-private-key.txt
```

## Cutting a release

```sh
./scripts/release-signed.sh                 # build → sign → notarize → staple → zip → appcast
gh release create v0.9.1 dist/OpenDisplay.zip dist/appcast.xml --title "…" --notes-file …
```

or, against a release that already exists:

```sh
PUBLISH=1 ./scripts/release-signed.sh       # uploads both assets with gh
```

The script derives the version from the built app's `CFBundleShortVersionString`, uses `v<version>`
as the release tag (override with `RELEASE_TAG=`), and lifts that version's section out of
`CHANGELOG.md` as the release notes Sparkle shows in its update window.

## Things that will bite you

* **Every release needs its appcast.** `SUFeedURL` resolves to the *newest* release's `appcast.xml`.
  A release published without one makes `releases/latest/download/appcast.xml` 404 — apps in the
  field then find nothing until the next release fixes it. `release-signed.sh` prints the upload
  command for exactly this reason; `PUBLISH=1` uploads both together.
* **The first Sparkle-enabled release still has to be installed by hand.** Sparkle only updates *from*
  a build that already contains it. Every copy older than that (≤ 0.9.0) has no updater, so those
  users download the release themselves once; from then on the in-app update works.
* **Appcast generation must come after stapling.** The signature and length cover the exact bytes
  users download, and `xcrun stapler` rewrites the zip. The script already orders it that way.
* **Losing the private key means users can't update.** An app in the field only installs what its
  embedded public key verifies. Recovering means generating a new key, shipping an app with the new
  `SUPublicEDKey`… which nobody can auto-update to. Keep the login keychain backed up.
* **A build running from DerivedData will happily update itself** into the released app. That is
  Sparkle working as designed on a debug build; quit the dev copy before testing an update, or turn
  the automatic check off in Settings while developing.
