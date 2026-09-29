//! Capsi by CAPSICOM - "Download. Run. Connect."
//!
//! Platform-independent core: identity, crypto, LAN discovery, storage,
//! transfers, and the local workplace model.
//!
//! File transfers are chunked and use a 64-bit file size in the protocol. There
//! is deliberately no application-level total file-size cap; practical limits
//! are the source filesystem, destination storage, and platform APIs. The
//! transport still keeps an individual network frame bounded for safety.

pub mod crypto;
pub mod discovery;
pub mod error;
pub mod identity;
pub mod protocol;
pub mod storage;
pub mod transport;
pub mod util;
pub mod workplace;

pub use error::{CapsiError, IntoTauri, Result};

pub const PROTOCOL_VERSION: &str = "capsi/1";
pub const DISCOVERY_PORT: u16 = 45893;
pub const TCP_SERVICE_PORT: u16 = 45892;
pub const ANNOUNCE_INTERVAL_SECS: u64 = 5;
pub const PEER_TIMEOUT_SECS: u64 = 20;
pub const TRANSFER_CHUNK_SIZE: usize = 256 * 1024;
pub const MAX_TEXT_MESSAGE_BYTES: usize = 64 * 1024;
