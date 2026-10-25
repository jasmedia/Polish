#!/usr/bin/env bash
# Build the SwiftPM executable and wrap it into a signed Polish.app.
#
#   scripts/bundle.sh              # debug build  -> .build/app/Polish.app
#   CONFIG=release scripts/bundle.sh
#
# Signing identity, in order of preference:
#   1. $POLISH_SIGN_IDENTITY (e.g. "Apple Development: Jane Doe (ABCDE12345)")
#   2. the first "Apple Development" or "Developer ID Application" identity in the keychain
#   3. ad-hoc ("-"), with a warning
# A stable identity matters: macOS ties the Accessibility permission to the code signature,
# so ad-hoc builds lose that permission on every rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-debug}"
APP_DIR=".build/app"
APP="$APP_DIR/Polish.app"

swift build -c "$CONFIG" --product Polish
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Polish" "$APP/Contents/MacOS/Polish"
cp App/Info.plist "$APP/Contents/Info.plist"
cp App/Resources/AppIcon.icns "$APP/Contents/Resources/"  # drawn by scripts/make-icon.swift

# SwiftPM resource bundles (e.g. from dependencies) go in Contents/Resources,
# where the generated Bundle.module accessor looks via Bundle.main.resourceURL.
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done
shopt -u nullglob

IDENTITY="${POLISH_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  # By SHA-1 fingerprint, not name: a renewed certificate leaves two identities with the same name,
  # which codesign rejects as ambiguous.
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/Apple Development|Developer ID Application/ { print $2; exit }')"
fi
if [[ -z "$IDENTITY" ]]; then
  echo "warning: no signing identity found; signing ad-hoc." >&2
  echo "         Accessibility permission will reset on every rebuild." >&2
  IDENTITY="-"
fi

TIMESTAMP="--timestamp=none"
[[ "$CONFIG" == "release" ]] && TIMESTAMP="--timestamp"

codesign --force --options runtime $TIMESTAMP \
  --entitlements App/Polish.entitlements \
  --sign "$IDENTITY" \
  "$APP"

echo "Built $APP ($CONFIG, signed: $IDENTITY)"
