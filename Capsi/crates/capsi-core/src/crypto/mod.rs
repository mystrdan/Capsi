//! Capsi's end-to-end cryptography.
//!
//! ```text
//! crypto/
//!   session  - X25519 handshake + XChaCha20-Poly1305 frame sealing
//! ```
//!
//! Everything that travels over the wire goes through one [`session::Session`].
//! The rules the rest of the code relies on:
//!
//! 1. Both devices already know each other's long-term keys, because a device id
//!    *is* its Ed25519 public key and the trust list pins it.
//! 2. Each connection starts with a fresh random 32-byte nonce from **each**
//!    side. Those two nonces, plus the X25519 shared secret, plus both public
//!    keys go into a BLAKE2b KDF, producing separate send and receive keys.
//!    Because the nonces are new every time, putting Capsi on a coffee-shop
//!    Wi-Fi never reuses a keystream even though the long-term keys are static.
//! 3. Every frame carries a monotonic counter which doubles as the nonce suffix
//!    and as additional authenticated data, and a sliding replay window rejects
//!    anything seen before or too old to matter.

pub mod session;

pub use session::{Handshake, Session, SessionKeys, FRAME_OVERHEAD, MAX_REPLAY_WINDOW};