// Capsi - Tauri command module.
//
// Aggregates every `#[tauri::command]` endpoint and the small helpers shared
// between them (app data dir, device name persistence, re-exports).

pub mod app;
pub mod device;
pub mod trust;
pub mod chat;
pub mod files;
pub mod settings;

use std::path::{Path, PathBuf};

use serde::Serialize;
use tauri::Manager;

/// The device identity as exposed to the frontend.
#[derive(Debug, Serialize)]
pub struct IdentityInfo {
    pub device_id: capsi_core::identity::DeviceId,
    pub fingerprint: String,
    pub device_name: String,
    pub exchange_key: String,
    pub pending_count: usize,
    pub trusted_count: usize,
    pub data_dir: String,
}

/// One row in the trust / contacts list.
///
/// `Clone` is required because the discovery loop hands this straight to Tauri's
/// event emitter, which takes the payload by value.
#[derive(Debug, Clone, Serialize)]
pub struct TrustListEntry {
    pub device_id: String,
    pub name: String,
    pub alias: Option<String>,
    pub fingerprint: String,
    pub state: String,
    pub first_seen: i64,
    pub last_seen: i64,
    pub last_address: Option<String>,
}

/// A conversation list item.
#[derive(Debug, Serialize)]
pub struct ConversationSummary {
    pub device_id: String,
    pub name: String,
    pub unread: u32,
    pub last_message_at: i64,
}

/// A full conversation with its messages.
#[derive(Debug, Serialize)]
pub struct ConversationDetail {
    pub device_id: String,
    pub name: String,
    pub messages: Vec<MessageEntry>,
}

/// A single message row.
#[derive(Debug, Serialize)]
pub struct MessageEntry {
    pub id: String,
    pub outgoing: bool,
    pub sent_at: i64,
    pub kind: String,
    pub body: String,
    pub file_name: Option<String>,
    pub file_size: Option<u64>,
    pub file_state: Option<String>,
}

/// The name a conversation should be filed under.
///
/// The user's own alias wins, then the name the peer advertised, and only then a
/// short form of the device id - so the conversation list never shows a raw
/// 64-character hex string when something friendlier is known.
pub fn conversation_name(dir: &Path, device_id: &capsi_core::identity::DeviceId) -> String {
    capsi_core::identity::trust::TrustStore::load(dir)
        .ok()
        .and_then(|trust| {
            trust
                .get(device_id)
                .map(|known| known.display_name().to_string())
        })
        .filter(|name| !name.trim().is_empty())
        .unwrap_or_else(|| device_id.short())
}

/// Ensure the data directory exists and return its path.
///
/// Generic over the Tauri runtime so this works on desktop (`Wry`) and on
/// mobile, where the same call resolves to the app-private data directory.
pub fn setup_app_data<R: tauri::Runtime>(app: &tauri::AppHandle<R>) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("cannot resolve app data dir: {e}"))?;
    std::fs::create_dir_all(&dir).map_err(|e| format!("cannot create data dir: {e}"))?;
    Ok(dir)
}

/// Save the device name to the app data directory.
pub fn save_device_name(dir: &Path, name: &str) -> Result<(), String> {
    std::fs::write(dir.join("device_name.txt"), name.trim())
        .map_err(|e| format!("cannot save device name: {e}"))
}

/// Load the device name if one was saved.
pub fn load_device_name(dir: &Path) -> Result<Option<String>, String> {
    let path = dir.join("device_name.txt");
    if path.exists() {
        Ok(Some(
            std::fs::read_to_string(&path)
                .map_err(|e| format!("cannot read device name: {e}"))?
                .trim()
                .to_string(),
        ))
    } else {
        Ok(None)
    }
}
