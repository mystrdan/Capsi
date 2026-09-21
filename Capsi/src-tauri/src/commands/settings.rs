// Capsi - Tauri command: settings operations.
//
// Toggle notifications, auto-accept, and other preferences stored on disk.

use super::setup_app_data;
use serde::{Deserialize, Serialize};

/// Persisted user preferences.
#[derive(Debug, Serialize, Deserialize, Default)]
pub struct Settings {
    pub notifications_enabled: bool,
    pub auto_accept_files: bool,
    pub start_minimized: bool,
    pub start_discovery: bool,
}

/// Read the current settings.
#[tauri::command]
pub async fn get_settings(app: tauri::AppHandle) -> Result<Settings, String> {
    let data_dir = setup_app_data(&app)?;
    let path = data_dir.join("settings.json");
    if path.exists() {
        let raw = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
        serde_json::from_str(&raw).map_err(|e| e.to_string())
    } else {
        Ok(Settings::default())
    }
}

/// Write the current settings.
#[tauri::command]
pub async fn save_settings(app: tauri::AppHandle, settings: Settings) -> Result<(), String> {
    let data_dir = setup_app_data(&app)?;
    let raw = serde_json::to_string_pretty(&settings).map_err(|e| e.to_string())?;
    std::fs::write(data_dir.join("settings.json"), raw).map_err(|e| e.to_string())
}
