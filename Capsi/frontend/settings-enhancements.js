// Small settings-only UX enhancements. Keeps the existing settings commands and
// presentation intact while making native actions explicit.

(() => {
  const run = () => {
    const panel = document.getElementById('detail-panel');
    const body = document.getElementById('detail-body');
    if (!panel || !body || panel.classList.contains('hidden')) return;

    const rows = body.querySelectorAll('.detail-row');
    rows.forEach((row) => {
      const label = row.querySelector('.detail-label');
      const value = row.querySelector('.detail-value');
      if (!label || !value || label.textContent.trim().toLowerCase() !== 'data folder') return;
      if (row.querySelector('[data-open-data-folder]')) return;

      const action = document.createElement('button');
      action.type = 'button';
      action.className = 'btn btn-sm settings-folder-action';
      action.dataset.openDataFolder = 'true';
      action.textContent = 'Open folder';
      action.addEventListener('click', async () => {
        try {
          await window.__TAURI__.core.invoke('open_data_folder');
        } catch (error) {
          const toast = document.getElementById('toast');
          if (toast) {
            toast.textContent = String(error);
            toast.classList.add('show', 'error');
            setTimeout(() => toast.classList.remove('show', 'error'), 3500);
          }
        }
      });
      row.appendChild(action);
    });

    const aboutBy = body.querySelector('.about-by');
    if (aboutBy) aboutBy.remove();
  };

  const observer = new MutationObserver(run);
  const start = () => {
    const body = document.getElementById('detail-body');
    if (!body) return;
    observer.observe(body, { childList: true, subtree: true });
    run();
  };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
  else start();
})();
