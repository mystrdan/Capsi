export function renderFooter() {
  const mount = document.querySelector('[data-component="footer"]');
  if (!mount) return;
  mount.innerHTML = `
<footer class="site-footer">
  <div class="container footer-inner">
    <div class="footer-brand"><p class="footer-name">CAPSI</p></div>
    <nav class="footer-nav" aria-label="Footer">
      <a href="./index.html#download">Download</a>
      <a href="./about.html">About</a>
      <a href="./about.html#contact">Contact</a>
    </nav>
  </div>
</footer>`;
}