// Capsi - Tauri command: device operations.
//
// Identity inspection, export and reset. All of these are read-only except
// reset, which requires the user to confirm in the UI first.

use super::{IdentityInfo, setup_app_data, load_device_name, save_device_name};
use capsi_core::identity::DeviceIdentity;

/// The local device fingerprint and exchange key as the UI needs it.
#[derive(serde::Serialize)]
pub struct DeviceSnapshot {
    pub device_id: String,
    pub fingerprint: String,
    pub device_name: String,
    pub exchange_key: String,
    pub data_dir: String,
}

/// Return the current device identity summary.
#[tauri::command]
pub async fn get_device_info(app: tauri::AppHandle) -> Result<IdentityInfo, String> {
    let data_dir = setup_app_data(&app)?;
    let identity = DeviceIdentity::load_or_create(&data_dir)
        .map_err(|e| e.to_string())?;
    let trust = capsi_core::identity::trust::TrustStore::load(&data_dir)
        .map_err(|e| e.to_string())?;

    Ok(IdentityInfo {
        device_id: identity.id().clone(),
        fingerprint: identity.fingerprint().to_string(),
        device_name: load_device_name(&data_dir)
            .map_err(|e| e.to_string())?
            .unwrap_or_else(|| identity.id().short()),
        exchange_key: hex::encode(identity.exchange_public()),
        pending_count: trust.pending().len(),
        trusted_count: trust.trusted().len(),
        data_dir: data_dir.to_string_lossy().to_string(),
    })
}

/// Persist a user-chosen device name.
#[tauri::command]
pub async fn set_device_name(
    app: tauri::AppHandle,
    name: String,
) -> Result<(), String> {
    let data_dir = setup_app_data(&app)?;
    let trimmed = name.trim();
    if trimmed.is_empty() {
        return Err("device name must not be empty".into());
    }
    if trimmed.len() > 32 {
        return Err("device name is limited to 32 characters".into());
    }
    if !trimmed
        .chars()
        .all(|c| c.is_alphanumeric() || matches!(c, '-' | '_' | '.' | ' '))
    {
        return Err(
            "device name may only contain letters, digits, spaces, hyphens, underscores and dots"
                .into(),
        );
    }
    save_device_name(&data_dir, trimmed)?;
    Ok(())
}

/// Export the device id as a short, copyable string.
#[tauri::command]
pub async fn export_device_id(app: tauri::AppHandle) -> Result<String, String> {
    let data_dir = setup_app_data(&app)?;
    let identity = DeviceIdentity::load_or_create(&data_dir)
        .map_err(|e| e.to_string())?;
    // The device id itself is the Ed25519 public key, hex-encoded.
    Ok(identity.id().as_str().to_string())
}

/// Wipe this device's identity and create a brand-new one.
///
/// There is no going back from this: old conversations cannot be decrypted
/// anymore. The UI must confirm before calling.
#[tauri::command]
pub async fn reset_device(app: tauri::AppHandle) -> Result<IdentityInfo, String> {
    let data_dir = setup_app_data(&app)?;

    // Remove the old identity file so `load_or_create` generates a new one.
    let id_path = capsi_core::identity::device::identity_path(&data_dir);
    let _ = std::fs::remove_file(&id_path);

    // Blow away trust state too: a new device is a stranger to all old peers.
    let trust_path = capsi_core::identity::trust::TrustStore::path(&data_dir);
    let _ = std::fs::remove_file(&trust_path);

    // Remove per-conversation history so the user is not left with orphaned files.
    let conv_dir = data_dir.join("conversations");
    if conv_dir.exists() {
        let _ = std::fs::remove_dir_all(&conv_dir);
    }

    let identity = DeviceIdentity::load_or_create(&data_dir)
        .map_err(|e| e.to_string())?;
    let trust = capsi_core::identity::trust::TrustStore::load(&data_dir)
        .map_err(|e| e.to_string())?;

    save_device_name(&data_dir, &format!("Capsi-{}", identity.id().short()))?;

    Ok(IdentityInfo {
        device_id: identity.id().clone(),
        fingerprint: identity.fingerprint().to_string(),
        device_name: load_device_name(&data_dir)
            .map_err(|e| e.to_string())?
            .unwrap_or_else(|| identity.id().short()),
        exchange_key: hex::encode(identity.exchange_public()),
        pending_count: trust.pending().len(),
        trusted_count: trust.trusted().len(),
        data_dir: data_dir.to_string_lossy().to_string(),
    })
}

/// Download a hex dump of the signed handshake for manual verification.
#[tauri::command]
pub async fn export_handshake(app: tauri::AppHandle) -> Result<HandshakeExport, String> {
    let data_dir = setup_app_data(&app)?;
    let identity = DeviceIdentity::load_or_create(&data_dir)
        .map_err(|e| e.to_string())?;

    let handshake = capsi_core::crypto::session::Handshake::create(&identity)
        .map_err(|e| e.to_string())?;

    // `signed_bytes` only borrows the handshake, so it has to be computed before
    // the `String` fields are moved out into the response.
    let signed_bytes_hex = handshake
        .signed_bytes()
        .map_err(|e| e.to_string())?
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect::<Vec<_>>()
        .join("");

    Ok(HandshakeExport {
        device_id: identity.id().as_str().to_string(),
        nonce: handshake.nonce,
        exchange_key: handshake.exchange_key,
        signature: handshake.signature,
        signed_bytes_hex,
    })
}

#[derive(serde::Serialize)]
pub struct HandshakeExport {
    pub device_id: String,
    pub nonce: String,
    pub exchange_key: String,
    pub signature: String,
    pub signed_bytes_hex: String,
}
