// Capsi - Tauri command: application bootstrap.
//
// Brings the data directory, the device identity and the LAN discovery loop to
// life, and reports the identity back to the frontend.
//
// This lives in its own module rather than in the crate root on purpose: for a
// `pub` function, `#[tauri::command]` emits `#[macro_export]` copies of the
// `__cmd__<name>` / `__tauri_command_name_<name>` helper macros. `macro_export`
// hoists them to the crate root, so a command defined *at* the crate root would
// collide with its own hoisted copy and fail with E0255.

use std::sync::Arc;

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
    let trust = capsi_core::identity::trust::TrustStore::load(&data_dir)
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

/// Run the LAN discovery loop. Spawned on a background thread so it survives
/// window minimise and close-to-tray.
///
/// Every event is re-broadcast to the frontend as `discovery-event`, carrying a
/// [`TrustListEntry`] so the "Nearby" list has the current state for each peer.
async fn run_discovery(app: &AppHandle) -> Result<(), String> {
    let data_dir = setup_app_data(app)?;
    let identity = capsi_core::identity::DeviceIdentity::load_or_create(&data_dir)
        .map_err(|e| e.to_string())?;
    let trust = capsi_core::identity::trust::TrustStore::load(&data_dir)
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
        let entry = trust_entry(&trust, event);
        // A closed window is not a failure: the tray keeps Capsi running.
        let _ = discovery_handle.emit("discovery-event", entry);
    }

    Ok(())
}

/// Translate a discovery event into the row shape the frontend renders.
fn trust_entry(
    trust: &capsi_core::identity::trust::TrustStore,
    event: capsi_core::discovery::DiscoveryEvent,
) -> TrustListEntry {
    use capsi_core::discovery::DiscoveryEvent;

    match event {
        DiscoveryEvent::PeerFound(peer) => {
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