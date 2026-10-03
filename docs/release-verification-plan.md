# Capsi Release-Candidate Verification Plan

**Product:** Capsi by CAPSICOM — "Download. Run. Connect."
**Candidate:** `1.1.0` (Flutter `pubspec.yaml` version `1.1.0+2`; Rust workspace `1.1.0`)
**Protocol:** `capsi/1`
**Platforms in scope:** Windows (x64) and Android
**Platforms explicitly out of scope:** iOS, macOS, Linux — `Capsi/flutter` contains no
`ios/`, `macos/` or `linux/` runner, and `CapsiNative.tryLoad()` returns `null` on every
platform other than Windows and Android.

This document is the operating procedure for taking the current `main` build to a
release candidate: what to run, what a pass looks like, what a failure looks like, and
what evidence has to exist afterwards.

---

## 1. How to read this document

### 1.1 Evidence rule

Every claim in this plan is either (a) a **fact audited from the repository** and cited
with `path:line`, or (b) a **procedure to be executed**. Nothing is asserted from memory.
Where the repository does not prove something, the plan says so and makes it a
verification step instead of an assumption.

Two rules follow from that, and both are non-negotiable for sign-off:

1. **No step is "passed" without captured evidence.** A green command with no log, no
   screenshot, or no artifact listing is not a pass.
2. **A claim that contradicts the running artifact is a bug, not a wording problem.** The
   UI is only allowed to say "Ready" when the engine proved it
   (`Capsi/flutter/lib/main.dart:371`).

### 1.2 Automated vs manual

| Class | Meaning | Where it runs |
|---|---|---|
| **A — Automated** | Deterministic command with an exit code and a log. Must pass in CI and locally. | Phases P1–P3 |
| **B — Semi-automated** | Script plus human judgement of an artifact or a file listing. | Phases P0, P4 |
| **C — Manual** | Two physical devices, human at the keyboard. **Out of CI automation scope by design.** | Phases P5–P6 |

Phase P5's Windows-to-Windows run and all of P6 are **Class C**. They cannot be
automated by anything in this repository today, and the plan marks them so that a green
CI run is never mistaken for a verified product.

### 1.3 Shell constraint that affects every procedure

This environment runs Windows PowerShell, and **PowerShell aborts a script when a native
executable writes to stderr** — even when the executable succeeded. `cargo` and `flutter`
both do this routinely (progress bars, "Building..." lines).

Every command in this plan therefore follows the pattern already used by
`Capsi/scripts/check-backend.bat`: redirect the native tool's output to a log file and
read the log afterwards.

```powershell
# Canonical pattern used throughout this plan.
$log = "$env:TEMP\capsi_rc_<step>.log"
Start-Process -FilePath cmd.exe `
  -ArgumentList '/c', "<command> 1> `"$log`" 2>&1" `
  -WorkingDirectory <dir> -Wait -NoNewWindow
Get-Content $log
```

A bare `& cargo ...` or `& flutter ...` in a PowerShell script is a latent bug. Do not
introduce one.

### 1.4 Environment baseline observed on this machine

| Item | Observed value |
|---|---|
| Flutter SDK location | `D:\flutter` exists |
| `flutter` on `PATH` | **No** — not resolvable in a default PowerShell session. Add `D:\flutter\bin` to `PATH` before running any `tool/*.ps1` script. |
| `cargo` | `C:\Users\Christiana\.cargo\bin\cargo.exe` |
| `cargo-ndk` | `C:\Users\Christiana\.cargo\bin\cargo-ndk.exe` (required for Android, `Capsi/flutter/tool/build_android.ps1:27`) |
| Repository root | `D:\Capsi` (contains `README.md`, `Website/`, `scripts/`, `.github/`, `Capsi/`) |
| Flutter project root | `D:\Capsi\Capsi\flutter` |
| Rust workspace root | `D:\Capsi\Capsi` (`Cargo.toml`, members = `crates/capsi-core`) |
| Git HEAD at time of writing | `2dd683e8` (merge), including `b46f823a` "Add self-test functionality and reporting to Capsi" |

**Path caveat.** Two directories exist: `D:\Capsi` (git root, docs, website) and
`D:\Capsi\Capsi` (product code). Every path in this plan is spelled in full so the
distinction cannot be lost.

---
## 2. Verified baseline (audited from `main`)

These are the facts the rest of the plan depends on. Each one was read out of the
repository, not inferred.

### 2.1 Protocol and constants

| Fact | Value | Source |
|---|---|---|
| Protocol version | `capsi/1` | `Capsi/crates/capsi-core/src/lib.rs:23` |
| Discovery port (UDP broadcast) | `45893` | `Capsi/crates/capsi-core/src/lib.rs:24` |
| TCP service port (messages + files) | `45892` | `Capsi/crates/capsi-core/src/lib.rs:25` |
| Discovery announce interval | 5 s | `Capsi/crates/capsi-core/src/lib.rs:26` |
| Peer timeout | 20 s | `Capsi/crates/capsi-core/src/lib.rs:27` |
| File transfer chunk size | 256 KiB | `Capsi/crates/capsi-core/src/lib.rs:28` |
| Max text message size | 64 KiB | `Capsi/crates/capsi-core/src/lib.rs:29` |
| File size field | 64-bit, **no application-level total cap** by design | `lib.rs:6-9` |
| Release profile | `lto`, `codegen-units=1`, `opt-level="s"`, `panic="abort"`, `strip` | `Capsi/Cargo.toml` |
| Rust workspace members | `crates/capsi-core` only | `Capsi/Cargo.toml` |

### 2.2 The startup self-check (the product's own gate)

`capsi_self_test` is exported from `Capsi/flutter/native/src/lib.rs:2001` and returns a
JSON object `{ ok, runtime, protocol, steps[] }`. It runs **six** steps, in this order,
and the order is asserted by a unit test at `Capsi/flutter/native/src/lib.rs:2235`:

| # | Step name | What it actually does |
|---|---|---|
| 1 | `core_linked` | A real Ed25519 signing round-trip through `capsi-core` (`:2018`) |
| 2 | `protocol` | Reports `capsi/1` (`:2028`) |
| 3 | `storage` | Creates the data dir, round-trips a write, opens `TrustStore` and `MessageStore` (`:2035-2049`) |
| 4 | `identity` | Loads or creates the device identity; reports id + fingerprint (`:2060`) |
| 5 | `network_listener` | **Really binds** TCP service port (`:2077`) |
| 6 | `discovery` | **Really binds** the UDP socket via `Discovery::bind` (`:2095-2099`) |

Any step that fails makes the whole report `ok: false` (`:2081`).

### 2.3 The truth states the UI is allowed to show

`engineOperational` is defined once, at `Capsi/flutter/lib/main.dart:371-375`:

```
native != null  &&  (selfTestReport?.ok ?? false)  &&  discoveryHandle != 0  &&  messageHandle != 0
```

From that, the shell badge has exactly three states (`main.dart:1613-1626`):

| Condition | Badge | Tooltip |
|---|---|---|
| library did not load | `Unavailable` | "Capsi did not load its native engine on this device." |
| `engineOperational == true` | `Ready` | "The engine checked itself and is listening for devices." |
| library loaded but not operational | `Limited` | "Capsi is running, but not everything it needs is working. Open Settings for the startup check." |

Supporting behaviour that must be preserved:

- A failed self-check step is a **refusal to start**, not a warning (`main.dart:461-470`),
  and the reason is listed per failing step (`main.dart:514-521`).
- A self-check pass followed by a **zero listener handle** is a distinct, separately
  reported failure — "Another copy of Capsi may already be running on this port."
  (`main.dart:484-492`).
- The FFI `{"error": ...}` envelope is parsed into a **failed `self_test` step carrying
### 2.4 Native artifact loading

`CapsiNative.tryLoad()` (`Capsi/flutter/lib/capsi_native.dart:329-359`):

- Windows → opens `capsi_ffi.dll` (expected beside `capsi.exe`).
- Android → opens `libcapsi_ffi.so` (packaged under `jniLibs/<abi>/`).
- Every other platform → returns `null`, which is the honest `Unavailable` outcome.

The Dart layer looks up these symbols (`capsi_native.dart:249-283`); a missing symbol
throws and yields `null` from `tryLoad`:

`capsi_runtime_version`, `capsi_core_linked`, `capsi_protocol_version`,
`capsi_service_port`, `capsi_self_test`, `capsi_discovery_probe`,
`capsi_discovery_start`, `capsi_discovery_poll`, `capsi_discovery_stop`,
`capsi_trust_list`, `capsi_trust_accept`, `capsi_trust_ignore`,
`capsi_message_start`, `capsi_message_poll`, `capsi_message_stop`, `capsi_message_send`,
`capsi_conversations_list`, `capsi_conversation_load`,
`capsi_file_send`, `capsi_file_accept`, `capsi_file_decline`, `capsi_file_cancel`,
`capsi_workplace_load`, `capsi_workplace_create`, `capsi_workplace_create_group`,
`capsi_workplace_create_department`, `capsi_workplace_create_broadcast`,
`capsi_workplace_send_message`, `capsi_workplace_add_group_member`,
`capsi_workplace_remove_group_member`, `capsi_workplace_move_group_member`,
`capsi_workplace_set_member_role`, `capsi_workplace_rename`, `capsi_workplace_delete`,
`capsi_free_string`.

Note the plural in `capsi_conversations_list` — it is easy to "fix" into a symbol that
does not exist.

### 2.5 File-transfer integrity and state model

| Fact | Source |
|---|---|
| Whole-file digest is BLAKE2b-256, hex-encoded (64 chars), carried in `FileOffer.digest` | `crates/capsi-core/src/protocol/message.rs:39-47`, `util.rs:26-32` |
| Each chunk carries its own digest of its raw bytes | `message.rs:157`, test at `:297` |
| `FileReceipt` success means "Every chunk arrived and the digest matched." | `message.rs:55-60` |
| Files are hashed incrementally (`digest_file`), never loaded whole into memory | `util.rs:35-47` |
| Transfer states: `Offered`, `Transferring`, `Complete`, `Declined`, `Failed`, `Cancelled` | `crates/capsi-core/src/storage/conversation.rs:37` |

### 2.6 Windows platform facts

| Fact | Source |
|---|---|
| Binary name `capsi`; static C runtime via `/MT` replacing CMake's `/MD` for **all** configs | `flutter/windows/CMakeLists.txt:7`, `:55-69` |
| The Rust bridge is built with `+crt-static` for the same reason | comment at `CMakeLists.txt:35-54`, `tool/build_windows.ps1` |
| `build_windows.ps1` **re-reads every `.exe`/`.dll` in the bundle** and **throws** if `MSVCP140` or `VCRUNTIME140` appears | `tool/build_windows.ps1:195-208` |
| Runner + plugins are `cxx_std_17`, `/W4 /WX` | `CMakeLists.txt:76-82` |
| Installer is WiX **3.14.1**, pinned by SHA-256 `6AC824E1…43D31` | `tool/build_windows_installer.ps1:39-43` |
| MSI `UpgradeCode` is frozen at `{4F9B7C3E-2A61-4E88-9C3D-B5A1E7D0F2C4}` | `build_windows_installer.ps1:35-37` |
| MSI version is read from `pubspec.yaml` | `build_windows_installer.ps1:45-53` |
| Installer firewall ports are read from `crates/capsi-core/src/lib.rs`, not hard-coded | `build_windows_installer.ps1:55-71` |
| The build **reads the built MSI back** and asserts Publisher/Product/Version/Website, and requires **≥ 2 `WixFirewallException` rows** | `build_windows_installer.ps1:429-457` |
| Tray icon + balloon notifications implemented in the runner | `flutter/windows/runner/flutter_window.cpp:147-213` |
| Platform channel `win.capsi.app/platform`; methods `notify`, `setNotificationsEnabled` | `flutter_window.cpp:90-140`, `lib/main.dart:1413` |
| Window title `Capsi`, default 1280×720 | `flutter/windows/runner/main.cpp:29-30` |

### 2.7 Android platform facts

| Fact | Source |
|---|---|
| ABIs built: `arm64-v8a`, `armeabi-v7a`, `x86_64` | `tool/build_android.ps1:16` |
| Output `android/app/src/main/jniLibs/<abi>/libcapsi_ffi.so`; script **throws if any ABI is missing** before running `flutter build apk --release` | `build_android.ps1:56-64` |
| APK output path | `build/app/outputs/flutter-apk/app-release.apk` |
| Application id `win.capsi.app` | `android/app/build.gradle*:19` |
| `compileSdk`/`minSdk`/`targetSdk`/`ndkVersion` all come from Flutter defaults (`flutter.*`) — **not pinned in this repo** | `build.gradle*:9,10,22,23` |
| Permissions: `INTERNET`, `ACCESS_NETWORK_STATE`, `CHANGE_WIFI_MULTICAST_STATE`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS` | `android/app/src/main/AndroidManifest.xml:4-22` |
| `.MessageListenerService` declared `foregroundServiceType="dataSync"`, `exported="false"` | `AndroidManifest.xml:51-54` |
| HTTPS `VIEW` intent declared in `<queries>` so the About link resolves on Android 11+ | `AndroidManifest.xml:71-77` |
| `POST_NOTIFICATIONS` requested at runtime on API 33+ | `MainActivity.kt:168-175` |
| `WifiManager.MulticastLock` acquired so UDP broadcast discovery is received | `MainActivity.kt:202-217`; rationale at `AndroidManifest.xml:6-11` |
| `notify()` reports failure rather than claiming success when notifications are blocked/denied | `MainActivity.kt:94-98` |
| jniLibs for all three ABIs **already present** in the working tree | `flutter/android/app/src/main/jniLibs/*/libcapsi_ffi.so` |

### 2.8 Duplicate / legacy artifacts found during the audit

| Finding | Evidence |
|---|---|
| `Capsi/scripts/check-backend.bat` does `cd /d "d:\Capsi\Capsi\src-tauri"` — **that directory does not exist** (`Test-Path` → `False`); the Tauri client was retired | `Capsi/scripts/check-backend.bat:6`, `Capsi/flutter/README.md:13-15` |
| Tauri-era tooling still present: `install-rc-preproc.bat`, `rc-preproc/main.rs`, `setup-gnu-target.bat` | listing of `Capsi/scripts` |
| Root `README.md:122` still documents "macOS and iOS development" although `Capsi/flutter` has no `ios/` or `macos/` runner | `README.md:122`, `Capsi/flutter` listing |
| Editor workspace metadata reported HEAD `5637a247`; actual `git log` HEAD is `2dd683e8` | `git log --oneline -8` |

---
## 3. What CI already proves — and what it does not

`D:\Capsi\.github\workflows\ci.yml` has five jobs. Four of them touch this release
candidate.

| CI job | What it actually runs | Verdict for this RC |
|---|---|---|
| `rust` (`ci.yml:14-25`) | `cargo test -p capsi-core` on `ubuntu-latest`, cwd `Capsi` | **Gate.** Covers the platform-independent core on Linux only. |
| `flutter` (`ci.yml:27-45`) | `flutter pub get`, `flutter analyze`, `flutter test` | **Gate.** Lints and widget tests. |
| `android` (`ci.yml:47-74`) | Installs the three android Rust targets + `cargo-ndk`, runs `bash ./tool/build_android.sh`, uploads `app-release.apk` | **Gate + artifact.** Uses the **bash** variant, not the PowerShell one used locally. |
| `windows` (`ci.yml:187-214`) | `.\tool\build_windows.ps1` (which also builds the MSI), then `Compress-Archive build\windows\x64\runner\Release\*` and uploads that zip | **Gate, but the wrong artifact.** See gap G3 below. |
| `macos`, `ios` (`ci.yml:76-185`) | Generate runners with `flutter create`, cross-compile Rust, sign with an ad-hoc identity | **Out of scope for this RC.** These platforms have no runner in the repository and no real-device validation; a red result here is not an RC blocker, but a red result must still be explained in the release notes. |

### 3.1 Gaps CI does not close

| ID | Gap | Why it matters |
|---|---|---|
| **G1** | No CI step **loads** `capsi_ffi.dll` / `libcapsi_ffi.so` and calls `capsi_self_test`. CI proves the files were produced and copied; it never proves the symbols resolve or the six steps pass on the target. | A DLL that links but cannot be `dlopen`ed ships a `Limited`/`Unavailable` badge on every machine. This is exactly the failure the self-check exists to catch. |
| **G2** | No CI step runs the app. `flutter test` is widget tests only (`Capsi/flutter/test/widget_test.dart`, `self_test_report_test.dart`); `flutter run -d windows` is never invoked. | The gate logic in `_initializeRuntime()` (`main.dart:416-507`) is only covered by unit tests, never by a live engine. |
| **G3** | The `windows` job uploads `build\windows\x64\runner\Release\*` — **the bare bundle** — and never uploads `build\Capsi-<version>-x64.msi`. Confirmed by `tool/build_windows_installer.ps1:227,386`, where the MSI is written to `build\`. | **The artifact that actually ships (the MSI) is not preserved by CI.** Local evidence: `build\Capsi-1.0.2-x64.msi` and `build\Capsi-1.1.0-x64.msi` both exist — one stale. Nobody can tell from CI which installer was tested. |
| **G4** | macOS and iOS jobs generate runners with `flutter create` at build time. | Those jobs can go red for reasons unrelated to Windows/Android. Keep them out of the RC gate to avoid a false blocker. |
| **G5** | Android `minSdk`/`targetSdk`/`compileSdk`/`ndkVersion` are **not pinned** in this repository (`android/app/build.gradle*:9,10,22,23` all read `flutter.*`). | The APK's OS floor and NDK come from whatever Flutter version the runner has. Two CI runs months apart can produce different minimum OS versions with no diff in this repo. Record them at candidate time (Phase P3). |
| **G6** | Nothing verifies the **install** of the MSI (firewall rules applying, shortcuts, Add/Remove Programs entry) on a clean machine. The build script verifies the MSI *declares* ≥ 2 `WixFirewallException` rows (`build_windows_installer.ps1:447-457`) — a strong static check, but not an install. | A declared rule that fails to apply leaves a product that looks fine and is undiscoverable on the LAN. Manual — Phase P4. |

---


  the engine's own reason**, so the gate can always name a cause
  (`Capsi/flutter/lib/capsi_native.dart:208-227`).
- Settings exposes a **Startup check** section that renders the engine's steps verbatim
  (`main.dart:1185-1198`), with human labels mapped at `main.dart:148-156`.


## 4. Phase map

Eight phases. `P0`–`P3` are automated and must be re-run on the exact commit that ships;
`P4`–`P7` are the manual gates that turn a build into a release candidate.

| Phase | Name | Class | Gate type | Est. effort |
|---|---|---|---|---|
| **P0** | Environment and candidate freeze | B | Record, do not pass/fail | 30 min |
| **P1** | Automated gate: core + Dart | A | Hard stop | 15 min |
| **P2** | Windows artifact integrity | A | Hard stop | 45 min |
| **P3** | Android artifact integrity | A | Hard stop | 45 min |
| **P4** | Install and first-run truth states | B | Hard stop | 60 min per platform |
| **P5** | Two-device connectivity matrices | C | Hard stop | 2–3 h |
| **P6** | File transfer: integrity, resume, cancellation | C | Hard stop | 2–3 h |
| **P7** | RC sign-off and evidence bundle | B | Release gate | 60 min |

### 4.1 Dependency graph

```
P0  candidate freeze (commit hash, versions, artifact list)
 |
 +--> P1  automated gate  ---------+
 |        cargo test -p capsi-core |
 |        flutter analyze / test   |
 |                                 |
 +--> P2  Windows artifacts        +--> P4  install + first run (Win)
 |        (bundle, MSI, DLL)  -----+        badge truth states
 |                                 |
 +--> P3  Android artifacts  ------+--> P4b install + first run (Android)
 |        (APK, ABIs, manifest)    |
 |                                 |
 +---------------------------------+--> P5  two-device matrices
                                          (Win-Win / Android-Android / Win-Android)
                                           |
                                           +--> P6  file transfer integrity
                                                   (hash, resume, cancel, large file)
                                                     |
                                                     +--> P7  RC sign-off
```

Rules that the graph encodes:

- **P2 and P3 must run after P1.** A bundle built from a tree that fails `cargo test` is
  not a candidate, however green the build log looks.
- **P4 depends on P2/P3.** Do not install an MSI whose bundle you have not verified.
- **P6 depends on P5.** A transfer test on a pair that cannot exchange a text message
  measures the wrong thing.
- **P1–P3 are re-runnable and cheap.** Re-run them after every change; re-run P4–P6 only
  after a change that touches what they cover.

---

## 5. Phase detail

### P0 — Environment and candidate freeze

**Class B · no pass/fail, but nothing downstream is trustworthy without it.**

#### Objective
Record exactly *what* is being tested, on *what* toolchain, from *which* commit. Every
later phase cites these values, so ambiguity here becomes an unanswerable question at
sign-off.

#### Preconditions
- Working tree clean except for known untracked files. Observed at audit time:
  `git status --porcelain` → `?? mdlist.txt` only.
- Flutter SDK reachable. `D:\flutter` exists but **`flutter` is not on `PATH`** in a
  default PowerShell session; prepend it before running any `tool\*.ps1` script:

```powershell
$env:PATH = 'D:\flutter\bin;C:\Users\Christiana\.cargo\bin;' + $env:PATH
```

#### Procedure

1. **Freeze the commit hash.**

```powershell
git -C D:\Capsi rev-parse HEAD
git -C D:\Capsi status --porcelain
```

2. **Record toolchain versions** (log-capture pattern from §1.3):

```powershell
$log = "$env:TEMP\capsi_rc_versions.log"
Start-Process cmd.exe -ArgumentList '/c', "flutter --version 1> `"$log`" 2>&1 & cargo --version 1>> `"$log`" 2>&1 & cargo ndk --version 1>> `"$log`" 2>&1 & rustc -Vv 1>> `"$log`" 2>&1" -Wait -NoNewWindow
Get-Content $log
```

Also record the Android side, because it is **not pinned in this repository**
(`android/app/build.gradle*:9,10,22,23` read `flutter.*`):

```powershell
$log = "$env:TEMP\capsi_rc_doctor.log"
Start-Process cmd.exe -ArgumentList '/c', "flutter doctor -v 1> `"$log`" 2>&1" -Wait -NoNewWindow
Get-Content $log   # capture: Android SDK version, NDK version, Java version
```

3. **Record the version string** the candidate will claim:

```powershell
Select-String -Path D:\Capsi\Capsi\flutter\pubspec.yaml -Pattern '^version:'
Select-String -Path D:\Capsi\Capsi\Cargo.toml -Pattern '^version'
```

Expected: `version: 1.1.0+2` and workspace `version = "1.1.0"`. **These must agree.** The
MSI version is read from `pubspec.yaml` (`build_windows_installer.ps1:45-53`) but the
DLL's reported runtime version comes from `CARGO_PKG_VERSION`
(`Capsi/flutter/native/src/lib.rs:2084`). A mismatch makes the Windows About surface and
the MSI disagree — record both.

4. **Inventory the artifacts already on disk** so a stale file cannot be mistaken for a
   new one. **Delete stale artifacts first**; `build\Capsi-1.0.2-x64.msi` was left over
   from a previous version at audit time.

```powershell
Get-ChildItem D:\Capsi\Capsi\flutter\build -Recurse -Include '*.msi','*.apk','*.zip' -File |
  Select-Object FullName, Length, LastWriteTime
Get-ChildItem D:\Capsi\Capsi\flutter\android\app\src\main\jniLibs -Recurse -File |
  Select-Object FullName, Length
Get-ChildItem D:\Capsi\Capsi\flutter\build\windows\x64\runner\Release -File |
  Select-Object Name, Length
```

#### Success criteria
- [ ] Commit hash recorded and unchanged for the rest of the run.
- [ ] `pubspec.yaml` version == `Cargo.toml` workspace version == `1.1.0+2` / `1.1.0`.
- [ ] Flutter, Rust, `cargo-ndk`, Android SDK and NDK versions captured.
- [ ] Every artifact in `build\` predates the freeze, or has been deleted.
- [ ] Windows Release bundle contains: `capsi.exe`, `capsi_ffi.dll`,
      `flutter_windows.dll`, `native_assets.json`, and the plugin DLLs
      (`file_selector_windows_plugin.dll`, `url_launcher_windows_plugin.dll`).
      Composition verified at audit time.

#### Failure indicators

| Symptom | Likely cause | Action |
|---|---|---|
| `flutter` not found when a `tool\*.ps1` runs | `PATH` lacks `D:\flutter\bin` | Fix `$env:PATH`; do not "fix" it by copying binaries around |
| Two MSI files with different versions in `build\` | Previous release never cleaned | Delete both; rebuild; the version in the filename must match `pubspec.yaml` |
| `pubspec.yaml` ≠ `Cargo.toml` version | Version bumped in one place | Run `Capsi/scripts/bump-version.ps1`; re-freeze |
| `jniLibs` has only one or two ABIs | A previous `cargo-ndk` run partially failed | Delete `jniLibs\*` and rebuild with `tool\build_android.ps1`; it throws if any ABI is missing (`build_android.ps1:56-61`) |

#### Evidence
`p0-versions.log`, `p0-doctor.log`, `p0-artifacts.txt`, the freeze commit hash.

---

### P1 — Automated gate: core and Dart

**Class A · hard stop. Nothing downstream runs until this is green.**

#### Objective
Prove the platform-independent core and the Dart UI layer are sound **on this exact
commit**, using the same commands CI uses (`ci.yml:25`, `ci.yml:41-45`).

#### Procedure

1. **Core tests.** Use the repository's own wrapper, which handles the MSVC-vs-GNU
   toolchain choice (`Capsi/scripts/test-core.ps1`):

```powershell
$log = "$env:TEMP\capsi_rc_core.log"
Start-Process cmd.exe -ArgumentList '/c', "powershell -ExecutionPolicy Bypass -File D:\Capsi\Capsi\scripts\test-core.ps1 1> `"$log`" 2>&1" -Wait -NoNewWindow
Get-Content $log
```

The script prepends `%USERPROFILE%\.cargo\bin` itself (`test-core.ps1:21`), so it does not
depend on the caller's `PATH`.

2. **Dart static analysis.**

```powershell
$log = "$env:TEMP\capsi_rc_analyze.log"
Start-Process cmd.exe -ArgumentList '/c', "flutter analyze 1> `"$log`" 2>&1" -WorkingDirectory "D:\Capsi\Capsi\flutter" -Wait -NoNewWindow
Get-Content $log
```

3. **Dart tests.**

```powershell
$log = "$env:TEMP\capsi_rc_fluttertest.log"
Start-Process cmd.exe -ArgumentList '/c', "flutter pub get 1> `"$log`" 2>&1 & flutter test 1>> `"$log`" 2>&1" -WorkingDirectory "D:\Capsi\Capsi\flutter" -Wait -NoNewWindow
Get-Content $log
```

4. **Confirm the self-check contract is covered by a test.** The one behaviour that makes
   the startup gate legible to a user is the FFI `{"error": ...}` envelope becoming a
   failed `self_test` step carrying the engine's reason (`capsi_native.dart:208-227`).
   Confirm an assertion for it exists in
   `Capsi/flutter/test/self_test_report_test.dart`; if it is missing, add it before
   sign-off, because that path is otherwise untested.

5. **Reachability screen (defensive).** `Capsi/scripts/check-backend.bat` targets
   `d:\Capsi\Capsi\src-tauri`, which does not exist. Running it "to be safe" is what
   makes a stale script look like a failing gate. If it is still present at RC time,
   either delete it or note in the release notes that it is retired Tauri tooling.

#### Success criteria
- [ ] `cargo test -p capsi-core` exits `0`.
- [ ] `flutter analyze` → "No issues found".
- [ ] `flutter test` → all tests pass, `0` failures.
- [ ] A test asserts `CapsiSelfTestReport.fromJson({'error': ...})` yields `ok == false`
      with exactly one failing step named `self_test`.
- [ ] The core test count and Flutter test count are recorded (they must match or exceed
      the counts from the previous candidate; a drop is a silent deletion of coverage).

#### Failure indicators

| Symptom | Likely cause | Action |
|---|---|---|
| `error: linking with 'link.exe' failed` | No MSVC linker | `test-core.ps1:25-29` falls back to GNU automatically when `link.exe` is absent **and** the GNU toolchain is installed. If neither exists, install one. |
| `error calling dlltool` | mingw-w64 `self-contained` bin dir not on `PATH` | Run `Capsi/scripts/install-gnu-binutils.ps1`, or let the script set `RUSTFLAGS=-C dlltool=D:\Capsi\.toolchain\zig-dlltool.bat` (`test-core.ps1:33-37`) |
| A PowerShell script dies with no output mid-command | The PowerShell/stderr rule (§1.3) | Use the log pattern; never invoke the native tool directly |
| `flutter test` passes but `flutter analyze` warns | Dead code introduced | Remove it. The project's C++ standard is `/W4 /WX` (`windows/CMakeLists.txt:78`); hold Dart to the same bar. |

#### Evidence
`p1-core.log`, `p1-analyze.log`, `p1-fluttertest.log`, plus the reported test counts.

---

### P2 — Windows artifact integrity (x64)

**Class A · hard stop.**

#### Objective
Prove three separate things that a green build log does **not** prove:

1. the bundle is self-contained (no Visual C++ redistributable dependency),
2. `capsi_ffi.dll` actually loads and its six-step self-check actually passes **outside
   Flutter**,
3. the MSI that ships contains the exact binaries that were just verified.

Point 3 exists because CI never uploads the MSI (§3.1, gap **G3**), so the only defence
against shipping a stale installer is to check it locally.

#### Procedure

**Step 1 — Build the bundle and the installer.**

```powershell
$log = "$env:TEMP\capsi_rc_winbuild.log"
Start-Process cmd.exe -ArgumentList '/c', "powershell -ExecutionPolicy Bypass -File .\tool\build_windows.ps1 1> `"$log`" 2>&1" -WorkingDirectory "D:\Capsi\Capsi\flutter" -Wait -NoNewWindow
Get-Content $log
```

`-SkipInstaller` produces the bare bundle only. Use it while iterating, and **always run
the full build (no switch) for the candidate**, because `build_windows.ps1:214-217` is
what invokes `build_windows_installer.ps1`, and the installer is the shipping artifact.

Note the script's own two fallbacks and do not mistake them for passes:

- If vswhere finds the C++ tools but not the workload marker, the script drives CMake
  directly (`build_windows.ps1:68-178`). That is a supported path, but the log then says
  `Building Capsi Windows application with CMake...` instead of using `flutter build`.
  Record which path was taken.
- `-RequireFlutterToolchain` turns the fallback into a failure. Use it when the goal is to
  prove a machine is set up the standard way.

**Step 2 — Self-containment re-check (independent of the build script).**

The build fails hard if it finds the redistributable (`build_windows.ps1:195-208`), so
this is a second, recorded reading rather than a duplicate control:

```powershell
$dir = 'D:\Capsi\Capsi\flutter\build\windows\x64\runner\Release'
Get-ChildItem $dir -File | ForEach-Object {
  $bytes = [IO.File]::ReadAllBytes($_.FullName)
  $text  = [Text.Encoding]::ASCII.GetString($bytes)
  [pscustomobject]@{
    Name        = $_.Name
    Bytes       = $_.Length
    Sha256      = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    Msvcp140    = $text.Contains('MSVCP140')
    Vcruntime140= $text.Contains('VCRUNTIME140')
  }
} | Format-Table -AutoSize
```

**Every row must read `False` for both import names.**

**Step 3 — Architecture check.**

Confirm the executable really is x64. A 32-bit artifact in an x64-named folder is a
failure that only shows up on a customer's machine:

```powershell
function Get-PeMachine([string]$path) {
  $b = [IO.File]::ReadAllBytes($path)
  $peOffset = [BitConverter]::ToInt32($b, 0x3C)
  [BitConverter]::ToUInt16($b, $peOffset + 4)
}
Get-PeMachine "$dir\capsi.exe"      # expect 0x8664 (x64); 0x014C would be x86
Get-PeMachine "$dir\capsi_ffi.dll"  # expect 0x8664
Get-PeMachine "$dir\flutter_windows.dll"  # expect 0x8664
```

**Step 4 — Live FFI probe against the finished DLL.**

This is the check that closes gap **G1**. It loads `capsi_ffi.dll` from the bundle and
calls the same entry points the Dart layer calls, **without Flutter**:

```powershell
$dir    = 'D:\Capsi\Capsi\flutter\build\windows\x64\runner\Release'
$dataDir = Join-Path $env:TEMP 'capsi-rc-probe'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
$env:PATH = "$dir;" + $env:PATH     # so DllImport resolves capsi_ffi.dll from the bundle

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CapsiProbe {
  [DllImport("capsi_ffi.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern IntPtr capsi_runtime_version();
  [DllImport("capsi_ffi.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern int capsi_core_linked();
  [DllImport("capsi_ffi.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern ushort capsi_service_port();
  [DllImport("capsi_ffi.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
  public static extern IntPtr capsi_self_test(string dataDir, string deviceName, ushort tcpPort);
  [DllImport("capsi_ffi.dll", CallingConvention = CallingConvention.Cdecl)]
  public static extern void capsi_free_string(IntPtr p);
}
'@

"Capsi runtime version : " + [Runtime.InteropServices.Marshal]::PtrToStringAnsi([CapsiProbe]::capsi_runtime_version())
"Capsi core linked      : " + [CapsiProbe]::capsi_core_linked()
"Capsi service port     : " + [CapsiProbe]::capsi_service_port()

# tcp_port 0 asks the OS for a free port, exactly as the crate's own test does
# (Capsi/flutter/native/src/lib.rs:2221-2223), so the probe never fights a running Capsi.
$ptr = [CapsiProbe]::capsi_self_test($dataDir, 'RC probe', 0)
$report = [Runtime.InteropServices.Marshal]::PtrToStringAnsi($ptr)
[CapsiProbe]::capsi_free_string($ptr)
$report
```

Expected output, decoded:

- `capsi_runtime_version()` → the crate version, expected `1.1.0` (must match §P0 step 3).
- `capsi_core_linked()` → `1`.
- `capsi_service_port()` → `45892`.
- `capsi_self_test(...)` → a JSON object with `"ok": true`, `"protocol": "capsi/1"`, and
  **six** steps named, in order: `core_linked`, `protocol`, `storage`, `identity`,
  `network_listener`, `discovery`, each with `"ok": true`
  (`Capsi/flutter/native/src/lib.rs:2018-2087`; order asserted at `:2235`).

An equivalent probe was exercised during the audit to confirm the DLL's exported symbols
resolve; re-run it at freeze time and attach the raw JSON. If `Add-Type` is slow or
C# compilation is unavailable in a locked-down environment, the same calls can be made
from a throwaway Dart script using `DynamicLibrary.open('capsi_ffi.dll')` and the
typedefs already written in `Capsi/flutter/lib/capsi_native.dart:6-88`.

**Step 5 — Read the built MSI back (independent of the build script).**

The build already asserts these (`build_windows_installer.ps1:429-457`), but this reading
is what gets attached as evidence, and it can be re-run on an MSI built earlier:

```powershell
$msi = 'D:\Capsi\Capsi\flutter\build\Capsi-1.1.0-x64.msi'

function Get-MsiProperty([string]$Path, [string]$Name) {
  $installer = New-Object -ComObject WindowsInstaller.Installer
  $database  = $installer.GetType().InvokeMember('OpenDatabase','InvokeMethod',$null,$installer,@($Path,0))
  $view      = $database.GetType().InvokeMember('OpenView','InvokeMethod',$null,$database,@("SELECT ``Value`` FROM ``Property`` WHERE ``Property``='$Name'"))
  [void]$view.GetType().InvokeMember('Execute','InvokeMethod',$null,$view,$null)
  $record = $view.GetType().InvokeMember('Fetch','InvokeMethod',$null,$view,$null)
  if ($record) { $record.GetType().InvokeMember('StringData','GetProperty',$null,$record,@(1)) }
}

'ProductName    : ' + (Get-MsiProperty $msi 'ProductName')
'ProductVersion : ' + (Get-MsiProperty $msi 'ProductVersion')
'Manufacturer   : ' + (Get-MsiProperty $msi 'Manufacturer')
'Website (ARP)  : ' + (Get-MsiProperty $msi 'ARPURLINFOABOUT')
'ALLUSERS       : ' + (Get-MsiProperty $msi 'ALLUSERS')
```

Expected, per `build_windows_installer.ps1:23-25`, `:323` and `:429-445`: `Capsi`,
`1.1.0`, `Capsicom`, `https://capsi.win`, and `ALLUSERS = 1`. **`ProductVersion` must
equal the `pubspec.yaml` version**, or the MSI will not be detected as an upgrade of a
previously installed Capsi. `InstallScope="perMachine"` matters because a per-user
install cannot create firewall rules at all.

Then confirm the two firewall exceptions exist and name the right ports:

```powershell
$sql = 'SELECT ``Name`` FROM ``WixFirewallException``'
$installer = New-Object -ComObject WindowsInstaller.Installer
$database  = $installer.GetType().InvokeMember('OpenDatabase','InvokeMethod',$null,$installer,@($msi,0))
$view      = $database.GetType().InvokeMember('OpenView','InvokeMethod',$null,$database,@($sql))
[void]$view.GetType().InvokeMember('Execute','InvokeMethod',$null,$view,$null)
while (($rec = $view.GetType().InvokeMember('Fetch','InvokeMethod',$null,$view,$null))) {
  $rec.GetType().InvokeMember('StringData','GetProperty',$null,$rec,@(1))
}
```

Expected: the two rules the WiX source generates (`build_windows_installer.ps1:279-286`).

| Id | Program | Port | Protocol | Scope | Profile |
|---|---|---|---|---|---|
| `fw_Discovery` | `capsi.exe` | `45893` (from `DISCOVERY_PORT`) | `udp` | `localSubnet` | `all` |
| `fw_Service` | `capsi.exe` | `45892` (from `TCP_SERVICE_PORT`) | `tcp` | `localSubnet` | `all` |

The ports are read out of `Capsi/crates/capsi-core/src/lib.rs` at build time
(`build_windows_installer.ps1:55-71`, `:168-169`). If a rule's port disagrees with §2.1,
the release must not ship: discovery would look permitted while nothing listens.

> **Quoting note (this bites easily).** The `` `` `` pairs in those two snippets are
> PowerShell's escape for a *literal* backtick, which is what MSI SQL needs around table and
> column names. They survive being typed into a `.ps1` file, but they get mangled when the
> snippet is passed through another quoting layer (a shell one-liner, a CI `run:` string, or a
> `Start-Process` argument). If `OpenView` throws a `COMException`, suspect the backticks
> first — run the snippet from a saved script file, or build the query with a literal:
>
> ```powershell
> $bt = [char]96
> $sql = "SELECT ${bt}Name${bt} FROM ${bt}WixFirewallException${bt}"
> ```
>
> Run against the audit MSI, this reports **2** rows, which is the expected value
> (`build_windows_installer.ps1:455-457` refuses anything below 2).

**Step 6 — Prove the MSI ships the binaries that were just tested (closes G3).**

```powershell
$extract = Join-Path $env:TEMP 'capsi-msi-extract'
Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
Start-Process msiexec.exe -ArgumentList '/a', "`"$msi`"", '/qn', "TARGETDIR=`"$extract`"" -Wait
Get-ChildItem $extract -Recurse -Include 'capsi.exe','capsi_ffi.dll' -File |
  ForEach-Object { [pscustomobject]@{ Name=$_.Name; Sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash } }
```

Each hash must **equal** the matching hash recorded in Step 2. If the MSI's `capsi.exe`
differs from the bundle's, a stale installer is about to ship — rebuild it.

**Step 7 — Upgrade continuity.**

The `UpgradeCode` is frozen at `{4F9B7C3E-2A61-4E88-9C3D-B5A1E7D0F2C4}`
(`build_windows_installer.ps1:35-37`) precisely so a new MSI replaces an installed Capsi
instead of installing a second copy beside it. Verify on a machine that already has
`1.0.2` installed:

```powershell
Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\* |
  Where-Object DisplayName -eq 'Capsi' |
  Select-Object DisplayName, DisplayVersion, Publisher, URLInfoAbout
```

Expected after installing the new MSI: **one** Capsi entry with `DisplayVersion 1.1.0`.

#### Success criteria
- [ ] Build produced `build\Capsi-1.1.0-x64.msi`, and no other MSI version remains in `build\`.
- [ ] No `.exe`/`.dll` in the bundle contains `MSVCP140` or `VCRUNTIME140`.
- [ ] `capsi.exe`, `capsi_ffi.dll` and `flutter_windows.dll` are all `0x8664`.
- [ ] The live probe reports runtime `1.1.0`, `core_linked 1`, service port `45892`, and a
      self-check report with `ok: true` and **six** passing steps.
- [ ] MSI declares `Capsi` / `1.1.0` / `Capsicom` / `https://capsi.win`.
- [ ] MSI declares exactly two firewall exceptions: UDP `45893` and TCP `45892`,
      `localSubnet`, `Profile=all`, both scoped to `capsi.exe`.
- [ ] MSI `ALLUSERS = 1`.
- [ ] `capsi.exe` and `capsi_ffi.dll` extracted from the MSI hash-match the verified bundle.
- [ ] Upgrading over `1.0.2` leaves exactly one Add/Remove Programs entry, at `1.1.0`.

#### Failure indicators

| Symptom | Likely cause | Action |
|---|---|---|
| `build_windows.ps1` throws naming `MSVCP140`/`VCRUNTIME140` | A plugin or stale object file compiled with `/MD`; the `/MT` replacement did not reach it | Rebuild from a clean `build\windows` directory. The `/MT` logic is `windows/CMakeLists.txt:55-69`; the flags are inherited through `APPLY_STANDARD_SETTINGS` (`:76-82`). A new plugin that bypasses it is the usual culprit. |
| Probe throws `DllNotFoundException` | `capsi_ffi.dll` missing from the bundle, or a different copy earlier on `PATH` wins | Confirm the file is in `Release\` (copied at `build_windows.ps1:187`) and that `$dir` is prepended to `PATH` |
| Probe's `network_listener` step fails | Something already holds TCP `45892` — typically a running Capsi or a second probe | Close the other instance. The self-check reports a distinct reason for this instead of a generic "not ready" (`main.dart:484-492`). |
| MSI `ProductVersion` ≠ `pubspec.yaml` | MSI built before a version bump | Bump once via `Capsi/scripts/bump-version.ps1`, then rebuild the whole chain |
| Extracted `capsi.exe` hash ≠ bundle hash | Stale MSI from an earlier build | Delete `build\*.msi` and rebuild the installer |
| `WixFirewallException` has 0 rows | `WixFirewallExtension` not passed to candle/light | Do not ship; the build's own check (`build_windows_installer.ps1:447-457`) should already have thrown |
| Two Capsi entries in Add/Remove Programs | `UpgradeCode` changed | Restore the frozen GUID; a changed upgrade code orphans the previous install |

#### Evidence
`p2-winbuild.log`, `p2-bundle-hashes.csv`, `p2-pe-machine.txt`, `p2-ffi-probe.json`
(the raw self-check JSON), `p2-msi-properties.txt`, `p2-msi-firewall.txt`, the MSI itself,
and the Add/Remove Programs reading after upgrade.

---

### P3 — Android artifact integrity

**Class A · hard stop. One finding in this phase is a *release blocker*, not a check.**

#### Objective
Prove the APK actually carries a loadable `libcapsi_ffi.so` for every ABI it claims,
declares every permission the product needs, is **signed with a release key**, and starts
with a truthful badge on a real device.

#### ⚠ Blocker B1 — the release APK is debug-signed

Confirmed in the repository at audit time:

- `Capsi/flutter/android/app/build.gradle.kts:33-36` sets
  `signingConfig = signingConfigs.getByName("debug")` for the `release` build type, with
  the comment "Signing with the debug keys for now, so `flutter run --release` works."
- No `key.properties` exists in `android/` or `android/app/`.
- No `key.properties` reference exists in the Gradle files.

Consequences, in release terms:

1. The APK cannot be published to Google Play. Play rejects an APK signed with the
   standard debug key.
2. **The debug key is public.** Anyone can sign anything with it, and Android will accept
   it as an update to an installed Capsi. This is a supply-chain hole, not a cosmetic gap.
3. The signing identity becomes permanent the moment the first debug-signed build reaches
   a user: switching to a real release key later requires every user to uninstall first.

**Therefore: no Android artifact may be declared a release candidate until the release
`signingConfig` is configured and the APK is verified with `apksigner` (Step 5).**
If the intent for this candidate is an internal/limited distribution, that limitation must
be stated explicitly in the release notes and the risk register (R1), not left implicit.

#### Procedure

**Step 1 — Build the APK.**

```powershell
$log = "$env:TEMP\capsi_rc_androidbuild.log"
Start-Process cmd.exe -ArgumentList '/c', "powershell -ExecutionPolicy Bypass -File .\tool\build_android.ps1 1> `"$log`" 2>&1" -WorkingDirectory "D:\Capsi\Capsi\flutter" -Wait -NoNewWindow
Get-Content $log
```

The script requires `flutter`, `cargo` and `cargo-ndk` (`build_android.ps1:18-29`), builds
all three ABIs with `cargo-ndk`, **throws if any ABI's `.so` is missing**
(`:56-61`), and only then runs `flutter build apk --release` (`:64`). A build that
"succeeded" without that throw is the only acceptable outcome.

**Step 2 — Inspect the APK's native libraries.**

The APK is a ZIP; no Android tooling is needed to list it:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$apk = 'D:\Capsi\Capsi\flutter\build\app\outputs\flutter-apk\app-release.apk'
$zip = [IO.Compression.ZipFile]::OpenRead($apk)
$zip.Entries | Where-Object { $_.FullName -like 'lib/*' } |
  Select-Object FullName, Length, CompressedLength | Sort-Object FullName
$zip.Dispose()
```

Expected **exactly**:

```
lib/arm64-v8a/libcapsi_ffi.so
lib/armeabi-v7a/libcapsi_ffi.so
lib/x86_64/libcapsi_ffi.so
```

Then confirm the APK's copies are the ones just built, not leftovers:

```powershell
Get-ChildItem 'D:\Capsi\Capsi\flutter\android\app\src\main\jniLibs' -Recurse -File |
  ForEach-Object { [pscustomobject]@{ ABI=$_.Directory.Name; Sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash; Bytes=$_.Length } }
```

**Step 3 — Confirm each `.so` is the right machine type.**

An `armeabi-v7a` library built as ARM64 (or an x86_64 library built as ARM) loads on a
desktop emulator and then fails on a real phone:

```powershell
function Get-ElfMachine([string]$path) {
  $b = [IO.File]::ReadAllBytes($path)
  [BitConverter]::ToUInt16($b, 0x12)
}
$root = 'D:\Capsi\Capsi\flutter\android\app\src\main\jniLibs'
'arm64-v8a   -> ' + (Get-ElfMachine "$root\arm64-v8a\libcapsi_ffi.so")    # expect 183 (0xB7, AArch64)
'armeabi-v7a -> ' + (Get-ElfMachine "$root\armeabi-v7a\libcapsi_ffi.so")  # expect 40  (0x28, ARM)
'x86_64      -> ' + (Get-ElfMachine "$root\x86_64\libcapsi_ffi.so")       # expect 62  (0x3E, x86-64)
```

**Step 4 — Verify the packaged manifest.**

Use `aapt2` from the Android SDK build-tools (the SDK path is in the `flutter doctor -v`
output recorded in P0):

```powershell
$bt = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Directory |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
& "$bt\aapt2.exe" dump badging $apk |
  Select-String 'package:|sdkVersion|targetSdkVersion|uses-permission|native-code|application-label'
```

Expected:

- `package: name='win.capsi.app'`
- `native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'` — if an ABI is missing here, an entire
  class of devices gets a `Unavailable` badge with no error.
- `uses-permission` entries for **all six** permissions the manifest declares
  (`AndroidManifest.xml:4-22`):
  `android.permission.INTERNET`, `ACCESS_NETWORK_STATE`,
  `CHANGE_WIFI_MULTICAST_STATE`, `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`.
- `application-label` → `Capsi`.

`INTERNET` deserves special attention: the Flutter template only declares it in the debug
and profile manifests, which is exactly why `tool/configure_android.ps1` moves it into the
main manifest (`Capsi/flutter/README.md:73-81`). **A release APK without `INTERNET` builds
cleanly and can open no socket at all.**

Also record the OS floor, since it is not pinned in this repository (§3.1, gap **G5**):

```powershell
& "$bt\aapt2.exe" dump badging $apk | Select-String 'sdkVersion'
```

**Step 5 — Verify the signature (this is blocker B1's gate).**

```powershell
& "$bt\apksigner.bat" verify --print-certs $apk
```

| Result | Meaning |
|---|---|
| `Signer #1 certificate DN: CN=Android Debug, O=Android, C=US` | **FAIL.** Blocker B1. Not a release artifact. |
| `Signer #1 certificate DN: CN=Capsi…` (the project's release key) | Pass, provided the DN and SHA-256 fingerprint are recorded in the release notes |

Verify the signing scheme too, so the APK installs on the range of Android versions it
claims to support:

```powershell
& "$bt\apksigner.bat" verify -v $apk | Select-String 'Verified using v1|Verified using v2|Verified using v3'
```

**Step 6 — Install, launch, and read the truth states on a device.**

```powershell
adb devices                                   # the target must be listed as "device", not "unauthorized"
adb install -r $apk
adb shell am start -n win.capsi.app/.MainActivity
Start-Sleep -Seconds 8

# 1. The APK's native library directory — proves the right ABI was extracted for this device.
adb shell dumpsys package win.capsi.app | Select-String 'nativeLibraryDir|versionName'

# 2. No fatal crash, and no library-load failure.
adb logcat -d -t 400 | Select-String 'AndroidRuntime|dlopen|cannot locate symbol|capsi'

# 3. The foreground listener service is running (declared android:foregroundServiceType="dataSync").
adb shell dumpsys activity services win.capsi.app | Select-String 'MessageListenerService|isForeground'

# 4. Evidence of what the badge actually said.
adb exec-out screencap -p > "$env:TEMP\capsi_android_boot.png"
```

Then, on the device, open **Settings → Connection** and confirm the Startup check lists
six steps with the labels from `main.dart:148-156`: Self-check is not a step name in the
success path; the six rendered rows are **Engine core, Protocol version, Local storage,
Device identity, Service port, Discovery**, each "Passed."

An `Unavailable` badge means `CapsiNative.tryLoad()` returned `null` — almost always a
missing or unloadable `libcapsi_ffi.so`, which Step 2 and the `dlopen` line in logcat will
show. A `Limited` badge means the library loaded but the self-check or a listener handle
did not; the Startup check section names which.

#### Success criteria
- [ ] `tool\build_android.ps1` completed and produced
      `build\app\outputs\flutter-apk\app-release.apk` (≈56.8 MB at audit time).
- [ ] APK contains exactly the three `lib/<abi>/libcapsi_ffi.so` entries.
- [ ] ELF machine type per ABI: `183` / `40` / `62`.
- [ ] Packaged manifest: `win.capsi.app`, label `Capsi`, all six permissions, and
      `native-code` listing all three ABIs.
- [ ] OS floor (`sdkVersion`/`targetSdkVersion`) recorded, because it is not pinned here.
- [ ] `apksigner verify` succeeds **and** the signer is the release identity, not
      `CN=Android Debug`.
- [ ] On a real device: no `AndroidRuntime` fatal, no `dlopen` failure, `MessageListenerService`
      is running and in the foreground, and the badge reads **Ready** with all six startup
      steps passed.
- [ ] On a second device with a different ABI (e.g. an `armeabi-v7a` phone), the same
      result — this is what proves the ABI matrix, not the emulator.

#### Failure indicators

| Symptom | Likely cause | Action |
|---|---|---|
| Build throws "Expected …libcapsi_ffi.so was not produced" | `cargo-ndk` missing, or the android Rust targets are not installed | Install them: `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android`, plus `cargo install cargo-ndk --locked` (`build_android.ps1:27-29`) |
| APK has only one `lib/<abi>` entry | `flutter build apk` produced an ABI split, or a stale `jniLibs` was pruned | Check the build used `--release` without `--split-per-abi`; re-verify `jniLibs` has all three |
| App starts, badge says `Unavailable` | `libcapsi_ffi.so` failed to load — wrong ABI, or missing symbol | Read `dlopen`/`cannot locate symbol` in logcat; re-check Step 3's ELF machine types |
| Badge says `Limited`, Discovery step failed | UDP broadcast blocked — device on a network with client isolation, or the multicast lock was not acquired | Ensure Wi-Fi (not cellular-only), disable AP isolation; `MainActivity.kt:202-217` acquires the lock best-effort only |
| Badge says `Limited`, Service port step failed | TCP `45892` already in use, or another Capsi instance is running | Force-stop the other instance; the failure is reported per-step, not as a generic error |
| Notifications never appear on Android 13+ | `POST_NOTIFICATIONS` not granted (runtime permission) | Grant it when prompted; `notify()` deliberately reports failure instead of pretending (`MainActivity.kt:94-98`) |
| `apksigner` prints a debug DN | Blocker B1 | Configure a real release `signingConfig` and `key.properties`, keep them out of version control, rebuild, re-run Step 5 |
| `adb install` fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | A previously installed Capsi was signed with a different key | Uninstall the old build once; this is the cost B1 imposed and it is worth stating in the notes |

#### Evidence
`p3-androidbuild.log`, `p3-apk-libs.txt`, `p3-jnilibs-hashes.csv`, `p3-elf-machines.txt`,
`p3-aapt2-badging.txt`, `p3-apksigner.txt`, `p3-logcat.txt`, `p3-dumpsys-service.txt`,
`capsi_android_boot.png`, and the recorded OS floor.

---

### P4 — Install and first-run truth states

**Class B · hard stop. This is where the product's honesty is actually tested.**

#### Objective
Prove that installing the shipping artifacts on a machine that has never seen Capsi
produces a working product **and a badge that always tells the truth** — including when
the engine is broken. The three-state badge (`main.dart:1592-1648`) exists precisely so
that "Ready" can never be shown over a dead listener; this phase verifies that claim by
trying to make it lie.

#### Procedure

##### P4.1 — Windows install on a clean VM

Use a VM (or a machine) with no Visual C++ redistributable installed — that is the whole
point of the static `/MT` build (`CMakeLists.txt:35-54`).

1. **Install** by double-clicking `Capsi-1.1.0-x64.msi`.
2. **Verify the install layout:**

```powershell
Get-ChildItem 'C:\Program Files\Capsi' -Recurse -File | Select-Object FullName, Length
Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\* |
  Where-Object DisplayName -eq 'Capsi' |
  Select-Object DisplayName, DisplayVersion, Publisher, URLInfoAbout, InstallLocation
```

Expected: `Capsi` / `1.1.0` / `Capsicom` / `https://capsi.win`, one entry only.

3. **Verify the firewall rules were actually created** — not merely declared. The MSI
   declares them (`build_windows_installer.ps1:279-286`); Windows has to have applied them:

```powershell
Get-NetFirewallRule -DisplayName 'Capsi*' |
  Select-Object DisplayName, Direction, Action, Enabled, Profile |
  Format-Table -AutoSize
Get-NetFirewallPortFilter |
  Where-Object { $_.LocalPort -in 45892, 45893 } |
  Select-Object LocalPort, Protocol, RemoteAddress
```

Expected: two enabled inbound **Allow** rules for `capsi.exe`, one UDP on `45893` and one
TCP on `45892`, `Profile` covering Domain/Private/Public, remote address restricted to the
local subnet.

4. **Verify shortcuts and first run:** Start Menu entry and desktop shortcut exist
   (`build_windows_installer.ps1:299-365`); the window title is `Capsi`
   (`main.cpp:30`); no console window appears (the runner attaches to a parent console only
   when one exists, `main.cpp:10-14`).

5. **Record the data directory** shown in **Settings → Storage → Capsi data**
   (`main.dart:1227-1230`) — it comes from `getApplicationSupportDirectory()`
   (`main.dart:425`). Confirm the folder exists and that a second launch reuses it
   (identity must not be regenerated).

##### P4.2 — The badge truth matrix (the core of this phase)

Deliberately induce each of the four reachable states and confirm the UI reports it. Each
row is a separate pass/fail.

| ID | Induced condition | Expected badge | Expected detail visible to the user |
|---|---|---|---|
| **T1** | Normal, first launch | `Ready` (green) | Settings → Connection: "Capsi is ready to connect"; Startup check lists all six steps as Passed |
| **T2** | Rename `capsi_ffi.dll` (or move it out of the install dir), relaunch | `Unavailable` (orange) | Tooltip: "Capsi did not load its native engine on this device."; Settings → Connection: "Capsi is not ready" |
| **T3** | Launch a **second** Capsi instance while the first holds TCP `45892` | `Limited` (orange) | Startup check shows **Service port** failed; the app names the likely cause — another copy already running (`main.dart:484-492`) |
| **T4** | Make the data directory unwritable (deny *Write* to your user), launch | `Limited` (orange), **engine refuses to start** | The startup gate lists the failing step(s) with the engine's own reason (`main.dart:461-470`, `:514-521`) — e.g. "Local storage: …" |
| **T5** | Disable/delete the **UDP 45893** firewall rule (or block it), relaunch | `Ready` (green) | **No error is shown** — see the limitation note below |

Expected strings are exactly those in the source: `Ready` / `Limited` / `Unavailable`
(`main.dart:1615-1623`), `Capsi is ready to connect` / `Capsi is running in a limited
state` / `Capsi is not ready` (`main.dart:1171-1180`).

**Known limitation, and it must be documented rather than discovered by a user:** the
self-check *binds* the discovery socket, which proves the port is usable locally. It
cannot prove that a firewall or an AP-isolated network will let a datagram through.
**Therefore T5 is expected to read `Ready` while discovery silently finds nothing.** This
is the one place the badge is honest about the engine and not about the network. It is
worth a line in the release notes; it must not be "fixed" by making the badge pessimistic,
because that would break T1's meaning.

**Restore the environment after each row.** In particular, after T2/T4 put the DLL back and
restore the ACL, or every later phase runs against a broken install.

##### P4.3 — Android install on a device

1. `adb install -r <apk>` on a device that has never had Capsi.
2. First launch: confirm the notification-permission prompt appears on Android 13+
   (`MainActivity.kt:168-175`) and that granting it makes a notification appear on the next
   incoming message.
3. Confirm **Settings → Storage** shows the private sandbox path *without* an "Open folder"
   button — `_dataFolderIsOpenable` is false on Android by design (`main.dart:163-164`).
4. Confirm **Settings** does **not** offer "Keep running in the system tray"
   (`_traySupported`, `main.dart:1146`): Android has no tray, and offering a switch that
   does nothing would be exactly the kind of control the project forbids
   (`Capsi/flutter/README.md:120-121`).
5. Background the app, then send it a message from a paired peer: the foreground
   `MessageListenerService` must keep the process alive and the notification must arrive
   (declared at `AndroidManifest.xml:12-18`, `:51-54`).

#### Success criteria
- [ ] Clean-machine install works with **no** Visual C++ redistributable present.
- [ ] One Add/Remove Programs entry, `Capsi` `1.1.0` by `Capsicom`, linking `https://capsi.win`.
- [ ] Start Menu and desktop shortcuts exist and launch the app.
- [ ] Two enabled inbound firewall Allow rules are present after install (UDP `45893`, TCP `45892`)
      and are **removed on uninstall**.
- [ ] Badge matrix **T1–T5** each match the table. In particular T2 and T3 produce their
      *specific* messages — a generic "not ready" is a failure of this phase even though the
      badge colour is right.
- [ ] T4 shows a refusal to start plus the engine's reason, not a silent half-start.
- [ ] Data directory is stable across launches (device identity is not regenerated).
- [ ] Android: no tray switch, no "Open folder" button, notification permission prompt on
      API 33+, listener survives backgrounding.

#### Failure indicators

| Symptom | Likely cause | Action |
|---|---|---|
| App fails to start with a missing-DLL error on a clean VM | A binary still imports `MSVCP140`/`VCRUNTIME140` | P2 Step 2 should have caught it; check the VM had no redistributable and that the MSI's binaries match the verified bundle (P2 Step 6) |
| Badge says `Ready` with `capsi_ffi.dll` renamed | `engineOperational` regressed to something weaker than `main.dart:371-375` | This is the exact bug the three-state badge replaced. Do not ship; add a regression test in `flutter/test/`. |
| Badge says `Limited` but the Startup check names no failing step | A report with `ok: false` and no failed steps — the FFI error-envelope path was not parsed | Check `CapsiSelfTestReport.fromJson` (`capsi_native.dart:207-227`) still synthesises the `self_test` step |
| Firewall rules missing after install | MSI lacks the exception rows, or the install was per-user | Re-run P2 Step 5; confirm `ALLUSERS = 1` |
| Rules remain after uninstall | WiX component not removed on uninstall | Record as a defect: a stale allow-rule for `capsi.exe` outlives the product |
| Second launch shows `Limited` permanently | The previous instance was not actually closed (tray setting keeps it alive) | `main.dart:1146` offers "Keep running in the system tray"; check the notification area before reporting a bug |
| Android: notification never arrives | `POST_NOTIFICATIONS` denied, or the foreground service was reclaimed | Re-grant; confirm `MessageListenerService` in `dumpsys activity services` |

#### Evidence
`p4-install-tree.txt`, `p4-arp-entry.txt`, `p4-firewall-rules.txt`,
`p4-firewall-after-uninstall.txt`, screenshots of the badge for **T1–T5**, the T4 failure
text, `p4-android-settings.png`, `p4-android-notification.png`.

---

### P5 — Two-device connectivity matrices

**Class C · manual, interactive, and deliberately out of automation scope.**

There is no CI job for this and there cannot be one: it needs two machines, two keyboards,
and a human to accept a trust prompt. **A green CI run must never be read as evidence that
this phase passed.** The point of separating it out is to make that confusion impossible.

#### Objective
Prove that two independent Capsi devices discover each other, establish trust, and exchange
traffic — in all three pairings, in both directions, and under the conditions that actually
break LAN products (multi-NIC hosts, VPNs, idle time, restarts).

#### Preconditions
- Both devices on the **same L2 network / subnet**, with AP client isolation disabled.
- Android: Wi-Fi on — the multicast lock depends on the Wi-Fi stack
  (`MainActivity.kt:202-217`). A cellular-only phone can never hear the broadcast.
- Windows: the two firewall rules from P4.1 step 3 are present and enabled.
- **Two separate Windows machines or VMs for Win↔Win.** Two instances on one machine
  *cannot* both run: they collide on TCP `45892`, which is exactly what P4 row **T3**
  demonstrates. Do not run Win↔Win on a single host and report the resulting `Limited`
  badge as a bug.
- Both devices showing a `Ready` badge before the run starts.

#### Procedure

Run the full checklist for each pairing, **in both directions**, then swap the roles and
repeat.

**Step 1 — Discovery.**
1. Launch both apps. Within `PEER_TIMEOUT_SECS` (20 s, `lib.rs:27`) each must list the other
   in **Nearby**.
2. Leave both idle for 60 s and confirm the peer is still listed. The beacon repeats every
   `ANNOUNCE_INTERVAL_SECS` (5 s, `lib.rs:26`), so a peer that vanishes while idle means the
   interval or the timeout handling is wrong.
3. Rename one device in **Settings → Device**. The peer list on the other device must show
   the new name within a few seconds: a rename restarts discovery so the *signed* beacon is
   rebuilt (`main.dart:395-414`). A stale name is a real defect, not cosmetic.

**Step 2 — Trust.**
1. Accept the peer on both sides.
2. **Compare fingerprints out-of-band.** The fingerprint the accepting device shows for its
   peer must equal the peer's own fingerprint. This is what makes the trust model mean
   something: a device id *is* its Ed25519 public key, and the trust list pins it
   (`capsi-core/src/crypto/mod.rs:11-12`). If the two fingerprints disagree, stop the run and
   raise it as a security defect.
3. Confirm the device appears under **Trusted devices** with the expected name and
   fingerprint, and that the count in **Settings → Privacy & devices** matches.

**Step 3 — Messaging.**
1. Send text messages A → B and B → A; confirm both are delivered and rendered in the
   conversation.
2. Restart both apps; confirm conversation history survives.
3. Confirm a notification is raised when the receiving app is **backgrounded**: a tray
   balloon when Capsi is minimised on Windows (`flutter_window.cpp:194-213`), an Android
   notification from `MessageListenerService` otherwise.

**Step 4 — Offline delivery.**
1. Stop Capsi entirely on B. Send messages from A while B is down.
2. Start B. Confirm the queued messages arrive (feature listed at `README.md:189`).
3. Confirm they arrive in order and are not duplicated after a second restart.

**Step 5 — Trust controls.**
1. **Rename** a trusted device; confirm the new name persists after a restart.
2. **Block** a device; confirm it can no longer be discovered or accepted by that peer, and
   that the block survives a restart.
3. **Forget** a device; confirm the connection requires a fresh acceptance afterwards.

**Step 6 — Network conditions (Windows side).**
1. On a Windows host with **two active interfaces** (e.g. Ethernet + a VPN adapter), confirm
   discovery still succeeds. The core announces to every interface's broadcast address and
   keeps the limited broadcast address as a fallback
   (`capsi-core/src/discovery/interfaces.rs:24-40`); a multi-NIC host is the classic place
   this breaks.
2. Toggle the VPN off and back on mid-run; confirm the peer is re-found **without**
   restarting the app.
3. Switch the Windows network profile between Private and Public. The firewall rules are
   declared for all profiles (`Profile="all"`, `build_windows_installer.ps1:282,286`), so
   discovery must survive the change.

**Step 7 — Workplace synchronisation and conflicts.**

`README.md:231` lists "Workplace synchronization conflicts" as a required real-device test, and
the Workplace surface is a first-class part of the product (navigation listed at
`Capsi/flutter/README.md:114`; the `capsi_workplace_*` entry points are enumerated in §2.4).

1. Create a workplace on A, then invite/accept on B and confirm B sees the same groups and
   members.
2. Create a group and a department on one side; confirm the other side converges.
3. Add a member, change a member's role, move a member between groups; confirm the peer
   reflects each change.
4. Broadcast to the workplace and confirm every member device receives it.
5. **Force a conflict:** take both devices offline, make a *conflicting* change on each (for
   example, rename the same workplace differently on each side), then reconnect. Record
   exactly what happens — which change wins, whether any error is surfaced, and whether the
   UI ever shows a state that is not true. The expected outcome is "deterministic and
   documented"; an undefined merge is a defect even if it looks tidy.
6. Restart both devices and confirm the converged state persists.

**Step 8 — Lifecycle, sleep/wake, hotspot and isolation.**

These are the remaining conditions `README.md:225-233` calls out.

1. **Sleep/wake:** put the Windows machine to sleep and the phone into deep sleep (screen
   off, do-not-disturb off) for 10 minutes, then wake both. Confirm the peer is re-found
   within `PEER_TIMEOUT_SECS` (20 s) and that no manual restart is needed on either side.
2. **Hotspot:** connect both devices to a phone's hotspot instead of the normal LAN. Confirm
   discovery and transfer still work — this is the "hotspot" case and it exercises a
   different subnet and DHCP arrangement.
3. **Wi-Fi client isolation:** connect both to a network known to isolate clients (most
   guest Wi-Fi). Record the behaviour: peers will not be found. Confirm the UI does **not**
   claim success — this is the practical side of the `Ready`-but-not-discoverable limitation
   from P4 row T5, and it must be reproducible and explicable rather than mysterious.
4. **Background/mobile lifecycle:** with Capsi backgrounded on Android, send messages and a
   file; confirm the foreground service keeps delivery working (`AndroidManifest.xml:12-18`).
   Then swipe the app away and confirm the behaviour is *consistent* — either it keeps
   delivering, or it stops and the user can tell. Record which.
5. **Observational performance and battery (not a pass/fail gate):** with Capsi idle for
   30 minutes on the phone, read Android's per-app battery usage and note the idle CPU on the
   Windows side (Task Manager). Then repeat during an active 1 GB transfer. The purpose is to
   catch a runaway loop, not to set a threshold.

#### Matrix — record one row per run

| # | Pairing | Discovery | Persists 60 s | Trust + fingerprint match | A→B msg | B→A msg | History after restart | Offline queue | Rename | Block | Forget |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Windows ↔ Windows | | | | | | | | | | |
| 2 | Android ↔ Android | | | | | | | | | | |
| 3 | Windows → Android | | | | | | | | | | |
| 4 | Android → Windows | | | | | | | | | | |
| 5 | Windows ↔ Windows, multi-NIC + VPN | | | | | | | | | | |
| 6 | Workplace sync (either pairing) | — | — | — | — | — | — | — | — | — | — |
| 7 | Sleep/wake recovery (either pairing) | | — | — | | | | | — | — | — |

Row 6 records the Step 7 results (`Group/Dept converge`, `Role change`, `Broadcast`,
`Conflicting edit outcome`, `Persists after restart`); row 7 records wake-from-sleep
recovery only, which is why most cells are `—`.

Each cell: `OK` / `FAIL` plus a one-line note. Rows 1 and 3–5 must also be run with the
roles swapped, so that "who announces first" cannot hide an asymmetry. Announcement and
trust are *intended* to be symmetric; asymmetric bugs are common.

#### Success criteria
- [ ] All five matrix rows fully green, in both role directions.
- [ ] Peer fingerprint shown by the other device equals the device's own fingerprint, on
      every pairing. A mismatch is a **security defect**, not a test failure.
- [ ] A renamed device is seen under its new name by the peer without restarting either app.
- [ ] Offline messages arrive, in order, without duplication.
- [ ] Blocked devices stay blocked after a restart; forgotten devices require re-acceptance.
- [ ] Discovery survives a VPN toggle and a Private↔Public profile switch on Windows.
- [ ] Workplace: groups, departments, membership and roles converge on the peer; a broadcast
      reaches every member; a forced conflict produces a **deterministic, recorded** outcome.
- [ ] Sleep/wake: both peers are re-found within the peer timeout without a manual restart.
- [ ] Hotspot: discovery and a transfer succeed on a phone hotspot.
- [ ] Client-isolated Wi-Fi: the failure is reproducible and explicable (no false success).
- [ ] Zero messages lost, zero duplicated, zero delivered to the wrong device.

#### Failure indicators

| Symptom | Likely cause | Action |
|---|---|---|
| Neither device ever sees the other | Broadcast not leaving the host, or client isolation on the Wi-Fi network | Check the Wi-Fi AP settings; try a hotspot created by one of the devices; on Windows re-check the two firewall rules |
| Android never sees the peer while Windows does | `MulticastLock` not acquired (best-effort by design, `MainActivity.kt:198-217`) or Wi-Fi power-save dropping broadcasts | Keep the screen on / disable battery optimisation for Capsi while testing; if it persists, treat it as a defect in the lock's lifecycle |
| Peer vanishes after ~20 s | Beacons stopped (5 s interval, `lib.rs:26`), or the discovery listener died without the badge changing | Check the badge — if it still says `Ready` while peers disappear, the truth-state contract has a hole; report it |
| Discovery works on one interface only | Multi-NIC announcement path | This is what Step 6.1 exists for; record which interface failed |
| Messages arrive but no notification | Notification preference off in Settings, Android permission denied, or the app was in the foreground (notifications are suppressed when the user is already looking at the conversation, `main.dart:377-379`) | Check all three before filing a bug |
| Trust prompt never appears | Device already trusted, or blocked | Check **Trusted devices** first |
| Workplace changes do not reach the peer | Sync only runs on an active session, or the peer was not a member | Confirm both are trusted and the peer is listed in the group before reporting |
| A conflict silently loses one side's change | Undefined merge | Record both pre-merge states; an undefined merge is a defect, not an acceptable answer |
| Peer not re-found after sleep/wake | Listener thread died on resume while the badge still said `Ready` | Capture the badge state *before* waking; a `Ready` badge over a dead listener is the highest-value bug this plan can find |
| Hotspot works but normal LAN does not (or vice versa) | Interface/announcement selection | Record both environments; `interfaces.rs:24-40` is the code to inspect |

#### Evidence
`p5-matrix.csv` (the filled table), screenshots of Nearby on both devices, the
fingerprint comparison screenshots, a logcat/tray-balloon capture per pairing, and a note
of the network topology used (SSID, subnet, whether a VPN was active).

---

### P6 — File transfer: integrity, boundaries, resume, and failure paths

**Class C for the transfer itself; the integrity comparison is Class A once the file lands.**

#### Objective
Prove that a file arrives byte-identical, that the boundary cases derived from the protocol
constants behave, and that the unhappy paths (decline, cancel, disconnect, disk full) end in
an honest, named state rather than a silent half-success.

#### Why these specific cases

| Case is chosen because | Source |
|---|---|
| Chunk size is 256 KiB, so the interesting sizes are around it | `capsi-core/src/lib.rs:28` |
| File size is a 64-bit field with deliberately no application-level cap | `capsi-core/src/lib.rs:6-9` |
| Whole-file and per-chunk digests are BLAKE2b-256, hex-encoded | `message.rs:39-47`, `:157` |
| Success is defined as "Every chunk arrived and the digest matched." | `message.rs:55-60` |
| Transfer states are explicit: Offered / Transferring / Complete / Declined / Failed / Cancelled | `storage/conversation.rs:37` |
| Contiguous-prefix resume is a documented feature | `README.md:188` |

#### Procedure

##### P6.1 — Integrity across the size boundaries

Run each case **in both directions** and verify the landed file is byte-identical to the
source:

```powershell
# On the receiving Windows machine; for Android, `adb pull` the file first, then compare.
$src = 'D:\fixtures\<name>'
$dst = 'C:\Users\<user>\Downloads\<name>'
[pscustomobject]@{
  SameBytes = ((Get-FileHash $src -Algorithm SHA256).Hash -eq (Get-FileHash $dst -Algorithm SHA256).Hash)
  SrcBytes  = (Get-Item $src).Length
  DstBytes  = (Get-Item $dst).Length
}
```

Comparing the whole-file hash is the honest check. The product's internal digest is
BLAKE2b-256 (`util.rs:26-47`), so *its* digest cannot be reproduced with `Get-FileHash` —
but byte-identity is the property that actually matters, and that is reproducible.

Also confirm the UI's own per-transfer check code agrees between the two devices. Those
codes exist so a tampered payload can be spotted without re-hashing the conversation
(`util.rs:21-25`).

| ID | Fixture | Why this one |
|---|---|---|
| F1 | 1 KB text file | trivial path |
| F2 | exactly 256 KiB (`262144` bytes) | one full chunk, no remainder |
| F3 | 262145 bytes | one full chunk + 1 byte — the off-by-one case |
| F4 | ≈1.5 GB file | 64-bit size, progress reporting, disk space |
| F5 | 0-byte file | degenerate; must not hang, must not claim `Complete` for a missing file |
| F6 | file named with spaces, Unicode and a very long name | `safe_file_name` sanitisation (`util.rs:75`) |
| F7 | file inside a folder whose path has spaces/Unicode | source-path handling |

##### P6.2 — Failure and control paths

| ID | Action | Expected state | Expected user-visible behaviour |
|---|---|---|---|
| F8 | Receiver **declines** the offer | `Declined` | Sender is told; no file written on the receiver |
| F9 | Sender **cancels** mid-transfer | `Cancelled` | The receiver's partial file is not presented as complete |
| F10 | Kill the network (Wi-Fi off / unplug) mid-transfer, then restore | failed, or resume | With resume support the transfer continues from the contiguous prefix instead of restarting from zero (`README.md:188`); a completed file must still hash-match |
| F11 | Receiver has insufficient disk space | `Failed` with a reason | No `Complete` claim, and no truncated file left looking valid |
| F12 | Two transfers at once between the same pair | recorded | Whatever the product does, **record it**. If the UI claims both progressed while only one did, that is a truth-state defect. |
| F13 | Large file during back-and-forth messaging | both work | Frame interleaving must not corrupt either stream |

**Digest-mismatch handling cannot be induced without tampering with the payload** — do not
fake it. Verify by inspection instead that `FileReceipt`'s success meaning is "every chunk
arrived and the digest matched" (`message.rs:55-60`), and that a mismatch routes to a failed
transfer rather than to `Complete`.

##### P6.3 — Throughput, duration, and bounded memory (observational)

`README.md:229` lists "Large and concurrent file transfers" as a required validation.

1. Transfer the F4 fixture (≈1.5 GB) on a normal LAN and again on a hotspot. Record wall-clock
   duration and derive MB/s. There is no target threshold here — the purpose is a baseline so
   a later regression is visible.
2. Watch Windows Task Manager (or Resource Monitor) during the transfer and confirm the
   process working set stays roughly flat rather than growing with the file. The core hashes
   files incrementally for exactly this reason (`util.rs:34-35`: "Hash a file incrementally
   without loading the entire file into memory"), so a growing working set contradicts the
   design and is a real finding.
3. Confirm the progress indicator advances monotonically and does not jump backwards or
   freeze while data is clearly moving.
4. Run F12 (two concurrent transfers) and record whether the aggregate throughput roughly
   splits or one starves the other.


#### Success criteria
- [ ] F1–F7: received file byte-identical (SHA-256 equal) and same size, in both directions.
- [ ] F2 and F3 in particular pass — chunk boundaries are where transfer bugs live.
- [ ] F5 (0 bytes) terminates in a named state, not a spinner.
- [ ] F8/F9/F11 end in `Declined` / `Cancelled` / `Failed` respectively, with the reason
      visible, and never in `Complete`.
- [ ] F10 either resumes from the contiguous prefix or fails cleanly; a completed file is
      byte-identical.
- [ ] F6/F7: sanitised names still land, and the original name is still shown correctly in
      the conversation.
- [ ] Both devices display the same per-transfer check code.

#### Failure indicators

| Symptom | Likely cause | Action |
|---|---|---|
| Received file differs by a few bytes near a 256 KiB boundary | Chunk framing or offset bug | Escalate immediately — this is data corruption, the highest-severity class in this plan |
| Transfer stalls at 100% and never reaches `Complete` | Final receipt missing, or the last partial chunk was not flushed | Check the whole-file digest path (`util.rs:35-47`) |
| A cancelled transfer leaves a file that looks complete | Partial file not marked | Defect: a user would trust a truncated file |
| Resume restarts from zero | Contiguous-prefix detection not working | `README.md:188` documents resume, so a restart from zero contradicts the documentation — record it as a doc-or-code defect |
| Zero-byte file never completes | Degenerate-size handling | Defect |
| Disk-full reported as `Complete` | Error swallowed in the write path | Defect; confirm no truncated file is left behind |

#### Evidence
`p6-integrity.csv` (fixture × direction × source hash × destination hash × result),
screenshots of the transfer states for F8–F11, the recorded behaviour for F12/F13, and the
observed resume offset for F10.

---

### P7 — RC sign-off and evidence bundle

**Class B · the release gate.**

#### Objective
Convert a history of runs into a single, defensible yes/no, plus an explicit statement of
what has **not** been verified. `README.md:248` states the principle — "Source
implementation, CI success, and real-device behavior are separate things" — and this phase is
where the project keeps that promise.

#### Procedure

1. **Confirm the commit is unchanged.** The hash from P0 must still be `HEAD`. If anything
   landed since — even a documentation commit — re-run P1–P3 and re-verify the P2 Step 2/6
   hashes, because the artifacts no longer correspond to the frozen tree.

2. **Confirm each phase's evidence exists.** Walk the evidence list of P0–P6; a phase with no
   evidence is a phase that did not happen.

3. **Confirm the hard stops.** None of these may be open:
   - P1: any core or Dart test failing.
   - P2: a redistributable import, a non-x64 binary, a failing live probe, a missing
     self-check step, an MSI whose version or hashes do not match the bundle.
   - P3: a missing ABI, a missing permission, **or a debug-signed APK** (blocker B1).
   - P4: any badge-matrix row that produces the wrong state *or* the wrong message.
   - P5/P6: any discovery, message, or transfer failure on a supported configuration.

4. **Write the release notes with the limits stated, not implied.** At minimum:

   | Must be stated | Because |
   |---|---|
   | Android signing status (release key or debug key) | Blocker B1; a user comparing builds must know whether this APK can be updated |
   | The Android OS floor and target SDK actually baked into the APK | They are Flutter defaults, not pinned in this repo (gap G5) |
   | That `Ready` means the *engine* is ready, not that the network will carry traffic | P4 row T5; otherwise a blocked-network user reports a Capsi bug |
   | Which platforms were physically tested (Windows, Android) and which were not (macOS, iOS, Linux) | `README.md:224`; the CD pipelines build macOS/iOS but nothing here validates them on hardware |
   | The TSV/summary of the P5 matrix and the P6 integrity results | Turns "we tested it" into "here is what we ran" |
   | Any observational performance/battery numbers with no threshold | `README.md:233`; do not dress observations up as guarantees |

5. **Assemble the bundle.** One folder, named for the candidate:

```
capsi-rc-1.1.0-<commit7>/
  ARTIFACTS/   Capsi-1.1.0-x64.msi, app-release.apk, hashes.txt (SHA-256 of each)
  LOGS/        p1-*.log, p2-*.log, p3-*.log, build logs
  EVIDENCE/    p2-ffi-probe.json, p2-msi-properties.txt, p2-msi-firewall.txt,
               p3-aapt2-badging.txt, p3-apksigner.txt, p3-logcat.txt,
               p4-firewall-rules.txt, p4-firewall-after-uninstall.txt
  MATRICES/    p5-matrix.csv, p6-integrity.csv, p6-throughput.csv
  SHOTS/       badge screenshots T1–T5, Nearby on both devices, fingerprints,
               Android settings/notification
  RELEASE-NOTES.md
  SIGN-OFF.md
```

6. **Sign off.** `SIGN-OFF.md` holds the frozen commit, the artifact hashes, the phase
   results, and who verified each phase. An unexplained gap in that table is a "no".

#### Success criteria
- [ ] Frozen commit still `HEAD`; artifact hashes re-verified against it.
- [ ] Evidence present for P0–P6, and every hard stop closed.
- [ ] Release notes state the signing status, the OS floor, the `Ready` limitation, and the
      untested platforms.
- [ ] Bundle assembled and reproducible: a second person can follow this plan, using only
      the bundle, and reach the same conclusions.
- [ ] `SIGN-OFF.md` complete, with no unexplained omission.

#### Failure indicators

| Symptom | Meaning |
|---|---|
| A phase has no evidence, but "everyone remembers it passing" | Not a pass. Re-run it. |
| Commit moved after the artifacts were built | The artifacts are not the frozen tree's. Rebuild or re-freeze. |
| Release notes describe intended behaviour rather than observed behaviour | Violates `README.md:249` ("Do not invent capabilities") |
| An exception is granted "just for this candidate" | Record it as an accepted risk with an owner and a date, or do not ship |

#### Evidence
`SIGN-OFF.md`, `RELEASE-NOTES.md`, and the assembled bundle itself.

---

## 6. Consolidated matrices

### 6.1 Traceability to the repository's own required-validation list

`README.md:217-233` already lists what the project considers unvalidated. This plan closes
each item or states explicitly that it is out of scope — so nothing from the project's own
list is silently dropped.

| `README.md` item | Phase / step | Automated? | Out of scope? |
|---|---|---|---|
| Windows ↔ Windows communication | P5 row 1 | No — Class C | |
| Windows ↔ Android communication | P5 rows 3–4 | No — Class C | |
| Android ↔ Android communication | P5 row 2 | No — Class C | |
| macOS and iOS compatibility | — | No | **Yes** — no `ios/` or `macos/` runner exists in `Capsi/flutter`; CI generates them (`ci.yml:93-94`, `:152-153`) and nothing here validates them on hardware. P7 requires this to be stated in the release notes. |
| Network changes and reconnects | P5 Step 6.2 (VPN toggle), Step 8.1 (sleep/wake) | No — Class C | |
| Hotspot and Wi-Fi isolation behavior | P5 Step 8.2, Step 8.3 | No — Class C | |
| Firewall behavior | P4.1 step 3 (rules exist), P5 Step 6.3 (profile switch), P4 row T5 | Partly — rule presence is scriptable, behaviour is not | |
| Sleeping/waking devices | P5 Step 8.1 | No — Class C | |
| Large and concurrent file transfers | P6 F4, F12, P6.3 | No — Class C (hash compare is scriptable) | |
| Interrupted transfer recovery | P6 F10 | No — Class C | |
| Workplace synchronization conflicts | P5 Step 7 | No — Class C | |
| Mobile lifecycle/background behavior | P4.3 step 5, P5 Step 8.4 | No — Class C | |
| Performance and battery behavior on mobile | P5 Step 8.5, P6.3 | No — observational | |
| Protocol compatibility | P2 Step 4 / P3 (self-check reports `capsi/1`; cross-version check is not automated) | Partly | Cross-version (1.0.2 ↔ 1.1.0) interop is **not** covered by any current step — see risk R13 |

### 6.2 Minimum device and environment coverage

| # | Environment | Covers |
|---|---|---|
| E1 | Windows 11 x64, clean VM, no Visual C++ redistributable | P2, P4.1 — the self-containment claim |
| E2 | Windows 11 x64, machine with an existing Capsi `1.0.2` install | P2 Step 7 — upgrade continuity |
| E3 | Windows 10 x64 (or 11), second machine for peer tests | P5 Win↔Win |
| E4 | Windows host with a second interface active (VPN/extra NIC) | P5 Step 6.1 |
| E5 | Android 13+ (API 33+), `arm64-v8a` | P3, P4.3, P5 — exercises the runtime `POST_NOTIFICATIONS` request and `FOREGROUND_SERVICE_DATA_SYNC` |
| E6 | Android ≤ 12, `arm64-v8a` | The no-runtime-permission path (`MainActivity.kt:168-169` returns early) |
| E7 | Android `armeabi-v7a` device, if one is available | Proves the 32-bit ABI actually loads; otherwise the ABI is unverified |
| E8 | Android emulator `x86_64` | Proves the emulator ABI load, but **not** a substitute for E5/E6 — Wi-Fi broadcast behaves differently |
| E9 | Phone hotspot network | P5 Step 8.2 |
| E10 | Client-isolated guest Wi-Fi | P5 Step 8.3, P4 row T5 |

E7 is the one most likely to be skipped, and it is the one that leaves a shipped ABI with no
evidence behind it. If no `armeabi-v7a` device is available, say so in the release notes
rather than leaving the ABI implicitly claimed as verified.

### 6.3 Artifact → verification traceability

| Artifact | Built by | Verified by | What is actually proven |
|---|---|---|---|
| `capsi.exe` | `tool/build_windows.ps1` | P2 Step 2 (imports), Step 3 (PE machine), Step 4 (via the DLL), P4.1 | x64, statically linked CRT, the managed app runs |
| `capsi_ffi.dll` | `tool/build_windows.ps1` (cargo, `+crt-static`) | P2 Step 2, Step 4 (**live probe**), Step 6 | Loads outside Flutter, all six self-check steps pass, and the MSI carries this exact file |
| `flutter_windows.dll` + plugin DLLs | `flutter build windows --release` / CMake | P2 Step 2, Step 3 | x64 and free of redistributable imports |
| `Capsi-1.1.0-x64.msi` | `tool/build_windows_installer.ps1` (WiX 3.14.1) | P2 Steps 5–7, P4.1 | Properties, two firewall rules, per-machine scope, payload hashes, upgrade continuity, and that it installs on a clean VM |
| `app-release.apk` | `tool/build_android.ps1` | P3 Steps 2–6 | Three ABIs present and loadable, permissions packaged, **signature identity**, starts and reports `Ready` |
| `libcapsi_ffi.so` (×3) | `cargo-ndk`, `native/` crate | P3 Steps 2, 3, 6 | Correct ELF machine per ABI, packaged and extracted to the right `nativeLibraryDir` |

---

## 7. Risk register

Each risk lists what this plan does about it and what remains. "Residual" is what a release
would still be carrying if this plan is executed exactly as written.

| ID | Risk | Likelihood | Impact | Mitigation in this plan | Residual / recommended fix |
|---|---|---|---|---|---|
| **R1** | Android release APK is signed with the **debug** key (`android/app/build.gradle.kts:33-36`; no `key.properties`) | Certain | **High** — supply-chain and upgradeability | P3 blocker **B1**, Step 5, and the P7 notes requirement | Not mitigable by testing. Fix by adding a release `signingConfig` + `key.properties` (kept out of VCS) and rebuilding |
| **R2** | CI uploads the bare Windows bundle and never the MSI (`ci.yml:208`) | Certain | Medium-High | P2 Step 6 hash-compares bundle vs MSI; P7 archives the MSI | Add the MSI path to the CI upload in `ci.yml` |
| **R3** | No automated check that the FFI library loads and the self-check passes | Certain | High — the product's own gate is unverified in CI | P2 Step 4 live probe (manual but repeatable) | Add a Windows CI step running the same probe, plus an `adb`-based Android variant |
| **R4** | Android `minSdk`/`targetSdk`/`compileSdk`/`ndkVersion` come from Flutter defaults, not pinned here | High | Medium | P0 records the toolchain; P3 records the packaged OS floor; P7 requires it in the notes | Pin them in `android/app/build.gradle.kts` |
| **R5** | `Ready` proves the engine, not the network path (P4 row T5) | Certain | Medium — a blocked user sees a healthy badge | Documented as an explicit limitation; P5 Step 8.3 makes it reproducible | State it in the release notes; only add a reachability hint if it can be made truthful |
| **R6** | Two instances on one host cannot coexist (single TCP `45892`) | Certain | Low-Medium — user confusion | P4 row T3 tests it; P5 preconditions forbid Win↔Win on one host | Mention it in support material |
| **R7** | Stale legacy tooling and docs: `Capsi/scripts/check-backend.bat` targets a non-existent `src-tauri`; `README.md:122` documents macOS/iOS development | Certain | Low, but it wastes release time and contradicts `README.md:249` | P1 step 5 flags it; P7 requires honest platform statements | Delete or mark retired the Tauri-era scripts; update the README platform sections |
| **R8** | Android broadcast reception depends on a best-effort `MulticastLock` and on Wi-Fi power-save behaviour | Medium | High — discovery is the product's front door | P5 Steps 8.2/8.3 plus failure indicators; environments E5/E6/E9/E10 | If failures appear, review the lock lifecycle in `MainActivity.kt:198-225` |
| **R9** | macOS/iOS CI jobs can go red for reasons unrelated to this candidate | Medium | Low — release noise under time pressure | §3 keeps them out of the RC gate; P7 requires only an explanation | Annotate them as not part of the Windows+Android RC |
| **R10** | `pubspec.yaml` version and `Cargo.toml` workspace version drift | Low | Medium — MSI and DLL disagree | P0 step 3 asserts equality; P2 Step 4 compares the probe's runtime version | Keep using the single bump script (`Capsi/scripts/bump-version.ps1`) |
| **R11** | PowerShell aborts on native stderr, producing false failures or "passes" that never ran | Medium | Medium | §1.3 mandates the log-capture pattern in every procedure | Keep the pattern for new scripts; `check-backend.bat` is the existing precedent |
| **R12** | Windows binaries and the MSI are **unsigned** — no `signtool` step exists in any `tool/*.ps1` | Certain | Medium — SmartScreen warnings, no signature to verify | P2 verifies SHA-256 hashes instead; P7 archives them | Code-sign the MSI and `capsi.exe` when a certificate exists |
| **R13** | No cross-version compatibility test: nothing verifies a `1.0.2` peer interoperates with a `1.1.0` peer | Medium | High — per-device upgrades depend on it | **Not covered.** P2/P3 only confirm the engine reports `capsi/1` | Add a P5 sub-case: upgrade one side only, then run the matrix. `PROTOCOL_VERSION` is a single string (`capsi-core/src/lib.rs:23`), so test it rather than assume it |
| **R14** | Uninstall may leave the firewall rules behind | Low | Medium — a stale allow-rule outlives the product | P4 success criteria require their removal | If it fails it is a WiX component defect; fix before shipping |
| **R15** | The startup gate (`main.dart:416-507`) is covered only by widget tests, never by a live engine | Medium | High — this is the truth-state logic itself | P4's badge matrix T1–T5 exercises it against a real engine | Consider a scripted probe that runs the built app and asserts the badge |

---

## 8. Definition of Done

Three levels. A candidate is done only when all three are satisfied.

### 8.1 Candidate-level DoD (the release gate)

- [ ] Every phase P0–P7 has its evidence in the bundle; the frozen commit is still `HEAD`.
- [ ] P1 green: `cargo test -p capsi-core`, `flutter analyze`, `flutter test`.
- [ ] P2 green: no redistributable imports, x64 binaries, live FFI probe returns six passing
      steps, MSI properties and two firewall rules verified, MSI payload hashes match the
      bundle, upgrade replaces `1.0.2`.
- [ ] P3 green: three ABIs present and correctly typed, six permissions packaged,
      **release-signed APK**, device launch reports `Ready`.
- [ ] P4 green: clean install works, firewall rules applied and removed, badge matrix T1–T5
      all correct **including the wording**.
- [ ] P5 and P6 green across every supported pairing, with the matrices filled in.
- [ ] Release notes state: signing status, OS floor, the `Ready` limitation, untested
      platforms, and the observation that performance figures are baselines, not guarantees.
- [ ] Risk register reviewed; R1 either fixed or explicitly accepted with an owner and date.

### 8.2 Per-phase DoD

For each phase, all four must hold:

- [ ] The procedure was executed **on the frozen commit** (or on artifacts built from it).
- [ ] Every success-criteria box is ticked, or the exception is written down with a reason.
- [ ] The evidence artifacts named in the phase exist and are readable by someone else.
- [ ] Anything that failed produced a defect entry — not a note in a chat.

### 8.3 Task-level DoD (any change that lands before the candidate)

This is the bar a change has to clear to avoid corrupting the phases above. It follows from
`README.md:241-249`.

- [ ] **The core owns behaviour.** New product logic goes in `capsi-core`, then is exposed
      through `native/` to Flutter — not reimplemented in Dart
      (`Capsi/flutter/README.md:17-18`).
- [ ] **`cargo test -p capsi-core` passes**, and any new core behaviour has a test. The
      existing self-check tests are the model: assert the successful order *and* a failure
      case (`Capsi/flutter/native/src/lib.rs:2218-2280`).
- [ ] **`flutter analyze` is clean and `flutter test` passes.** No new analyzer warnings.
- [ ] **New FFI entry points** are added to `native/`, exported with `#[no_mangle]`, looked
      up in `capsi_native.dart`, and covered by a Dart test where the failure mode matters —
      the FFI `{"error": ...}` envelope is the precedent that this is done
      (`capsi_native.dart:208-227`).
- [ ] **No claim without evidence.** If a surface or a doc line says something works, either a
      test covers it or the line says it still needs validation (`README.md:249`).
- [ ] **The badge contract still holds.** `engineOperational` stays exactly
      `native != null && selfTestReport.ok && discoveryHandle != 0 && messageHandle != 0`
      (`main.dart:371-375`). Anything weaker re-introduces the "Ready over a dead listener"
      bug.
- [ ] **No control that does nothing.** Platform-specific settings stay behind their platform
      gate (`_traySupported`, `_dataFolderIsOpenable`; `main.dart:163-164`, `:1146`).
- [ ] **Version bumped once**, via `Capsi/scripts/bump-version.ps1`, keeping `pubspec.yaml`
      and `Cargo.toml` in step.
- [ ] **CI is green** — or the failure is explained and shown to be unrelated to this
      candidate (§3, R9).

---

## 9. Appendix

### A. Entry points in the repository

| Purpose | Entry point | Notes |
|---|---|---|
| Core tests | `Capsi/scripts/test-core.ps1` (`cargo test -p capsi-core`) | Handles the MSVC/GNU toolchain choice; also `cargo test -p capsi-core` directly |
| Flutter analysis and tests | `flutter analyze`, `flutter test` in `Capsi/flutter` | `tests/`: `widget_test.dart`, `self_test_report_test.dart` |
| Flutter preflight | `Capsi/flutter/tool/preflight.ps1` | Checks `flutter`/`cargo`, then `pub get`, `cargo check --manifest-path native/Cargo.toml`, `flutter analyze`; asserts the presence of `lib/main.dart`, `lib/capsi_native.dart`, `native/Cargo.toml`, `assets/capsi-logo-512.png` |
| Windows build | `Capsi/flutter/tool/build_windows.ps1` (`-SkipInstaller`, `-RequireFlutterToolchain`) | Also `.sh` variant |
| Windows installer | `Capsi/flutter/tool/build_windows_installer.ps1` | Called automatically by the Windows build unless `-SkipInstaller` |
| Android build | `Capsi/flutter/tool/build_android.ps1` (or repo-root `build-android.bat`) | Also `.sh` variant |
| Android configuration | `Capsi/flutter/tool/configure_android.ps1` | Application id, label, `INTERNET` in the main manifest, `MainActivity.kt` location |
| Platform scaffolding | `Capsi/flutter/tool/bootstrap_platforms.ps1` / `.sh` | Generates runners |
| Icons | `Capsi/flutter/tool/make_icons.ps1` / `.sh` | |
| Version bump | `Capsi/scripts/bump-version.ps1` | Keeps `pubspec.yaml` and the Rust version in step |

Not part of this plan: `Capsi/scripts/check-backend.bat` (targets the retired
`src-tauri`), `install-rc-preproc.bat`, `rc-preproc/`, `setup-gnu-target.bat` (Tauri-era),
and the `*.ps1` iOS/macOS helpers (`prepare_ios.sh`, `link_ios_rust.sh`,
`configure_apple_networking.sh`), which belong to platforms outside this candidate's scope.

### B. The log-capture pattern, in one place

Every native command in this plan is invoked this way, because PowerShell aborts a script on
native stderr:

```powershell
$log = "$env:TEMP\capsi_rc_<step>.log"
Start-Process cmd.exe `
  -ArgumentList '/c', "<command> 1> `"$log`" 2>&1" `
  -WorkingDirectory <dir> -Wait -NoNewWindow
Get-Content $log
```

`Capsi/scripts/check-backend.bat` is the in-repo precedent for the same idea, including its
completion-marker file (`%TEMP%\capsi_cargo_done.marker`). Use the marker approach when a
step must be run detached, and the `Start-Process -Wait` form when the result is needed
immediately. Either way: **the log is the evidence, not the exit code.**

### C. CI changes that would close the gaps in §3.1

In rough order of value:

1. **G1** — add a step after `build_windows.ps1` that runs the P2 Step 4 probe against the
   built bundle and fails the job unless all six steps report `ok: true`. The same idea works
   for Android with `adb` + a single `am start` plus a logcat assertion.
2. **G3** — change the Windows upload path to include `build\Capsi-*-x64.msi`, or upload a
   zip containing both the MSI and the bundle.
3. **G5** — pin `compileSdk`, `minSdk`, `targetSdk` and `ndkVersion` in
   `android/app/build.gradle.kts`, and record them as build outputs.
4. **G2 / R15** — add a smoke step that launches the built Windows app and asserts the badge
   text, once a reliable headless path exists. Until then, keep P4 as the manual gate.
5. **G6** — add an install-and-uninstall job (a Windows runner can install the MSI quietly and
   read the firewall table back), which would make P4.1 partly automatic.

### D. Terminology

| Term | Meaning in this document |
|---|---|
| **Self-check** | The six-step engine verification exposed as `capsi_self_test`, which the app runs before it will call itself ready |
| **Truth state** | One of `Ready` / `Limited` / `Unavailable`; the badge must never overstate |
| **Frozen commit** | The `HEAD` recorded in P0; every artifact in the bundle must be built from it |
| **Class A / B / C** | Automated / semi-automated / manual — see §1.2 |
| **Hard stop** | A phase result that forbids promoting the candidate, regardless of other results |
| **Evidence** | A file in the bundle: a log, a JSON report, a hash listing, a screenshot, or a filled matrix |

---

*This plan describes what the repository at commit `2dd683e8` actually contains, and what has
therefore not yet been proven. Where it lists a check, the check exists because a specific
file in this repository says the behaviour exists — and a green build is not the same thing as
a verified product (`README.md:248`).*
