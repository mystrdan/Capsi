//! The typed messages Capsi exchanges, and the envelope that versions them.
//!
//! Every payload is JSON inside a sealed frame, so the plaintext never appears on
//! the wire. The envelope carries the protocol version so a future Capsi can
//! refuse (rather than misread) a peer speaking a different dialect.

use serde::{Deserialize, Serialize};

use crate::error::{CapsiError, Result};
use crate::util::new_id;
use crate::{MAX_TEXT_MESSAGE_BYTES, PROTOCOL_VERSION};

/// A plain text message.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TextMessage {
    pub body: String,
}

impl TextMessage {
    /// Validate and trim a message before it is sent.
    pub fn new(body: &str) -> Result<Self> {
        let trimmed = body.trim_end().to_string();
        if trimmed.trim().is_empty() {
            return Err(CapsiError::Invalid("cannot send an empty message".into()));
        }
        if trimmed.len() > MAX_TEXT_MESSAGE_BYTES {
            return Err(CapsiError::Invalid(format!(
                "message is {} bytes, the limit is {}",
                trimmed.len(),
                MAX_TEXT_MESSAGE_BYTES
            )));
        }
        Ok(Self { body: trimmed })
    }
}

/// "I have a file for you" - sent before any bytes move.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FileOffer {
    /// Random id tying every chunk of this transfer together.
    pub transfer_id: String,
    /// Suggested file name; the receiver sanitises it again on arrival.
    pub file_name: String,
    /// Total size in bytes.
    pub size: u64,
    /// BLAKE2b digest of the whole file, so the receiver can prove it arrived.
    pub digest: String,
    /// How many chunks the sender will send.
    pub chunks: u64,
}

/// What happened to a file we sent, or to a file we were offered.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FileReceipt {
    /// The peer accepted and is ready for chunks.
    Accepted,
    /// The peer said no (or has no room for it).
    Declined,
    /// Every chunk arrived and the digest matched.
    Completed,
    /// Something went wrong; the transfer stopped.
    Failed,
    /// The peer cancelled, so we stop sending.
    Cancelled,
}

/// "I am typing" / "I stopped typing".
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Typing {
    pub active: bool,
}

/// A text message addressed to a workplace group.
///
/// The group id is a routing/authorization identifier, not a server-side
/// destination. The eventual transport sends this payload directly to each
/// eligible trusted device using Capsi's existing encrypted peer sessions.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkplaceTextMessage {
    pub group_id: String,
    pub body: String,
}

/// A workplace broadcast sent directly to eligible workplace members.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkplaceBroadcastMessage {
    pub broadcast_id: String,
    pub title: String,
    pub body: String,
    pub department_id: Option<String>,
}

/// Application-level acknowledgement for a previously received message.
///
/// Transport success only proves that the encrypted frame reached the peer's
/// socket. This receipt is emitted after the peer has accepted and persisted
/// the message, allowing senders to distinguish "sent" from "delivered".
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeliveryReceipt {
    pub message_id: String,
}

impl WorkplaceTextMessage {
    pub fn new(group_id: &str, body: &str) -> Result<Self> {
        let group_id = group_id.trim();
        if group_id.is_empty() {
            return Err(CapsiError::Invalid("workplace group id cannot be empty".into()));
        }
        let text = TextMessage::new(body)?;
        Ok(Self { group_id: group_id.to_string(), body: text.body })
    }
}

/// The message bodies.
///
/// `#[serde(tag = "kind")]` keeps the JSON self-describing, which makes it
/// readable in a packet capture *after* decryption and lets a new variant be
/// added without breaking peers that do not know it yet.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Message {
    /// A text message.
    Text(TextMessage),
    /// A file is on offer.
    FileOffer(FileOffer),
    /// A text message addressed to a workplace group.
    WorkplaceText(WorkplaceTextMessage),
    /// A workplace broadcast delivered to eligible members.
    WorkplaceBroadcast(WorkplaceBroadcastMessage),
    /// Application-level delivery acknowledgement for a text/workplace message.
    DeliveryReceipt(DeliveryReceipt),
    /// A response to [`Message::FileOffer`].
    FileReceipt {
        /// Which transfer this is about.
        transfer_id: String,
        /// What the peer decided.
        state: FileReceipt,
    },
    /// One chunk of a file; `data` is base64 of at most one chunk.
    FileChunk {
        /// Which transfer this belongs to.
        transfer_id: String,
        /// Zero-based chunk number.
        index: u64,
        /// Digest of this chunk's raw bytes.
        digest: String,
        /// The chunk itself, base64-encoded.
        data: String,
    },
    /// Typing indicator.
    Typing(Typing),
    /// Sent before either side hangs up, so the other can show "offline".
    Goodbye,
}

impl Message {
    /// A short name for logs and the UI.
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Text(_) => "text",
            Self::FileOffer(_) => "file_offer",
            Self::WorkplaceText(_) => "workplace_text",
            Self::WorkplaceBroadcast(_) => "workplace_broadcast",
            Self::DeliveryReceipt(_) => "delivery_receipt",
            Self::FileReceipt { .. } => "file_receipt",
            Self::FileChunk { .. } => "file_chunk",
            Self::Typing(_) => "typing",
            Self::Goodbye => "goodbye",
        }
    }

    /// True for messages that belong in the conversation history.
    ///
    /// Typing indicators and chunk traffic are transient: they drive the UI while
    /// they fly, but storing every chunk would bloat the message log.
    pub fn is_conversation_item(&self) -> bool {
        matches!(self, Self::Text(_) | Self::FileOffer(_) | Self::WorkplaceText(_))
    }
}

/// A versioned, identified, timestamped message.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Envelope {
    /// Protocol version, e.g. `capsi/1`.
    #[serde(rename = "capsi")]
    pub version: String,
    /// Message id, unique per sender.
    pub id: String,
    /// Unix seconds, as the sender saw them.
    pub sent_at: i64,
    #[serde(flatten)]
    pub message: Message,
}

impl Envelope {
    /// Wrap a message with a fresh id and timestamp.
    pub fn new(message: Message) -> Self {
        Self {
            version: PROTOCOL_VERSION.to_string(),
            id: new_id("m"),
            sent_at: crate::util::now(),
            message,
        }
    }

    /// Check the protocol version, so a mismatch is a clear error rather than a
    /// half-parsed payload.
    pub fn check_version(&self) -> Result<()> {
        if self.version != PROTOCOL_VERSION {
            return Err(CapsiError::Protocol(format!(
                "peer speaks {} but this is {PROTOCOL_VERSION}",
                self.version
            )));
        }
        Ok(())
    }

    /// Serialise for sending.
    pub fn to_json(&self) -> Result<Vec<u8>> {
        Ok(serde_json::to_vec(self)?)
    }

    /// Parse a received frame, rejecting an unknown protocol version.
    pub fn from_json(bytes: &[u8]) -> Result<Self> {
        let envelope: Self = serde_json::from_slice(bytes)?;
        envelope.check_version()?;
        Ok(envelope)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::Engine as _;

    #[test]
    fn text_messages_are_validated_and_trimmed() {
        // Trailing whitespace is noise, but leading whitespace is not: pasting
        // indented code or a list into Capsi must keep its shape.
        assert_eq!(TextMessage::new("  hi  ").unwrap().body, "  hi");
        assert_eq!(TextMessage::new("line\n").unwrap().body, "line");
        assert_eq!(TextMessage::new("code:\n    x = 1\n").unwrap().body, "code:\n    x = 1");
        assert!(TextMessage::new("   ").is_err());
        assert!(TextMessage::new("").is_err());
        assert!(TextMessage::new("\n\n").is_err());
        assert!(TextMessage::new(&"x".repeat(MAX_TEXT_MESSAGE_BYTES + 1)).is_err());
    }

    #[test]
    fn envelopes_round_trip_through_json() {
        let envelope = Envelope::new(Message::Text(TextMessage::new("hello").unwrap()));
        let json = envelope.to_json().unwrap();
        let parsed = Envelope::from_json(&json).unwrap();
        assert_eq!(parsed, envelope);
        assert_eq!(parsed.version, PROTOCOL_VERSION);
        assert!(parsed.id.starts_with("m-"));
    }

    #[test]
    fn the_json_is_self_describing() {
        let envelope = Envelope::new(Message::Goodbye);
        let value: serde_json::Value =
            serde_json::from_slice(&envelope.to_json().unwrap()).unwrap();
        assert_eq!(value["kind"], "goodbye");
        assert_eq!(value["capsi"], PROTOCOL_VERSION);
        assert!(value.get("message").is_none(), "the tag flattens the body");
    }

    #[test]
    fn a_file_offer_round_trips_with_all_its_metadata() {
        let offer = FileOffer {
            transfer_id: "t-abc".into(),
            file_name: "holiday.jpg".into(),
            size: 4_200_000,
            digest: "00ff".into(),
            chunks: 17,
        };
        let envelope = Envelope::new(Message::FileOffer(offer.clone()));
        let parsed = Envelope::from_json(&envelope.to_json().unwrap()).unwrap();
        assert_eq!(parsed.message, Message::FileOffer(offer));
    }

    #[test]
    fn a_file_chunk_carries_its_own_digest() {
        let data = base64::engine::general_purpose::STANDARD.encode(b"payload");
        let message = Message::FileChunk {
            transfer_id: "t-abc".into(),
            index: 3,
            digest: crate::util::digest_hex(b"payload"),
            data,
        };
        let envelope = Envelope::new(message.clone());
        let parsed = Envelope::from_json(&envelope.to_json().unwrap()).unwrap();
        assert_eq!(parsed.message, message);
    }

    #[test]
    fn a_receipt_round_trips() {
        for state in [
            FileReceipt::Accepted,
            FileReceipt::Declined,
            FileReceipt::Completed,
            FileReceipt::Failed,
            FileReceipt::Cancelled,
        ] {
            let envelope = Envelope::new(Message::FileReceipt {
                transfer_id: "t-1".into(),
                state,
            });
            let parsed = Envelope::from_json(&envelope.to_json().unwrap()).unwrap();
            assert_eq!(parsed.message, envelope.message);
        }
    }

    #[test]
    #[test]
    fn a_workplace_broadcast_round_trips() {
        let b = WorkplaceBroadcastMessage {
            broadcast_id: "b-1".into(),
            title: "Notice".into(),
            body: "Hello team".into(),
            department_id: None,
        };
        let envelope = Envelope::new(Message::WorkplaceBroadcast(b.clone()));
        let parsed = Envelope::from_json(&envelope.to_json().unwrap()).unwrap();
        assert_eq!(parsed.message, Message::WorkplaceBroadcast(b));
    }

    #[test]
    fn a_delivery_receipt_round_trips() {
        let receipt = DeliveryReceipt { message_id: "m-123".into() };
        let envelope = Envelope::new(Message::DeliveryReceipt(receipt.clone()));
        let parsed = Envelope::from_json(&envelope.to_json().unwrap()).unwrap();
        assert_eq!(parsed.message, Message::DeliveryReceipt(receipt));
        assert_eq!(parsed.message.kind(), "delivery_receipt");
    }

    #[test]
    fn delivery_receipts_are_not_conversation_items() {
        assert!(!Message::DeliveryReceipt(DeliveryReceipt { message_id: "m".into() }).is_conversation_item());
    }

    fn an_unknown_protocol_version_is_refused() {
        let mut envelope = Envelope::new(Message::Goodbye);
        envelope.version = "capsi/99".into();
        assert!(envelope.check_version().is_err());
        let err = Envelope::from_json(&envelope.to_json().unwrap())
            .unwrap_err()
            .to_string();
        assert!(err.contains("capsi/99"), "{err}");
    }

    #[test]
    fn an_unknown_message_kind_is_refused() {
        let json = br#"{"capsi":"capsi/1","id":"m-1","sent_at":1,"kind":"launch_missiles"}"#;
        assert!(Envelope::from_json(json).is_err());
    }

    #[test]
    fn only_real_messages_belong_in_the_history() {
        assert!(Message::Text(TextMessage::new("ok").unwrap()).is_conversation_item());
        assert!(Message::FileOffer(FileOffer {
            transfer_id: "t".into(),
            file_name: "a.txt".into(),
            size: 1,
            digest: "00".into(),
            chunks: 1,
        })
        .is_conversation_item());
        assert!(!Message::Typing(Typing { active: true }).is_conversation_item());
        assert!(!Message::Goodbye.is_conversation_item());
        assert!(Message::WorkplaceText(WorkplaceTextMessage::new("g", "ok").unwrap()).is_conversation_item());
        assert!(!Message::FileChunk {
            transfer_id: "t".into(),
            index: 0,
            digest: String::new(),
            data: String::new(),
        }
        .is_conversation_item());
    }

    #[test]
    fn a_workplace_text_round_trips_with_group_id() {
        let message = WorkplaceTextMessage::new("group-1", "hello team").unwrap();
        let envelope = Envelope::new(Message::WorkplaceText(message.clone()));
        let parsed = Envelope::from_json(&envelope.to_json().unwrap()).unwrap();
        assert_eq!(parsed.message, Message::WorkplaceText(message));
        assert_eq!(parsed.message.kind(), "workplace_text");
    }

    #[test]
    fn workplace_text_reuses_normal_message_validation() {
        assert!(WorkplaceTextMessage::new("", "hello").is_err());
        assert!(WorkplaceTextMessage::new("group-1", "   ").is_err());
        assert!(WorkplaceTextMessage::new("group-1", &"x".repeat(MAX_TEXT_MESSAGE_BYTES + 1)).is_err());
    }

    #[test]
    fn message_kinds_are_named_for_logs() {
        assert_eq!(Message::Goodbye.kind(), "goodbye");
        assert_eq!(Message::Typing(Typing { active: false }).kind(), "typing");
        assert_eq!(Message::Text(TextMessage::new("x").unwrap()).kind(), "text");
    }
}