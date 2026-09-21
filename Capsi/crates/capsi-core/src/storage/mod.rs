//! The local message store.
//!
//! ```text
//! storage/
//!   conversation  - one JSON file per contact, plus the in-memory index
//! ```
//!
//! Capsi keeps your history on your own machine and nowhere else: a conversation
//! is a single file under the Capsi data directory, named after the peer's device
//! id. There is no database to corrupt and no server to leak - and deleting a
//! conversation is deleting a file.

pub mod conversation;

pub use conversation::{
    Conversation, DeliveryState, MessageKind, MessageStore, StoredFile, StoredMessage,
    TransferState,
};