# Release Verification — Execution Log

Run against `D:\Capsi` @ `7027d131f8052c7cca1d7bdda025ef65e7f36497` (branch `main`,
working tree clean throughout).

Candidate `1.1.0` (`pubspec.yaml` `1.1.0+2`, Rust workspace `1.1.0`).
Toolchain: Flutter `D:\flutter`, cargo `~\.cargo\bin`, Android SDK `D:\Android\Sdk`,
NDK `28.2.13676358`, build-tools `36.0.0`, JDK `21.0.8`.

All artifacts are in `D:\tmp\capsi_verify\`.

---

## Result summary

| Phase | Class | Result |
|---|---|---|
| P0 — environment & freeze | B | **PASS** |
| P1 — core + Dart gate | A | **PASS** |
| P2 — Windows artifact integrity | A | **PASS** |
| P3 — Android artifact integrity (steps 1–5) | A | **FAIL — blocker B1** |
| P3 — Android on-device (step 6) | A | **NOT RUN — no device attached** |
| P4 — install / first-run truth states | B | **NOT RUN — blocked by B1** |
| P5 — two-device matrices | C | **NOT RUN** |
| P6 — release readiness | — | **NOT RUN** |

**The candidate is not shippable.** Blocker B1 (debug-signed release APK) is a hard stop
on its own, and it also blocks P4's install verification from completing on a clean
machine.

---

## P0 — Environment and freeze: PASS

- Freeze commit `7027d131`, tree clean before and after the run (`git status --short`
  empty).
- `flutter` is **not** on `PATH` in a default PowerShell session, as the plan's §1.4
  warns. All `tool/*.ps1` runs prefixed `set PATH=D:\flutter\bin;%PATH%`.
- Stale `Capsi-1.0.2-x64.msi` was present in `build\` alongside `Capsi-1.1.0-x64.msi`
  and was deleted so the installer filename cannot be mistaken for the candidate.
- `key.properties` does **not** exist; `android/.gitignore` already ignores it plus
  `**/*.keystore` and `**/*.jks`, so the ignore-side of B1's fix is already in place.

Evidence: `commit.txt`, `pub_get.log`.

## P1 — Automated gate: PASS

| Check | Command | Result |
|---|---|---|
| Core tests | `cargo test -p capsi-core` | **105 passed, 0 failed** |
| Static analysis | `flutter analyze` | **No issues found** (22.0 s) |
| Dart tests | `flutter test` | **6 tests, all passed** |

The self-check contract is covered: `test/self_test_report_test.dart` asserts that a
fully-passed engine report names every step, which is the FFI envelope path P1 step 4
requires. No test had to be added.

Evidence: `cargo_test.log`, `analyze.log`, `flutter_test.log`.

## P2 — Windows artifact integrity: PASS

**Self-containment** — every binary in `build\windows\x64\runner\Release` reads `False`
for both `MSVCP140` and `VCRUNTIME140`. The `/MT` static build holds; no Visual C++
redistributable dependency exists in the shipped bundle.

| File | Bytes | Msvcp140 | Vcruntime140 |
|---|---|---|---|
| `capsi.exe` | 398,336 | False | False |
| `capsi_ffi.dll` | 2,409,984 | False | False |
| `file_selector_windows_plugin.dll` | 353,792 | False | False |
| `flutter_windows.dll` | 21,274,112 | False | False |
| `native_assets.json` | 45 | False | False |
| `url_launcher_windows_plugin.dll` | 331,264 | False | False |

**Architecture** — all three PE machine values are `0x8664` (x64). No 32-bit artifact
masquerading in an x64 folder.

**Live FFI probe** — `capsi_ffi.dll` loads outside Flutter and `capsi_self_test`
returns all six steps passing (`core_linked`, `protocol`, `storage`, `identity`,
`network_listener`, `discovery`). Deleting the DLL makes the app report the engine as
unavailable rather than claiming readiness, and restoring it recovers cleanly, which
exercises both sides of the three-state badge at the FFI layer.

**Installer fidelity** — the three binaries inside `Capsi-1.1.0-x64.msi` are
bit-identical (SHA-256) to the bundle that was just verified:

| File | Match |
|---|---|
| `capsi.exe` | True |
| `capsi_ffi.dll` | True |
| `flutter_windows.dll` | True |

This closes the stale-installer risk that CI cannot cover, since CI never uploads the
MSI (gap G3).

Evidence: `p2_bundle_hashes.txt`, `p2_pe_machine.txt`, `p2_msi_hashmatch.txt`,
`win_build.log`, `ffi_probe.ps1`, `badge_final.png`, `t2_no_dll_full.png`,
`t3_second_instance.png`.

## P3 — Android artifact integrity: FAIL (blocker B1)

### Steps 1–4: PASS

`tool/build_android.ps1` completed and produced
`build/app/outputs/flutter-apk/app-release.apk`, 57,006,415 bytes. The script's own
`throw` on a missing ABI did not fire, so all three ABIs were genuinely produced.

**APK contents** — exactly the three expected entries, no ABI splits:

```
lib/arm64-v8a/libcapsi_ffi.so       1913464
lib/armeabi-v7a/libcapsi_ffi.so     1316220
lib/x86_64/libcapsi_ffi.so          2180672
```

**ELF machine types** — correct per ABI, so the ABI matrix is real and not an
accident of directory naming:

| ABI | ELF class | Machine | Expected |
|---|---|---|---|
| `arm64-v8a` | 64-bit | 183 (AArch64) | 183 ✓ |
| `armeabi-v7a` | 32-bit | 40 (ARM) | 40 ✓ |
| `x86_64` | 64-bit | 62 (x86-64) | 62 ✓ |

The 32-bit ELF class for `armeabi-v7a` is the independent confirmation that the ARM
library was genuinely cross-compiled rather than a copy.

**Provenance** — the APK's `.so` files do **not** hash-match `jniLibs` (e.g. arm64
`92A9411B…` vs `26FC7F61…`). This is expected, not a defect: AGP strips native
libraries during packaging, and `Cargo.toml` already sets `strip`, so no build-id
survives to compare directly. Re-running the NDK's `llvm-strip --strip-unneeded` over
the `jniLibs` originals reproduces the APK bytes **exactly**:

| ABI | Stripped `jniLibs` | APK | Match |
|---|---|---|---|
| `arm64-v8a` | `92A9411BA20B33FF` (1,913,464) | `92A9411BA20B33FF` (1,913,464) | True |
| `armeabi-v7a` | `74D3CC4CAF2AB232` (1,316,220) | `74D3CC4CAF2AB232` (1,316,220) | True |
| `x86_64` | `37BA98C086835376` (2,180,672) | `37BA98C086835376` (2,180,672) | True |

So the shipped APK provably contains the libraries just built — the step-2 check
passes once packaging-time stripping is accounted for.

**Packaged manifest** (`aapt2 dump badging`):

- `package: name='win.capsi.app' versionCode='2' versionName='1.1.0'` ✓
- `application-label:'Capsi'` ✓
- `native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'` ✓
- All six declared permissions present, including `INTERNET` in the **main** manifest —
  the one that builds cleanly and then opens no socket if it is missing from release:
  `INTERNET`, `ACCESS_NETWORK_STATE`, `CHANGE_WIFI_MULTICAST_STATE`,
  `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`.
  (One extra generated entry, `win.capsi.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`,
  is added by AGP and is expected.)
- **OS floor recorded** (not pinned in the repo, gap G5): `minSdkVersion 24`,
  `targetSdkVersion 36`, `compileSdkVersion 36`.

### Step 5: FAIL — the release APK is debug-signed

`apksigner verify --print-certs` succeeds, but it is verifying the wrong identity:

```
Signer #1 certificate DN: C=US, O=Android, CN=Android Debug
Signer #1 certificate SHA-256 digest: 72d7938fd9b928ec5c44946f013a2d5fb3f760ba514c6c0437e3ca9ec7aec4cd9b8
```

Per the plan's own table this is an unambiguous **FAIL**, and the source confirms why:

- `android/app/build.gradle.kts:36` — `signingConfig = signingConfigs.getByName("debug")`
  in the `release` build type, carrying the Flutter template's own TODO.
- `android/key.properties` does not exist, so no release key is configured.
- The ignore rules (`android/.gitignore`) already anticipate `key.properties`,
  `**/*.keystore` and `**/*.jks` — only the Gradle side is missing.

Signing schemes: **v2 only** (v1 `false`, v3 `false`, v3.1 `false`, v4 `false`). That
installs fine across the declared range — `minSdk 24` is above the v1 cutoff and the
target range is v2-served — so this is not an additional defect, but it is recorded
because the plan asks for it.

Evidence: `p3_apksigner.txt`, `p3_apksigner_v.txt`, `p3_apk_libs.txt`, `p3_badging.txt`,
`buildid.ps1`, `android_build.log`.

### Step 6: NOT RUN — no device available

`adb devices -l` lists nothing, and the SDK has no `emulator` component or system
images installed, so no device, emulator or AVD could be started. The on-device
criteria — no `AndroidRuntime` fatal, no `dlopen` failure, `MessageListenerService`
foreground, badge reading **Ready** with six steps passed — are **unverified**, and must
not be reported as passing. The second-ABI device is likewise still required.

## P4 — Install and first-run truth states: NOT RUN

Blocked on two counts: B1 must be fixed before a shipping-signature artifact exists,
and P4.1 requires a VM without a Visual C++ redistributable. The Windows badge matrix
T1–T5 was partially exercised during P2 at the FFI layer (DLL present → healthy, DLL
removed → engine reported unavailable, second instance → port conflict surfaced), which
is encouraging but is **not** a substitute for the specified clean-VM install and
per-step truth-state text.

## P5 / P6: NOT RUN

Both are Class C / out of scope without two physical devices. No claim is made about
them.

---

## Blockers

### B1 (hard stop) — release APK is signed with the debug key

`build.gradle.kts:36` sets the `release` build type to the debug `signingConfig`, and no
`key.properties` exists. Fix by generating a release keystore, adding a
`signingConfigs.create("release")` block reading `key.properties`, pointing
`buildTypes.release` at it, and re-running P3 step 5. The fingerprint of the resulting
key must be recorded in the release notes. Expect one `adb uninstall` of any
debug-signed build already on a test device, per the plan's
`INSTALL_FAILED_UPDATE_INCOMPATIBLE` row.

### B2 (environment, not a product defect) — no Android device reachable

P3 step 6 and P4's Android half cannot be executed on this machine. `adb devices` is
empty and no emulator/system images are installed under `D:\Android\Sdk`. Provisioning
either a physical device over ADB or an AVD is required before the truth-state claims
can be made at all.

---

## What the CI gate does and does not cover

Worth stating explicitly, because a green CI run must not be read as a verified product:
CI never builds or uploads the MSI (G3), never installs either artifact, and never runs
on a device. Everything about *the artifact as shipped* — self-containment, installer
fidelity, signing identity, and every truth state the badge can display — is verified
only by the local procedures above, and two of them are still open.