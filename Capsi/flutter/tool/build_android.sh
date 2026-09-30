#!/usr/bin/env bash
# Build the Capsi Android release APK with the Rust FFI bridge for every ABI.
#
# The Flutter UI and the shared Rust core are packaged together: the core is
# cross-compiled with cargo-ndk into android/app/src/main/jniLibs/<abi>/
# libcapsi_ffi.so, which is what lib/capsi_native.dart opens at start-up.
#
# Usage:
#   bash tool/build_android.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ABIS=(arm64-v8a armeabi-v7a x86_64)

for command_name in flutter cargo; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name was not found on PATH." >&2
    exit 1
  fi
done

if ! command -v cargo-ndk >/dev/null 2>&1; then
  echo "cargo-ndk was not found on PATH. Install it with: cargo install cargo-ndk --locked" >&2
  exit 1
fi

if [ ! -d "android" ]; then
  echo "Flutter Android runner is missing. Generating it..."
  flutter create --platforms=android .
fi

bash "$ROOT/tool/configure_android.sh"
bash "$ROOT/tool/make_icons.sh"

echo "Resolving Flutter packages..."
flutter pub get

ndk_targets=()
for abi in "${ABIS[@]}"; do
  ndk_targets+=(-t "$abi")
done

echo "Building Capsi Rust native bridge for: ${ABIS[*]}"
(cd native && cargo ndk "${ndk_targets[@]}" -o ../android/app/src/main/jniLibs build --release)

for abi in "${ABIS[@]}"; do
  library="android/app/src/main/jniLibs/$abi/libcapsi_ffi.so"
  if [ ! -f "$library" ]; then
    echo "Expected $library was not produced. The APK would start without the Rust core." >&2
    exit 1
  fi
done

echo "Building Capsi Android application..."
flutter build apk --release

apk="build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$apk" ]; then
  echo "Flutter build completed but $apk was not found." >&2
  exit 1
fi

echo
echo "Capsi Android release is ready:"
echo "$(cd "$(dirname "$apk")" && pwd)/$(basename "$apk")"
