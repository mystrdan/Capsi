#!/usr/bin/env bash
set -euo pipefail

project="ios/Runner.xcodeproj/project.pbxproj"
library="$(SRCROOT)/../native/target/aarch64-apple-ios/release/libcapsi_ffi.a"

if [ ! -f "$project" ]; then
  echo "iOS Runner project not found: $project"
  exit 1
fi

if [ ! -f "native/target/aarch64-apple-ios/release/libcapsi_ffi.a" ]; then
  echo "Rust iOS static library not found."
  exit 1
fi

python3 - "$project" "$library" <<'PY'
from pathlib import Path
import sys

project = Path(sys.argv[1])
library = sys.argv[2]
text = project.read_text()

if "-force_load" in text and "libcapsi_ffi.a" in text:
    print("Rust iOS FFI linker flags already present.")
    raise SystemExit(0)

needle = "buildSettings = {"
insertion = (
    'buildSettings = {\n'
    f'\t\t\t\tOTHER_LDFLAGS = ("$(inherited)", "-force_load", "{library}", "-Wl,-export_dynamic");\n'
)

if needle not in text:
    raise SystemExit("No Xcode build settings blocks found.")

text = text.replace(needle, insertion, 1)
project.write_text(text)
print(f"Added Rust FFI linker flags to {project}.")
PY

grep -n "libcapsi_ffi.a\|-force_load\|export_dynamic" "$project"
