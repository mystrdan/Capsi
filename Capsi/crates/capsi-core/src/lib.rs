//! Capsi by CAPSICOM - "Download. Run. Connect."
//!
//! This crate is the whole of Capsi that does not need a window: the device
//! identity, the end-to-end crypto, the LAN discovery protocol, the local
//! message store and the transfer plumbing. The Tauri shell in `src-tauri`
//! is a thin command layer on top of it, and the UI is plain HTML/CSS/JS.
//!
//! Design rules that every module in here follows:
//!
//! * **Nothing leaves the machine unencrypted.** Anything that crosses the
//!   socket is sealed with a per-connection key derived from X25519.
//! * **No accounts, no servers, no telemetry.** A device is its key pair; when
//!   two devices are on the same network they can see each other, and that is
//!   the entire "sign-in" story.
//! * **Nothing is trusted implicitly.** Peers are signed-off by a human before
//!   any payload is accepted, and every payload carries a Message Authentication
//!   Code so a tampered file is discarded rather than saved.
//!
//! ```text
//! discovery  -> announce/listen on UDP, verified Ed25519 beacons
//! crypto     -> X25519 handshake, XChaCha20-Poly1305 frames
//! protocol   -> JSON envelope, versioned ("capsi/1")
//! storage    -> append-only JSON store per conversation, on disk
//! transfer   -> chunked, hashed, resumable file moves
//! ```

pub mod crypto;
pub mod discovery;
pub mod error;
pub mod identity;
pub mod protocol;
pub mod storage;
pub mod util;

pub use error::{CapsiError, IntoTauri, Result};

/// Protocol version advertised in every beacon and envelope.
pub const PROTOCOL_VERSION: &str = "capsi/1";

/// Default UDP port used to discover other Capsi devices on the LAN.
///
/// Chosen inside the dynamic/private range so it never collides with an
/// assigned service, and fixed so that discovery works without configuration.
pub const DISCOVERY_PORT: u16 = 45893;

/// How often a device re-announces itself while running, in seconds.
pub const ANNOUNCE_INTERVAL_SECS: u64 = 5;

/// A peer is considered gone after this many seconds of silence.
pub const PEER_TIMEOUT_SECS: u64 = 20;

/// Chunk size used for file transfers (256 KiB).
pub const TRANSFER_CHUNK_SIZE: usize = 256 * 1024;

/// Largest message the local store accepts before it is rejected, in bytes.
pub const MAX_TEXT_MESSAGE_BYTES: usize = 64 * 1024;
