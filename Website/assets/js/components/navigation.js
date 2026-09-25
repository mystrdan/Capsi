export function initNavigation() {
  const toggle = document.getElementById("menu-toggle");
  const menu = document.getElementById("mobile-menu");
  if (!toggle || !menu) return;
  const close = () => {
    menu.setAttribute("hidden", "");
    toggle.setAttribute("aria-expanded", "false");
    toggle.setAttribute("aria-label", "Open menu");
  };
  toggle.addEventListener("click", () => {
    if (menu.hasAttribute("hidden")) {
      menu.removeAttribute("hidden");
      toggle.setAttribute("aria-expanded", "true");
      toggle.setAttribute("aria-label", "Close menu");
    } else close();
  });
  menu.addEventListener("click", event => {
    if (event.target.closest("a")) close();
  });
  window.addEventListener("resize", () => {
    if (window.matchMedia("(min-width: 641px)").matches) close();
  });
}