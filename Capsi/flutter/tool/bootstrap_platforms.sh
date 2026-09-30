#!/usr/bin/env bash
# Generates the standard Flutter runners for every Capsi platform.
#
# A fresh `flutter create` runner is only a template: the Android side still
# carries the placeholder application id and debug-only INTERNET permission,
# and every platform still shows the stock Flutter icon. Bootstrap therefore
# finishes with the same two steps the platform builds run - the Capsi runner
# settings and the logo stamp - so a generated tree is correct immediately.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required."
  exit 1
fi

flutter pub get
flutter create --platforms=windows,android,ios,macos,linux .
if [ -d android ]; then
  bash "$ROOT/tool/configure_android.sh"
fi
bash "$ROOT/tool/make_icons.sh"
echo
echo "Flutter platform runners generated and configured for Capsi."
echo "Next: build the Rust bridge for the target platform and package/link it into the runner."
