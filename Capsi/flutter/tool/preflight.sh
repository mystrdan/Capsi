#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

command -v flutter >/dev/null 2>&1 || { echo 'Flutter SDK was not found on PATH.' >&2; exit 1; }
command -v cargo >/dev/null 2>&1 || { echo 'Cargo was not found on PATH.' >&2; exit 1; }

for path in pubspec.yaml lib/main.dart lib/capsi_native.dart native/Cargo.toml assets/capsi-logo-512.png; do
  if [ ! -e "$path" ]; then
    echo "Required path is missing: $path" >&2
    exit 1
  fi
done

echo 'Capsi Flutter preflight'
echo '-----------------------'
flutter --version
cargo --version

echo 'Checking Flutter package metadata...'
flutter pub get

echo 'Checking Rust FFI crate...'
cargo check --manifest-path native/Cargo.toml

echo 'Checking Flutter analyzer...'
flutter analyze

echo
echo 'Preflight passed.'
