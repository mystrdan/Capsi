// Capsi - frontend application logic.
//
// Talks to the Rust backend through the Tauri invoke API and listens for
// `discovery-event` pushes from the discovery loop. Every class name used here
// is one that `style.css` actually styles, so the two files stay in step.

const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const state = {
  conversations: [],
  peers: [],
  transfers: [],
  activeConv: null,
  activeWorkplaceGroup: null,
  activePanel: 'conversations',
  identity: null,
  workplace: null,
};

const $ = (id) => document.getElementById(id);

/* ---------- helpers ---------- */

function escapeHtml(s) {
  const div = document.createElement('div');
  div.textContent = s == null ? '' : String(s);
  return div.innerHTML;
}

function shortId(id) {
  return id ? String(id).slice(0, 8) : '';
}

/// "Studio Mac" -> "SM", "Kitchen" -> "KI": the avatar text in list rows.
function initials(name) {
  const parts = String(name || '').trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return '?';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

function formatTime(secs) {
  if (!secs) return '';
  const d = new Date(secs * 1000);
  return d.toDateString() === new Date().toDateString()
    ? d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
    : d.toLocaleDateString([], { month: 'short', day: 'numeric' });
}

function formatSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

function showToast(message, isError = false) {
  const toast = $('toast');
  toast.textContent = message;
  toast.classList.toggle('error', isError);
  toast.classList.add('show');
  clearTimeout(showToast._t);
  showToast._t = setTimeout(() => toast.classList.remove('show'), 3000);
}

/// The best label we have for a device, in the order the user cares about.
function peerName(deviceId) {
  const peer = state.peers.find((p) => p.device_id === deviceId);
  if (peer) return peer.alias || peer.name || shortId(deviceId);
  const conv = state.conversations.find((c) => c.device_id === deviceId);
  return conv && conv.name ? conv.name : shortId(deviceId);
}

/* ---------- data loading ---------- */

async function loadConversations() {
  try {
    state.conversations = await invoke('list_conversations');
    renderConversations();
  } catch (e) {
    showToast(`Failed to load conversations: ${e}`, true);
  }
}

async function loadPeers() {
  try {
    state.peers = await invoke('list_peers');
    renderPeers();
  } catch (e) {
    showToast(`Failed to load peers: ${e}`, true);
  }
}

async function loadTransfers() {
  try {
    state.transfers = await invoke('list_transfers');
    renderTransfers();
  } catch (e) {
    showToast(`Failed to load transfers: ${e}`, true);
  }
}

async function loadWorkplace() {
  try {
    const snapshot = await invoke('get_workplace');
    state.workplace = snapshot.workspace;
    renderWorkplace(snapshot);
  } catch (e) {
    showToast(`Failed to load workplace: ${e}`, true);
  }
}

function renderWorkplace(snapshot) {
  const panel = $('panel-workplace');
  const workspace = snapshot && snapshot.workspace;
  if (!workspace) {
    panel.innerHTML = `
      <div class="workplace-empty">
        <div class="workplace-mark">W</div>
        <h2>Create a workplace</h2>
        <p class="muted">Set up a local workplace for this device. Trusted Capsi devices can be added as people.</p>
        <form id="workplace-create-form" class="workplace-form">
          <input class="detail-input" id="workplace-name" maxlength="64" placeholder="Workplace name" autocomplete="off" required>
          <button class="btn btn-primary" type="submit">Create workplace</button>
        </form>
      </div>`;
    $('workplace-create-form').addEventListener('submit', async (e) => {
      e.preventDefault();
      const name = $('workplace-name').value.trim();
      if (!name) return;
      try {
        await invoke('create_workplace', { name });
        showToast('Workplace created');
        await loadWorkplace();
      } catch (err) { showToast(`Could not create workplace: ${err}`, true); }
    });
    return;
  }

  const memberIds = new Set(workspace.members.map((m) => m.device_id));
  const candidates = state.peers.filter((p) => p.state === 'trusted' && !memberIds.has(p.device_id));
  const canManage = (snapshot.permissions || []).includes('ManageMembers');
  const canGroups = (snapshot.permissions || []).includes('ManageGroups');

  panel.innerHTML = `
    <div class="workplace-summary">
      <div class="workplace-mark">${escapeHtml(initials(workspace.name))}</div>
      <div class="workplace-title">${escapeHtml(workspace.name)}</div>
      <div class="workplace-id mono">${escapeHtml(shortId(workspace.id))}</div>
    </div>
    <div class="workplace-section">
      <div class="workplace-section-title">Groups · ${workspace.groups.length}</div>
      ${workspace.groups.length ? workspace.groups.map((g) => `
        <button class="workplace-group-row ${state.activeWorkplaceGroup === g.id ? 'active' : ''}" data-open-group="${escapeHtml(g.id)}">
          <span class="workplace-group-icon">#</span>
          <span class="workplace-group-row-info"><strong>${escapeHtml(g.name)}</strong><small>${g.member_ids.length} people · ${escapeHtml(g.description || 'Workplace group')}</small></span>
          <span class="mono">${workspace.messages.filter(m => m.group_id === g.id).length || ''}</span>
        </button>`).join('') : '<p class="muted workplace-hint">No groups yet.</p>'}
      ${canGroups ? `
        <form id="workplace-group-form" class="workplace-form workplace-group-form">
          <input class="detail-input" id="workplace-group-name" maxlength="64" placeholder="Group name" required>
          <input class="detail-input" id="workplace-group-description" maxlength="160" placeholder="Description (optional)">
          <button class="btn btn-sm btn-primary" type="submit">Create group</button>
        </form>` : ''}
    </div>
    <div class="workplace-section">
      <div class="workplace-section-title">People · ${workspace.members.length}</div>
      <div class="workplace-members">
        ${workspace.members.map((m) => `
          <div class="workplace-member">
            <div class="conv-avatar">${escapeHtml(initials(m.display_name || shortId(m.device_id)))}</div>
            <div class="workplace-member-info"><div class="workplace-member-name">${escapeHtml(m.display_name || shortId(m.device_id))}</div><div class="workplace-member-meta">${escapeHtml(m.role)}</div></div>
            ${canManage && m.device_id !== workspace.owner_device_id ? `<button class="btn btn-sm btn-danger" data-remove-member="${escapeHtml(m.device_id)}">Remove</button>` : ''}
          </div>`).join('')}
      </div>
      ${canManage ? `<div class="workplace-add"><div class="workplace-section-title">Add trusted device</div>${candidates.length ? candidates.map((p) => `
        <button class="workplace-candidate" data-add-member="${escapeHtml(p.device_id)}"><span class="conv-avatar">${escapeHtml(initials(p.alias || p.name || shortId(p.device_id)))}</span><span><strong>${escapeHtml(p.alias || p.name || shortId(p.device_id))}</strong><small>Trusted</small></span><b>+</b></button>`).join('') : '<p class="muted workplace-hint">Trust a device in Nearby first.</p>'}</div>` : ''}
    </div>
    <div class="workplace-section">
      <div class="workplace-section-title">Departments · ${workspace.departments.length}</div>
      ${workspace.departments.length ? workspace.departments.map((d) => `<div class="workplace-group"><div><strong>${escapeHtml(d.name)}</strong><small>${d.member_ids.length} people</small></div></div>`).join('') : '<p class="muted workplace-hint">No departments yet.</p>'}
      ${canGroups ? '<form id="workplace-department-form" class="workplace-form"><input class="detail-input" id="workplace-department-name" maxlength="64" placeholder="Department name" required><button class="btn btn-sm btn-primary" type="submit">Create department</button></form>' : ''}
    </div>`;

  panel.querySelectorAll('[data-open-group]').forEach((el) => el.addEventListener('click', () => openWorkplaceGroup(el.dataset.openGroup)));
  panel.querySelectorAll('[data-add-member]').forEach((el) => el.addEventListener('click', async () => {
    try { await invoke('add_workplace_member', { deviceId: el.dataset.addMember, displayName: '', role: 'Member' }); showToast('Person added'); await loadWorkplace(); }
    catch (e) { showToast(`Could not add person: ${e}`, true); }
  }));
  panel.querySelectorAll('[data-remove-member]').forEach((el) => el.addEventListener('click', async () => {
    try { await invoke('remove_workplace_member', { deviceId: el.dataset.removeMember }); showToast('Person removed'); await loadWorkplace(); }
    catch (e) { showToast(`Could not remove person: ${e}`, true); }
  }));
  const groupForm = $('workplace-group-form');
  if (groupForm) groupForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const name = $('workplace-group-name').value.trim(), description = $('workplace-group-description').value.trim();
    if (!name) return;
    try { await invoke('create_workplace_group', { name, description }); showToast('Group created'); await loadWorkplace(); }
    catch (e) { showToast(`Could not create group: ${e}`, true); }
  });
  const departmentForm = $('workplace-department-form');
  if (departmentForm) departmentForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const name = $('workplace-department-name').value.trim();
    if (!name) return;
    try { await invoke('create_workplace_department', { name }); showToast('Department created'); await loadWorkplace(); }
    catch (e) { showToast(`Could not create department: ${e}`, true); }
  });
}

async function openWorkplaceGroup(groupId) {
  const workspace = state.workplace;
  if (!workspace) return;
  const group = workspace.groups.find((g) => g.id === groupId);
  if (!group) return;
  state.activeWorkplaceGroup = groupId;
  switchPanel('workplace');
  await loadWorkplace();
  const identity = state.identity || await invoke('get_device_info').catch(() => null);
  state.identity = identity;
  renderWorkplaceMessages(group);
}

function renderWorkplaceMessages(group) {
  const workspace = state.workplace;
  const messages = (workspace.messages || []).filter((m) => m.group_id === group.id);
  $('chat-header').innerHTML = `
    <div class="chat-status"><strong># ${escapeHtml(group.name)}</strong><span>${group.member_ids.length} people</span></div>`;
  $('messages').innerHTML = messages.length ? messages.map((m) => {
    const mine = state.identity && m.sender_device_id === state.identity.device_id;
    const sender = workspace.members.find((x) => x.device_id === m.sender_device_id);
    const name = sender ? sender.display_name : shortId(m.sender_device_id);
    return `<div class="msg-bubble ${mine ? 'outgoing' : 'incoming'}">${!mine ? `<div class="workplace-message-sender">${escapeHtml(name)}</div>` : ''}<div>${escapeHtml(m.body)}</div><div class="msg-meta">${formatTime(m.sent_at)}</div></div>`;
  }).join('') : '<div class="empty-state"><p>No messages yet.</p><p class="muted">Send the first message to this group.</p></div>';
  $('messages').scrollTop = $('messages').scrollHeight;
  $('message-input').disabled = false;
  $('message-input').placeholder = `Message #${group.name}`;
  $('btn-send').disabled = false;
}

async function sendWorkplaceMessage() {
  const input = $('message-input');
  const body = input.value.trim();
  const groupId = state.activeWorkplaceGroup;
  if (!body || !groupId) return;
  try {
    await invoke('send_workplace_group_message', { groupId, body });
    input.value = '';
    input.style.height = 'auto';
    await loadWorkplace();
    const group = state.workplace.groups.find((g) => g.id === groupId);
    if (group) renderWorkplaceMessages(group);
  } catch (e) {
    showToast(`Failed to send workplace message: ${e}`, true);
  }
}

async function openConversation(deviceId, fallbackName) {
  state.activeConv = deviceId;
  try {
    const conv = await invoke('load_conversation', { deviceId });
    // Reading a conversation clears its unread badge on the Rust side.
    await invoke('mark_read', { deviceId }).catch(() => {});
    renderMessages(conv, fallbackName || peerName(deviceId));
    renderConversations();
    await loadConversations();
  } catch (e) {
    showToast(`Failed to open conversation: ${e}`, true);
  }
}

async function sendMessage() {
  if (state.activeWorkplaceGroup) return sendWorkplaceMessage();
  const input = $('message-input');
  const body = input.value.trim();
  if (!body || !state.activeConv) return;
  try {
    await invoke('send_message', { deviceId: state.activeConv, body });
    input.value = '';
    input.style.height = 'auto';
    await openConversation(state.activeConv);
  } catch (e) {
    showToast(`Failed to send: ${e}`, true);
  }
}

async function deleteActiveConversation() {
  if (!state.activeConv) return;
  const name = peerName(state.activeConv);
  try {
    await invoke('delete_conversation', { deviceId: state.activeConv });
    state.activeConv = null;
    $('messages').innerHTML =
      '<div class="empty-state"><p>Select a conversation</p><p class="muted">Chats live on this machine only.</p></div>';
    $('chat-header').innerHTML = '<div class="chat-status">Select a conversation</div>';
    $('message-input').disabled = true;
    $('btn-send').disabled = true;
    showToast(`Deleted the conversation with ${name}`);
    await loadConversations();
  } catch (e) {
    showToast(`Failed to delete: ${e}`, true);
  }
}

/* ---------- rendering ---------- */

function renderConversations() {
  const panel = $('panel-conversations');
  if (!state.conversations.length) {
    panel.innerHTML = `
      <div class="empty-state">
        <svg class="empty-icon" viewBox="0 0 24 24" width="40" height="40">
          <path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H5.17L4 17.17V4h16v12z" fill="currentColor"/>
        </svg>
        <p>No conversations yet.</p>
        <p class="muted">Trust a device on the Nearby tab to start chatting.</p>
      </div>`;
    return;
  }
  panel.innerHTML = state.conversations
    .map((c) => {
      const name = c.name || peerName(c.device_id);
      const badge = c.unread ? `<span class="unread-badge">${c.unread}</span>` : '';
      return `
      <div class="conv-item ${c.device_id === state.activeConv ? 'active' : ''}" data-id="${escapeHtml(c.device_id)}">
        <div class="conv-top">
          <div class="conv-avatar">${escapeHtml(initials(name))}</div>
          <div class="conv-name">${escapeHtml(name)}</div>
          <div class="conv-time">${formatTime(c.last_message_at)}</div>
        </div>
        <div class="conv-preview">${badge}<span class="muted">${escapeHtml(shortId(c.device_id))}</span></div>
      </div>`;
    })
    .join('');
  panel.querySelectorAll('.conv-item').forEach((el) =>
    el.addEventListener('click', () => openConversation(el.dataset.id))
  );
}

function renderPeers() {
  const panel = $('panel-peers');
  if (!state.peers.length) {
    panel.innerHTML = `
      <div class="empty-state">
        <p>No devices found.</p>
        <p class="muted">Make sure the other device is running Capsi and both devices have a supported communication path.</p>
      </div>`;
    return;
  }
  panel.innerHTML = state.peers
    .map((p) => {
      const label = p.alias || p.name || shortId(p.device_id);
      return `
      <div class="peer-item" data-id="${escapeHtml(p.device_id)}">
        <div class="peer-avatar ${escapeHtml(p.state)}">${escapeHtml(initials(label))}</div>
        <div class="peer-info">
          <div class="peer-name">${escapeHtml(label)}</div>
          <div class="peer-fingerprint">${escapeHtml(p.fingerprint)}</div>
        </div>
        <span class="peer-state ${escapeHtml(p.state)}">${escapeHtml(p.state)}</span>
      </div>`;
    })
    .join('');
  panel.querySelectorAll('.peer-item').forEach((el) =>
    el.addEventListener('click', () => openPeerPanel(el.dataset.id))
  );
}

function renderTransfers() {
  const panel = $('panel-transfers');
  if (!state.transfers.length) {
    panel.innerHTML = `
      <div class="empty-state">
        <p>No file transfers.</p>
        <p class="muted">Files offered or in flight will appear here.</p>
      </div>`;
    return;
  }
  panel.innerHTML = state.transfers
    .map(
      (t) => `
      <div class="transfer-item">
        <div class="transfer-top">
          <div class="transfer-file-icon">&#128206;</div>
          <div class="transfer-info">
            <div class="transfer-file-name">${escapeHtml(t.file_name)}</div>
            <div class="transfer-file-meta">${formatSize(t.size)} &middot; ${escapeHtml(t.state)}</div>
          </div>
        </div>
        <div class="transfer-peers">${escapeHtml(t.peer_name)}</div>
        <div class="transfer-actions">
          ${
            t.state === 'offered'
              ? `<button class="btn btn-sm btn-primary" data-act="accept" data-id="${escapeHtml(t.device_id)}" data-tid="${escapeHtml(t.transfer_id)}">Accept</button>
                 <button class="btn btn-sm btn-danger" data-act="decline" data-id="${escapeHtml(t.device_id)}" data-tid="${escapeHtml(t.transfer_id)}">Decline</button>`
              : `<span class="muted">${escapeHtml(t.state)}</span>`
          }
        </div>
      </div>`
    )
    .join('');
  panel
    .querySelectorAll('.transfer-actions button[data-act]')
    .forEach((btn) => btn.addEventListener('click', () => handleTransferAction(btn)));
}

async function handleTransferAction(btn) {
  const { act, id, tid } = btn.dataset;
  try {
    if (act === 'accept') {
      await invoke('accept_file', { deviceId: id, transferId: tid, saveTo: null });
      showToast('Transfer accepted');
    } else {
      await invoke('decline_file', { deviceId: id, transferId: tid });
      showToast('Transfer declined');
    }
    await loadTransfers();
  } catch (e) {
    showToast(`Transfer failed: ${e}`, true);
  }
}

function renderMessages(conv, fallbackName) {
  const name = (conv && conv.name) || fallbackName || peerName(state.activeConv);
  // `chat-open` flips the phone layout (see style.css) to the chat screen.
  document.body.classList.add('chat-open');
  $('chat-header').innerHTML = `
    <div class="chat-header-row">
      <button class="btn btn-sm" id="btn-back-list" title="Back">&larr;</button>
      <div class="chat-status"><strong>${escapeHtml(name || 'Unknown')}</strong> &middot; <span class="mono">${escapeHtml(shortId(state.activeConv))}</span></div>
      <button class="btn btn-sm btn-danger" id="btn-delete-conv">Delete chat</button>
    </div>`;
  $('btn-back-list').addEventListener('click', () => {
    state.activeConv = null;
    document.body.classList.remove('chat-open');
  });
  $('btn-delete-conv').addEventListener('click', deleteActiveConversation);

  const messages = $('messages');
  const list = (conv && conv.messages) || [];
  if (!list.length) {
    messages.innerHTML =
      '<div class="empty-state"><p>No messages yet.</p><p class="muted">Say hello!</p></div>';
  } else {
    messages.innerHTML = list
      .map((m) => {
        const body = m.body ? escapeHtml(m.body) : '';
        const file =
          m.kind === 'file'
            ? `<div class="msg-file">
                <div class="file-icon">&#128206;</div>
                <div class="file-info">
                  <div class="file-name">${escapeHtml(m.file_name || 'file')}</div>
                  <div class="file-size">${m.file_size ? formatSize(m.file_size) : ''}</div>
                </div>
                <span class="file-state ${escapeHtml(m.file_state || '')}">${escapeHtml(m.file_state || '')}</span>
              </div>`
            : '';
        return `<div class="msg-bubble ${m.outgoing ? 'outgoing' : 'incoming'}">
          ${body}${file}
          <div class="msg-meta">${formatTime(m.sent_at)}</div>
        </div>`;
      })
      .join('');
    messages.scrollTop = messages.scrollHeight;
  }
  $('message-input').disabled = false;
  $('btn-send').disabled = false;
}

/* ---------- detail panel ---------- */

function closeDetail() {
  $('detail-panel').classList.add('hidden');
}

function showDetail(title, html) {
  $('detail-title').textContent = title;
  $('detail-body').innerHTML = html;
  $('detail-panel').classList.remove('hidden');
}

function detailRow(label, value, mono) {
  return `<div class="detail-row">
    <div class="detail-label">${escapeHtml(label)}</div>
    <div class="detail-value${mono ? ' mono' : ''}">${escapeHtml(value)}</div>
  </div>`;
}

function toggleRow(id, label, checked) {
  return `<label class="detail-toggle">
    <input type="checkbox" id="opt-${id}" ${checked ? 'checked' : ''}>
    <span>${escapeHtml(label)}</span>
  </label>`;
}

/// "This Device": identity, storage location and the stored preferences.
async function openDevicePanel() {
  try {
    const [identity, settings] = await Promise.all([
      invoke('get_device_info'),
      invoke('get_settings'),
    ]);
    state.identity = identity;
    showDetail(
      'This Device',
      `
      <div class="detail-row">
        <div class="detail-label">Name</div>
        <input class="detail-input" id="device-name-input" maxlength="32"
               value="${escapeHtml(identity.device_name)}">
      </div>
      ${detailRow('Device id', identity.device_id, true)}
      ${detailRow('Fingerprint', identity.fingerprint, true)}
      ${detailRow('Contacts', `${identity.trusted_count} trusted, ${identity.pending_count} waiting`)}
      ${detailRow('Data folder', identity.data_dir, true)}
      <h3>Preferences</h3>
      ${toggleRow('notifications_enabled', 'Desktop notifications', settings.notifications_enabled)}
      ${toggleRow('auto_accept_files', 'Accept files automatically', settings.auto_accept_files)}
      ${toggleRow('start_minimized', 'Start minimised', settings.start_minimized)}
      ${toggleRow('start_discovery', 'Show this device to others', settings.start_discovery)}
      <div class="detail-actions">
        <button class="btn btn-primary" id="btn-save-device">Save</button>
        <button class="btn" id="btn-copy-id">Copy device id</button>
      </div>
      <div class="about-block">
        <h3>About</h3>
        <div class="about-app">Capsi</div>
        <div class="about-by">by CAPSICOM</div>
        <div class="about-version">Version 1.0.0</div>
        <button class="about-link" id="btn-about-website">Website &#8599;</button>
      </div>`
    );
    $('btn-save-device').addEventListener('click', saveDevicePanel);
    $('btn-copy-id').addEventListener('click', copyDeviceId);
  } catch (e) {
    showToast(`Could not read device info: ${e}`, true);
  }
}

async function saveDevicePanel() {
  const name = $('device-name-input').value.trim();
  const settings = {
    notifications_enabled: $('opt-notifications_enabled').checked,
    auto_accept_files: $('opt-auto_accept_files').checked,
    start_minimized: $('opt-start_minimized').checked,
    start_discovery: $('opt-start_discovery').checked,
  };
  try {
    if (state.identity && name !== state.identity.device_name) {
      await invoke('set_device_name', { name });
    }
    await invoke('save_settings', { settings });
    showToast('Settings saved');
  } catch (e) {
    showToast(`Could not save: ${e}`, true);
  }
}

/// Copy the device id. `navigator.clipboard` is not always available inside a
/// webview, so fall back to the old select-and-copy trick.
async function copyDeviceId() {
  try {
    const id = await invoke('export_device_id');
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(id);
    } else {
      const scratch = document.createElement('textarea');
      scratch.value = id;
      document.body.appendChild(scratch);
      scratch.select();
      document.execCommand('copy');
      scratch.remove();
    }
    showToast('Device id copied');
  } catch (e) {
    showToast(`Could not copy: ${e}`, true);
  }
}

/* ---------- detail panel: a peer ---------- */

/// What the user can do with a device, depending on where the trust list has it.
function peerActions(peer) {
  if (peer.state === 'trusted') {
    return `<button class="btn btn-primary" data-act="chat">Message</button>
      <button class="btn" data-act="rename">Rename</button>
      <button class="btn btn-danger" data-act="forget">Forget</button>`;
  }
  if (peer.state === 'blocked') {
    return `<button class="btn btn-primary" data-act="accept">Unblock</button>
      <button class="btn btn-danger" data-act="forget">Forget</button>`;
  }
  return `<button class="btn btn-primary" data-act="accept">Trust this device</button>
    <button class="btn btn-danger" data-act="ignore">Block</button>`;
}

function openPeerPanel(deviceId) {
  const peer = state.peers.find((p) => p.device_id === deviceId);
  if (!peer) return;
  const label = peer.alias || peer.name || shortId(deviceId);
  showDetail(
    label,
    `${detailRow('State', peer.state)}
     ${detailRow('Fingerprint', peer.fingerprint, true)}
     ${detailRow('Device id', peer.device_id, true)}
     ${detailRow('Address', peer.last_address || 'not seen yet', true)}
     ${detailRow('Last seen', formatTime(peer.last_seen))}
     <div class="detail-actions">${peerActions(peer)}</div>`
  );
  $('detail-body')
    .querySelectorAll('button[data-act]')
    .forEach((btn) =>
      btn.addEventListener('click', () => runPeerAction(btn.dataset.act, deviceId))
    );
}

/// Renaming happens inline in the panel: a webview cannot be relied on for
/// `window.prompt`, and an input fits the panel better anyway.
function openRenamePanel(deviceId) {
  const peer = state.peers.find((p) => p.device_id === deviceId);
  const current = (peer && (peer.alias || peer.name)) || '';
  showDetail(
    'Rename device',
    `<div class="detail-row">
       <div class="detail-label">Name</div>
       <input class="detail-input" id="alias-input" maxlength="32" value="${escapeHtml(current)}">
     </div>
     <p>Only this machine sees this name.</p>
     <div class="detail-actions">
       <button class="btn btn-primary" id="btn-save-alias">Save</button>
       <button class="btn" id="btn-cancel-alias">Cancel</button>
     </div>`
  );
  $('btn-save-alias').addEventListener('click', async () => {
    const alias = $('alias-input').value.trim();
    try {
      await invoke('rename_peer', { deviceId, alias: alias || null });
      showToast('Device renamed');
      closeDetail();
      await loadPeers();
      await loadConversations();
    } catch (e) {
      showToast(`Could not rename: ${e}`, true);
    }
  });
  $('btn-cancel-alias').addEventListener('click', () => openPeerPanel(deviceId));
}

async function runPeerAction(act, deviceId) {
  if (act === 'chat') {
    closeDetail();
    await openConversation(deviceId);
    return;
  }
  if (act === 'rename') {
    openRenamePanel(deviceId);
    return;
  }
  try {
    if (act === 'accept') {
      await invoke('accept_peer', { deviceId, alias: null });
      showToast('Device trusted');
    } else if (act === 'ignore') {
      await invoke('ignore_peer', { deviceId });
      showToast('Device blocked');
    } else if (act === 'forget') {
      await invoke('forget_peer', { deviceId });
      showToast('Device forgotten');
    }
    closeDetail();
    await loadPeers();
    await loadConversations();
  } catch (e) {
    showToast(`Action failed: ${e}`, true);
  }
}

/* ---------- panels & events ---------- */

function switchPanel(name) {
  state.activePanel = name;
  document
    .querySelectorAll('.nav-tab')
    .forEach((t) => t.classList.toggle('active', t.dataset.panel === name));
  ['conversations', 'peers', 'transfers'].forEach((p) => {
    $(`panel-${p}`).classList.toggle('hidden', p !== name);
  });
  if (name === 'conversations') { state.activeWorkplaceGroup = null; loadConversations(); }
  else if (name === 'peers') loadPeers();
  else if (name === 'transfers') loadTransfers();
  else if (name === 'workplace') loadWorkplace();
}

function wireEvents() {
  // About link: opened through the backend so the URL is allow-listed in one
  // place instead of trusting arbitrary strings from the webview.
  document.addEventListener('click', (e) => {
    const link = e.target && e.target.closest ? e.target.closest('#btn-about-website') : null;
    if (link) {
      invoke('open_website').catch((err) => showToast(`Could not open website: ${err}`, true));
    }
  });

  document
    .querySelectorAll('.nav-tab')
    .forEach((tab) =>
      tab.addEventListener('click', () => switchPanel(tab.dataset.panel))
    );

  $('btn-settings').addEventListener('click', openDevicePanel);

  $('composer').addEventListener('submit', (e) => {
    e.preventDefault();
    sendMessage();
  });

  const input = $('message-input');
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  });
  input.addEventListener('input', () => {
    input.style.height = 'auto';
    input.style.height = Math.min(input.scrollHeight, 140) + 'px';
  });

  $('btn-close-detail').addEventListener('click', closeDetail);

  // Escape closes the detail panel, the way a side sheet should behave.
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') closeDetail();
  });

  // Push events from the Rust discovery loop.
  listen('workplace-message', async () => {
    await loadWorkplace();
    if (state.activeWorkplaceGroup && state.activePanel === 'workplace') {
      const group = state.workplace && state.workplace.groups.find((g) => g.id === state.activeWorkplaceGroup);
      if (group) renderWorkplaceMessages(group);
    }
  });

  listen('message-received', async (deviceId) => {
    await loadConversations();
    if (state.activeConv && state.activeConv === deviceId) {
      await openConversation(deviceId);
    }
  });

  listen('file-offer-received', async () => {
    await loadConversations();
    await loadTransfers();
    showToast('Incoming file offer');
  });

  listen('discovery-event', () => {
    if (state.activePanel === 'peers') loadPeers();
    if (state.activePanel === 'conversations') loadConversations();
  });
}

/* ---------- boot ---------- */

wireEvents();
loadConversations();
loadPeers();
loadTransfers();
