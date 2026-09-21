//! X25519 handshake + XChaCha20-Poly1305 frame sealing.
//!
//! See the module documentation in [`crate::crypto`] for the reasoning; this is
//! the implementation both devices run.

use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{Key, XChaCha20Poly1305, XNonce};
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::error::{CapsiError, Result};
use crate::identity::device::random_bytes;
use crate::identity::{DeviceId, DeviceIdentity};
use crate::util::digest_hex;

/// Domain-separation label for the session key schedule.
const KDF_LABEL: &[u8] = b"capsi/1/session-key";

/// Domain-separation label for the signed handshake.
const HANDSHAKE_LABEL: &[u8] = b"capsi/1/handshake";

/// Bytes a sealed frame costs on top of the plaintext:
/// 8 (counter) + 16 (Poly1305 tag).
pub const FRAME_OVERHEAD: usize = 8 + 16;

/// How many out-of-order frames we are willing to remember.
pub const MAX_REPLAY_WINDOW: u64 = 1024;

/// One side of the connection handshake.
///
/// Nothing here is secret - the nonce and the X25519 public key are meant to be
/// seen. The `signature` is what makes them trustworthy: it is an Ed25519
/// signature by the device whose *id* the peer already has in its trust list, so
/// an attacker cannot substitute their own exchange key and silently become the
/// man in the middle.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Handshake {
    /// Sender's device id, so the receiver can pick the right pinned key.
    pub device_id: DeviceId,
    /// Fresh 32-byte random nonce, new for every connection.
    pub nonce: String,
    /// Sender's X25519 public key.
    pub exchange_key: String,
    /// Ed25519 signature over [`Self::signed_bytes`].
    pub signature: String,
}

impl Handshake {
    /// Build and sign our half of the handshake.
    pub fn create(identity: &DeviceIdentity) -> Result<Self> {
        let mut nonce = [0u8; 32];
        random_bytes(&mut nonce)?;
        let mut handshake = Self {
            device_id: identity.id().clone(),
            nonce: hex::encode(nonce),
            exchange_key: hex::encode(identity.exchange_public()),
            signature: String::new(),
        };
        handshake.signature = identity.sign_hex(&handshake.signed_bytes()?);
        Ok(handshake)
    }

    /// The exact bytes covered by the signature.
    ///
    /// Both fields are validated first so a malformed value is rejected as a
    /// protocol error rather than being signed into the transcript.
    pub fn signed_bytes(&self) -> Result<Vec<u8>> {
        let nonce = self.nonce_bytes()?;
        let exchange = self.exchange_bytes()?;
        let mut out = Vec::with_capacity(160);
        out.extend_from_slice(HANDSHAKE_LABEL);
        out.extend_from_slice(b"|");
        out.extend_from_slice(self.device_id.as_str().as_bytes());
        out.extend_from_slice(b"|");
        out.extend_from_slice(hex::encode(nonce).as_bytes());
        out.extend_from_slice(b"|");
        out.extend_from_slice(hex::encode(exchange).as_bytes());
        Ok(out)
    }

    /// Check the signature against the key the device id commits to.
    pub fn verify(&self) -> Result<()> {
        let key = DeviceIdentity::peer_verifying_key(&self.device_id)?;
        DeviceIdentity::verify_hex(&key, &self.signed_bytes()?, &self.signature)
    }

    /// Raw nonce bytes.
    pub fn nonce_bytes(&self) -> Result<[u8; 32]> {
        decode_32(&self.nonce, "handshake nonce")
    }

    /// Raw X25519 public key bytes.
    pub fn exchange_bytes(&self) -> Result<[u8; 32]> {
        decode_32(&self.exchange_key, "handshake exchange key")
    }
}

/// Decode a 32-byte hex string.
fn decode_32(value: &str, what: &str) -> Result<[u8; 32]> {
    let mut out = [0u8; 32];
    hex::decode_to_slice(value, &mut out)
        .map_err(|e| CapsiError::Protocol(format!("bad {what}: {e}")))?;
    Ok(out)
}

/// The two direction-specific keys derived from one handshake.
///
/// Send and receive are keyed separately so the two counter sequences can never
/// collide, and a frame reflected back at its sender fails to decrypt instead of
/// being accepted as its own.
#[derive(Zeroize, ZeroizeOnDrop)]
pub struct SessionKeys {
    /// Key used to seal outgoing frames.
    send: [u8; 32],
    /// Key used to open incoming frames.
    receive: [u8; 32],
    /// Public 16-byte session salt; every frame nonce starts with it.
    salt: [u8; 16],
}

impl SessionKeys {
    /// Derive the session keys from **both** handshakes.
    ///
    /// `initiator` is whoever opened the connection (the side that dialled TCP).
    /// Both peers agree on it by construction, which is what lets them order the
    /// two handshakes identically without another round trip.
    pub fn derive(
        identity: &DeviceIdentity,
        mine: &Handshake,
        theirs: &Handshake,
        initiator: bool,
    ) -> Result<Self> {
        if theirs.device_id == *identity.id() {
            return Err(CapsiError::Crypto("refusing to talk to ourselves".into()));
        }
        // The peer's exchange key is only usable if their own Ed25519 key signed
        // it - otherwise this could be an impostor's key.
        theirs.verify()?;
        let shared = identity.shared_secret(&theirs.exchange_bytes()?);

        // Canonical order: the initiator's handshake always comes first, so both
        // sides hash the same transcript.
        let (first, second) = if initiator { (mine, theirs) } else { (theirs, mine) };

        // A fresh salt per session. Because the nonces are new every connection,
        // the same long-term keys never produce the same keystream twice.
        let mut salt = [0u8; 16];
        let salt_hex = digest_hex(&[first.nonce.as_bytes(), second.nonce.as_bytes()].concat());
        hex::decode_to_slice(&salt_hex[..32], &mut salt)
            .map_err(|e| CapsiError::Crypto(format!("salt derivation failed: {e}")))?;

        let (send_dir, receive_dir) = if initiator {
            (&b"initiator->responder"[..], &b"responder->initiator"[..])
        } else {
            (&b"responder->initiator"[..], &b"initiator->responder"[..])
        };

        Ok(Self {
            send: kdf(send_dir, &shared, &salt, first, second),
            receive: kdf(receive_dir, &shared, &salt, first, second),
            salt,
        })
    }

    /// The public session salt, mixed into every frame nonce.
    pub fn salt(&self) -> [u8; 16] {
        self.salt
    }

    /// Sanity check used by tests: the two directions must use different keys.
    pub fn directions_differ(&self) -> bool {
        self.send != self.receive
    }
}

/// BLAKE2b-based KDF. 32 bytes out, every input that matters mixed in.
fn kdf(
    direction: &[u8],
    shared: &[u8; 32],
    salt: &[u8; 16],
    first: &Handshake,
    second: &Handshake,
) -> [u8; 32] {
    let mut input = Vec::with_capacity(320);
    input.extend_from_slice(KDF_LABEL);
    input.extend_from_slice(b"|");
    input.extend_from_slice(direction);
    input.extend_from_slice(b"|");
    input.extend_from_slice(shared);
    input.extend_from_slice(salt);
    input.extend_from_slice(first.device_id.as_str().as_bytes());
    input.extend_from_slice(b"|");
    input.extend_from_slice(first.nonce.as_bytes());
    input.extend_from_slice(b"|");
    input.extend_from_slice(first.exchange_key.as_bytes());
    input.extend_from_slice(b"|");
    input.extend_from_slice(second.device_id.as_str().as_bytes());
    input.extend_from_slice(b"|");
    input.extend_from_slice(second.nonce.as_bytes());
    input.extend_from_slice(b"|");
    input.extend_from_slice(second.exchange_key.as_bytes());

    let mut key = [0u8; 32];
    hex::decode_to_slice(&digest_hex(&input), &mut key).expect("blake2b digest is 64 hex chars");
    key
}

/// Sliding replay window over the frame counter.
///
/// Bit `n` means "the frame `highest - n` was already accepted". Anything older
/// than [`MAX_REPLAY_WINDOW`] frames is refused, which bounds how much state an
/// attacker can make us remember while still tolerating reordering on a lossy
/// Wi-Fi link.
#[derive(Debug, Default)]
struct ReplayWindow {
    highest: u64,
    bitmap: [u64; 16],
    started: bool,
}

impl ReplayWindow {
    fn bit_set(&self, offset: u64) -> bool {
        let word = (offset / 64) as usize;
        let bit = offset % 64;
        word < self.bitmap.len() && self.bitmap[word] & (1u64 << bit) != 0
    }

    fn set_bit(&mut self, offset: u64) {
        let word = (offset / 64) as usize;
        let bit = offset % 64;
        if word < self.bitmap.len() {
            self.bitmap[word] |= 1u64 << bit;
        }
    }

    /// Move every remembered frame `delta` counter values further into the past.
    fn shift_up(&mut self, delta: u64) {
        if delta >= MAX_REPLAY_WINDOW {
            self.bitmap = [0u64; 16];
            return;
        }
        let word_shift = (delta / 64) as usize;
        let bit_shift = (delta % 64) as u32;
        let old = self.bitmap;
        let mut out = [0u64; 16];
        for (i, word) in old.iter().enumerate() {
            if *word == 0 {
                continue;
            }
            let target = i + word_shift;
            if target < out.len() {
                out[target] |= word << bit_shift;
            }
            if bit_shift > 0 && target + 1 < out.len() {
                out[target + 1] |= word >> (64 - bit_shift);
            }
        }
        self.bitmap = out;
    }

    /// Register a counter; false means "replay or too old, drop the frame".
    fn accept(&mut self, counter: u64) -> bool {
        if !self.started {
            self.started = true;
            self.highest = counter;
            self.bitmap = [0u64; 16];
            self.set_bit(0);
            return true;
        }
        if counter > self.highest {
            self.shift_up(counter - self.highest);
            self.highest = counter;
            self.set_bit(0);
            return true;
        }
        let offset = self.highest - counter;
        if offset >= MAX_REPLAY_WINDOW || self.bit_set(offset) {
            return false;
        }
        self.set_bit(offset);
        true
    }
}

/// An authenticated, ordered, replay-protected channel to one peer.
///
/// One `Session` per TCP connection. It owns the counters, so the transport just
/// hands it plaintext and writes whatever comes back.
pub struct Session {
    send_cipher: XChaCha20Poly1305,
    receive_cipher: XChaCha20Poly1305,
    salt: [u8; 16],
    send_counter: u64,
    replay: ReplayWindow,
    peer: DeviceId,
}

impl Session {
    /// Build a session from already-derived keys.
    pub fn new(keys: SessionKeys, peer: DeviceId) -> Self {
        let send_cipher = XChaCha20Poly1305::new(Key::from_slice(&keys.send));
        let receive_cipher = XChaCha20Poly1305::new(Key::from_slice(&keys.receive));
        Self {
            send_cipher,
            receive_cipher,
            salt: keys.salt,
            send_counter: 0,
            replay: ReplayWindow::default(),
            peer,
        }
    }

    /// Handshake + key derivation in one call, which is what callers want: hand
    /// it your identity and the two handshakes.
    pub fn establish(
        identity: &DeviceIdentity,
        mine: &Handshake,
        theirs: &Handshake,
        initiator: bool,
    ) -> Result<Self> {
        let keys = SessionKeys::derive(identity, mine, theirs, initiator)?;
        Ok(Self::new(keys, theirs.device_id.clone()))
    }

    /// The device on the other end.
    pub fn peer(&self) -> &DeviceId {
        &self.peer
    }

    /// How many frames we have sent (also the next counter value).
    pub fn frames_sent(&self) -> u64 {
        self.send_counter
    }

    /// The 24-byte XChaCha20 nonce: public salt + big-endian counter.
    ///
    /// A nonce must never repeat under one key, so the counter is unique per key
    /// and the salt is unique per session - which matters because the long-term
    /// X25519 keys are static.
    fn nonce_for(&self, counter: u64) -> [u8; 24] {
        let mut nonce = [0u8; 24];
        nonce[..16].copy_from_slice(&self.salt);
        nonce[16..].copy_from_slice(&counter.to_be_bytes());
        nonce
    }

    /// Encrypt one frame.
    ///
    /// Layout: `counter (8, big-endian) || ciphertext || Poly1305 tag`. The
    /// counter is also the associated data, so it cannot be reordered or
    /// rewritten without invalidating the tag.
    pub fn seal(&mut self, plaintext: &[u8]) -> Result<Vec<u8>> {
        let counter = self.send_counter;
        let nonce_bytes = self.nonce_for(counter);
        let header = counter.to_be_bytes();
        let sealed = self
            .send_cipher
            .encrypt(
                XNonce::from_slice(&nonce_bytes),
                Payload {
                    msg: plaintext,
                    aad: &header,
                },
            )
            .map_err(|_| CapsiError::Crypto("frame could not be sealed".into()))?;
        // Only advance once the frame really exists.
        self.send_counter += 1;

        let mut frame = Vec::with_capacity(header.len() + sealed.len());
        frame.extend_from_slice(&header);
        frame.extend_from_slice(&sealed);
        Ok(frame)
    }

    /// Seal a JSON payload (what the protocol layer actually sends).
    pub fn seal_json<T: serde::Serialize>(&mut self, value: &T) -> Result<Vec<u8>> {
        let json = serde_json::to_vec(value)?;
        self.seal(&json)
    }

    /// Decrypt and authenticate one frame, rejecting replays.
    pub fn open(&mut self, frame: &[u8]) -> Result<Vec<u8>> {
        if frame.len() < FRAME_OVERHEAD {
            return Err(CapsiError::Protocol(format!(
                "frame too short: {} bytes",
                frame.len()
            )));
        }
        let mut header = [0u8; 8];
        header.copy_from_slice(&frame[..8]);
        let counter = u64::from_be_bytes(header);

        // Authenticate *before* touching the replay window: a forged counter must
        // not be able to consume window space or push the window forward.
        let nonce_bytes = self.nonce_for(counter);
        let plaintext = self
            .receive_cipher
            .decrypt(
                XNonce::from_slice(&nonce_bytes),
                Payload {
                    msg: &frame[8..],
                    aad: &header,
                },
            )
            .map_err(|_| CapsiError::Crypto("frame failed authentication".into()))?;

        if !self.replay.accept(counter) {
            return Err(CapsiError::Crypto(format!(
                "replayed or stale frame #{counter}"
            )));
        }
        Ok(plaintext)
    }

    /// Decrypt a frame that is expected to hold JSON.
    pub fn open_json<T: serde::de::DeserializeOwned>(&mut self, frame: &[u8]) -> Result<T> {
        let plaintext = self.open(frame)?;
        serde_json::from_slice(&plaintext)
            .map_err(|e| CapsiError::Protocol(format!("frame did not contain valid json: {e}")))
    }
}

impl std::fmt::Debug for Session {
    /// Never print keys or counters.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Session")
            .field("peer", &self.peer.as_str())
            .finish_non_exhaustive()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Two peers, each with its own handshake, wired up ready to talk.
    struct Pair {
        a: Session,
        b: Session,
    }

    fn pair() -> Pair {
        let alice = DeviceIdentity::from_secrets(&[1u8; 32], &[2u8; 32]);
        let bob = DeviceIdentity::from_secrets(&[3u8; 32], &[4u8; 32]);
        let a_hs = Handshake::create(&alice).unwrap();
        let b_hs = Handshake::create(&bob).unwrap();
        // Alice dialled, so she is the initiator.
        let a = Session::establish(&alice, &a_hs, &b_hs, true).unwrap();
        let b = Session::establish(&bob, &b_hs, &a_hs, false).unwrap();
        Pair { a, b }
    }

    #[test]
    fn handshakes_are_signed_and_verifiable() {
        let identity = DeviceIdentity::generate().unwrap();
        let handshake = Handshake::create(&identity).unwrap();
        assert!(handshake.verify().is_ok());
        assert_eq!(handshake.device_id, *identity.id());
        assert_eq!(handshake.nonce.len(), 64);
        assert_eq!(handshake.exchange_key.len(), 64);
    }

    #[test]
    fn a_tampered_handshake_is_rejected() {
        let identity = DeviceIdentity::generate().unwrap();
        let mut handshake = Handshake::create(&identity).unwrap();
        // Swap in a different X25519 key, keeping the original signature.
        let attacker = DeviceIdentity::generate().unwrap();
        handshake.exchange_key = hex::encode(attacker.exchange_public());
        assert!(handshake.verify().is_err());

        // And a handshake claiming to be someone else entirely.
        let mut forged = Handshake::create(&identity).unwrap();
        forged.device_id = attacker.id().clone();
        assert!(forged.verify().is_err());
    }

    #[test]
    fn both_peers_agree_on_the_session() {
        let Pair { mut a, mut b } = pair();
        let frame = a.seal(b"meet me at the printer").unwrap();
        assert_eq!(b.open(&frame).unwrap(), b"meet me at the printer");

        let reply = b.seal(b"on my way").unwrap();
        assert_eq!(a.open(&reply).unwrap(), b"on my way");
    }

    #[test]
    fn the_two_directions_use_different_keys() {
        let alice = DeviceIdentity::from_secrets(&[7u8; 32], &[8u8; 32]);
        let bob = DeviceIdentity::from_secrets(&[9u8; 32], &[10u8; 32]);
        let a_hs = Handshake::create(&alice).unwrap();
        let b_hs = Handshake::create(&bob).unwrap();
        let keys = SessionKeys::derive(&alice, &a_hs, &b_hs, true).unwrap();
        assert!(keys.directions_differ());
        assert_ne!(keys.salt(), [0u8; 16]);
    }

    #[test]
    fn a_third_device_cannot_join_the_session() {
        let Pair { mut a, .. } = pair();
        let frame = a.seal(b"private").unwrap();

        let eve = DeviceIdentity::from_secrets(&[5u8; 32], &[6u8; 32]);
        let alice = DeviceIdentity::from_secrets(&[1u8; 32], &[2u8; 32]);
        let alice_hs = Handshake::create(&alice).unwrap();
        let eve_hs = Handshake::create(&eve).unwrap();
        let mut eavesdropper = Session::establish(&eve, &eve_hs, &alice_hs, false).unwrap();
        assert!(eavesdropper.open(&frame).is_err());
    }

    #[test]
    fn tampering_with_a_frame_is_detected() {
        let Pair { mut a, mut b } = pair();
        let frame = a.seal(b"transfer 1 file").unwrap();

        let mut flipped = frame.clone();
        let last = flipped.len() - 1;
        flipped[last] ^= 0x01;
        assert!(b.open(&flipped).is_err());

        // Truncation is caught by the header length check.
        assert!(b.open(&frame[..8]).is_err());
        // A short frame never reaches the cipher.
        assert!(b.open(&[]).is_err());
    }

    #[test]
    fn replaying_a_frame_is_refused() {
        let Pair { mut a, mut b } = pair();
        let frame = a.seal(b"only once").unwrap();
        assert!(b.open(&frame).is_ok());
        let err = b.open(&frame).unwrap_err().to_string();
        assert!(err.contains("replayed"), "unexpected error: {err}");
    }

    #[test]
    fn out_of_order_frames_are_accepted_once_each() {
        let Pair { mut a, mut b } = pair();
        let one = a.seal(&1u32.to_be_bytes()).unwrap();
        let two = a.seal(&2u32.to_be_bytes()).unwrap();
        let three = a.seal(&3u32.to_be_bytes()).unwrap();

        // Arriving out of order is normal on real Wi-Fi.
        assert_eq!(b.open(&three).unwrap(), 3u32.to_be_bytes());
        assert_eq!(b.open(&one).unwrap(), 1u32.to_be_bytes());
        assert_eq!(b.open(&two).unwrap(), 2u32.to_be_bytes());
        // But each one still only counts once.
        assert!(b.open(&one).is_err());
        assert!(b.open(&two).is_err());
        assert!(b.open(&three).is_err());
    }

    #[test]
    fn json_payloads_round_trip_through_a_session() {
        #[derive(serde::Serialize, serde::Deserialize, PartialEq, Debug)]
        struct Note {
            body: String,
            sent_at: i64,
        }
        let Pair { mut a, mut b } = pair();
        let note = Note {
            body: "photos attached".into(),
            sent_at: 1_700_000_000,
        };
        let frame = a.seal_json(&note).unwrap();
        assert_eq!(b.open_json::<Note>(&frame).unwrap(), note);
        assert_eq!(a.frames_sent(), 1);
    }

    #[test]
    fn fresh_handshakes_produce_fresh_salts() {
        let alice = DeviceIdentity::from_secrets(&[11u8; 32], &[12u8; 32]);
        let bob = DeviceIdentity::from_secrets(&[13u8; 32], &[14u8; 32]);
        let a_hs = Handshake::create(&alice).unwrap();
        let b_hs = Handshake::create(&bob).unwrap();
        let first = SessionKeys::derive(&alice, &a_hs, &b_hs, true).unwrap();
        let second = SessionKeys::derive(&alice, &a_hs, &b_hs, true).unwrap();
        // Identical handshake transcripts give identical keys (that is what makes
        // derivation deterministic), but every real connection makes new ones.
        assert_eq!(first.salt(), second.salt());

        let a_hs2 = Handshake::create(&alice).unwrap();
        let b_hs2 = Handshake::create(&bob).unwrap();
        let third = SessionKeys::derive(&alice, &a_hs2, &b_hs2, true).unwrap();
        assert_ne!(first.salt(), third.salt());
    }

    #[test]
    fn a_device_refuses_to_handshake_with_itself() {
        let alice = DeviceIdentity::from_secrets(&[15u8; 32], &[16u8; 32]);
        let a_hs = Handshake::create(&alice).unwrap();
        assert!(SessionKeys::derive(&alice, &a_hs, &a_hs, true).is_err());
    }

    #[test]
    fn the_replay_window_forgets_frames_that_are_too_old() {
        let mut window = ReplayWindow::default();
        assert!(window.accept(0));
        assert!(window.accept(MAX_REPLAY_WINDOW + 10));
        // 0 is now far outside the window.
        assert!(!window.accept(0));
        // Something inside the window is still fine the first time.
        assert!(window.accept(MAX_REPLAY_WINDOW + 9));
        assert!(!window.accept(MAX_REPLAY_WINDOW + 9));
    }

    #[test]
    fn the_window_shifts_correctly_across_word_boundaries() {
        let mut window = ReplayWindow::default();
        assert!(window.accept(0));
        // A jump that crosses a 64-bit word boundary.
        assert!(window.accept(200));
        assert!(!window.accept(0), "stale frame must stay refused");
        assert!(window.accept(199));
        assert!(!window.accept(199));
        assert!(window.accept(141), "oldest frame still inside the window");
    }
}