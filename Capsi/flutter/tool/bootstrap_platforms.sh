#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required."
  exit 1
fi

flutter pub get
flutter create --platforms=windows,android,ios,macos,linux .
echo
echo "Flutter platform runners generated."
echo "Next: build the Rust bridge for the target platform and package/link it into the runner."
