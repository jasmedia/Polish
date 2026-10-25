#!/usr/bin/env bash
# Rebuild Polish.app, quit any running copy, and launch the new one.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/bundle.sh
pkill -x Polish 2>/dev/null || true
# Launch Services fails (-600) when asked to open the app while the old copy is still quitting,
# and sometimes just after it has gone: wait for the exit, then retry once.
for _ in {1..50}; do pgrep -x Polish >/dev/null || break; sleep 0.1; done
open .build/app/Polish.app || { sleep 1; open .build/app/Polish.app; }
echo "Polish is running. Stream logs with: make logs"
