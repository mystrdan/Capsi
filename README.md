# Capsi

**CAPSI — Messages and files, device to device.**

> Run it. Find the computers. Send.

Capsi by **CAPSICOM** is a lightweight on-premises / local-network
communication and file-transfer utility. Computers on the same local network
discover each other and exchange messages and files directly — no cloud, no
accounts, no unnecessary infrastructure.

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

