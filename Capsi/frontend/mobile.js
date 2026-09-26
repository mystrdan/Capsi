/* Capsi mobile presentation layer. Product logic remains in app.js. */
const sidebar = document.getElementById('sidebar');
const menu = document.getElementById('btn-mobile-menu');
const backdrop = document.getElementById('mobile-menu-backdrop');
const mobileSettings = document.getElementById('btn-mobile-settings');

function closeMenu() {
  sidebar?.classList.remove('mobile-open');
  backdrop?.classList.remove('show');
}

function openMenu() {
  sidebar?.classList.add('mobile-open');
  backdrop?.classList.add('show');
}

menu?.addEventListener('click', openMenu);
backdrop?.addEventListener('click', closeMenu);

mobileSettings?.addEventListener('click', () => {
  document.getElementById('btn-settings')?.click();
  closeMenu();
});

document.querySelectorAll('[data-mobile-panel]').forEach((button) => {
  button.addEventListener('click', () => {
    const target = button.dataset.mobilePanel;
    document.querySelector(`.nav-tab[data-panel="${target}"]`)?.click();
    document.querySelectorAll('[data-mobile-panel]').forEach((item) => item.classList.toggle('active', item === button));
  });
});

document.querySelectorAll('.nav-tab').forEach((tab) => {
  tab.addEventListener('click', () => {
    const target = tab.dataset.panel;
    document.querySelectorAll('[data-mobile-panel]').forEach((item) => item.classList.toggle('active', item.dataset.mobilePanel === target));
    if (window.matchMedia('(max-width: 760px)').matches) closeMenu();
  });
});
