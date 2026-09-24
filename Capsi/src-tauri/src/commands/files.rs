// Capsi - Tauri command: file transfer operations.
//
// Offer a file, accept/decline incoming offers, and track transfer progress.

use super::{conversation_name, setup_app_data};
use capsi_core::identity::{trust::TrustStore, DeviceId, DeviceIdentity};
use capsi_core::storage::conversation::{
    DeliveryState, MessageKind, MessageStore, StoredFile, StoredMessage, TransferState,
};
use capsi_core::util::{digest_hex, human_size, new_id, safe_file_name};
use capsi_core::TRANSFER_CHUNK_SIZE;

/// Largest file Capsi will offer, until the chunked sender lands.
const MAX_FILE_BYTES: u64 = 100 * 1024 * 1024;

/// Offer a file to a trusted peer.
#[tauri::command]
pub async fn offer_file(
    app: tauri::AppHandle,
    device_id: String,
    path: String,
) -> Result<String, String> {
    let data_dir = setup_app_data(&app)?;
    let id = DeviceId::from_hex(&device_id).map_err(|e| e.to_string())?;

    let trust = TrustStore::load(&data_dir).map_err(|e| e.to_string())?;
    if !trust.is_trusted(&id) {
        return Err(format!(
            "peer {} is not trusted",
            id.as_str().chars().take(8).collect::<String>()
        ));
    }

    let raw_path = std::path::Path::new(&path);
    if !raw_path.exists() {
        return Err(format!("no such file: {path}"));
    }
    if !raw_path.is_file() {
        return Err(format!("not a file: {path}"));
    }

    let metadata = std::fs::metadata(raw_path).map_err(|e| e.to_string())?;
    let file_size = metadata.len();
    if file_size > MAX_FILE_BYTES {
        return Err("files larger than 100 MB are not supported yet".into());
    }

    let digest = capsi_core::util::digest_file(raw_path).map_err(|e| e.to_string())?;

    let file_name = safe_file_name(
        raw_path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("capsi-file"),
    );

    let transfer_id = new_id("f");
    let chunk_size = TRANSFER_CHUNK_SIZE as u64;
    let chunks = ((file_size + chunk_size - 1) / chunk_size).max(1);

    let offer = capsi_core::protocol::FileOffer {
        transfer_id: transfer_id.clone(),
        file_name: file_name.clone(),
        size: file_size,
        digest: digest.clone(),
        chunks,
    };

    // `Envelope::new` is infallible: it stamps the version, id and timestamp.
    let envelope =
        capsi_core::protocol::Envelope::new(capsi_core::protocol::Message::FileOffer(offer));

    let stored = StoredMessage {
        id: envelope.id.clone(),
        outgoing: true,
        sent_at: capsi_core::identity::device::now_secs(),
        kind: MessageKind::File,
        body: format!("{} ({})", file_name, human_size(file_size)),
        file: Some(StoredFile {
            transfer_id: transfer_id.clone(),
            file_name,
            size: file_size,
            digest,
            local_path: Some(raw_path.to_string_lossy().to_string()),
            state: TransferState::Offered,
        }),
        state: DeliveryState::Queued,
    };

    let peer = trust
        .get(&id)
        .ok_or_else(|| "peer is not known to Capsi".to_string())?;
    let address = peer
        .last_address
        .as_deref()
        .ok_or_else(|| "peer address is not currently known".to_string())?;
    let mut socket = address
        .parse::<std::net::SocketAddr>()
        .map_err(|e| format!("invalid peer address: {e}"))?;
    socket.set_port(45892);

    let identity = DeviceIdentity::load_or_create(&data_dir).map_err(|e| e.to_string())?;
    capsi_core::transport::connect_and_send(
        &socket.to_string(),
        &identity,
        &id,
        &envelope,
    )
    .await
    .map_err(|e| format!("file offer delivery failed: {e}"))?;

    let peer_name = conversation_name(&data_dir, &id);
    let mut store = MessageStore::load(&data_dir).map_err(|e| e.to_string())?;
    stored.state = DeliveryState::Sent;
    store
        .append(&id, &peer_name, stored)
        .map_err(|e| e.to_string())?;

    Ok(transfer_id)
}

/// Accept an incoming file offer from a peer.
///
/// Returns the transfer id so the frontend can keep tracking it.
#[tauri::command]
pub async fn accept_file(
    app: tauri::AppHandle,
    device_id: String,
    transfer_id: String,
    save_to: Option<String>,
) -> Result<String, String> {
    let data_dir = setup_app_data(&app)?;
    let id = DeviceId::from_hex(&device_id).map_err(|e| e.to_string())?;

    let dest_dir = match save_to {
        Some(dir) => std::path::PathBuf::from(dir),
        None => std::env::temp_dir().join("Capsi").join("received"),
    };
    std::fs::create_dir_all(&dest_dir)
        .map_err(|e| format!("cannot create {}: {e}", dest_dir.display()))?;

    let mut store = MessageStore::load(&data_dir).map_err(|e| e.to_string())?;
    let conversation = store
        .get(&id)
        .ok_or_else(|| "file offer was not found".to_string())?;
    let file = conversation
        .find_transfer(&transfer_id)
        .ok_or_else(|| "file offer was not found".to_string())?;
    let safe_name = safe_file_name(&file.file_name);
    let mut target = dest_dir.join(&safe_name);
    // Never overwrite an existing local file. Generate a deterministic,
    // collision-safe name while keeping the original extension.
    if target.exists() {
        let stem = std::path::Path::new(&safe_name)
            .file_stem().and_then(|s| s.to_str()).unwrap_or("capsi-file");
        let ext = std::path::Path::new(&safe_name)
            .extension().and_then(|s| s.to_str()).map(|s| format!(".{s}")).unwrap_or_default();
        for n in 1..10_000u32 {
            let candidate = dest_dir.join(format!("{stem} ({n}){ext}"));
            if !candidate.exists() {
                target = candidate;
                break;
            }
        }
    }
    let target_string = target.to_string_lossy().to_string();
    let expected_peer = id.clone();

    store
        .update_transfer(
            &id,
            &transfer_id,
            TransferState::Transferring,
            Some(target_string),
        )
        .map_err(|e| e.to_string())?;

    let trust = TrustStore::load(&data_dir).map_err(|e| e.to_string())?;
    let peer = trust.get(&expected_peer).ok_or_else(|| "peer is not known".to_string())?;
    let address = peer.last_address.as_deref().ok_or_else(|| "peer address is not currently known".to_string())?;
    let mut socket = address.parse::<std::net::SocketAddr>().map_err(|e| format!("invalid peer address: {e}"))?;
    socket.set_port(45892);
    let identity = DeviceIdentity::load_or_create(&data_dir).map_err(|e| e.to_string())?;
    let receipt = capsi_core::protocol::Envelope::new(
        capsi_core::protocol::Message::FileReceipt {
            transfer_id,
            state: capsi_core::protocol::FileReceipt::Accepted,
        },
    );
    capsi_core::transport::connect_and_send(
        &socket.to_string(),
        &identity,
        &expected_peer,
        &receipt,
    )
    .await
    .map_err(|e| format!("could not notify sender: {e}"))?;

    Ok(receipt.id)
}

/// Decline an incoming file offer from a peer.
#[tauri::command]
pub async fn decline_file(
    app: tauri::AppHandle,
    device_id: String,
    transfer_id: String,
) -> Result<(), String> {
    let data_dir = setup_app_data(&app)?;
    let id = DeviceId::from_hex(&device_id).map_err(|e| e.to_string())?;

    let mut store = MessageStore::load(&data_dir).map_err(|e| e.to_string())?;
    store
        .update_transfer(&id, &transfer_id, TransferState::Declined, None)
        .map_err(|e| e.to_string())?;

    Ok(())
}

/// List all pending or in-progress transfers across all conversations.
#[tauri::command]
pub async fn list_transfers(app: tauri::AppHandle) -> Result<Vec<TransferRow>, String> {
    let data_dir = setup_app_data(&app)?;
    let store = MessageStore::load(&data_dir).map_err(|e| e.to_string())?;

    let mut out = Vec::new();
    for conv in store.list() {
        for msg in &conv.messages {
            let Some(file) = msg.file.as_ref() else {
                continue;
            };
            // Finished and refused transfers are history, not work in progress.
            if file.state != TransferState::Offered && file.state != TransferState::Transferring {
                continue;
            }
            out.push(TransferRow {
                transfer_id: file.transfer_id.clone(),
                device_id: conv.device_id.as_str().into(),
                peer_name: conv.name.clone(),
                file_name: file.file_name.clone(),
                size: file.size,
                digest: file.digest.clone(),
                state: match file.state {
                    TransferState::Offered => "offered",
                    TransferState::Transferring => "transferring",
                    _ => "other",
                }
                .into(),
                local_path: file.local_path.clone(),
            });
        }
    }
    out.sort_by(|a, b| b.size.cmp(&a.size));
    Ok(out)
}

#[derive(serde::Serialize)]
pub struct TransferRow {
    pub transfer_id: String,
    pub device_id: String,
    pub peer_name: String,
    pub file_name: String,
    pub size: u64,
    pub digest: String,
    pub state: String,
    pub local_path: Option<String>,
}


