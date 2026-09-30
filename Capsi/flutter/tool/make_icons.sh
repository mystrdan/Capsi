#!/usr/bin/env bash
# Regenerates every platform icon set from the official Capsi logo.
#
# `flutter create` drops the stock Flutter icon into the runner, so the logo has
# to be stamped in afterwards: this runs scripts/make-icons.mjs, which writes the
# Android launcher set (legacy + adaptive + launch screen) and the Windows
# .ico/PNG set used by the runner.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
generator="$(dirname "$ROOT")/scripts/make-icons.mjs"

if [ ! -f "$generator" ]; then
  echo "Capsi icon generator is missing: $generator" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  if [ -f "$ROOT/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml" ]; then
    echo "Node.js is not on PATH; keeping the committed Capsi icons." >&2
    exit 0
  fi
  echo "Node.js is required to stamp the Capsi logo into the generated runner icons." >&2
  exit 1
fi

echo "Stamping the Capsi logo into the platform icon sets..."
node "$generator"
