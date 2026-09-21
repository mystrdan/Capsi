//! Capsi identity: who *this* device is, and which other devices it trusts.
//!
//! ```text
//! identity/
//!   device  - this device's key pair + stable Capsi device id
//!   trust   - the trust list ("Accept" / "Ignore" decisions)
//! ```

pub mod device;
pub mod trust;

pub use device::{identity_path, DeviceId, DeviceIdentity, Fingerprint};
pub use trust::{KnownDevice, TrustState, TrustStore};