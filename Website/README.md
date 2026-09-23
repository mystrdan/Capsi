# CAPSI — Official Website

**Capsi — Messages and files, device to device.**

> Run it. Find the computers. Send.

This folder contains the official static website for **CAPSI** by **CAPSICOM**
(`https://capsi.win`).

## Files

| File | Purpose |
|---|---|
| `index.html` | Homepage: hero, how it works, features, on-premises, Windows, download CTA |
| `about.html` | About + contact page |
| `styles.css` | All website styles (dark Capsi theme, responsive) |
| `app.js` | Mobile menu + applies the centralized download URL |
| `config.js` | **Single place to change the download link** (`CAPSI_CONFIG.DOWNLOAD_URL`) |
| `app-screenshot.png` | **Hero screenshot (image 1)** — full dark-UI collage: main chat window + splash/welcome + broadcast, file transfer, groups, settings, tray menu. Replace this file with the first image you posted. Displayed large in the hero (max 640px) and used as og:image / twitter:image. |
| `app-live.png` | **Live-app band (image 2)** — real Windows photo of Capsi running (Conversations / Nearby / Files, type-a-message bar). Save the second image you posted under this name; the staged `<section class="shot-band" hidden>` in `index.html` unhides automatically once the file exists. |
| `logo-solid.png` | Capsi logo variant |
| `favicon.png` | Favicon |

## Download URL configuration

All **Download Capsi** buttons carry class `js-download` and point at the
direct GitHub release asset. `app.js` overwrites them at runtime from
`config.js`, so there is exactly one value to change:

```js
// config.js
const CAPSI_CONFIG = {
  DOWNLOAD_URL: "https://github.com/mystrdan/Capsi/releases/latest/download/Capsi_1.0.0_x64-setup.exe",
  ...
};
```

Flow: `capsi.win` → **Download Capsi** → installer downloads directly.
No repository/release page in between.

## Auto latest-release resolution

`app.js` keeps the buttons fresh without manual edits:

1. On load it applies `CAPSI_CONFIG.DOWNLOAD_URL` immediately (works offline).
2. It then calls `GET https://api.github.com/repos/{GITHUB_REPO}/releases/latest`,
   picks the Windows asset (NSIS `*-setup.exe` → any `.exe` → `.msi`;
   source archives are never picked), and rewrites every `.js-download` href
   to that asset's `browser_download_url`.

To retarget (new owner/repo), edit `GITHUB_REPO` in `config.js` only.
If the API is unreachable or rate-limited, buttons silently keep the fallback.

## Run locally

No build step, no dependencies. Serve statically, e.g.:

```powershell
cd Website
python -m http.server 8080
# open http://localhost:8080/
```

Or open `index.html` directly in a browser.

## Deploy

Copy the contents of `Website/` to any static host (GitHub Pages, Netlify,
Vercel, Nginx, IIS, …) serving `index.html` at `/`. All asset paths are
relative (`./…`) so the site works under `capsi.win` or a sub-path preview.
