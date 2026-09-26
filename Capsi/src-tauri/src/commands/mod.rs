// Capsi - Tauri command module.

pub mod app;
pub mod device;
pub mod trust;
pub mod chat;
pub mod files;
pub mod settings;
pub mod workplace;

use std::path::{Path, PathBuf};

use serde::Serialize;
use tauri::Manager;

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

#[derive(Debug, Serialize)]
pub struct ConversationSummary {
    pub device_id: String,
    pub name: String,
    pub unread: u32,
    pub last_message_at: i64,
}

#[derive(Debug, Serialize)]
pub struct ConversationDetail {
    pub device_id: String,
    pub name: String,
    pub messages: Vec<MessageEntry>,
}

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

pub fn conversation_name(dir: &Path, device_id: &capsi_core::identity::DeviceId) -> String {
    capsi_core::identity::trust::TrustStore::load(dir)
        .ok()
        .and_then(|trust| trust.get(device_id).map(|known| known.display_name().to_string()))
        .filter(|name| !name.trim().is_empty())
        .unwrap_or_else(|| device_id.short())
}

pub fn setup_app_data<R: tauri::Runtime>(app: &tauri::AppHandle<R>) -> Result<PathBuf, String> {
    let dir = app.path().app_data_dir().map_err(|e| format!("cannot resolve app data dir: {e}"))?;
    std::fs::create_dir_all(&dir).map_err(|e| format!("cannot create data dir: {e}"))?;
    Ok(dir)
}

pub fn save_device_name(dir: &Path, name: &str) -> Result<(), String> {
    std::fs::write(dir.join("device_name.txt"), name.trim())
        .map_err(|e| format!("cannot save device name: {e}"))
}

pub fn load_device_name(dir: &Path) -> Result<Option<String>, String> {
    let path = dir.join("device_name.txt");
    if path.exists() {
        Ok(Some(std::fs::read_to_string(&path)
            .map_err(|e| format!("cannot read device name: {e}"))?
            .trim()
            .to_string()))
    } else {
        Ok(None)
    }
}
