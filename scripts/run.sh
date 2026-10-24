#!/usr/bin/env bash
# Rebuild Polish.app, quit any running copy, and launch the new one.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/bundle.sh
pkill -x Polish 2>/dev/null || true
open .build/app/Polish.app
echo "Polish is running. Stream logs with: make logs"
