#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE="$ROOT/native"
IOS="$ROOT/ios"
XCFRAMEWORK="$NATIVE/CapsiFfi.xcframework"

if [ ! -f "$NATIVE/target/aarch64-apple-ios/release/libcapsi_ffi.a" ]; then
  echo "Missing iOS Rust device library."
  exit 1
fi

if [ ! -f "$NATIVE/target/aarch64-apple-ios-sim/release/libcapsi_ffi.a" ]; then
  echo "Missing iOS Rust arm64 simulator library."
  exit 1
fi

if [ ! -f "$NATIVE/target/x86_64-apple-ios/release/libcapsi_ffi.a" ]; then
  echo "Missing iOS Rust x86_64 simulator library."
  exit 1
fi

SIM_DIR="$NATIVE/target/ios-sim-universal"
mkdir -p "$SIM_DIR"
lipo -create \
  "$NATIVE/target/aarch64-apple-ios-sim/release/libcapsi_ffi.a" \
  "$NATIVE/target/x86_64-apple-ios/release/libcapsi_ffi.a" \
  -output "$SIM_DIR/libcapsi_ffi.a"

rm -rf "$XCFRAMEWORK"
xcodebuild -create-xcframework \
  -library "$NATIVE/target/aarch64-apple-ios/release/libcapsi_ffi.a" \
  -library "$SIM_DIR/libcapsi_ffi.a" \
  -output "$XCFRAMEWORK"

PODFILE="$IOS/Podfile"
if ! grep -q "capsi_ffi" "$PODFILE"; then
  python3 - "$PODFILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = "target 'Runner' do\n"
if needle not in text:
    raise SystemExit("Runner target not found in iOS Podfile")
text = text.replace(
    needle,
    needle + "  pod 'capsi_ffi', :path => '../native'\n",
    1,
)
path.write_text(text)
PY
fi

echo "Prepared CapsiFfi.xcframework and CocoaPods integration."
