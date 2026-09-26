# Capsi

**CAPSI — Messages and files, device to device.**

> Run it. Find the computers. Send.

Capsi by **CAPSICOM** is a lightweight on-premises communication and file-transfer utility. Devices discover
each other over an available local communication network and exchange messages
and files directly — including LAN, Wi-Fi, mobile hotspot, and other supported
network interfaces. No cloud, no accounts, no unnecessary infrastructure.

- **Website:** https://capsi.win
- **Repository:** https://github.com/mystrdan/Capsi

## Repository layout

| Path | Contents |
|---|---|
| `Capsi/` | Desktop application (Tauri + frontend) |
| `Source/` | Brand sources: logos, UI reference, master prompt |
| `Website/` | Official static website for `capsi.win` (see `Website/README.md`) |

## Website quick start

```powershell
cd Website
python -m http.server 8080
# open http://localhost:8080/
```

The download buttons point at the latest Windows release asset:

```text
https://github.com/mystrdan/Capsi/releases/latest/download/Capsi_1.0.0_x64-setup.exe
```

The URL lives in exactly one place: `Website/config.js`
(`CAPSI_CONFIG.DOWNLOAD_URL`), and `Website/app.js` auto-resolves the newest
Windows asset from the GitHub Releases API at runtime
(`CAPSI_CONFIG.GITHUB_REPO`).

## Building the Windows installer

Requirements: Rust with the MSVC toolchain, the Visual Studio *Desktop
development with C++* workload (for `rc.exe`, which embeds the icon and version
metadata into `capsi.exe`), and a Tauri CLI (`cargo install tauri-cli
--version "^2" --locked`, or the npm package `@tauri-apps/cli` which provides a
`tauri` command). NSIS does **not** need to be installed — the Tauri CLI
downloads its own copy the first time it bundles.

```powershell
cd Capsi
.\scripts\build-msvc.bat            # debug build for local testing
.\scripts\build-msvc.bat release    # target\release\capsi.exe (portable)
.\scripts\build-msvc.bat bundle     # release exe + NSIS installer
```

`bundle` writes the file users actually download:

```text
Capsi/target/release/bundle/nsis/Capsi_1.0.0_x64-setup.exe
```

The installer is per-user (`currentUser`): it installs into `%LOCALAPPDATA%\Capsi`,
adds Start Menu and desktop shortcuts, registers an uninstaller in *Apps &
features* with publisher **CAPSICOM**, and installs the WebView2 runtime when the
machine does not have it (`webviewInstallMode: downloadBootstrapper`).

Pushing a `v*` tag runs the same build on GitHub Actions
(`.github/workflows/release.yml`) and attaches the installer to the release.



## Workplace features

Capsi is also being extended as a local workplace communication layer, built on
top of its existing device discovery, trust and encrypted transport.

### Implemented and working

The following features are implemented in the current feature branch and have
working code paths/tests where applicable:

- **Device identity** — each installation has its own persistent device identity
  and fingerprint.
- **Network discovery** — Capsi advertises and discovers nearby devices over UDP on a supported local/network interface.
- **Trusted devices** — peers can be accepted, blocked, renamed, or forgotten.
  Workplace membership requires a trusted device.
- **Encrypted peer transport** — Capsi uses a signed handshake and encrypted
  TCP frames for direct device-to-device transport.
- **Workspaces** — a local workplace can be created with the current device as Owner.
- **People** — trusted devices can be added to the workplace as members.
- **Roles & permissions** — Owner, Admin, Manager, and Member permissions are
  enforced by the workplace commands.
- **Groups** — groups can be created, members can be added/removed, and groups
  can be deleted.
- **Departments** — departments can be created and members can be assigned.
- **Broadcast model** — authored broadcasts with optional department targeting
  are represented and permission-checked locally.
- **Workplace group messaging** — messages are stored locally and sent directly
  to trusted group members over the encrypted transport.
- **Workplace conversation UI** — groups can be opened as conversations with
  message history, sender names, timestamps, and a message composer.
- **Live incoming messages** — incoming workplace messages update the active
  conversation through a Tauri event.
- **Offline delivery queue** — workplace and regular 1-to-1 messages are
  persisted locally before delivery, so an unavailable recipient does not lose
  the message.
- **Automatic retry** — queued deliveries retry in the background when
  recipients become reachable again.
- **Application delivery acknowledgements** — a message is marked delivered
  only after the receiving device has accepted and persisted it.
- **Idempotent delivery** — received envelope IDs/message IDs are tracked so a
  retry cannot create duplicate history entries.
- **Workplace broadcasts** — broadcasts can now fan out directly to all
  workplace members or a selected department, using the same encrypted delivery
  queue and acknowledgement path.
- **Local-first storage** — workplace state and pending deliveries are persisted
  on-device; no cloud account or central workplace server is required.
- **Direct workplace synchronization** — workplace membership, groups,
  departments, broadcasts and workplace message history can synchronize directly
  between trusted workplace devices over the existing encrypted transport. No
  workplace server is introduced.

### Needs review / validation

The current implementation has not yet been compile-validated in this environment.
Before calling the branch release-ready, run the Rust/Tauri build and tests, then
validate Windows-to-Windows and Windows-to-Android behavior with real installations.

The following areas specifically need review or further implementation:

- **File resume/recovery** — interrupted transfers can now resume from the
  receiver's contiguous chunk prefix. A full arbitrary missing-chunk bitmap is
  not implemented yet.
- **Concurrent file transfers** — cancellation is now wired through the
  protocol, but concurrent-transfer stress testing and frontend progress polish
  still need review.
- **Network edge cases** — peer address changes, firewall rules, hotspot
  isolation, sleeping devices, and reconnect behavior need real-device testing.
- **Workplace synchronization validation** — the direct peer-to-peer sync path
  is implemented, but it still needs Windows-to-Windows and Windows-to-Android
  validation, including offline/reconnect and multiple-administrator changes.
- **Android runtime validation** — the shared Rust core is designed for Windows
  and Android and the Tauri shell is mobile-aware, but live Android device
  validation is still required.
- **File byte transfer validation** — encrypted offers, acceptance, chunk
  delivery, integrity verification, completion receipts and contiguous-prefix
  resume are implemented, but real cross-device stress testing is still
  required.

### Deliberately not part of Capsi

- **Central workplace administration** — Capsi's current philosophy is local-first
  and does not introduce a cloud service, organization server, or central
  account system. A centralized workplace administration service should not be
  added merely to make synchronization easier.

The workplace layer remains local-first: no cloud service, external server,
organization account system, or Internet connection is introduced. Devices only
need a supported communication path to reach one another.

## Implementation status

This branch is being developed incrementally. “Implemented” above means the
feature has been added to the current source and, where a deterministic test
exists, covered by tests. Cross-device behavior should still be validated with
two real Capsi installations before being treated as release-ready.
