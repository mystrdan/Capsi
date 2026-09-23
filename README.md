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
https://github.com/mystrdan/Capsi/releases/latest/download/capsi.exe
```

The URL lives in exactly one place: `Website/config.js`
(`CAPSI_CONFIG.DOWNLOAD_URL`).
