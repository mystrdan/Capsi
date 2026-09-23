(function () {
  var cfg = window.CAPSI_CONFIG || {};
  var FALLBACK_URL = cfg.DOWNLOAD_URL || "https://github.com/mystrdan/Capsi/releases/latest/download/Capsi_1.0.0_x64-setup.exe";
  var REPO = cfg.GITHUB_REPO || "mystrdan/Capsi";

  function applyDownloadUrl(url) {
    var links = document.querySelectorAll("a.js-download");
    for (var i = 0; i < links.length; i++) {
      links[i].setAttribute("href", url);
    }
  }

  function pickWindowsAsset(assets) {
    if (!assets || !assets.length) return null;
    function find(re) {
      for (var i = 0; i < assets.length; i++) {
        if (re.test(assets[i] && assets[i].name || "")) return assets[i];
      }
      return null;
    }
    // NSIS setup exe first, then any exe, then MSI — never source archives.
    return find(/setup.*\.exe$/i) || find(/\.exe$/i) || find(/\.msi$/i) || null;
  }

  // Auto-resolve the newest Windows asset so Download buttons never go stale
  // when a new GitHub Release is published. Falls back silently.
  function resolveLatestRelease() {
    try {
      var controller = new AbortController();
      var timer = setTimeout(function () { controller.abort(); }, 6000);
      fetch("https://api.github.com/repos/" + REPO + "/releases/latest", { signal: controller.signal })
        .then(function (res) {
          clearTimeout(timer);
          if (!res.ok) throw new Error("release lookup failed");
          return res.json();
        })
        .then(function (rel) {
          var asset = pickWindowsAsset(rel && rel.assets);
          if (asset && asset.browser_download_url) applyDownloadUrl(asset.browser_download_url);
        })
        .catch(function () { /* keep fallback URL */ });
    } catch (e) { /* keep fallback URL */ }
  }

  applyDownloadUrl(FALLBACK_URL);
  resolveLatestRelease();
  // Unhide the live-app band the moment app-live.png exists (HEAD check, no
  // download). Until you save image 2 as Website/app-live.png the section
  // stays hidden so there is never a broken image icon.
  (function revealLiveShot() {
    var band = document.querySelector('.shot-band[hidden]');
    if (!band) return;
    var img = band.querySelector('img');
    if (!img) return;
    var url = img.getAttribute('src');
    if (!url) return;
    function show() { band.removeAttribute('hidden'); band.classList.remove('shot-hidden'); }
    try {
      fetch(url, { method: 'HEAD' }).then(function (res) {
        if (res && res.ok) show();
        else { img.addEventListener('error', function () {}, { once: true }); }
      }).catch(function () { /* stays hidden until the file is uploaded */ });
    } catch (e) { /* stays hidden */ }
    // Fallback: if the file loads despite HEAD being blocked, reveal it.
    img.addEventListener('load', show, { once: true });
  })();
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
