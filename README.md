# Capsi

**CAPSI — Messages and files, device to device.**

> **Run it. Find devices. Send.**

Capsi is a lightweight device-to-device communication utility. It lets connected devices discover one another, exchange messages, and transfer files directly over a supported local communication network — with no Internet required for local communication.

Capsi is local-first: local communication does not require a Capsi cloud service, account system, or central workplace server.

## Product

- **Messages** — direct device-to-device messaging.
- **Files** — direct file offers, acceptance, transfer, integrity checks, and delivery handling.
- **Nearby** — discover other Capsi devices on the connected network.
- **Trusted devices** — accept, block, rename, or forget peers.
- **Workplace** — an optional local communication layer for trusted devices, with people, groups, departments, roles, broadcasts, and workplace conversations.
- **Offline delivery** — pending messages are stored locally and retried when a recipient becomes reachable.
- **Encrypted transport** — direct peer communication uses the application's signed handshake and encrypted transport.

Capsi is intentionally not a cloud collaboration platform. The workplace layer is also designed to operate directly between trusted devices rather than introducing a central organization server.

## Platforms

The application is built from one shared Flutter UI with a shared Rust core:

The local peer TCP service uses port **45892** by default. The UDP discovery socket uses port **45893** by default; discovery beacons advertise the TCP service port so a discovered device can be contacted directly for messages and files.

- Windows
- Android
- macOS
- iOS

**Current release focus:** Windows.

Flutter owns the product interface and platform UX. Rust provides the shared
networking, identity, discovery, encryption, storage, messaging and file-transfer
behavior through a C-compatible FFI bridge.

## Architecture

```text
                 CAPSI
                   │
          ┌────────┴────────┐
          │                 │
       Flutter          Rust core
        UI/UX           capsi-core
          │                 │
          └────── FFI ──────┘
                   │
        Windows / Android /
          macOS / iOS
```

The former HTML/CSS/JavaScript frontend and Tauri application shell have been
retired. New application UI belongs in `Capsi/flutter`.

Product behavior belongs in `crates/capsi-core` where possible. The native
bridge in `Capsi/flutter/native` exposes that behavior to Flutter without
reimplementing networking or security logic in Dart.

## Website

The official website is:

**https://capsi.win**

Run the website locally:

```powershell
cd Website
python -m http.server 8080
```

Then open `http://localhost:8080/`.

The website and application intentionally share the same product identity: Capsi, its dark utility-oriented visual language, restrained green accent, terminology, and icon style. The website is a React/Vite product presentation; the application is the working utility.

## Windows development

From `Capsi/flutter`:

```powershell
flutter pub get
flutter run -d windows
```

For a release build:

```powershell
.\tool\build_windows.ps1
```

The native bridge is built from `Capsi/flutter/native` and the resulting
`capsi_ffi.dll` is placed beside the Flutter executable.

## Android development

Build the release APK with the script that also cross-compiles the Rust bridge:

```powershell
cd Capsi/flutter
.\tool\build_android.ps1
```

or from `Capsi`:

```batch
build-android.bat
```

The script generates the Flutter Android runner when it is missing, applies the
Capsi application id and the `INTERNET` permission that a release build needs,
builds `libcapsi_ffi.so` for `arm64-v8a`, `armeabi-v7a` and `x86_64` with
`cargo-ndk`, drops them into `android/app/src/main/jniLibs/`, and runs
`flutter build apk --release`.

The Android build uses the same Flutter UI and Rust FFI architecture. Real-device
validation is still required before treating Android support as production-ready.

## macOS and iOS development

Generate the Apple platform runners when needed:

```powershell
cd Capsi/flutter
flutter create --platforms=macos,ios .
flutter pub get
```

Build macOS locally:

```powershell
flutter build macos --release
```

Build iOS without code signing:

```powershell
flutter build ios --release --no-codesign
```

GitHub Actions verifies both Apple Flutter runners in clean macOS environments.
The macOS release pipeline bundles the Rust FFI library inside the app's
Contents/Frameworks directory and publishes the packaged app as a CI artifact.

The iOS pipeline configures the generated Runner before synchronizing CocoaPods,
then builds with dependency resolution disabled so Flutter does not rewrite the
Podfile after the lockfile has been synchronized. It links the Rust device library
using `tool/link_ios_rust.sh` and verifies the native bridge is linked into the
iOS application; real-device communication and simulator runtime behavior still
require platform-specific validation before release.

Apple local-network metadata is configured during the generated-platform CI build. The iOS runner receives `NSLocalNetworkUsageDescription`; because Capsi uses UDP broadcast for discovery, a physical iOS release also requires Apple's `com.apple.developer.networking.multicast` entitlement. That entitlement is intentionally not fabricated by CI and must be provisioned before claiming physical-device iOS discovery support. macOS receives the local-network usage description plus sandbox client/server network entitlements.

## Cross-platform interface principles

Capsi uses one product identity across platforms, but the layout should respect the device.

### Desktop

The desktop interface can use the larger navigation/sidebar and conversation workspace.

### Mobile

The mobile interface uses touch-sized controls, adaptive navigation, safe-area handling, and full-screen conversation views rather than shrinking the desktop layout into a phone-sized viewport.

### Tablet

Tablet layouts should sit between the desktop and phone experiences, using the same components and visual system.

The goal is **one Capsi, adapted to the device**, not four unrelated applications.

## Current implementation status

### Implemented in source

- Device identity and fingerprinting.
- Local network discovery.
- Trusted-device management.
- Signed peer handshake.
- Encrypted direct transport.
- One-to-one messaging.
- Local conversation history.
- Direct file-transfer protocol.
- File integrity verification.
- Transfer cancellation and contiguous-prefix resume support.
- Offline delivery queue.
- Automatic delivery retry.
- Delivery acknowledgements.
- Idempotent message delivery.
- Workplace creation and local membership model.
- Workplace people, roles, permissions, groups, and departments.
- Workplace broadcasts.
- Workplace conversations.
- Direct workplace synchronization between trusted devices.
- Shared responsive Flutter application UI.
- Flutter startup/runtime handling.
- Android CI build path.
- macOS Rust FFI bundle path and packaged release artifact.
- iOS Rust FFI linkage in the CI-generated Runner.

### Automated verification

GitHub Actions now checks every push and pull request to `main` with:

- Rust core tests (`cargo test -p capsi-core`).
- Flutter dependency resolution, static analysis, and widget tests.
- Android release APK build with Rust libraries for arm64-v8a, armeabi-v7a, and x86_64.
- Windows release build using the checked-in PowerShell build script.
- macOS release build with a bundled universal Rust FFI library.
- iOS release build with the Rust FFI static library linked into the generated Runner.

The CI build verifies that the source can compile in a clean environment and packages release artifacts. It does not replace real-device network and installation testing.

### Still requires real-device validation

Source implementation is not the same as production validation. The following must be tested with actual installations:

The concrete, evidence-based procedure for all of these — with exact commands, success criteria, failure indicators, and the evidence to capture — is **[`docs/release-verification-plan.md`](docs/release-verification-plan.md)**.

- Windows ↔ Windows communication.
- Windows ↔ Android communication.
- Android ↔ Android communication.
- macOS and iOS compatibility.
- Network changes and reconnects.
- Hotspot and Wi-Fi isolation behavior.
- Firewall behavior.
- Sleeping/waking devices.
- Large and concurrent file transfers.
- Interrupted transfer recovery.
- Workplace synchronization conflicts.
- Mobile lifecycle/background behavior.
- Performance and battery behavior on mobile.

## What Capsi does not introduce

Capsi does not require a central cloud workspace for its local communication model.

The project should not add a cloud account system, organization server, or centralized workplace administration layer merely to make peer-to-peer synchronization easier. Such additions would change the product's local-first architecture and philosophy.

## Development principles

1. **Keep it useful.** Avoid features that exist only to make the product look bigger.
2. **Keep it local-first.** Do not introduce cloud infrastructure where direct communication is sufficient.
3. **Keep the interface consistent.** Website and application should clearly belong to the same product.
4. **Share the core.** Platform differences should live at the native boundary whenever possible.
5. **Adapt the UI, not the identity.** Desktop, tablet, and mobile can have different layouts without becoming different products.
6. **Verify before claiming.** Source implementation, CI success, and real-device behavior are separate things.
7. **Do not invent capabilities.** Documentation should describe what the current code actually implements or clearly mark what still needs validation.

## License

See the repository license and individual project files for licensing information.
