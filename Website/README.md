# CAPSI — Official Website

**Capsi — Messages and files, device to device.**

> Run it. Find the computers. Send.

`Website/` contains the public-facing static website for **CAPSI by CAPSICOM** at `https://capsi.win`.

## Public website

The website is intentionally product-first. It communicates what Capsi is, how it works, its core features, local-first philosophy, current platform, FAQs, and contact information.

Implementation details, repository workflow, release mechanics, and other developer-facing material stay out of the public-facing copy.

## Files

| File | Purpose |
|---|---|
| `index.html` | Main product homepage |
| `about.html` | Product/about and contact page |
| `styles.css` | Website styling and responsive layout |
| `app.js` | Download-link resolution and mobile navigation |
| `config.js` | Central website configuration |
| `app-screenshot.png` | Capsi application preview |
| `logo.png`, `logo-solid.png` | Capsi logo assets |
| `favicon*.png`, `apple-touch-icon.png` | Browser/app icons |
| `thanks.html` | Contact-form confirmation page |

## Download links

All download buttons use the `js-download` class.

`config.js` contains the fallback release asset and repository information. `app.js` applies the fallback immediately and then attempts to resolve the newest Windows installer from the latest release. If that lookup fails, the configured fallback remains in place.

The release lookup is an implementation detail and is not presented as product functionality on the public site.

## Run locally

No build step or package installation is required:

```powershell
cd Website
python -m http.server 8080
# open http://localhost:8080/
```

Or open `index.html` directly in a browser.

## Deploy

Serve the contents of `Website/` as a static site. All asset paths are relative, so the folder can be served from `capsi.win` or another static host.

Keep changes in this folder limited to the website unless a change outside it is explicitly required by the task.