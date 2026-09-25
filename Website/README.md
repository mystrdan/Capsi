# CAPSI — Official Website

**Capsi — Messages and files, device to device.**

> Run it. Find the computers. Send.

`Website/` contains the public-facing static website for **CAPSI by CAPSICOM** at `https://capsi.win`.

## Structure

- `index.html` — main product homepage
- `about.html` — product/about and contact page
- `thanks.html` — contact-form confirmation page
- `assets/css/` — stylesheet entry point
- `assets/js/` — website runtime modules
- `assets/js/components/` — reusable header, footer, navigation, download and FAQ components
- `assets/js/data/` — structured website data
- `assets/icons/` — curated SVG interface icons
- `assets/imgs/` — website image and brand assets

The website remains plain static HTML, CSS and JavaScript. No framework or package installation is required.

## Public website boundary

The public site is product-first. It explains what Capsi is, how it works, its documented capabilities, local-first behavior, current Windows availability, FAQs and contact information.

Repository workflow and other developer-facing implementation details are not presented as product content.

## Run locally

No build step is required:

```powershell
cd Website
python -m http.server 8080
# open http://localhost:8080/
```

## Deployment

Serve the contents of `Website/` as a static site. Asset paths are relative so the site can be hosted directly at `capsi.win`.

Keep website changes inside this folder unless a change outside it is explicitly required.
