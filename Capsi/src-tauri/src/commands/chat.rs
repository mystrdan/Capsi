// Capsi - Tauri command: chat and conversation operations.
//
// List conversations, load one, send a text message, delete, mark read.

use super::{
    conversation_name, setup_app_data, ConversationDetail, ConversationSummary, MessageEntry,
};
use capsi_core::identity::{trust::TrustStore, DeviceId};
use capsi_core::storage::conversation::{
    DeliveryState, MessageKind, MessageStore, StoredMessage, TransferState,
};

/// List all conversations, most-recently-active first.
#[tauri::command]
pub async fn list_conversations(app: tauri::AppHandle) -> Result<Vec<ConversationSummary>, String> {
    let data_dir = setup_app_data(&app)?;
    let store = MessageStore::load(&data_dir).map_err(|e| e.to_string())?;
    Ok(store
        .list()
        .into_iter()
        .map(|c| ConversationSummary {
            device_id: c.device_id.as_str().into(),
            name: c.name,
            unread: c.unread,
            last_message_at: c.updated_at,
        })
        .collect())
}

/// Load a single conversation's messages.
#[tauri::command]
pub async fn load_conversation(
    app: tauri::AppHandle,
    device_id: String,
) -> Result<Option<ConversationDetail>, String> {
    let data_dir = setup_app_data(&app)?;
    let store = MessageStore::load(&data_dir).map_err(|e| e.to_string())?;
    let id = DeviceId::from_hex(&device_id).map_err(|e| e.to_string())?;
    match store.get(&id) {
        Some(conv) => Ok(Some(ConversationDetail {
            device_id: conv.device_id.as_str().into(),
            name: conv.name.clone(),
            messages: conv
                .messages
                .iter()
                .map(|m| MessageEntry {
                    id: m.id.clone(),
                    outgoing: m.outgoing,
                    sent_at: m.sent_at,
                    kind: match m.kind {
                        MessageKind::Text => "text",
                        MessageKind::File => "file",
                    }
                    .into(),
                    body: m.body.clone(),
                    file_name: m.file.as_ref().map(|f| f.file_name.clone()),
                    file_size: m.file.as_ref().map(|f| f.size),
                    file_state: m.file.as_ref().map(|f| {
                        match f.state {
                            TransferState::Offered => "offered",
                            TransferState::Transferring => "transferring",
                            TransferState::Complete => "complete",
                            TransferState::Declined => "declined",
                            TransferState::Failed => "failed",
                            TransferState::Cancelled => "cancelled",
                        }
                        .to_string()
                    }),
                })
                .collect(),
        })),
        None => Ok(None),
    }
}

/// Send a text message to a trusted peer.
#[tauri::command]
pub async fn send_message(
    app: tauri::AppHandle,
    device_id: String,
    body: String,
) -> Result<String, String> {
    let data_dir = setup_app_data(&app)?;
    let trust = TrustStore::load(&data_dir).map_err(|e| e.to_string())?;
    let id = DeviceId::from_hex(&device_id).map_err(|e| e.to_string())?;
    if !trust.is_trusted(&id) {
        return Err(format!(
            "peer {} is not trusted",
            id.as_str().chars().take(8).collect::<String>()
        ));
    }

    // `TextMessage::new` trims and validates the body and owns the cleaned copy,
    // so take it before the envelope moves the message away.
    let message = capsi_core::protocol::TextMessage::new(&body).map_err(|e| e.to_string())?;
    let clean_body = message.body.clone();
    let envelope = capsi_core::protocol::Envelope::new(capsi_core::protocol::Message::Text(message));

    let peer_name = conversation_name(&data_dir, &id);
    let mut store = MessageStore::load(&data_dir).map_err(|e| e.to_string())?;
    let stored = StoredMessage {
        id: envelope.id.clone(),
        outgoing: true,
        sent_at: capsi_core::identity::device::now_secs(),
        kind: MessageKind::Text,
        body: clean_body,
        file: None,
        state: DeliveryState::Queued,
    };
    store
        .append(&id, &peer_name, stored)
        .map_err(|e| e.to_string())?;
    Ok(envelope.id)
}

/// Delete a conversation and its stored history.
#[tauri::command]
pub async fn delete_conversation(
    app: tauri::AppHandle,
    device_id: String,
) -> Result<(), String> {
    let data_dir = setup_app_data(&app)?;
    let mut store = MessageStore::load(&data_dir).map_err(|e| e.to_string())?;
    let id = DeviceId::from_hex(&device_id).map_err(|e| e.to_string())?;
    store.delete(&id).map_err(|e| e.to_string())
}

/// Mark a conversation as read.
#[tauri::command]
pub async fn mark_read(app: tauri::AppHandle, device_id: String) -> Result<(), String> {
    let data_dir = setup_app_data(&app)?;
    let mut store = MessageStore::load(&data_dir).map_err(|e| e.to_string())?;
    let id = DeviceId::from_hex(&device_id).map_err(|e| e.to_string())?;
    store.mark_read(&id).map_err(|e| e.to_string())
}
