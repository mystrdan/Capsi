#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-all}"

LOCAL_NETWORK_DESCRIPTION="Capsi uses your local network to discover trusted devices and exchange messages and files directly between them."

patch_info() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "Missing Info.plist: $file"
    exit 1
  fi

  /usr/libexec/PlistBuddy -c "Delete :NSLocalNetworkUsageDescription" "$file" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string $LOCAL_NETWORK_DESCRIPTION" "$file"
}

patch_entitlements() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "Missing entitlements file: $file"
    exit 1
  fi

  /usr/libexec/PlistBuddy -c "Delete :com.apple.security.network.client" "$file" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.network.client bool true" "$file"
  /usr/libexec/PlistBuddy -c "Delete :com.apple.security.network.server" "$file" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.network.server bool true" "$file"
}

case "$TARGET" in
  ios)
    patch_info "$ROOT/ios/Runner/Info.plist"
    ;;
  macos)
    patch_info "$ROOT/macos/Runner/Info.plist"
    for entitlements in "$ROOT"/macos/Runner/*.entitlements; do
      [ -f "$entitlements" ] || continue
      patch_entitlements "$entitlements"
    done
    ;;
  *)
    echo "Usage: $0 ios|macos"
    exit 2
    ;;
esac

echo "Configured Capsi $TARGET local-network metadata."
