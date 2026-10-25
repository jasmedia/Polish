#!/usr/bin/env bash
# Build Polish-<version>.dmg for a GitHub release, in .build/release-dist/ with its SHA-256 checksum.
#
#   scripts/release.sh              # ad-hoc signed, not notarized (what GitHub releases ship)
#   NOTARIZE=1 scripts/release.sh   # Developer ID signed, notarized and stapled (needs a paid account)
#
# Ad-hoc builds open only after the user allows them once (System Settings › Privacy & Security ›
# Open Anyway; README › Install), and macOS asks for Accessibility again after each update, since the
# permission is tied to the exact build. Never ship a build signed with an Apple Development identity:
# it doesn't pass Gatekeeper either, and it puts the developer's Apple ID in every copy.
#
# NOTARIZE=1 one-time setup (Apple Developer Program membership):
#   1. A "Developer ID Application" certificate in the login keychain
#      (Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application).
#   2. A notarytool profile named "polish" with an app-specific password from account.apple.com:
#        xcrun notarytool store-credentials polish --apple-id <your Apple ID> --team-id <team ID>
#   Override the identity with $POLISH_SIGN_IDENTITY and the profile with $POLISH_NOTARY_PROFILE.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)"
OUT=".build/release-dist"
APP=".build/app/Polish.app"
DMG="$OUT/Polish-$VERSION.dmg"
rm -rf "$OUT"
mkdir -p "$OUT"

if [[ -n "${NOTARIZE:-}" ]]; then
  PROFILE="${POLISH_NOTARY_PROFILE:-polish}"
  IDENTITY="${POLISH_SIGN_IDENTITY:-}"
  if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
      | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
  fi
  if [[ "$IDENTITY" != Developer\ ID\ Application* ]]; then
    echo "error: NOTARIZE=1 needs a Developer ID Application identity; see the setup steps at the top of $0." >&2
    exit 1
  fi
else
  IDENTITY="-"
fi

# 1. Release build with hardened runtime, signed with $IDENTITY.
CONFIG=release POLISH_SIGN_IDENTITY="$IDENTITY" scripts/bundle.sh
codesign --verify --deep --strict --verbose=2 "$APP"

# 2. Notarize the app (as a zip) and staple the ticket, so it opens offline on first launch.
if [[ -n "${NOTARIZE:-}" ]]; then
  ditto -c -k --keepParent "$APP" "$OUT/Polish.zip"
  xcrun notarytool submit "$OUT/Polish.zip" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  rm "$OUT/Polish.zip"
fi

# 3. DMG with the app and an Applications link.
STAGE="$OUT/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Polish $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"

if [[ -n "${NOTARIZE:-}" ]]; then
  codesign --sign "$IDENTITY" --timestamp "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  spctl --assess --type execute --verbose=2 "$APP"
fi

(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Built $DMG ($([[ -n "${NOTARIZE:-}" ]] && echo notarized || echo "ad-hoc signed, not notarized"))"
