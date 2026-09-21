//! Capsi - device identity.
//!
//! Every Capsi install owns two long-term key pairs, created on first launch and
//! stored locally. Nothing is registered anywhere; the device *is* its key.
//!
//! * **Ed25519** - the device id, and every announcement is signed with it, so a
//!   peer's name and port cannot be spoofed on the LAN.
//! * **X25519** - static Diffie-Hellman key used to derive a fresh session key
//!   for each connection, which is then used with XChaCha20-Poly1305.

use std::fs;
use std::path::{Path, PathBuf};

use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine as _;
use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};
use serde::{Deserialize, Serialize};
use x25519_dalek::{PublicKey as ExchangePublicKey, StaticSecret};

use crate::error::{CapsiError, Result};

/// Number of random bytes in a Capsi key.
const KEY_BYTES: usize = 32;

/// A Capsi device id: the hex-encoded Ed25519 public key (64 characters).
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub struct DeviceId(String);

impl DeviceId {
    /// Wrap an already-known id (used when reading the wire protocol).
    pub fn from_hex(hex: &str) -> Result<Self> {
        if hex.len() != 64 || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err(CapsiError::Invalid(format!("bad device id: {hex}")));
        }
        Ok(Self(hex.to_ascii_lowercase()))
    }

    /// Build an id from a verifying key.
    pub fn from_verifying_key(key: &VerifyingKey) -> Self {
        Self(hex::encode(key.to_bytes()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// Short form for compact UI (first 8 hex characters).
    pub fn short(&self) -> String {
        self.0.chars().take(8).collect()
    }

    /// Human-comparable fingerprint, e.g. `3F2A 91C4 B7E0 5D18`.
    pub fn fingerprint(&self) -> Fingerprint {
        Fingerprint::from_hex(&self.0)
    }
}

/// A short, human-readable rendering of a device id.
///
/// Users compare these out loud when they want to be certain who they are
/// talking to: "Accept", then read the four blocks.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Fingerprint(String);

impl Fingerprint {
    /// `ABCD 1234 EF56 7890` - the first 8 bytes of the device id.
    pub fn from_hex(hex_id: &str) -> Self {
        let upper = hex_id.to_ascii_uppercase();
        let bytes = upper.as_bytes();
        let mut groups = Vec::new();
        let mut i = 0;
        while i + 3 < bytes.len() && groups.len() < 4 {
            groups.push(String::from_utf8_lossy(&bytes[i..i + 4]).to_string());
            i += 4;
        }
        Self(groups.join(" "))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Display for Fingerprint {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

/// What is persisted on disk. Keys are base64 so the file stays readable and
/// diff-friendly while still being compact.
#[derive(Debug, Serialize, Deserialize)]
struct StoredIdentity {
    version: u32,
    signing_key: String,
    exchange_key: String,
    created_at: i64,
}

/// This device's cryptographic identity.
pub struct DeviceIdentity {
    /// Ed25519 signing key - never leaves the machine.
    signing: SigningKey,
    /// X25519 static secret - never leaves the machine.
    exchange: StaticSecret,
    /// Cached id = hex(Ed25519 public key).
    id: DeviceId,
}

impl DeviceIdentity {
    /// Load the identity from `dir`, creating it on first launch.
    ///
    /// The device id is never regenerated unless the file is removed, which is
    /// exactly what "Reset identity" in Settings does.
    pub fn load_or_create(dir: &Path) -> Result<Self> {
        let path = identity_path(dir);
        if path.exists() {
            match Self::read_from(&path) {
                Ok(identity) => return Ok(identity),
                Err(e) => {
                    // A corrupt key file must not lock the user out forever:
                    // keep it aside for support and generate a fresh identity.
                    let backup = path.with_extension(format!("corrupt-{}.bak", now_secs()));
                    let _ = fs::rename(&path, backup);
                    log::warn!("capsi identity unreadable ({e}); generated a fresh one");
                }
            }
        }
        let identity = Self::generate()?;
        identity.save(dir)?;
        Ok(identity)
    }

    /// Create a brand new identity from the operating system CSPRNG.
    pub fn generate() -> Result<Self> {
        let mut seed = [0u8; KEY_BYTES];
        let mut exchange = [0u8; KEY_BYTES];
        random_bytes(&mut seed)?;
        random_bytes(&mut exchange)?;
        Ok(Self::from_secrets(&seed, &exchange))
    }

    /// Rebuild an identity from its raw secrets (also used by unit tests).
    pub fn from_secrets(signing_seed: &[u8; KEY_BYTES], exchange: &[u8; KEY_BYTES]) -> Self {
        let signing = SigningKey::from_bytes(signing_seed);
        let id = DeviceId::from_verifying_key(&signing.verifying_key());
        Self {
            signing,
            exchange: StaticSecret::from(*exchange),
            id,
        }
    }

    /// Persist the identity into `dir` (creating the directory if needed).
    pub fn save(&self, dir: &Path) -> Result<()> {
        fs::create_dir_all(dir)?;
        let stored = StoredIdentity {
            version: 1,
            signing_key: B64.encode(self.signing.to_bytes()),
            exchange_key: B64.encode(self.exchange.to_bytes()),
            created_at: now_secs(),
        };
        write_private(&identity_path(dir), &serde_json::to_vec_pretty(&stored)?)
    }

    fn read_from(path: &Path) -> Result<Self> {
        let stored: StoredIdentity = serde_json::from_str(&fs::read_to_string(path)?)?;
        if stored.version != 1 {
            return Err(CapsiError::Protocol(format!(
                "unsupported identity version {}",
                stored.version
            )));
        }
        Ok(Self::from_secrets(
            &decode_fixed::<KEY_BYTES>(&stored.signing_key)?,
            &decode_fixed::<KEY_BYTES>(&stored.exchange_key)?,
        ))
    }

    /// This device's public id.
    pub fn id(&self) -> &DeviceId {
        &self.id
    }

    pub fn fingerprint(&self) -> Fingerprint {
        self.id.fingerprint()
    }

    /// The Ed25519 public key other devices use to verify what we signed.
    pub fn verifying_key(&self) -> VerifyingKey {
        self.signing.verifying_key()
    }

    /// Our X25519 public key, sent during the session handshake.
    pub fn exchange_public(&self) -> [u8; KEY_BYTES] {
        ExchangePublicKey::from(&self.exchange).to_bytes()
    }

    /// Sign `message` with the device key.
    pub fn sign(&self, message: &[u8]) -> Signature {
        self.signing.sign(message)
    }

    /// Signature as hex, for the JSON wire format.
    pub fn sign_hex(&self, message: &[u8]) -> String {
        hex::encode(self.sign(message).to_bytes())
    }

    /// Verify a hex signature produced by [`Self::sign_hex`].
    pub fn verify_hex(verifying_key: &VerifyingKey, message: &[u8], sig_hex: &str) -> Result<()> {
        let signature = Signature::from_bytes(&decode_fixed::<64>(sig_hex)?);
        verifying_key
            .verify(message, &signature)
            .map_err(|_| CapsiError::Crypto("signature check failed".into()))
    }

    /// Raw X25519 shared secret with a peer's public key.
    pub fn shared_secret(&self, peer_public: &[u8; KEY_BYTES]) -> [u8; KEY_BYTES] {
        self.exchange
            .diffie_hellman(&ExchangePublicKey::from(*peer_public))
            .to_bytes()
    }

    /// Recover a peer's `VerifyingKey` from their device id.
    pub fn peer_verifying_key(device_id: &DeviceId) -> Result<VerifyingKey> {
        let bytes = decode_fixed::<KEY_BYTES>(device_id.as_str())?;
        VerifyingKey::from_bytes(&bytes)
            .map_err(|e| CapsiError::Crypto(format!("peer public key rejected: {e}")))
    }

    /// Delete the stored identity ("Reset identity" in Settings).
    pub fn reset(dir: &Path) -> Result<()> {
        let path = identity_path(dir);
        if path.exists() {
            fs::remove_file(path)?;
        }
        Ok(())
    }
}

impl std::fmt::Debug for DeviceIdentity {
    /// Never print secret material.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("DeviceIdentity")
            .field("id", &self.id.as_str())
            .finish_non_exhaustive()
    }
}

/// `…/identity.json` inside the Capsi data directory.
pub fn identity_path(dir: &Path) -> PathBuf {
    dir.join("identity.json")
}

/// Decode a base64 (or hex) string into a fixed-size array.
fn decode_fixed<const N: usize>(value: &str) -> Result<[u8; N]> {
    let bytes = if value.len() == N * 2 && value.bytes().all(|b| b.is_ascii_hexdigit()) {
        hex::decode(value).map_err(|e| CapsiError::Crypto(e.to_string()))?
    } else {
        B64.decode(value)
            .map_err(|e| CapsiError::Crypto(format!("bad key encoding: {e}")))?
    };
    if bytes.len() != N {
        return Err(CapsiError::Crypto(format!(
            "expected {N} key bytes, got {}",
            bytes.len()
        )));
    }
    let mut out = [0u8; N];
    out.copy_from_slice(&bytes);
    Ok(out)
}

/// Write a file that is only readable by the current user where supported.
pub fn write_private(path: &Path, bytes: &[u8]) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, bytes)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o600));
    }
    Ok(())
}

/// Seconds since the Unix epoch.
pub fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Milliseconds since the Unix epoch.
pub fn now_millis() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Fill `buf` with operating-system randomness.
pub fn random_bytes(buf: &mut [u8]) -> Result<()> {
    getrandom::getrandom(buf).map_err(|e| CapsiError::Crypto(format!("no system randomness: {e}")))
}

/// A unique id for a message / transfer / group, e.g. `m-1a2b3c4d5e6f`.
///
/// Lives in [`crate::util::new_id`] so the id scheme is defined once.
pub use crate::util::new_id as new_local_id;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identity_ids_are_hex_and_stable() {
        let identity = DeviceIdentity::generate().unwrap();
        assert_eq!(identity.id().as_str().len(), 64);
        assert!(identity
            .id()
            .as_str()
            .bytes()
            .all(|b| b.is_ascii_hexdigit()));
        let again = DeviceIdentity::from_secrets(
            &identity.signing.to_bytes(),
            &identity.exchange.to_bytes(),
        );
        assert_eq!(identity.id(), again.id());
    }

    #[test]
    fn signatures_round_trip_and_reject_tampering() {
        let identity = DeviceIdentity::generate().unwrap();
        let message = b"capsi/1/announce|Office-PC|45893";
        let sig = identity.sign_hex(message);
        let key = identity.verifying_key();
        assert!(DeviceIdentity::verify_hex(&key, message, &sig).is_ok());
        let tampered = b"capsi/1/announce|Evil-PC|45893";
        assert!(DeviceIdentity::verify_hex(&key, tampered, &sig).is_err());
    }

    #[test]
    fn keyfiles_survive_a_round_trip_on_disk() {
        let dir = std::env::temp_dir().join(format!("capsi-identity-{}", now_millis()));
        let created = DeviceIdentity::load_or_create(&dir).unwrap();
        let reloaded = DeviceIdentity::load_or_create(&dir).unwrap();
        assert_eq!(created.id(), reloaded.id());
        assert_eq!(
            created.exchange_public(),
            reloaded.exchange_public(),
            "the exchange key must persist"
        );
        assert!(identity_path(&dir).exists());
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn fingerprints_are_short_and_grouped() {
        let id = DeviceId::from_hex(&"a1".repeat(32)).unwrap();
        assert_eq!(id.fingerprint().as_str(), "A1A1 A1A1 A1A1 A1A1");
        assert_eq!(id.short(), "a1a1a1a1");
        assert!(DeviceId::from_hex("nope").is_err());
    }

    #[test]
    fn public_keys_are_recoverable_from_the_device_id() {
        let identity = DeviceIdentity::generate().unwrap();
        let peer = DeviceIdentity::peer_verifying_key(identity.id()).unwrap();
        assert_eq!(peer.to_bytes(), identity.verifying_key().to_bytes());
    }

    #[test]
    fn both_sides_agree_on_the_shared_secret() {
        let a = DeviceIdentity::generate().unwrap();
        let b = DeviceIdentity::generate().unwrap();
        assert_eq!(
            a.shared_secret(&b.exchange_public()),
            b.shared_secret(&a.exchange_public())
        );
    }

    #[test]
    fn a_corrupt_identity_file_is_replaced_not_fatal() {
        let dir = std::env::temp_dir().join(format!("capsi-broken-{}", now_millis()));
        fs::create_dir_all(&dir).unwrap();
        fs::write(identity_path(&dir), b"{ not json").unwrap();
        let identity = DeviceIdentity::load_or_create(&dir).unwrap();
        assert_eq!(identity.id().as_str().len(), 64);
        fs::remove_dir_all(&dir).ok();
    }
}
