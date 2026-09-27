use std::ffi::{c_char, CStr, CString};
use std::time::Duration;
use tokio::net::TcpListener;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use capsi_core::discovery::Discovery;
use capsi_core::identity::{DeviceIdentity, DeviceId};
use capsi_core::identity::trust::TrustStore;
use capsi_core::protocol::{Envelope, Message, TextMessage};
use capsi_core::storage::conversation::{DeliveryState, MessageKind, MessageStore, StoredMessage};

struct DiscoverySession {
    stop: Arc<AtomicBool>,
    latest: Arc<Mutex<String>>,
}

fn c_string(value: *const c_char) -> Option<String> {
    if value.is_null() { return None; }
    unsafe { CStr::from_ptr(value).to_str().ok().map(str::to_owned) }
}

fn c_path(value: *const c_char) -> Option<PathBuf> {
    if value.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(value).to_str().ok().map(PathBuf::from) }
}

fn load_store(dir: &Path) -> Result<TrustStore, capsi_core::CapsiError> {
    TrustStore::load(dir)
}

fn trust_result<T: serde::Serialize>(value: T) -> *mut c_char {
    match serde_json::to_string(&value) {
        Ok(json) => into_c_string(json),
        Err(error) => error_json(&error.to_string()),
    }
}

static DISCOVERY_SESSIONS: OnceLock<Mutex<HashMap<u64, DiscoverySession>>> = OnceLock::new();
static NEXT_DISCOVERY_ID: AtomicU64 = AtomicU64::new(1);

struct MessageSession {
    stop: Arc<AtomicBool>,
    latest: Arc<Mutex<String>>,
}

static MESSAGE_SESSIONS: OnceLock<Mutex<HashMap<u64, MessageSession>>> = OnceLock::new();
static NEXT_MESSAGE_ID: AtomicU64 = AtomicU64::new(1);

fn message_sessions() -> &'static Mutex<HashMap<u64, MessageSession>> {
    MESSAGE_SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn message_event(latest: &Arc<Mutex<String>>, value: serde_json::Value) {
    if let Ok(mut out) = latest.lock() {
        *out = value.to_string();
    }
}

fn discovery_sessions() -> &'static Mutex<HashMap<u64, DiscoverySession>> {
    DISCOVERY_SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Start a persistent discovery session. The device identity is persisted
/// in the supplied application data directory so the device id remains stable.
#[no_mangle]
pub extern "C" fn capsi_discovery_start(
    name: *const c_char,
    tcp_port: u16,
    data_dir: *const c_char,
) -> u64 {
    let name = unsafe {
        if name.is_null() {
            return 0;
        }
        match CStr::from_ptr(name).to_str() {
            Ok(value) => value.to_owned(),
            Err(_) => return 0,
        }
    };
    let data_dir = match c_path(data_dir) {
        Some(path) => path,
        None => return 0,
    };

    let stop = Arc::new(AtomicBool::new(false));
    let latest = Arc::new(Mutex::new(String::from("[]")));
    let thread_stop = Arc::clone(&stop);
    let thread_latest = Arc::clone(&latest);

    let spawn_result = std::thread::Builder::new()
        .name("capsi-discovery".into())
        .spawn(move || {
            let runtime = match tokio::runtime::Builder::new_current_thread()
                .enable_io()
                .enable_time()
                .build()
            {
                Ok(runtime) => runtime,
                Err(_) => return,
            };

            runtime.block_on(async move {
                let identity = match DeviceIdentity::load_or_create(&data_dir) {
                    Ok(identity) => Arc::new(identity),
                    Err(_) => return,
                };
                let discovery = match Discovery::bind(Arc::clone(&identity), name, tcp_port).await {
                    Ok(discovery) => discovery,
                    Err(_) => return,
                };

                let _ = discovery.announce().await;

                while !thread_stop.load(Ordering::Acquire) {
                    let _ = tokio::time::timeout(
                        Duration::from_millis(500),
                        discovery.receive_once(),
                    )
                    .await;

                    let _ = discovery.prune().await;

                    let peers = discovery.peers().await;
                    if let Ok(mut store) = TrustStore::load(&data_dir) {
                        for peer in &peers {
                            let _ = store.observe(&peer.device_id, &peer.name, &peer.tcp_address());
                        }
                        let _ = store.save_if_dirty(&data_dir);
                    }
                    if let Ok(json) = serde_json::to_string(&peers) {
                        if let Ok(mut current) = thread_latest.lock() {
                            *current = json;
                        }
                    }
                }
            });
        });

    if spawn_result.is_err() {
        return 0;
    }

    let id = NEXT_DISCOVERY_ID.fetch_add(1, Ordering::Relaxed);
    if let Ok(mut sessions) = discovery_sessions().lock() {
        sessions.insert(id, DiscoverySession { stop, latest });
        id
    } else {
        0
    }
}


#[no_mangle]
pub extern "C" fn capsi_trust_list(data_dir: *const c_char) -> *mut c_char {
    let dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    match load_store(&dir) {
        Ok(store) => trust_result(store.all()),
        Err(error) => error_json(&error.to_string()),
    }
}

#[no_mangle]
pub extern "C" fn capsi_trust_accept(
    data_dir: *const c_char,
    device_id: *const c_char,
    alias: *const c_char,
) -> *mut c_char {
    let dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    let id = match c_string(device_id).and_then(|s| DeviceId::from_hex(&s).ok()) {
        Some(id) => id,
        None => return error_json("device id is invalid"),
    };
    let alias = c_string(alias);
    match load_store(&dir).and_then(|mut store| {
        let device = store.accept(&id, alias)?;
        store.save_if_dirty(&dir)?;
        Ok(device)
    }) {
        Ok(device) => trust_result(device),
        Err(error) => error_json(&error.to_string()),
    }
}

#[no_mangle]
pub extern "C" fn capsi_trust_ignore(
    data_dir: *const c_char,
    device_id: *const c_char,
) -> *mut c_char {
    let dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    let id = match c_string(device_id).and_then(|s| DeviceId::from_hex(&s).ok()) {
        Some(id) => id,
        None => return error_json("device id is invalid"),
    };
    match load_store(&dir).and_then(|mut store| {
        let device = store.ignore(&id)?;
        store.save_if_dirty(&dir)?;
        Ok(device)
    }) {
        Ok(device) => trust_result(device),
        Err(error) => error_json(&error.to_string()),
    }
}
/// Return the latest peer snapshot for a discovery session.
#[no_mangle]
pub extern "C" fn capsi_discovery_poll(handle: u64) -> *mut c_char {
    let json = discovery_sessions()
        .lock()
        .ok()
        .and_then(|sessions| sessions.get(&handle).map(|session| {
            session.latest.lock().ok()
                .map(|value| value.clone())
                .unwrap_or_else(|| "[]".into())
        }))
        .unwrap_or_else(|| "[]".into());

    into_c_string(json)
}

/// Stop a persistent discovery session.
#[no_mangle]
pub extern "C" fn capsi_discovery_stop(handle: u64) {
    if let Ok(mut sessions) = discovery_sessions().lock() {
        if let Some(session) = sessions.remove(&handle) {
            session.stop.store(true, Ordering::Release);
        }
    }
}

/// Stable native boundary for the Flutter client.
///
/// Keep this API C-compatible. Higher-level Capsi operations should be backed
/// by the existing capsi-core implementation rather than reimplemented in Dart.
#[no_mangle]
pub extern "C" fn capsi_runtime_version() -> *const c_char {
    static VERSION: &[u8] = b"1.0.2\0";
    VERSION.as_ptr().cast()
}

/// Returns a non-zero value when the shared Rust core is linked successfully.
#[no_mangle]
pub extern "C" fn capsi_core_linked() -> i32 {
    1
}

/// Returns the Capsi protocol version used by the Rust core.
#[no_mangle]
pub extern "C" fn capsi_protocol_version() -> *const c_char {
    static VERSION: &[u8] = b"capsi/1\0";
    VERSION.as_ptr().cast()
}

/// Probe the local network using the real Capsi UDP discovery implementation.
///
/// The returned value is a UTF-8 JSON array. The caller owns the returned
/// string and must release it with `capsi_free_string`.
#[no_mangle]
pub extern "C" fn capsi_discovery_probe(
    name: *const c_char,
    tcp_port: u16,
    wait_ms: u32,
) -> *mut c_char {
    let name = unsafe {
        if name.is_null() {
            return error_json("device name is null");
        }
        match CStr::from_ptr(name).to_str() {
            Ok(value) => value.to_owned(),
            Err(_) => return error_json("device name is not valid UTF-8"),
        }
    };

    let wait = Duration::from_millis(wait_ms.clamp(50, 2_000) as u64);
    let result = (|| -> capsi_core::Result<String> {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_io()
            .enable_time()
            .build()
            .map_err(|e| capsi_core::CapsiError::Unsupported(format!("runtime: {e}")))?;

        runtime.block_on(async move {
            let identity = std::sync::Arc::new(
                DeviceIdentity::generate()
                    .map_err(|e| capsi_core::CapsiError::Crypto(format!("identity: {e}")))?,
            );
            let discovery = Discovery::bind(identity, name, tcp_port).await?;
            let _ = discovery.announce().await?;

            let deadline = tokio::time::Instant::now() + wait;
            loop {
                if tokio::time::Instant::now() >= deadline {
                    break;
                }
                let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
                match tokio::time::timeout(remaining, discovery.receive_once()).await {
                    Ok(Ok(_)) => {}
                    Ok(Err(_)) | Err(_) => break,
                }
            }

            serde_json::to_string(&discovery.peers().await)
                .map_err(capsi_core::CapsiError::from)
        })
    })();

    match result {
        Ok(json) => into_c_string(json),
        Err(error) => error_json(&error.to_string()),
    }
}

/// Release a string returned by this FFI layer.
#[no_mangle]
pub unsafe extern "C" fn capsi_free_string(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}

fn into_c_string(value: String) -> *mut c_char {
    CString::new(value)
        .unwrap_or_else(|_| CString::new("null").unwrap())
        .into_raw()
}

fn error_json(message: &str) -> *mut c_char {
    let escaped = serde_json::to_string(message).unwrap_or_else(|_| "\"native error\"".into());
    into_c_string(format!("{{\"error\":{escaped}}}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn protocol_version_is_exposed() {
        let value = unsafe { CStr::from_ptr(capsi_protocol_version()) };
        assert_eq!(value.to_str().unwrap(), "capsi/1");
    }

    #[test]
    fn core_reports_as_linked() {
        assert_eq!(capsi_core_linked(), 1);
    }
}
