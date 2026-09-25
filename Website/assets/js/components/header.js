export function renderHeader() {
  const mount = document.querySelector('[data-component="header"]');
  if (!mount) return;
  mount.innerHTML = `
<header class="site-header">
  <div class="container header-inner">
    <a class="brand" href="./index.html" aria-label="Capsi home">
      <img src="./assets/imgs/logo.png" alt="Capsi logo" width="28" height="28" class="brand-logo">
      <span class="brand-text">CAPSI</span>
    </a>
    <nav class="site-nav" aria-label="Primary">
      <a href="./index.html#features">Features</a>
      <a href="./index.html#how-it-works">How it works</a>
      <a href="./index.html#download">Download</a>
    </nav>
    <div class="header-actions">
      <a class="btn btn-primary btn-sm js-download" href="#" download>Download Capsi</a>
      <button class="menu-toggle" id="menu-toggle" aria-expanded="false" aria-controls="mobile-menu" aria-label="Open menu"><span></span><span></span><span></span></button>
    </div>
  </div>
  <nav class="mobile-menu" id="mobile-menu" aria-label="Mobile" hidden>
    <a href="./index.html#features">Features</a>
    <a href="./index.html#how-it-works">How it works</a>
    <a href="./index.html#download">Download</a>
    <a class="btn btn-primary js-download" href="#" download>Download Capsi</a>
  </nav>
</header>`;
}