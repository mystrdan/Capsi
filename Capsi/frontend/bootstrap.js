/* Capsi runtime bootstrap.
 * Keep the UI visible while the native Tauri bridge initializes.
 * This prevents a missing/late bridge from turning the app into a blank page.
 */

const root = document.querySelector('main');

function showRuntimeState(message, error = false) {
  let banner = document.getElementById('runtime-state');
  if (!banner) {
    banner = document.createElement('div');
    banner.id = 'runtime-state';
    banner.style.cssText = 'position:fixed;inset:auto 16px 16px 16px;z-index:100;padding:10px 14px;border:1px solid var(--border,#253047);border-radius:8px;background:var(--bg-elev,#111827);color:var(--text-muted,#9CA3AF);font:12px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;text-align:center;box-shadow:0 4px 20px rgba(0,0,0,.35);';
    root?.appendChild(banner);
  }
  banner.textContent = message;
  banner.dataset.error = error ? 'true' : 'false';
}

async function waitForTauri(timeoutMs = 8000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    if (window.__TAURI__?.core?.invoke && window.__TAURI__?.event?.listen) return true;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return false;
}

const nativeReady = await waitForTauri();

if (!nativeReady) {
  showRuntimeState('Capsi is waiting for its native runtime. Please reopen the application.', true);
} else {
  try {
    await import('./app.js');
    await import('./mobile.js');
    document.getElementById('runtime-state')?.remove();
  } catch (error) {
    console.error('Capsi failed to start:', error);
    showRuntimeState('Capsi could not start. Please reopen the application.', true);
  }
}
