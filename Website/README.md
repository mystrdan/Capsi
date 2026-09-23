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
| `logo.png` | Capsi logo (from `../Source/`) |
| `logo-solid.png` | Capsi logo variant |
| `favicon.png` | Favicon |

## Download URL configuration

All **Download Capsi** buttons carry class `js-download` and point at the
direct GitHub release asset. `app.js` overwrites them at runtime from
`config.js`, so there is exactly one value to change:

```js
// config.js
const CAPSI_CONFIG = {
  DOWNLOAD_URL: "https://github.com/mystrdan/Capsi/releases/latest/download/capsi.exe",
  ...
};
```

Flow: `capsi.win` → **Download Capsi** → `capsi.exe` downloads directly.
No repository/release page in between.

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
