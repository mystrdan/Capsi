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
if [ ! -f "$PODFILE" ]; then
  cat > "$PODFILE" <<'RUBY'
platform :ios, '12.0'
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

project 'Runner', {
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
}

def flutter_root
  generated_xcode_build_settings = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings)
    raise "#{generated_xcode_build_settings} must exist. Run flutter pub get first"
  end

  File.foreach(generated_xcode_build_settings) do |line|
    matches = line.match(/FLUTTER_ROOT=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found in #{generated_xcode_build_settings}"
end

require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)

flutter_ios_podfile_setup

target 'Runner' do
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  pod 'capsi_ffi', :path => '../native'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
end
RUBY
else
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
fi

echo "Prepared CapsiFfi.xcframework and CocoaPods integration."
