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

The Windows Flutter client expects `capsi_ffi.dll` to be available beside
the application executable (or otherwise discoverable by the Windows loader).

Build the bridge from the repository root:

```powershell
cargo build --manifest-path Capsi/flutter/native/Cargo.toml --release
Copy-Item Capsi/flutter/native/target/release/capsi_ffi.dll Capsi/flutter/
```

Then run the Flutter Windows target. If the DLL is absent, Flutter still opens
the UI but native network/device features remain unavailable.

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

