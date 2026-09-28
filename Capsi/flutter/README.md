# Capsi Flutter client

This directory contains the Capsi application UI for all supported platforms.

## Architecture

- **Flutter** owns the application interface and platform UX.
- **Rust** remains the source of truth for networking, identity, discovery,
  encryption, storage, messaging and file transfer.
- `native/` is the C-compatible FFI bridge between Flutter and `capsi-core`.
- `crates/capsi-core/` contains the platform-independent Capsi behavior.

The former HTML/CSS/JavaScript + Tauri client has been retired. New application
UI belongs in Flutter. Do not add product UI to a legacy web frontend or Tauri
shell.

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
macOS and Linux.

## Windows native bridge

The Windows Flutter client expects `capsi_ffi.dll` beside the application
executable.

For a complete Windows release build, run from `Capsi/flutter`:

```powershell
.\tool\build_windows.ps1
```

Or from a Bash-compatible shell:

```bash
./tool/build_windows.sh
```

These scripts install Flutter dependencies, build the Rust FFI bridge, build
the Flutter Windows release, and copy `capsi_ffi.dll` beside `capsi.exe`.

For the native bridge alone:

```powershell
cargo build --manifest-path Capsi/flutter/native/Cargo.toml --release
```

## Application surfaces

The Flutter client is the product application. Current navigation includes:

- Nearby — discovery and device acceptance
- WorkPlace — local workspace, groups, departments and broadcasts
- Messages — trusted-device conversations
- Files — direct file transfers
- Trusted devices — accepted-device management
- Settings — connection, privacy, storage, appearance and runtime information

Keep settings and about information grounded in capabilities that actually
exist in the Rust core. Do not add controls that only look functional.

## Platform targets

The Dart FFI layer selects the native library for each target:

- Windows: `capsi_ffi.dll`
- Android: `libcapsi_ffi.so`
- macOS: `libcapsi_ffi.dylib`
- Linux: `libcapsi_ffi.so`
- iOS: the process image

Packaging/linking these artifacts into each Flutter runner is a platform
integration step. Keep the Rust ABI shared across platforms rather than
creating platform-specific application logic.

## Versioning

The Flutter client currently tracks Capsi `1.0.2`. Keep the Flutter version
and native bridge version aligned with the product release when publishing.
