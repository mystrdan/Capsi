//! Conversations on disk.
//!
//! One JSON file per contact (`conversations/<device_id>.json`). The format is
//! plain, pretty-printed JSON on purpose: a user can open, read, back up or
//! delete their history with a text editor, which is what "your data stays with
//! you" has to mean in practice.

use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::error::{CapsiError, Result};
use crate::identity::device::{now_secs, write_private, DeviceId};
use crate::protocol::{FileOffer, TextMessage};
use crate::util::human_size;

/// How far a message got.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DeliveryState {
    /// Written locally, waiting for the peer to be reachable.
    Queued,
    /// Handed to the network layer.
    Sent,
    /// The peer acknowledged it.
    Delivered,
    /// The peer opened the conversation.
    Read,
    /// Sending failed; the user can retry.
    Failed,
}

/// How far a file got.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TransferState {
    /// Offered, waiting for the other side to accept.
    Offered,
    /// Accepted; bytes are moving.
    Transferring,
    /// Every chunk arrived and the digest matched.
    Complete,
    /// Refused by the other side.
    Declined,
    /// Something went wrong mid-transfer.
    Failed,
    /// Stopped by either side.
    Cancelled,
}

/// What kind of message this is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MessageKind {
    Text,
    File,
}

/// A file attached to a message.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct StoredFile {
    /// Transfer id shared with the peer.
    pub transfer_id: String,
    /// The file name, already sanitised for this machine.
    pub file_name: String,
    /// Size in bytes, as advertised.
    pub size: u64,
    /// Whole-file digest used to prove the copy is intact.
    pub digest: String,
    /// Where the file lives locally once it is complete.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub local_path: Option<String>,
    pub state: TransferState,
}

impl StoredFile {
    /// `4.2 MB - complete` for the message bubble subtitle.
    pub fn subtitle(&self) -> String {
        let state = match self.state {
            TransferState::Offered => "waiting",
            TransferState::Transferring => "transferring",
            TransferState::Complete => "complete",
            TransferState::Declined => "declined",
            TransferState::Failed => "failed",
            TransferState::Cancelled => "cancelled",
        };
        format!("{} - {state}", human_size(self.size))
    }
}

/// A text envelope waiting for an application-level delivery receipt.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PendingDelivery {
    pub envelope: crate::protocol::Envelope,
    pub attempts: u32,
    pub next_attempt_at: i64,
    pub last_error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredMessage {
    /// Message id (the same value as the envelope id, so receipts can refer to it).
    pub id: String,
    /// True when this device sent it.
    pub outgoing: bool,
    /// Unix seconds.
    pub sent_at: i64,
    pub kind: MessageKind,
    /// Text body; empty for files.
    #[serde(default)]
    pub body: String,
    /// The attached file, for [`MessageKind::File`].
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub file: Option<StoredFile>,
    pub state: DeliveryState,
}

impl StoredMessage {
    /// Build a text message from an outgoing or incoming body.
    pub fn text(body: &str, outgoing: bool) -> Result<Self> {
        let text = TextMessage::new(body)?;
        Ok(Self {
            id: crate::util::new_id("m"),
            outgoing,
            sent_at: now_secs(),
            kind: MessageKind::Text,
            body: text.body,
            file: None,
            state: if outgoing {
                DeliveryState::Sent
            } else {
                DeliveryState::Delivered
            },
        })
    }

    /// Build a message carrying a file.
    pub fn file(offer: &FileOffer, outgoing: bool) -> Self {
        Self {
            id: crate::util::new_id("m"),
            outgoing,
            sent_at: now_secs(),
            kind: MessageKind::File,
            body: String::new(),
            file: Some(StoredFile {
                transfer_id: offer.transfer_id.clone(),
                file_name: crate::util::safe_file_name(&offer.file_name),
                size: offer.size,
                digest: offer.digest.clone(),
                local_path: None,
                state: TransferState::Offered,
            }),
            state: DeliveryState::Sent,
        }
    }

    /// The one-line summary the conversation list shows.
    pub fn preview(&self) -> String {
        match self.kind {
            MessageKind::Text => self.body.clone(),
            MessageKind::File => self
                .file
                .as_ref()
                .map(|f| format!("File: {}", f.file_name))
                .unwrap_or_else(|| "File".to_string()),
        }
    }
}

/// Everything exchanged with one contact.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conversation {
    /// Who this conversation is with.
    pub device_id: DeviceId,
    /// Cached display name, refreshed whenever a beacon arrives.
    pub name: String,
    /// The messages, oldest first.
    #[serde(default)]
    pub messages: Vec<StoredMessage>,
    /// How many incoming messages have not been read.
    #[serde(default)]
    pub unread: u32,
    /// Unix seconds of the newest activity.
    pub updated_at: i64,
    /// Durable outgoing deliveries. Entries are removed only after a
    /// DeliveryReceipt is received from the peer.
    #[serde(default)]
    pub pending_deliveries: Vec<PendingDelivery>,
}

impl Conversation {
    /// A new, empty conversation.
    pub fn new(device_id: DeviceId, name: impl Into<String>) -> Self {
        Self {
            device_id,
            name: name.into(),
            messages: Vec::new(),
            unread: 0,
            updated_at: now_secs(),
            pending_deliveries: Vec::new(),
        }
    }

    /// Append a message, keeping the list in time order.
    ///
    /// Inserted by timestamp rather than simply pushed, because an incoming
    /// message can easily arrive after a later one was sent.
    pub fn push(&mut self, message: StoredMessage) {
        self.updated_at = self.updated_at.max(message.sent_at);
        if !message.outgoing {
            self.unread += 1;
        }
        let position = self
            .messages
            .iter()
            .position(|existing| existing.sent_at > message.sent_at)
            .unwrap_or(self.messages.len());
        self.messages.insert(position, message);
    }

    /// The newest message, for the conversation-list preview.
    pub fn last_message(&self) -> Option<&StoredMessage> {
        self.messages.last()
    }

    /// All incoming messages are considered seen.
    pub fn mark_read(&mut self) {
        self.unread = 0;
    }

    /// Update a file's state, found by transfer id.
    pub fn set_transfer_state(
        &mut self,
        transfer_id: &str,
        state: TransferState,
        local_path: Option<String>,
    ) -> bool {
        for message in &mut self.messages {
            if let Some(file) = message.file.as_mut() {
                if file.transfer_id == transfer_id {
                    file.state = state;
                    if local_path.is_some() {
                        file.local_path = local_path;
                    }
                    return true;
                }
            }
        }
        false
    }

    /// Find the file record for a transfer.
    pub fn find_transfer(&self, transfer_id: &str) -> Option<&StoredFile> {
        self.messages
            .iter()
            .filter_map(|m| m.file.as_ref())
            .find(|f| f.transfer_id == transfer_id)
    }

    /// Trim the history to `limit` messages, dropping the oldest.
    pub fn trim(&mut self, limit: usize) {
        if limit > 0 && self.messages.len() > limit {
            let excess = self.messages.len() - limit;
            self.messages.drain(..excess);
        }
    }
}

/// Default history limit per conversation.
pub const DEFAULT_HISTORY_LIMIT: usize = 5_000;

/// All conversations, kept in step with the files on disk.
#[derive(Debug)]
pub struct MessageStore {
    root: PathBuf,
    conversations: std::collections::BTreeMap<DeviceId, Conversation>,
    /// Maximum number of messages kept per conversation.
    limit: usize,
}

impl MessageStore {
    /// Load every conversation under `data_dir`.
    pub fn load(data_dir: &Path) -> Result<Self> {
        let root = data_dir.join("conversations");
        fs::create_dir_all(&root)?;
        let mut conversations = std::collections::BTreeMap::new();

        for entry in fs::read_dir(&root)? {
            let path = entry?.path();
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                continue;
            }
            match read_conversation(&path) {
                Ok(conversation) => {
                    conversations.insert(conversation.device_id.clone(), conversation);
                }
                // One unreadable conversation must not hide the rest.
                Err(e) => log::warn!("capsi: skipping {}: {e}", path.display()),
            }
        }

        Ok(Self {
            root,
            conversations,
            limit: DEFAULT_HISTORY_LIMIT,
        })
    }

    /// Override how much history is kept (0 means "keep everything").
    pub fn set_limit(&mut self, limit: usize) {
        self.limit = limit;
    }

    /// Where one conversation lives.
    pub fn path_for(&self, device_id: &DeviceId) -> PathBuf {
        self.root.join(format!("{}.json", device_id.as_str()))
    }

    /// Every conversation, most recently active first.
    pub fn list(&self) -> Vec<Conversation> {
        let mut list: Vec<Conversation> = self.conversations.values().cloned().collect();
        list.sort_by(|a, b| {
            b.updated_at
                .cmp(&a.updated_at)
                .then_with(|| a.name.cmp(&b.name))
        });
        list
    }

    /// A conversation, created on first use so callers never deal with `Option`.
    pub fn conversation(&mut self, device_id: &DeviceId, name: &str) -> &mut Conversation {
        let entry = self
            .conversations
            .entry(device_id.clone())
            .or_insert_with(|| Conversation::new(device_id.clone(), name));
        // Keep the cached name fresh, but never clobber it with a blank one.
        if !name.trim().is_empty() {
            entry.name = name.to_string();
        }
        entry
    }

    /// Look up a conversation without creating one.
    pub fn get(&self, device_id: &DeviceId) -> Option<&Conversation> {
        self.conversations.get(device_id)
    }

    /// Internal mutable access used by the Tauri retry worker.
    pub fn conversations_mut_for_internal(&mut self, device_id: &DeviceId) -> Option<&mut Conversation> {
        self.conversations.get_mut(device_id)
    }

    /// Persist one conversation after an internal queue mutation.
    pub fn persist_for_internal(&self, device_id: &DeviceId) -> Result<()> {
        self.persist(device_id)
    }

    /// Add a message and write the conversation back to disk.
    pub fn append(
        &mut self,
        device_id: &DeviceId,
        name: &str,
        message: StoredMessage,
    ) -> Result<()> {
        let limit = self.limit;
        let conversation = self.conversation(device_id, name);
        conversation.push(message);
        conversation.trim(limit);
        self.persist(device_id)
    }

    /// Queue an outgoing envelope until the peer confirms persistence.
    pub fn queue_delivery(&mut self, envelope: crate::protocol::Envelope, next_attempt_at: i64) {
        if self.pending_deliveries.iter().any(|p| p.envelope.id == envelope.id) {
            return;
        }
        self.pending_deliveries.push(PendingDelivery {
            envelope,
            attempts: 0,
            next_attempt_at,
            last_error: None,
        });
    }

    pub fn remove_delivery(&mut self, message_id: &str) {
        self.pending_deliveries.retain(|p| p.envelope.id != message_id);
    }

    /// Mark an outgoing text message delivered and remove its retry entry.
    pub fn mark_delivery_delivered(&mut self, device_id: &DeviceId, message_id: &str) -> Result<bool> {
        let updated = match self.conversations.get_mut(device_id) {
            Some(conversation) => {
                let mut found = false;
                for message in &mut conversation.messages {
                    if message.id == message_id && message.outgoing && message.kind == MessageKind::Text {
                        message.state = DeliveryState::Delivered;
                        found = true;
                        break;
                    }
                }
                conversation.remove_delivery(message_id);
                found
            }
            None => false,
        };
        if updated {
            self.persist(device_id)?;
        }
        Ok(updated)
    }

    /// Update a transfer's state and persist.
    pub fn update_transfer(
        &mut self,
        device_id: &DeviceId,
        transfer_id: &str,
        state: TransferState,
        local_path: Option<String>,
    ) -> Result<bool> {
        let updated = match self.conversations.get_mut(device_id) {
            Some(conversation) => conversation.set_transfer_state(transfer_id, state, local_path),
            None => false,
        };
        if updated {
            self.persist(device_id)?;
        }
        Ok(updated)
    }

    /// Mark a conversation as read and persist.
    pub fn mark_read(&mut self, device_id: &DeviceId) -> Result<()> {
        if let Some(conversation) = self.conversations.get_mut(device_id) {
            if conversation.unread != 0 {
                conversation.mark_read();
                self.persist(device_id)?;
            }
        }
        Ok(())
    }

    /// Delete a conversation and its file.
    pub fn delete(&mut self, device_id: &DeviceId) -> Result<()> {
        self.conversations.remove(device_id);
        let path = self.path_for(device_id);
        if path.exists() {
            fs::remove_file(path)?;
        }
        Ok(())
    }

    /// Total unread count across all contacts, for the tray badge.
    pub fn total_unread(&self) -> u32 {
        self.conversations.values().map(|c| c.unread).sum()
    }

    /// Write one conversation out.
    fn persist(&self, device_id: &DeviceId) -> Result<()> {
        let conversation = self
            .conversations
            .get(device_id)
            .ok_or_else(|| CapsiError::NotFound("conversation vanished before saving".into()))?;
        let json = serde_json::to_vec_pretty(conversation)?;
        write_private(&self.path_for(device_id), &json)
    }
}

/// Read one conversation file.
fn read_conversation(path: &Path) -> Result<Conversation> {
    let raw = fs::read_to_string(path)?;
    serde_json::from_str(&raw)
        .map_err(|e| CapsiError::Protocol(format!("{}: {e}", path.display())))
}