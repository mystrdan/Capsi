(function () {
  var cfg = window.CAPSI_CONFIG || {};
  var downloadUrl = cfg.DOWNLOAD_URL || "https://github.com/mystrdan/Capsi/releases/latest/download/capsi.exe";
  var links = document.querySelectorAll("a.js-download");
  for (var i = 0; i < links.length; i++) {
    links[i].setAttribute("href", downloadUrl);
  }
  var toggle = document.getElementById("menu-toggle");
  var menu = document.getElementById("mobile-menu");
  if (toggle && menu) {
    toggle.addEventListener("click", function () {
      var open = menu.hasAttribute("hidden");
      if (open) {
        menu.removeAttribute("hidden");
        toggle.setAttribute("aria-expanded", "true");
        toggle.setAttribute("aria-label", "Close menu");
      } else {
        menu.setAttribute("hidden", "");
        toggle.setAttribute("aria-expanded", "false");
        toggle.setAttribute("aria-label", "Open menu");
      }
    });
    menu.addEventListener("click", function (e) {
      if (e.target && e.target.tagName === "A") {
        menu.setAttribute("hidden", "");
        toggle.setAttribute("aria-expanded", "false");
      }
    });
    // Safety: if the viewport grows to desktop while the menu is open,
    // close it so no mobile UI lingers.
    window.addEventListener("resize", function () {
      if (window.matchMedia("(min-width: 641px)").matches && !menu.hasAttribute("hidden")) {
        menu.setAttribute("hidden", "");
        toggle.setAttribute("aria-expanded", "false");
        toggle.setAttribute("aria-label", "Open menu");
      }
    });
  }
})();
