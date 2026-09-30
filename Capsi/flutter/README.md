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

## Android release build

The Android release build cross-compiles the Rust FFI bridge for `arm64-v8a`,
`armeabi-v7a` and `x86_64`, packages those libraries under
`android/app/src/main/jniLibs/`, and produces a release APK. One script does
all of it, from `Capsi/flutter`:

```powershell
.\tool\build_android.ps1
```

or, from the repository root on Windows:

```batch
build-android.bat
```

The script generates the Flutter Android runner when it is missing, applies the
Capsi runner settings, runs `flutter pub get`, builds the bridge with
`cargo-ndk`, verifies every ABI landed in `jniLibs`, and only then runs
`flutter build apk --release`. The APK is written to
`build/app/outputs/flutter-apk/app-release.apk`.

Requirements: a Flutter SDK, a Rust toolchain with the `aarch64-linux-android`,
`armv7-linux-androideabi` and `x86_64-linux-android` targets, `cargo-ndk`
(`cargo install cargo-ndk --locked`) and an Android SDK with an NDK installed.

`tool/configure_android.ps1` is safe to re-run after every `flutter create`.
It fixes the four things the Flutter template gets wrong for this product: the
placeholder application id (it becomes `win.capsi.app`, the id Capsi shipped
with before the Flutter migration), the placeholder label, the fact that
the template only declares `android.permission.INTERNET` in the debug and
profile manifests — a Capsi release build needs it to open any socket at all —
and the location of `MainActivity.kt`. The manifest names the activity
`.MainActivity`, which resolves against the application id, so the class has to
move out of the template's `com.example.capsi` package or the APK builds
cleanly and then dies on launch.

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
- Workplace — local workspace, groups, departments and broadcasts
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

The iOS build now creates a universal simulator archive plus a device archive,
packages them as an XCFramework, installs that bridge through CocoaPods, and
verifies that exported Capsi FFI symbols are present in the release Runner
executable. Real-device iOS communication testing is still required.

Packaging/linking these artifacts into each Flutter runner is a platform
integration step. Keep the Rust ABI shared across platforms rather than
creating platform-specific application logic.

## Versioning

The Flutter client currently tracks Capsi `1.0.2`. Keep the Flutter version
and native bridge version aligned with the product release when publishing.
