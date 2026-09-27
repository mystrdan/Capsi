# Capsi Flutter client

This directory contains the shared cross-platform application UI for Capsi.

## Architecture

- **Flutter** owns the application interface and platform UX.
- **Rust** remains the source of truth for networking, identity, discovery,
  encryption, storage, messaging and file transfer.
- `native/` is the C-compatible FFI bridge between Flutter and `capsi-core`.
- The existing Tauri client remains intact while the Flutter client is brought
  to feature parity.

New product operations belong in `capsi-core` first, then should be exposed
through `native/` to Flutter. Do not reimplement Capsi networking in Dart.

## Local development

From this directory:

```bash
flutter pub get
flutter run -d windows
```

Generate the platform runners when the Flutter SDK and target tooling are
available:

```bash
./tool/bootstrap_platforms.sh
```

On Windows PowerShell:

```powershell
.\tool\bootstrap_platforms.ps1
```

The bootstrap creates the standard Flutter runners for Windows, Android, iOS,
macOS and Linux. It does not build or package the Rust library automatically.

## Windows native bridge

The Windows Flutter client expects `capsi_ffi.dll` beside the application
executable.

For a complete Windows release build, run from `Capsi/flutter`:

```powershell
.\\tool\\build_windows.ps1
```

Or from a Bash-compatible shell:

```bash
./tool/build_windows.sh
```

These scripts generate the Windows runner when needed, install Flutter
dependencies, build the Rust FFI bridge, build the Flutter Windows release,
and copy `capsi_ffi.dll` beside `capsi.exe`.

For the native bridge alone:

```powershell
cargo build --manifest-path Capsi/flutter/native/Cargo.toml --release
```

If the DLL is absent from the application directory, Flutter can still open
the UI but native network/device features will be unavailable.

## Application surfaces

The Flutter client is being built as a complete application shell, not just a
communication screen. Current navigation includes:

- Nearby — discovery and device acceptance
- WorkPlace — local workspace, groups, departments and broadcasts
- Messages — trusted-device conversations
- Files — direct file transfers
- Trusted devices — accepted-device management
- Settings — connection, privacy, storage, appearance and runtime information
- About Capsi — product, version, runtime and protocol information

Keep settings and about information grounded in capabilities that actually
exist in the Rust core. Do not add controls that only look functional.

## Android and Apple targets

The Dart FFI layer already selects the platform library name:

- Android: `libcapsi_ffi.so`
- macOS: `libcapsi_ffi.dylib`
- Linux: `libcapsi_ffi.so`
- iOS: the process image

Packaging/linking these artifacts into each Flutter runner is a separate
platform integration step. Keep the Rust ABI shared across platforms rather
than creating platform-specific application logic.

## Versioning

The Flutter client currently tracks Capsi `1.0.2`. Keep the Flutter version
and native bridge version aligned with the product release when publishing.

