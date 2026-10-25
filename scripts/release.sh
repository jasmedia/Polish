#!/usr/bin/env bash
# Build a notarized, stapled Polish.app and DMG for distribution (Developer ID, not the App Store).
#
#   scripts/release.sh                   # -> .build/release-dist/Polish-<version>.dmg
#   SKIP_NOTARIZE=1 scripts/release.sh   # signed DMG only, to check the steps before notarizing
#
# One-time setup (needs your Apple Developer account):
#   1. A "Developer ID Application" certificate in the login keychain
#      (Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application).
#   2. A notarytool profile named "polish" with an app-specific password from account.apple.com:
#        xcrun notarytool store-credentials polish --apple-id <your Apple ID> --team-id <team ID>
#      (it prompts for the password and keeps it in the keychain).
# Override the identity with $POLISH_SIGN_IDENTITY and the profile with $POLISH_NOTARY_PROFILE.
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${POLISH_NOTARY_PROFILE:-polish}"
IDENTITY="${POLISH_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
fi
if [[ "$IDENTITY" != Developer\ ID\ Application* ]]; then
  echo "error: no Developer ID Application identity; see the setup steps at the top of $0." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)"
OUT=".build/release-dist"
APP=".build/app/Polish.app"
DMG="$OUT/Polish-$VERSION.dmg"
rm -rf "$OUT"
mkdir -p "$OUT"

notarize() {
  if [[ -n "${SKIP_NOTARIZE:-}" ]]; then
    echo "Skipping notarization of $1"
    return
  fi
  xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait
}

# 1. Release build, signed with Developer ID, hardened runtime and a secure timestamp.
CONFIG=release POLISH_SIGN_IDENTITY="$IDENTITY" scripts/bundle.sh
codesign --verify --deep --strict --verbose=2 "$APP"

# 2. Notarize the app (as a zip) and staple the ticket, so it opens offline on first launch.
ditto -c -k --keepParent "$APP" "$OUT/Polish.zip"
notarize "$OUT/Polish.zip"
[[ -z "${SKIP_NOTARIZE:-}" ]] && xcrun stapler staple "$APP"
rm "$OUT/Polish.zip"

# 3. DMG with the app and an Applications link, signed, notarized and stapled too.
STAGE="$OUT/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Polish $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --sign "$IDENTITY" --timestamp "$DMG"
notarize "$DMG"
if [[ -z "${SKIP_NOTARIZE:-}" ]]; then
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  spctl --assess --type execute --verbose=2 "$APP"
fi

echo "Built $DMG"
