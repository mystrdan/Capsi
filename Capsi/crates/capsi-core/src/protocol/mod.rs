//! The Capsi wire protocol (`capsi/1`).
//!
//! ```text
//! protocol/
//!   message  - typed JSON envelopes exchanged inside a crypto::Session
//!   framing  - length-prefixed frames over a TCP stream
//! ```
//!
//! Discovery beacons are *not* framed: they are single UDP datagrams, defined in
//! [`crate::discovery`] because they are only ever verified, never relayed.

pub mod framing;
pub mod message;

pub use framing::{read_frame, write_frame, MAX_FRAME_BYTES};
pub use message::{DeliveryReceipt, Envelope, FileOffer, FileReceipt, Message, TextMessage, Typing, WorkplaceBroadcastMessage, WorkplaceTextMessage};