#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

command -v flutter >/dev/null 2>&1 || {
  echo "Flutter SDK was not found on PATH." >&2
  exit 1
}

if [ ! -d "windows" ]; then
  echo "Flutter Windows runner is missing. Generating it..."
  flutter create --platforms=windows .
fi

bash "$(dirname "${BASH_SOURCE[0]}")/make_icons.sh"

flutter pub get

echo "Building Capsi Rust native bridge..."
# The Windows release must not depend on the Visual C++ redistributable: the
# bridge links the C runtime statically, exactly like the runner does (see
# windows/CMakeLists.txt), so the installer has no prerequisites to install.
RUSTFLAGS="-C target-feature=+crt-static" cargo build --manifest-path native/Cargo.toml --release

echo "Building Capsi Windows application..."
flutter build windows --release

ffi="$(pwd)/native/target/release/capsi_ffi.dll"
exe="$(find build/windows -type f -iname 'capsi.exe' -print -quit)"

if [ -z "$exe" ]; then
  echo "Flutter build completed but capsi.exe was not found under build/windows." >&2
  exit 1
fi

cp "$ffi" "$(dirname "$exe")/capsi_ffi.dll"

echo
echo "Capsi Windows release is ready:"
echo "$(dirname "$exe")"
