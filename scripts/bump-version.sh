#!/usr/bin/env bash
# Bump the app version in App/Info.plist and print the new one.
#
#   scripts/bump-version.sh patch   # 1.1.0 -> 1.1.1
#   scripts/bump-version.sh minor   # 1.1.0 -> 1.2.0
#   scripts/bump-version.sh major   # 1.1.0 -> 2.0.0
#
# CFBundleShortVersionString gets the new X.Y.Z; CFBundleVersion (the build number) goes up by one.
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST="App/Info.plist"
PART="${1:-}"
CURRENT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"

if [[ ! "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "error: $PLIST has version '$CURRENT', not X.Y.Z" >&2
  exit 1
fi
MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

case "$PART" in
  major) NEXT="$((MAJOR + 1)).0.0" ;;
  minor) NEXT="$MAJOR.$((MINOR + 1)).0" ;;
  patch) NEXT="$MAJOR.$MINOR.$((PATCH + 1))" ;;
  *) echo "usage: $0 major|minor|patch" >&2; exit 2 ;;
esac

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEXT" -c "Set :CFBundleVersion $((BUILD + 1))" "$PLIST"
echo "$NEXT"
