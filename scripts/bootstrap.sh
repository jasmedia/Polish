#!/usr/bin/env bash
# One-time setup on a Mac: run the tests, build the app, set up eval/, check the on-device model.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Tests"
make test

echo "==> App bundle"
make app

echo "==> Python eval environment"
if ! command -v uv >/dev/null; then
  brew install uv
fi
make eval-setup

echo "==> On-device model"
make check-model

echo
echo "Done. Launch with: make run"
