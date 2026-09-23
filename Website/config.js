/* Capsi download configuration — change in one place. */
const CAPSI_CONFIG = {
  // Fallback asset if the live GitHub lookup fails (offline, rate-limited, …).
  // Must remain a version-agnostic `releases/latest/download/...` URL.
  DOWNLOAD_URL: "https://github.com/mystrdan/Capsi/releases/latest/download/Capsi_1.0.0_x64-setup.exe",
  // Used by app.js to auto-resolve the newest Windows asset at runtime.
  GITHUB_REPO: "mystrdan/Capsi",
  GITHUB_URL: "https://github.com/mystrdan/Capsi",
  X_URL: "https://x.com/runcapsi",
  SITE_URL: "https://capsi.win",
  VERSION_LABEL: "Windows"
};
