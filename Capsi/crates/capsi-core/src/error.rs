//! Capsi - error type shared by the native layer.

use std::fmt;

/// Every fallible operation in Capsi funnels through this type so the frontend
/// receives a human-readable string instead of a panic.
#[derive(Debug)]
pub enum CapsiError {
    /// Filesystem / persistence problem.
    Io(String),
    /// The payload did not match the Capsi wire protocol.
    Protocol(String),
    /// A cryptographic check failed (signature, tag, nonce reuse).
    Crypto(String),
    /// The peer is not (yet) trusted for this operation.
    Untrusted(String),
    /// A device / conversation / transfer could not be found.
    NotFound(String),
    /// The caller supplied something invalid (empty name, huge file, ...).
    Invalid(String),
    /// Local network / socket problem.
    Network(String),
    /// Feature is not available on this platform or build.
    Unsupported(String),
}

impl fmt::Display for CapsiError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(m) => write!(f, "capsi io error: {m}"),
            Self::Protocol(m) => write!(f, "capsi protocol error: {m}"),
            Self::Crypto(m) => write!(f, "capsi crypto error: {m}"),
            Self::Untrusted(m) => write!(f, "capsi untrusted peer: {m}"),
            Self::NotFound(m) => write!(f, "capsi not found: {m}"),
            Self::Invalid(m) => write!(f, "capsi invalid input: {m}"),
            Self::Network(m) => write!(f, "capsi network error: {m}"),
            Self::Unsupported(m) => write!(f, "capsi unsupported: {m}"),
        }
    }
}

impl std::error::Error for CapsiError {}

impl From<std::io::Error> for CapsiError {
    fn from(e: std::io::Error) -> Self {
        Self::Io(e.to_string())
    }
}

impl From<serde_json::Error> for CapsiError {
    fn from(e: serde_json::Error) -> Self {
        Self::Protocol(format!("json: {e}"))
    }
}

impl From<CapsiError> for String {
    fn from(e: CapsiError) -> Self {
        e.to_string()
    }
}

/// Convenience alias used throughout the native layer.
pub type Result<T> = std::result::Result<T, CapsiError>;

/// Convert a `Result<T, CapsiError>` into the `Result<T, String>` shape that
/// Tauri commands hand back to JavaScript.
pub trait IntoTauri<T> {
    fn tauri(self) -> std::result::Result<T, String>;
}

impl<T> IntoTauri<T> for Result<T> {
    fn tauri(self) -> std::result::Result<T, String> {
        self.map_err(|e| e.to_string())
    }
}

/// Build an [`CapsiError::Invalid`] from a format string.
#[macro_export]
macro_rules! bail_invalid {
    ($($arg:tt)*) => {
        return Err($crate::error::CapsiError::Invalid(format!($($arg)*)))
    };
}

/// Build an [`CapsiError::Protocol`] from a format string.
#[macro_export]
macro_rules! bail_protocol {
    ($($arg:tt)*) => {
        return Err($crate::error::CapsiError::Protocol(format!($($arg)*)))
    };
}

/// Build an [`CapsiError::Crypto`] from a format string.
#[macro_export]
macro_rules! bail_crypto {
    ($($arg:tt)*) => {
        return Err($crate::error::CapsiError::Crypto(format!($($arg)*)))
    };
}