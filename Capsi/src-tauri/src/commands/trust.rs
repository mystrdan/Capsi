// Capsi - Tauri command: trust list operations.
//
// Accept / ignore / forget / rename peers. The trust store is the single
// source of truth for who this device talks to.

use super::setup_app_data;
use capsi_core::identity::{DeviceId, trust::TrustStore};

/// One row in the contacts / nearby list as sent to the frontend.
#[derive(serde::Serialize, Clone)]
pub struct PeerRow {
    pub device_id: String,
    pub name: String,
    pub alias: Option<String>,
    pub fingerprint: String,
    pub state: String,
    pub first_seen: i64,
    pub last_seen: i64,
    pub last_address: Option<String>,
}

/// Return every peer the trust store knows about, newest-first.
#[tauri::command]
pub async fn list_peers(app: tauri::AppHandle) -> Result<Vec<PeerRow>, String> {
    let data_dir = setup_app_data(&app)?;
    let store = TrustStore::load(&data_dir).map_err(|e| e.to_string())?;
    let mut rows: Vec<PeerRow> = store
        .all()
        .into_iter()
        .map(|d| PeerRow {
            device_id: d.device_id.as_str().into(),
            name: d.name,
            alias: d.alias,
            fingerprint: d.fingerprint.to_string(),
            state: match d.state {
                capsi_core::identity::trust::TrustState::Pending => "pending",
                capsi_core::identity::trust::TrustState::Trusted => "trusted",
                capsi_core::identity::trust::TrustState::Blocked => "blocked",
            }
            .into(),
            first_seen: d.first_seen,
            last_seen: d.last_seen,
            last_address: d.last_address,
        })
        .collect();
    rows.sort_by(|a, b| b.last_seen.cmp(&a.last_seen));
    Ok(rows)
}

/// Accept a pending peer, optionally giving them a local alias.
#[tauri::command]
pub async fn accept_peer(
    app: tauri::AppHandle,
    device_id: String,
    alias: Option<String>,
) -> Result<(), String> {
    let data_dir = setup_app_data(&app)?;
    let mut store = TrustStore::load(&data_dir).map_err(|e| e.to_string())?;
    let id = DeviceId::from_hex(&device_id).map_err(|e| e.to_string())?;
    store
        .accept(&id, alias.map(|s| s.trim().to_string()))
        .map_err(|e| e.to_string())?;
    store.save_if_dirty(&data_dir).map_err(|e| e.to_string())
}

/// Move a peer to the blocked list.
#[tauri::command]
pub async fn ignore_peer(app: tauri::AppHandle, device_id: String) -> Result<(), String> {
    let data_dir = setup_app_data(&app)?;
    let mut store = TrustStore::load(&data_dir).map_err(|e| e.to_string())?;
    let id = DeviceId::from_hex(&device_id).map_err(|e| e.to_string())?;
    store.ignore(&id).map_err(|e| e.to_string())?;
    store.save_if_dirty(&data_dir).map_err(|e| e.to_string())
}

/// Remove a peer from the trust list entirely.
#[tauri::command]
pub async fn forget_peer(app: tauri::AppHandle, device_id: String) -> Result<(), String> {
    let data_dir = setup_app_data(&app)?;
    let mut store = TrustStore::load(&data_dir).map_err(|e| e.to_string())?;
    let id = DeviceId::from_hex(&device_id).map_err(|e| e.to_string())?;
    store.forget(&id).map_err(|e| e.to_string())?;
    store.save_if_dirty(&data_dir).map_err(|e| e.to_string())
}

/// Change the local alias for a trusted peer.
#[tauri::command]
pub async fn rename_peer(
    app: tauri::AppHandle,
    device_id: String,
    alias: Option<String>,
) -> Result<(), String> {
    let data_dir = setup_app_data(&app)?;
    let mut store = TrustStore::load(&data_dir).map_err(|e| e.to_string())?;
    let id = DeviceId::from_hex(&device_id).map_err(|e| e.to_string())?;
    store
        .rename(&id, alias.map(|s| s.trim().to_string()))
        .map_err(|e| e.to_string())?;
    store.save_if_dirty(&data_dir).map_err(|e| e.to_string())
}
