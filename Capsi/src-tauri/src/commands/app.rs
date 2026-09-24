// Capsi - Tauri commands: application bootstrap and website link.
//
// The bootstrap brings the data directory, the device identity and the LAN
// discovery loop to life, and reports the identity back to the frontend.
//
// This lives in its own module rather than in the crate root on purpose: for a
// `pub` function, `#[tauri::command]` emits `#[macro_export]` copies of the
// `__cmd__<name>` / `__tauri_command_name_<name>` helper macros. `macro_export`
// hoists them to the crate root, so a command defined *at* the crate root would
// collide with its own hoisted copy and fail with E0255.

// Capsi - Tauri command: open the Capsi website.
//
// The URL is fixed in the backend (not passed from the webview) so the
// frontend cannot be tricked into opening an arbitrary link. It goes through
// the opener plugin, which uses the OS default browser on desktop and the
// system browser intent on Android/iOS.

/// Open https://capsi.win in the user's default browser.
#[tauri::command]
pub async fn open_website(app: tauri::AppHandle) -> Result<(), String> {
    open_url(&app, "https://capsi.win")
}

/// Open `url` in the default browser, but only for Capsi-owned addresses.
fn open_url(app: &tauri::AppHandle, url: &str) -> Result<(), String> {
    use tauri_plugin_opener::OpenerExt;

    if url != "https://capsi.win" && url != "https://www.capsi.win/" {
        return Err("refused to open non-Capsi URL".to_string());
    }
    app.opener()
        .open_url(url, None::<&str>)
        .map_err(|e| format!("cannot open browser: {e}"))?;
    Ok(())
}

use std::sync::Arc;
use tokio::net::TcpListener;

use tauri::{AppHandle, Emitter};

use super::{load_device_name, setup_app_data, IdentityInfo, TrustListEntry};

/// The well-known Capsi TCP port used for messages and files.
const TCP_PORT: u16 = 45892;

/// Bring Capsi up: the data directory, the device identity and the LAN
/// discovery loop.
///
/// `main` runs this once from its setup hook, before the window is shown. Each
/// call starts its own discovery loop, so treat it as once-per-process: to read
/// the identity again - after `reset_device`, say - use
/// [`super::device::get_device_info`], which only reads.
#[tauri::command]
pub async fn bootstrap(app: AppHandle) -> Result<IdentityInfo, String> {
    let data_dir = setup_app_data(&app)?;
    let identity = capsi_core::identity::DeviceIdentity::load_or_create(&data_dir)
        .map_err(|e| e.to_string())?;
    let mut trust = capsi_core::identity::trust::TrustStore::load(&data_dir)
        .map_err(|e| e.to_string())?;

    // Start a discovery loop on a tokio background thread so the UI can show
    // nearby peers even before the user opens a conversation.
    let app_handle = app.clone();
    std::thread::spawn(move || {
        let rt = match tokio::runtime::Runtime::new() {
            Ok(r) => r,
            Err(e) => {
                log::error!("capsi: cannot start tokio for discovery: {e}");
                return;
            }
        };
        rt.block_on(async {
            let transport_handle = app_handle.clone();
            tokio::spawn(async move {
                if let Err(e) = run_transport_listener(&transport_handle).await {
                    log::error!("capsi: transport listener failed: {e}");
                }
            });

            // Keep queued workplace messages moving when trusted peers return
            // to the LAN. The queue is persisted, so app restarts do not lose
            // pending deliveries.
            let retry_handle = app_handle.clone();
            tokio::spawn(async move {
                let mut ticker = tokio::time::interval(std::time::Duration::from_secs(5));
                loop {
                    ticker.tick().await;
                    if let Err(e) =
                        super::workplace::retry_workplace_deliveries(retry_handle.clone()).await
                    {
                        log::debug!("capsi: workplace retry failed: {e}");
                    }
                }
            });

            if let Err(e) = run_discovery(&app_handle).await {
                log::error!("capsi: discovery loop failed: {e}");
            }
        });
    });

    Ok(IdentityInfo {
        device_id: identity.id().clone(),
        fingerprint: identity.fingerprint().to_string(),
        device_name: load_device_name(&data_dir)
            .ok()
            .flatten()
            .unwrap_or_else(|| identity.id().short()),
        exchange_key: hex::encode(identity.exchange_public()),
        pending_count: trust.pending().len(),
        trusted_count: trust.trusted().len(),
        data_dir: data_dir.to_string_lossy().to_string(),
    })
}

/// Accept encrypted device-to-device messages on the same TCP port advertised
/// by LAN discovery. The listener is platform-neutral and therefore also works
/// for mobile Tauri targets.
async fn run_transport_listener(app: &AppHandle) -> Result<(), String> {
    let listener = TcpListener::bind(("0.0.0.0", TCP_PORT))
        .await
        .map_err(|e| format!("cannot bind Capsi TCP port {TCP_PORT}: {e}"))?;

    loop {
        let (stream, _) = listener
            .accept()
            .await
            .map_err(|e| format!("cannot accept Capsi connection: {e}"))?;
        let handle = app.clone();
        tokio::spawn(async move {
            if let Err(e) = handle_incoming_message(&handle, stream).await {
                log::debug!("capsi: incoming connection rejected: {e}");
            }
        });
    }
}

async fn handle_incoming_message(
    app: &AppHandle,
    stream: tokio::net::TcpStream,
) -> Result<(), String> {
    let data_dir = setup_app_data(app)?;
    let identity = capsi_core::identity::DeviceIdentity::load_or_create(&data_dir)
        .map_err(|e| e.to_string())?;
    let (peer_id, envelope) = capsi_core::transport::accept_and_read(stream, &identity)
        .await
        .map_err(|e| e.to_string())?;

    let trust = capsi_core::identity::trust::TrustStore::load(&data_dir)
        .map_err(|e| e.to_string())?;
    if !trust.is_trusted(&peer_id) {
        return Err("message received from an untrusted device".into());
    }

    match envelope.message {
        capsi_core::protocol::Message::WorkplaceText(message) => {
            let store = capsi_core::workplace::WorkspaceStore::new(&data_dir);
            let mut workspace = store.load()?.ok_or_else(|| "no local workplace".to_string())?;

            // Delivery retries can legitimately resend the same envelope. The
            // envelope id is the idempotency key, so accepting it twice must
            // never create duplicate workplace history entries.
            if workspace.has_received_message(&envelope.id) {
                return Ok(());
            }

            let sender = peer_id.as_str().to_string();
            if !workspace.members.iter().any(|m| m.device_id == sender) {
                return Err("sender is not a workplace member".into());
            }
            workspace
                .append_message(&message.group_id, &sender, message.body)
                .ok_or_else(|| "sender is not a member of the target group".to_string())?;
            workspace.mark_received_message(&envelope.id);
            store.save(&workspace)?;
            let _ = app.emit("workplace-message", &message);
            Ok(())
        }
        _ => Err("received message type is not handled by the workplace listener yet".into()),
    }
}

/// Run the LAN discovery loop. Spawned on a background thread so it survives
/// window minimise and close-to-tray.
///
/// Every event is re-broadcast to the frontend as `discovery-event`, carrying a
/// [`TrustListEntry`] so the "Nearby" list has the current state for each peer.
async fn run_discovery(app: &AppHandle) -> Result<(), String> {
    let data_dir = setup_app_data(app)?;
    let identity = capsi_core::identity::DeviceIdentity::load_or_create(&data_dir)
        .map_err(|e| e.to_string())?;
    let mut trust = capsi_core::identity::trust::TrustStore::load(&data_dir)
        .map_err(|e| e.to_string())?;

    // Use the saved device name if available, otherwise fall back to the short id.
    let device_name = load_device_name(&data_dir)
        .map_err(|e| e.to_string())?
        .unwrap_or_else(|| identity.id().short());

    let discovery =
        capsi_core::discovery::Discovery::bind(Arc::new(identity), device_name, TCP_PORT)
            .await
            .map_err(|e| e.to_string())?;

    // Discovery::run consumes self, so we spawn a task that owns the discovery
    // and drains events on a channel we can read from here.
    let (tx, mut rx) = tokio::sync::mpsc::channel(64);
    let discovery_handle = app.clone();
    tokio::spawn(async move {
        discovery.run(tx).await;
    });

    // Listen for discovery events and forward them to the frontend.
    while let Some(event) = rx.recv().await {
        let entry = trust_entry(&mut trust, event);
        // Persist the latest address so queued workplace messages can retry
        // against a peer's current LAN address after it moves.
        if let Err(e) = trust.save_if_dirty(&data_dir) {
            log::debug!("capsi: could not persist peer observation: {e}");
        }
        // A closed window is not a failure: the tray keeps Capsi running.
        let _ = discovery_handle.emit("discovery-event", entry);
    }

    Ok(())
}

/// Translate a discovery event into the row shape the frontend renders.
fn trust_entry(
    trust: &mut capsi_core::identity::trust::TrustStore,
    event: capsi_core::discovery::DiscoveryEvent,
) -> TrustListEntry {
    use capsi_core::discovery::DiscoveryEvent;

    match event {
        DiscoveryEvent::PeerFound(peer) => {
            trust.observe(
                &peer.device_id,
                &peer.name,
                &peer.address.to_string(),
            );
            let state = if trust.is_trusted(&peer.device_id) {
                "trusted"
            } else if trust.is_blocked(&peer.device_id) {
                "blocked"
            } else {
                "pending"
            };
            TrustListEntry {
                device_id: peer.device_id.as_str().into(),
                name: peer.name.clone(),
                alias: trust
                    .get(&peer.device_id)
                    .and_then(|known| known.alias.clone()),
                fingerprint: peer.fingerprint.to_string(),
                state: state.into(),
                // A beacon is the first and the latest sighting at once: the
                // peer table only keeps "last seen".
                first_seen: peer.last_seen,
                last_seen: peer.last_seen,
                last_address: Some(peer.address.to_string()),
            }
        }
        // A lost peer has nothing left but its id; the frontend drops the row.
        DiscoveryEvent::PeerLost(id) => TrustListEntry {
            device_id: id.as_str().into(),
            name: String::new(),
            alias: None,
            fingerprint: id.fingerprint().to_string(),
            state: "lost".into(),
            first_seen: 0,
            last_seen: 0,
            last_address: None,
        },
    }
}