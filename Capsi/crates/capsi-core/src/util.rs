//! Shared, dependency-light helpers used across the Capsi core.

use std::net::IpAddr;

use crate::error::Result;
use crate::identity::device::{now_millis, random_bytes};

/// Milliseconds / seconds since the Unix epoch are used everywhere instead of a
/// calendar library: Capsi only ever shows relative time ("2 min ago").
pub use crate::identity::device::{now_millis as now_ms, now_secs as now};

/// A short random id such as `m-1a2b3c4d5e6f`.
pub fn new_id(prefix: &str) -> String {
    let mut bytes = [0u8; 8];
    if random_bytes(&mut bytes).is_err() {
        return format!("{prefix}-{}", now_millis());
    }
    format!("{prefix}-{}", hex::encode(bytes))
}

/// Hex-encoded SHA-256-equivalent digest (BLAKE2b) of a byte slice.
///
/// Used both for file integrity and for the short per-message check codes the
/// UI shows, so a tampered payload can be spotted without a full re-hash of the
/// conversation.
pub fn digest_hex(bytes: &[u8]) -> String {
    use blake2::digest::consts::U32;
    use blake2::{Blake2b, Digest};
    let mut hasher = Blake2b::<U32>::new();
    hasher.update(bytes);
    hex::encode(hasher.finalize())
}

/// Hash a file incrementally without loading the entire file into memory.
pub fn digest_file(path: &std::path::Path) -> Result<String> {
    use std::io::Read;
    use blake2::digest::consts::U32;
    use blake2::{Blake2b, Digest};
    let mut input = std::fs::File::open(path)?;
    let mut hasher = Blake2b::<U32>::new();
    let mut buffer = [0u8; 128 * 1024];
    loop {
        let count = input.read(&mut buffer)?;
        if count == 0 { break; }
        hasher.update(&buffer[..count]);
    }
    Ok(hex::encode(hasher.finalize()))
}

/// True when `ip` is an address a Capsi beacon may legitimately come from.
///
/// Capsi is a local-network app, so the threat to defend against is a beacon that
/// arrived from *outside* - a router forwarding a datagram from the internet, or
/// a spoofed packet claiming to be a public host. Loopback, private and
/// link-local addresses are all accepted because they are all real Capsi
/// situations: two instances on one machine, a home or office LAN, and two
/// laptops joined by a cable. Everything else is refused.
pub fn is_lan_address(ip: &IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            v4.is_loopback() || v4.is_private() || v4.is_link_local()
        }
        IpAddr::V6(v6) => {
            // Unique local addresses (fc00::/7) plus loopback / link-local.
            let first = v6.segments()[0];
            v6.is_loopback() || (first & 0xfe00) == 0xfc00
        }
    }
}

/// Normalise a file name so it is safe to write on this machine.
///
/// Peer-supplied names are untrusted input: strip any directory component and
/// reject the Windows reserved names that would create a device handle.
pub fn safe_file_name(name: &str) -> String {
    let base = name
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or(name)
        .trim()
        .trim_matches('.')
        .to_string();
    let cleaned: String = base
        .chars()
        .filter(|c| !c.is_control() && !r#"<>:"/\|?*"#.contains(*c))
        .collect();
    let cleaned = cleaned.trim();
    if cleaned.is_empty() {
        return "capsi-file".to_string();
    }
    const RESERVED: [&str; 22] = [
        "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8",
        "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    ];
    let stem = cleaned.split('.').next().unwrap_or(cleaned).to_ascii_uppercase();
    if RESERVED.contains(&stem.as_str()) {
        return format!("_{cleaned}");
    }
    let truncated: String = cleaned.chars().take(120).collect();
    truncated
}

/// Human-readable size for the UI ("4.2 MB").
pub fn human_size(bytes: u64) -> String {
    const UNITS: [&str; 5] = ["B", "KB", "MB", "GB", "TB"];
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1024.0 && unit < UNITS.len() - 1 {
        value /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{bytes} B")
    } else {
        format!("{value:.1} {}", UNITS[unit])
    }
}

/// Best-effort sanity check that a string is a usable device name.
pub fn validate_device_name(name: &str) -> Result<String> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        return Err(crate::error::CapsiError::Invalid(
            "device name cannot be empty".into(),
        ));
    }
    if trimmed.chars().count() > 32 {
        return Err(crate::error::CapsiError::Invalid(
            "device name is limited to 32 characters".into(),
        ));
    }
    Ok(trimmed.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::Ipv4Addr;

    #[test]
    fn ids_are_unique_and_prefixed() {
        let a = new_id("m");
        let b = new_id("m");
        assert!(a.starts_with("m-"));
        assert_ne!(a, b);
    }

    #[test]
    fn digests_are_stable_and_sensitive() {
        assert_eq!(digest_hex(b"capsi"), digest_hex(b"capsi"));
        assert_ne!(digest_hex(b"capsi"), digest_hex(b"capsi!"));
        assert_eq!(digest_hex(b"capsi").len(), 64);
    }

    #[test]
    fn lan_detection_accepts_local_networks_and_refuses_the_internet() {
        // Real Capsi situations.
        assert!(is_lan_address(&IpAddr::V4(Ipv4Addr::new(192, 168, 6, 7))));
        assert!(is_lan_address(&IpAddr::V4(Ipv4Addr::new(10, 0, 0, 5))));
        assert!(is_lan_address(&IpAddr::V4(Ipv4Addr::new(172, 16, 4, 4))));
        assert!(is_lan_address(&IpAddr::V4(Ipv4Addr::LOCALHOST)));
        // A cable between two laptops.
        assert!(is_lan_address(&IpAddr::V4(Ipv4Addr::new(169, 254, 3, 4))));

        // Anything routable from the internet must not be trusted.
        assert!(!is_lan_address(&IpAddr::V4(Ipv4Addr::new(203, 0, 113, 5))));
        assert!(!is_lan_address(&IpAddr::V4(Ipv4Addr::new(8, 8, 8, 8))));
        assert!(!is_lan_address(&IpAddr::V4(Ipv4Addr::new(0, 0, 0, 0))));
        assert!(!is_lan_address(&IpAddr::V4(Ipv4Addr::new(239, 0, 0, 1))));
    }

    #[test]
    fn peer_file_names_cannot_escape_the_download_folder() {
        assert_eq!(safe_file_name("../../etc/passwd"), "passwd");
        assert_eq!(safe_file_name(r"C:\Windows\System32\cfg.ini"), "cfg.ini");
        assert_eq!(safe_file_name("CON.txt"), "_CON.txt");
        assert_eq!(safe_file_name("   "), "capsi-file");
        assert_eq!(safe_file_name("holiday:2026?.jpg"), "holiday2026.jpg");
    }

    #[test]
    fn sizes_are_human_readable() {
        assert_eq!(human_size(512), "512 B");
        assert_eq!(human_size(2048), "2.0 KB");
        assert_eq!(human_size(5 * 1024 * 1024), "5.0 MB");
    }

    #[test]
    fn device_names_are_validated() {
        assert_eq!(validate_device_name("  Office PC ").unwrap(), "Office PC");
        assert!(validate_device_name("").is_err());
        assert!(validate_device_name(&"x".repeat(33)).is_err());
    }
}