use std::ffi::{c_char, CStr, CString};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use base64::Engine as _;
use tokio::net::TcpListener;
use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use capsi_core::discovery::Discovery;
use capsi_core::identity::{DeviceIdentity, DeviceId};
use capsi_core::identity::trust::TrustStore;
use capsi_core::protocol::{Envelope, FileOffer, FileReceipt, Message, TextMessage};
use capsi_core::storage::conversation::TransferState;
use capsi_core::storage::conversation::{DeliveryState, MessageStore, StoredMessage};

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}

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

/// Errors that are serialized back to the Flutter UI.
///
/// `CapsiError`'s `Display` prefixes each message with a category so logs stay
/// greppable; an end user only ever sees the message itself. `String` errors
/// come from closures that already phrase the text for people.
trait UserFacingError {
    fn user(&self) -> String;
}

impl UserFacingError for capsi_core::CapsiError {
    fn user(&self) -> String {
        self.user_message()
    }
}

impl UserFacingError for String {
    fn user(&self) -> String {
        self.clone()
    }
}

impl UserFacingError for serde_json::Error {
    fn user(&self) -> String {
        self.to_string()
    }
}

fn trust_result<T: serde::Serialize>(value: T) -> *mut c_char {
    match serde_json::to_string(&value) {
        Ok(json) => into_c_string(json),
        Err(error) => error_json(&error.user()),
    }
}

static DISCOVERY_SESSIONS: OnceLock<Mutex<HashMap<u64, DiscoverySession>>> = OnceLock::new();
static NEXT_DISCOVERY_ID: AtomicU64 = AtomicU64::new(1);

struct MessageSession {
    stop: Arc<AtomicBool>,
    events: Arc<Mutex<VecDeque<String>>>,
}

static MESSAGE_SESSIONS: OnceLock<Mutex<HashMap<u64, MessageSession>>> = OnceLock::new();
static NEXT_MESSAGE_ID: AtomicU64 = AtomicU64::new(1);

fn message_sessions() -> &'static Mutex<HashMap<u64, MessageSession>> {
    MESSAGE_SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn message_event(events: &Arc<Mutex<VecDeque<String>>>, value: serde_json::Value) {
    if let Ok(mut queue) = events.lock() {
        // Keep a bounded queue so a busy peer cannot grow native memory without
        // limit while Flutter is paused or rendering another screen.
        if queue.len() >= 128 {
            queue.pop_front();
        }
        queue.push_back(value.to_string());
    }
}

fn broadcast_message_event(value: serde_json::Value) {
    let sessions = match message_sessions().lock() {
        Ok(sessions) => sessions,
        Err(_) => return,
    };
    for session in sessions.values() {
        message_event(&session.events, value.clone());
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
    let name = match c_string(name) {
        Some(value) => value,
        None => return 0,
    };
    let data_dir = match c_path(data_dir) {
        Some(path) => path,
        None => return 0,
    };

    // The runtime, the identity and the discovery socket are all created on the
    // calling thread. A device that cannot load its identity or bind the
    // discovery port has to fail synchronously: a handle returned by a thread
    // that has already given up let the shell show discovery as running when
    // nothing was listening on the network at all.
    let runtime = match tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .enable_time()
        .build()
    {
        Ok(runtime) => runtime,
        Err(_) => return 0,
    };

    let discovery = match runtime.block_on(async {
        let identity = Arc::new(DeviceIdentity::load_or_create(&data_dir)?);
        Discovery::bind(Arc::clone(&identity), name.clone(), tcp_port).await
    }) {
        Ok(discovery) => discovery,
        Err(_) => return 0,
    };

    let stop = Arc::new(AtomicBool::new(false));
    let latest = Arc::new(Mutex::new(String::from("[]")));
    let thread_stop = Arc::clone(&stop);
    let thread_latest = Arc::clone(&latest);

    let spawn_result = std::thread::Builder::new()
        .name("capsi-discovery".into())
        .spawn(move || {
            runtime.block_on(async move {
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
        Err(error) => error_json(&error.user()),
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
    let result = (|| -> capsi_core::Result<serde_json::Value> {
        let mut trust = load_store(&dir)?;
        let device = trust.accept(&id, alias)?;
        trust.save_if_dirty(&dir)?;

        // Accepting a device is also the point at which the owner can invite
        // that trusted device into the local workplace. The invite is sent
        // directly over the already-established Capsi encrypted transport.
        let identity = DeviceIdentity::load_or_create(&dir)?;
        let Some(mut workspace) = capsi_core::workplace::WorkspaceStore::new(&dir).load().map_err(capsi_core::CapsiError::Io)? else {
            return Ok(serde_json::to_value(device)?);
        };

        if workspace.owner_device_id == identity.id().as_str() {
            workspace.add_member(id.as_str(), device.display_name(), capsi_core::workplace::Role::Member);
            workspace.touch();
            capsi_core::workplace::WorkspaceStore::new(&dir)
                .save(&workspace)
                .map_err(capsi_core::CapsiError::Io)?;

            // The trust relationship is local and should not be rolled back
            // just because the invitee is temporarily offline. Initial workplace
            // synchronization is therefore best-effort; the next workplace
            // mutation can synchronize the member again.
            if let Some(address) = device.last_address.clone() {
                let host = address.rsplit_once(':').map(|(host, _)| host).unwrap_or(&address);
                let socket = format!("{host}:{}", capsi_core::TCP_SERVICE_PORT);
                let sync = Envelope::new(Message::WorkplaceSync(
                    capsi_core::protocol::WorkplaceSyncMessage {
                        actor_device_id: identity.id().as_str().to_string(),
                        state: workspace.network_state(),
                    },
                ));
                if let Ok(runtime) = tokio::runtime::Builder::new_current_thread()
                    .enable_io()
                    .enable_time()
                    .build()
                {
                    let _ = runtime.block_on(async {
                        capsi_core::transport::connect_and_send(&socket, &identity, &id, &sync).await
                    });
                }
            }
        }

        Ok(serde_json::to_value(device)?)
    })();

    match result {
        Ok(value) => trust_result(value),
        Err(error) => error_json(&error.user()),
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
        Err(error) => error_json(&error.user()),
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


#[no_mangle]
pub extern "C" fn capsi_message_start(data_dir: *const c_char, tcp_port: u16) -> u64 {
    let data_dir = match c_path(data_dir) { Some(path) => path, None => return 0 };
    // Built and bound on the calling thread: a service port that is already
    // taken has to be a synchronous failure, otherwise the shell starts a
    // listener it believes is running while nothing is accepting connections.
    let runtime = match tokio::runtime::Builder::new_current_thread().enable_io().enable_time().build() {
        Ok(runtime) => runtime,
        Err(_) => return 0,
    };
    let listener = match runtime.block_on(TcpListener::bind(("0.0.0.0", tcp_port))) {
        Ok(listener) => listener,
        Err(_) => return 0,
    };

    let stop = Arc::new(AtomicBool::new(false));
    let events = Arc::new(Mutex::new(VecDeque::new()));
    let thread_stop = Arc::clone(&stop);
    let thread_events = Arc::clone(&events);

    if std::thread::Builder::new().name("capsi-messages".into()).spawn(move || {
        runtime.block_on(async move {
            let identity = match DeviceIdentity::load_or_create(&data_dir) {
                Ok(identity) => Arc::new(identity),
                Err(error) => {
                    message_event(&thread_events, serde_json::json!({"error": error.to_string()}));
                    return;
                }
            };

            // Queued workplace deliveries (offline group messages and
            // broadcasts) are drained on this slow tick; the accept timeout
            // below is what bounds how late the tick can fire.
            let mut last_delivery_flush = std::time::Instant::now();
            while !thread_stop.load(Ordering::Acquire) {
                if last_delivery_flush.elapsed() >= Duration::from_secs(5) {
                    last_delivery_flush = std::time::Instant::now();
                    flush_workplace_deliveries(&data_dir, &identity).await;
                }
                let accepted = tokio::time::timeout(Duration::from_millis(500), listener.accept()).await;
                let (stream, addr) = match accepted {
                    Ok(Ok(value)) => value,
                    Ok(Err(error)) => {
                        message_event(&thread_events, serde_json::json!({"error": error.to_string()}));
                        continue;
                    }
                    Err(_) => continue,
                };

                let (peer_id, envelope) = match capsi_core::transport::accept_and_read(stream, &identity).await {
                    Ok(value) => value,
                    Err(error) => {
                        message_event(&thread_events, serde_json::json!({"error": error.to_string()}));
                        continue;
                    }
                };

                let trust = match TrustStore::load(&data_dir) {
                    Ok(store) => store,
                    Err(error) => {
                        message_event(&thread_events, serde_json::json!({"error": error.to_string()}));
                        continue;
                    }
                };
                let known = match trust.get(&peer_id) {
                    Some(device) if device.is_trusted() => device.clone(),
                    _ => {
                        message_event(&thread_events, serde_json::json!({"error":"untrusted device","device_id":peer_id.as_str()}));
                        continue;
                    }
                };

                match envelope.message.clone() {
                    Message::FileOffer(offer) => {
                        let mut messages = match MessageStore::load(&data_dir) {
                            Ok(store) => store,
                            Err(error) => {
                                message_event(&thread_events, serde_json::json!({"error": error.to_string()}));
                                continue;
                            }
                        };
                        let incoming_dir = data_dir.join("files").join("incoming");
                        if let Err(error) = std::fs::create_dir_all(&incoming_dir) {
                            message_event(&thread_events, serde_json::json!({"error": error.to_string()}));
                            continue;
                        }
                        let temp_path = incoming_dir.join(format!("{}.part", offer.transfer_id));
                        if let Err(error) = File::create(&temp_path) {
                            message_event(&thread_events, serde_json::json!({"error": error.to_string()}));
                            continue;
                        }
                        let mut stored = StoredMessage::file(&offer, false);
                        stored.id = envelope.id.clone();
                        stored.sent_at = envelope.sent_at;
                        if let Some(file) = stored.file.as_mut() {
                            file.local_path = Some(temp_path.to_string_lossy().to_string());
                            file.state = TransferState::Offered;
                        }
                        if let Err(error) = messages.append(&peer_id, &known.name, stored) {
                            message_event(&thread_events, serde_json::json!({"error": error.to_string()}));
                            continue;
                        }

                        message_event(&thread_events, serde_json::json!({
                            "type":"file_offer",
                            "device_id":peer_id.as_str(),
                            "device_name":known.name,
                            "transfer_id":offer.transfer_id,
                            "file_name":offer.file_name,
                            "size":offer.size,
                            "chunks":offer.chunks
                        }));
                    }
                    Message::FileChunk { transfer_id, index, digest, data } => {
                        let raw = match base64::engine::general_purpose::STANDARD.decode(data) {
                            Ok(bytes) => bytes,
                            Err(error) => {
                                message_event(&thread_events, serde_json::json!({"error": format!("invalid file chunk: {error}")}));
                                continue;
                            }
                        };
                        if capsi_core::util::digest_hex(&raw) != digest {
                            message_event(&thread_events, serde_json::json!({"error":"file chunk digest mismatch","transfer_id":transfer_id}));
                            continue;
                        }

                        let mut messages = match MessageStore::load(&data_dir) {
                            Ok(store) => store,
                            Err(error) => {
                                message_event(&thread_events, serde_json::json!({"error": error.to_string()}));
                                continue;
                            }
                        };
                        let conversation = match messages.get(&peer_id) {
                            Some(value) => value,
                            None => {
                                message_event(&thread_events, serde_json::json!({"error":"unknown file transfer","transfer_id":transfer_id}));
                                continue;
                            }
                        };
                        let file = match conversation.find_transfer(&transfer_id) {
                            Some(value) => value.clone(),
                            None => {
                                message_event(&thread_events, serde_json::json!({"error":"unknown file transfer","transfer_id":transfer_id}));
                                continue;
                            }
                        };
                        if file.state != TransferState::Transferring {
                            message_event(&thread_events, serde_json::json!({
                                "error":"file transfer is not accepted",
                                "transfer_id":transfer_id,
                                "state":format!("{:?}", file.state)
                            }));
                            continue;
                        }
                        let temp_path = match file.local_path {
                            Some(path) => PathBuf::from(path),
                            None => {
                                message_event(&thread_events, serde_json::json!({"error":"file transfer has no local path","transfer_id":transfer_id}));
                                continue;
                            }
                        };
                        let current_len = std::fs::metadata(&temp_path).map(|m| m.len()).unwrap_or(0);
                        let expected_index = current_len / capsi_core::TRANSFER_CHUNK_SIZE as u64;
                        if index != expected_index {
                            message_event(&thread_events, serde_json::json!({"error":"file chunk out of order","transfer_id":transfer_id,"expected":expected_index,"received":index}));
                            continue;
                        }
                        let mut output = match OpenOptions::new().append(true).open(&temp_path) {
                            Ok(file) => file,
                            Err(error) => {
                                message_event(&thread_events, serde_json::json!({"error": error.to_string()}));
                                continue;
                            }
                        };
                        if let Err(error) = output.write_all(&raw) {
                            message_event(&thread_events, serde_json::json!({"error": error.to_string()}));
                            continue;
                        }

                        let new_len = current_len + raw.len() as u64;
                        message_event(&thread_events, serde_json::json!({
                            "type":"file_progress",
                            "device_id":peer_id.as_str(),
                            "transfer_id":transfer_id,
                            "received":new_len,
                            "size":file.size
                        }));

                        if new_len >= file.size {
                            if new_len != file.size || capsi_core::util::digest_file(&temp_path).ok().as_deref() != Some(file.digest.as_str()) {
                                let _ = messages.update_transfer(&peer_id, &transfer_id, TransferState::Failed, None);
                                message_event(&thread_events, serde_json::json!({"error":"file digest or size mismatch","transfer_id":transfer_id}));
                                continue;
                            }
                            let download_dir = data_dir.join("files").join("downloads");
                            let _ = std::fs::create_dir_all(&download_dir);
                            let final_path = download_dir.join(&file.file_name);
                            if let Err(error) = std::fs::rename(&temp_path, &final_path) {
                                message_event(&thread_events, serde_json::json!({"error": error.to_string()}));
                                continue;
                            }
                            let _ = messages.update_transfer(&peer_id, &transfer_id, TransferState::Complete, Some(final_path.to_string_lossy().to_string()));
                            let receipt = Envelope::new(Message::FileReceipt {
                                transfer_id: transfer_id.clone(),
                                state: FileReceipt::Completed,
                            });
                            let socket = format!("{}:{}", addr.ip(), capsi_core::TCP_SERVICE_PORT);
                            let _ = capsi_core::transport::connect_and_send(&socket, &identity, &peer_id, &receipt).await;
                            message_event(&thread_events, serde_json::json!({"type":"file_complete","device_id":peer_id.as_str(),"transfer_id":transfer_id,"file_name":file.file_name,"size":file.size}));
                        }
                    }
                    Message::FileReceipt { transfer_id, state } => {
                        let state_name = match state {
                            FileReceipt::Accepted { .. } => TransferState::Transferring,
                            FileReceipt::Declined => TransferState::Declined,
                            FileReceipt::Completed => TransferState::Complete,
                            FileReceipt::Failed => TransferState::Failed,
                            FileReceipt::Cancelled => TransferState::Cancelled,
                        };
                        if let Ok(mut messages) = MessageStore::load(&data_dir) {
                            let local_path = messages.get(&peer_id)
                                .and_then(|conversation| conversation.find_transfer(&transfer_id))
                                .and_then(|file| file.local_path.clone());
                            let _ = messages.update_transfer(&peer_id, &transfer_id, state_name, None);
                            if matches!(state, FileReceipt::Cancelled | FileReceipt::Declined) {
                                if let Some(path) = local_path {
                                    let _ = std::fs::remove_file(path);
                                }
                            }
                        }
                        message_event(&thread_events, serde_json::json!({
                            "type":"file_receipt",
                            "device_id":peer_id.as_str(),
                            "transfer_id":transfer_id,
                            "state":format!("{:?}", state)
                        }));
                    }
                    Message::WorkplaceSync(sync) => {
                        if sync.actor_device_id != peer_id.as_str() {
                            message_event(&thread_events, serde_json::json!({
                                "error":"workplace sync actor does not match authenticated peer",
                                "device_id":peer_id.as_str()
                            }));
                            continue;
                        }

                        // Only the owner may delete a workplace, and only when
                        // the tombstone names this device's copy of it. The
                        // actor check above already pinned the sender, so this
                        // reduces to comparing the owner recorded in the state.
                        if sync.state.deleted {
                            let owned_by_sender = sync.state.owner_device_id == peer_id.as_str();
                            if !owned_by_sender {
                                message_event(&thread_events, serde_json::json!({
                                    "error":"workplace deletion refused",
                                    "device_id":peer_id.as_str()
                                }));
                                continue;
                            }
                            let store = capsi_core::workplace::WorkspaceStore::new(&data_dir);
                            if let Ok(Some(local)) = store.load() {
                                if local.id == sync.state.id && local.owner_device_id == peer_id.as_str() {
                                    if store.delete().is_ok() {
                                        message_event(&thread_events, serde_json::json!({
                                            "type":"workplace_deleted",
                                            "device_id":peer_id.as_str(),
                                            "workspace_id":sync.state.id
                                        }));
                                    }
                                }
                            }
                            continue;
                        }

                        let store = capsi_core::workplace::WorkspaceStore::new(&data_dir);
                        let existing = match store.load() {
                            Ok(value) => value,
                            Err(error) => {
                                message_event(&thread_events, serde_json::json!({"error":error}));
                                continue;
                            }
                        };
                        let local_id = identity.id().as_str().to_string();
                        let result = match existing {
                            Some(mut workspace) => workspace.apply_network_state(sync.state, peer_id.as_str()).map(|_| workspace),
                            None => capsi_core::workplace::Workspace::from_network_state(sync.state, peer_id.as_str(), &local_id),
                        };
                        match result {
                            Ok(workspace) => {
                                if let Err(error) = store.save(&workspace) {
                                    message_event(&thread_events, serde_json::json!({"error":error}));
                                    continue;
                                }
                                message_event(&thread_events, serde_json::json!({
                                    "type":"workplace_sync",
                                    "device_id":peer_id.as_str(),
                                    "workspace_id":workspace.id,
                                    "name":workspace.name
                                }));
                            }
                            Err(error) => {
                                message_event(&thread_events, serde_json::json!({
                                    "error":format!("workplace sync rejected: {error}"),
                                    "device_id":peer_id.as_str()
                                }));
                            }
                        }
                    }
                    Message::WorkplaceText(workplace_message) => {
                        let store = capsi_core::workplace::WorkspaceStore::new(&data_dir);
                        let Some(mut workspace) = (match store.load() {
                            Ok(value) => value,
                            Err(error) => {
                                message_event(&thread_events, serde_json::json!({"error":error}));
                                continue;
                            }
                        }) else {
                            continue;
                        };

                        if workspace.has_received_message(&envelope.id) {
                            continue;
                        }

                        let authorized = workspace.groups.iter()
                            .find(|group| group.id == workplace_message.group_id)
                            .map(|group| group.member_ids.iter().any(|id| id == peer_id.as_str()))
                            .unwrap_or(false)
                            && workspace.members.iter().any(|member| member.device_id == peer_id.as_str());

                        if !authorized {
                            message_event(&thread_events, serde_json::json!({
                                "error":"workplace message sender is not a member of the group",
                                "device_id":peer_id.as_str(),
                                "group_id":workplace_message.group_id
                            }));
                            continue;
                        }

                        if let Some(message_id) = workspace.append_message(
                            &workplace_message.group_id,
                            peer_id.as_str(),
                            workplace_message.body.clone(),
                        ) {
                            if let Some(message) = workspace.messages.last_mut() {
                                message.id = message_id.clone();
                            }
                            workspace.mark_received_message(&envelope.id);
                            workspace.touch();
                            if let Err(error) = store.save(&workspace) {
                                message_event(&thread_events, serde_json::json!({"error":error}));
                                continue;
                            }

                            let receipt = Envelope::new(Message::DeliveryReceipt(
                                capsi_core::protocol::DeliveryReceipt { message_id: envelope.id.clone() }
                            ));
                            let socket = format!("{}:{}", addr.ip(), capsi_core::TCP_SERVICE_PORT);
                            let _ = capsi_core::transport::connect_and_send(&socket, &identity, &peer_id, &receipt).await;

                            message_event(&thread_events, serde_json::json!({
                                "type":"workplace_message",
                                "device_id":peer_id.as_str(),
                                "group_id":workplace_message.group_id,
                                "message_id":message_id,
                                "body":workplace_message.body
                            }));
                        }
                    }
                    Message::WorkplaceBroadcast(broadcast) => {
                        if peer_id.as_str() == identity.id().as_str() {
                            continue;
                        }
                        let store = capsi_core::workplace::WorkspaceStore::new(&data_dir);
                        let Some(mut workspace) = (match store.load() {
                            Ok(value) => value,
                            Err(error) => {
                                message_event(&thread_events, serde_json::json!({"error":error}));
                                continue;
                            }
                        }) else {
                            continue;
                        };
                        if !workspace.members.iter().any(|m| m.device_id == peer_id.as_str()) {
                            continue;
                        }
                                        let created_at = std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .map(|d| d.as_secs() as i64)
                            .unwrap_or_default();
                        if workspace.receive_broadcast(
                            broadcast.broadcast_id.clone(),
                            broadcast.title.clone(),
                            broadcast.body.clone(),
                            peer_id.as_str().to_string(),
                            broadcast.department_id.clone(),
                            created_at,
                        ) {
                            let _ = store.save(&workspace);
                            message_event(&thread_events, serde_json::json!({
                                "type":"workplace_broadcast",
                                "broadcast_id":broadcast.broadcast_id
                            }));
                        }
                    }
                    Message::Text(text) => {
                        let mut stored = match StoredMessage::text(&text.body, false) {
                            Ok(message) => message,
                            Err(error) => {
                                message_event(&thread_events, serde_json::json!({"error": error.to_string()}));
                                continue;
                            }
                        };
                        stored.id = envelope.id.clone();
                        stored.sent_at = envelope.sent_at;
                        stored.state = DeliveryState::Delivered;

                        let mut messages = match MessageStore::load(&data_dir) {
                            Ok(store) => store,
                            Err(error) => {
                                message_event(&thread_events, serde_json::json!({"error": error.to_string()}));
                                continue;
                            }
                        };
                        if let Err(error) = messages.append(&peer_id, &known.name, stored) {
                            message_event(&thread_events, serde_json::json!({"error": error.to_string()}));
                            continue;
                        }

                        let receipt = Envelope::new(Message::DeliveryReceipt(capsi_core::protocol::DeliveryReceipt {
                            message_id: envelope.id.clone(),
                        }));
                        let socket = format!("{}:{}", addr.ip(), capsi_core::TCP_SERVICE_PORT);
                        let _ = capsi_core::transport::connect_and_send(&socket, &identity, &peer_id, &receipt).await;

                        message_event(&thread_events, serde_json::json!({
                            "type":"message",
                            "device_id":peer_id.as_str(),
                            "message_id":envelope.id,
                            "body":text.body
                        }));
                    }
                    Message::DeliveryReceipt(receipt) => {
                        if let Ok(mut messages) = MessageStore::load(&data_dir) {
                            let _ = messages.mark_delivery_delivered(&peer_id, &receipt.message_id);
                        }
                        if let Ok(Some(mut workspace)) = capsi_core::workplace::WorkspaceStore::new(&data_dir).load() {
                            if workspace.mark_delivery_delivered(&receipt.message_id, peer_id.as_str()) {
                                workspace.touch();
                                let _ = capsi_core::workplace::WorkspaceStore::new(&data_dir).save(&workspace);
                            }
                        }
                        message_event(&thread_events, serde_json::json!({
                            "type":"delivery_receipt",
                            "device_id":peer_id.as_str(),
                            "message_id":receipt.message_id
                        }));
                    }
                    _ => {}
                }
            }
        });
    }).is_err() {
        return 0;
    }

    let id = NEXT_MESSAGE_ID.fetch_add(1, Ordering::Relaxed);
    if let Ok(mut sessions) = message_sessions().lock() {
        sessions.insert(id, MessageSession { stop, events });
        id
    } else {
        0
    }
}

#[no_mangle]
pub extern "C" fn capsi_message_poll(handle: u64) -> *mut c_char {
    let json = message_sessions().lock().ok()
        .and_then(|sessions| {
            sessions.get(&handle).and_then(|session| {
                session.events.lock().ok().and_then(|mut queue| queue.pop_front())
            })
        })
        .unwrap_or_else(|| "null".into());
    into_c_string(json)
}

#[no_mangle]
pub extern "C" fn capsi_message_stop(handle: u64) {
    if let Ok(mut sessions) = message_sessions().lock() {
        if let Some(session) = sessions.remove(&handle) {
            session.stop.store(true, Ordering::Release);
        }
    }
}

#[no_mangle]
pub extern "C" fn capsi_message_send(
    data_dir: *const c_char,
    device_id: *const c_char,
    body: *const c_char,
) -> *mut c_char {
    let data_dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    let device_id = match c_string(device_id).and_then(|value| DeviceId::from_hex(&value).ok()) {
        Some(id) => id,
        None => return error_json("device id is invalid"),
    };
    let body = match c_string(body) { Some(value) => value, None => return error_json("message body is invalid") };

    let result = (|| -> capsi_core::Result<String> {
        let trust = TrustStore::load(&data_dir)?;
        let peer = trust.get(&device_id)
            .filter(|device| device.is_trusted())
            .ok_or_else(|| capsi_core::CapsiError::NotFound("device is not trusted".into()))?
            .clone();
        let address = peer.last_address.clone()
            .ok_or_else(|| capsi_core::CapsiError::NotFound("trusted device has no known address".into()))?;
        let host = address.rsplit_once(':').map(|(host, _)| host).unwrap_or(&address);
        let socket = format!("{host}:{}", capsi_core::TCP_SERVICE_PORT);

        let identity = DeviceIdentity::load_or_create(&data_dir)?;
        let text = TextMessage::new(&body)?;
        let envelope = Envelope::new(Message::Text(text.clone()));

        let runtime = tokio::runtime::Builder::new_current_thread().enable_io().enable_time().build()
            .map_err(|e| capsi_core::CapsiError::Unsupported(format!("runtime: {e}")))?;
        runtime.block_on(async {
            capsi_core::transport::connect_and_send(&socket, &identity, &device_id, &envelope).await
        })?;

        let mut messages = MessageStore::load(&data_dir)?;
        let mut stored = StoredMessage::text(&text.body, true)?;
        stored.id = envelope.id.clone();
        stored.sent_at = envelope.sent_at;
        stored.state = DeliveryState::Sent;
        messages.append(&device_id, &peer.name, stored)?;
        Ok(envelope.id)
    })();

    match result {
        Ok(id) => trust_result(id),
        Err(error) => error_json(&error.user()),
    }
}

#[no_mangle]
pub extern "C" fn capsi_file_send(
    data_dir: *const c_char,
    device_id: *const c_char,
    file_path: *const c_char,
) -> *mut c_char {
    let data_dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    let device_id = match c_string(device_id).and_then(|value| DeviceId::from_hex(&value).ok()) {
        Some(id) => id,
        None => return error_json("device id is invalid"),
    };
    let file_path = match c_path(file_path) { Some(path) => path, None => return error_json("file path is invalid") };

    let result = (|| -> capsi_core::Result<String> {
        let trust = TrustStore::load(&data_dir)?;
        let peer = trust.get(&device_id)
            .filter(|device| device.is_trusted())
            .ok_or_else(|| capsi_core::CapsiError::NotFound("device is not trusted".into()))?
            .clone();
        let address = peer.last_address.clone()
            .ok_or_else(|| capsi_core::CapsiError::NotFound("trusted device has no known address".into()))?;
        let host = address.rsplit_once(':').map(|(host, _)| host).unwrap_or(&address);
        let socket = format!("{host}:{}", capsi_core::TCP_SERVICE_PORT);

        let metadata = std::fs::metadata(&file_path)?;
        if !metadata.is_file() {
            return Err(capsi_core::CapsiError::Invalid("selected path is not a file".into()));
        }
        let size = metadata.len();
        let digest = capsi_core::util::digest_file(&file_path)?;
        let chunk_size = capsi_core::TRANSFER_CHUNK_SIZE as u64;
        let chunks = size.div_ceil(chunk_size);
        let transfer_id = capsi_core::util::new_id("t");
        let file_name = capsi_core::util::safe_file_name(
            file_path.file_name().and_then(|n| n.to_str()).unwrap_or("capsi-file")
        );
        let offer = FileOffer { transfer_id: transfer_id.clone(), file_name: file_name.clone(), size, digest, chunks };
        let identity = DeviceIdentity::load_or_create(&data_dir)?;
        let offer_envelope = Envelope::new(Message::FileOffer(offer.clone()));

        // Persist before opening the network round trip: the peer can accept
        // immediately, and the listener must have a durable transfer record to update.
        let mut messages = MessageStore::load(&data_dir)?;
        let mut stored = StoredMessage::file(&offer, true);
        if let Some(file) = stored.file.as_mut() {
            file.local_path = Some(file_path.to_string_lossy().to_string());
        }
        messages.append(&device_id, &peer.name, stored)?;

        let runtime = tokio::runtime::Builder::new_current_thread().enable_io().enable_time().build()
            .map_err(|e| capsi_core::CapsiError::Unsupported(format!("runtime: {e}")))?;
        runtime.block_on(async {
            capsi_core::transport::connect_and_send(&socket, &identity, &device_id, &offer_envelope).await
        })?;

        // The receiver acknowledges the offer before chunks are sent. Each
        // envelope currently uses its own TCP connection, so waiting for the
        // persisted receipt here prevents chunks from racing the offer.
        let deadline = std::time::Instant::now() + Duration::from_secs(30);
        loop {
            let store = MessageStore::load(&data_dir)?;
            let state = store
                .get(&device_id)
                .and_then(|conversation| conversation.find_transfer(&transfer_id))
                .map(|file| file.state);
            match state {
                Some(TransferState::Transferring) | Some(TransferState::Complete) => break,
                Some(TransferState::Declined) => {
                    return Err(capsi_core::CapsiError::Network("file offer was declined".into()));
                }
                Some(TransferState::Failed) | Some(TransferState::Cancelled) => {
                    return Err(capsi_core::CapsiError::Network("file transfer was rejected".into()));
                }
                Some(TransferState::Offered) | None => {}
            }
            if std::time::Instant::now() >= deadline {
                return Err(capsi_core::CapsiError::Network("timed out waiting for file offer acceptance".into()));
            }
            std::thread::sleep(Duration::from_millis(100));
        }

        let mut input = File::open(&file_path)?;
        let mut buffer = vec![0u8; capsi_core::TRANSFER_CHUNK_SIZE];
        for index in 0..chunks {
            let state = MessageStore::load(&data_dir)?
                .get(&device_id)
                .and_then(|conversation| conversation.find_transfer(&transfer_id))
                .map(|file| file.state);
            if matches!(state, Some(TransferState::Cancelled | TransferState::Declined | TransferState::Failed)) {
                return Err(capsi_core::CapsiError::Network("file transfer was cancelled or rejected".into()));
            }

            let read = input.read(&mut buffer)?;
            if read == 0 { break; }
            let raw = &buffer[..read];
            let chunk = Message::FileChunk {
                transfer_id: transfer_id.clone(),
                index,
                digest: capsi_core::util::digest_hex(raw),
                data: base64::engine::general_purpose::STANDARD.encode(raw),
            };
            let envelope = Envelope::new(chunk);
            runtime.block_on(async {
                capsi_core::transport::connect_and_send(&socket, &identity, &device_id, &envelope).await
            })?;

            let sent = ((index + 1) * chunk_size).min(size);
            broadcast_message_event(serde_json::json!({
                "type": "file_progress",
                "device_id": device_id.as_str(),
                "transfer_id": transfer_id,
                "sent": sent,
                "size": size
            }));
        }
        Ok(transfer_id)
    })();

    match result {
        Ok(id) => trust_result(id),
        Err(error) => error_json(&error.user()),
    }
}

fn send_file_receipt_action(
    data_dir: &Path,
    device_id: &DeviceId,
    transfer_id: &str,
    state: FileReceipt,
) -> capsi_core::Result<bool> {
    let trust = TrustStore::load(data_dir)?;
    let peer = trust
        .get(device_id)
        .filter(|device| device.is_trusted())
        .ok_or_else(|| capsi_core::CapsiError::NotFound("device is not trusted".into()))?
        .clone();
    let address = peer
        .last_address
        .ok_or_else(|| capsi_core::CapsiError::NotFound("trusted device has no known address".into()))?;
    let host = address.rsplit_once(':').map(|(host, _)| host).unwrap_or(&address);
    let socket = format!("{host}:{}", capsi_core::TCP_SERVICE_PORT);
    let identity = DeviceIdentity::load_or_create(data_dir)?;
    let receipt = Envelope::new(Message::FileReceipt {
        transfer_id: transfer_id.to_string(),
        state,
    });
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .enable_time()
        .build()
        .map_err(|e| capsi_core::CapsiError::Unsupported(format!("runtime: {e}")))?;
    runtime.block_on(async {
        capsi_core::transport::connect_and_send(&socket, &identity, device_id, &receipt).await
    })?;
    Ok(true)
}

fn file_transfer_action(
    data_dir: &Path,
    device_id: &DeviceId,
    transfer_id: &str,
    accept: bool,
) -> capsi_core::Result<bool> {
    let mut messages = MessageStore::load(data_dir)?;
    let conversation = messages
        .get(device_id)
        .ok_or_else(|| capsi_core::CapsiError::NotFound("conversation not found".into()))?;
    let file = conversation
        .find_transfer(transfer_id)
        .cloned()
        .ok_or_else(|| capsi_core::CapsiError::NotFound("file transfer not found".into()))?;
    if file.state != TransferState::Offered {
        return Err(capsi_core::CapsiError::Invalid("file transfer is no longer awaiting a decision".into()));
    }

    if accept {
        let next_chunk = file.local_path.as_deref()
            .and_then(|path| std::fs::metadata(path).ok())
            .map(|metadata| metadata.len() / capsi_core::TRANSFER_CHUNK_SIZE as u64)
            .unwrap_or(0);
        if file.size == 0 {
            let download_dir = data_dir.join("files").join("downloads");
            std::fs::create_dir_all(&download_dir)?;
            let final_path = download_dir.join(&file.file_name);
            if let Some(temp_path) = file.local_path.as_deref() {
                std::fs::rename(temp_path, &final_path)?;
            }
            messages.update_transfer(
                device_id,
                transfer_id,
                TransferState::Complete,
                Some(final_path.to_string_lossy().to_string()),
            )?;
        } else {
            messages.update_transfer(device_id, transfer_id, TransferState::Transferring, None)?;
        }
        send_file_receipt_action(
            data_dir,
            device_id,
            transfer_id,
            if file.size == 0 {
                FileReceipt::Completed
            } else {
                FileReceipt::Accepted { next_chunk }
            },
        )?;
    } else {
        if let Some(path) = file.local_path.as_deref() {
            let _ = std::fs::remove_file(path);
        }
        messages.update_transfer(device_id, transfer_id, TransferState::Declined, None)?;
        send_file_receipt_action(data_dir, device_id, transfer_id, FileReceipt::Declined)?;
    }

    Ok(true)
}

#[no_mangle]
pub extern "C" fn capsi_file_cancel(
    data_dir: *const c_char,
    device_id: *const c_char,
    transfer_id: *const c_char,
) -> *mut c_char {
    let dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    let device_id = match c_string(device_id).and_then(|value| DeviceId::from_hex(&value).ok()) {
        Some(id) => id,
        None => return error_json("device id is invalid"),
    };
    let transfer_id = match c_string(transfer_id).filter(|value| !value.trim().is_empty()) {
        Some(value) => value,
        None => return error_json("transfer id is invalid"),
    };

    let result = (|| -> capsi_core::Result<bool> {
        let mut messages = MessageStore::load(&dir)?;
        let conversation = messages
            .get(&device_id)
            .ok_or_else(|| capsi_core::CapsiError::NotFound("conversation not found".into()))?;
        let (outgoing, local_path, state) = conversation
            .messages
            .iter()
            .find_map(|message| {
                message.file.as_ref().filter(|file| file.transfer_id == transfer_id).map(|file| {
                    (message.outgoing, file.local_path.clone(), file.state)
                })
            })
            .ok_or_else(|| capsi_core::CapsiError::NotFound("file transfer not found".into()))?;

        if matches!(state, TransferState::Complete | TransferState::Cancelled | TransferState::Declined) {
            return Err(capsi_core::CapsiError::Invalid("file transfer is no longer active".into()));
        }

        messages.update_transfer(&device_id, &transfer_id, TransferState::Cancelled, None)?;
        if !outgoing {
            if let Some(path) = local_path {
                let _ = std::fs::remove_file(path);
            }
        }
        send_file_receipt_action(&dir, &device_id, &transfer_id, FileReceipt::Cancelled)?;
        Ok(true)
    })();

    match result {
        Ok(value) => trust_result(value),
        Err(error) => error_json(&error.user()),
    }
}

#[no_mangle]
pub extern "C" fn capsi_file_accept(
    data_dir: *const c_char,
    device_id: *const c_char,
    transfer_id: *const c_char,
) -> *mut c_char {
    let dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    let device_id = match c_string(device_id).and_then(|value| DeviceId::from_hex(&value).ok()) {
        Some(id) => id,
        None => return error_json("device id is invalid"),
    };
    let transfer_id = match c_string(transfer_id).filter(|value| !value.trim().is_empty()) {
        Some(value) => value,
        None => return error_json("transfer id is invalid"),
    };
    match file_transfer_action(&dir, &device_id, &transfer_id, true) {
        Ok(value) => trust_result(value),
        Err(error) => error_json(&error.user()),
    }
}

#[no_mangle]
pub extern "C" fn capsi_file_decline(
    data_dir: *const c_char,
    device_id: *const c_char,
    transfer_id: *const c_char,
) -> *mut c_char {
    let dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    let device_id = match c_string(device_id).and_then(|value| DeviceId::from_hex(&value).ok()) {
        Some(id) => id,
        None => return error_json("device id is invalid"),
    };
    let transfer_id = match c_string(transfer_id).filter(|value| !value.trim().is_empty()) {
        Some(value) => value,
        None => return error_json("transfer id is invalid"),
    };
    match file_transfer_action(&dir, &device_id, &transfer_id, false) {
        Ok(value) => trust_result(value),
        Err(error) => error_json(&error.user()),
    }
}

#[no_mangle]
pub extern "C" fn capsi_conversations_list(data_dir: *const c_char) -> *mut c_char {
    let dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    match MessageStore::load(&dir) {
        Ok(store) => trust_result(store.list()),
        Err(error) => error_json(&error.user()),
    }
}

#[no_mangle]
pub extern "C" fn capsi_conversation_load(data_dir: *const c_char, device_id: *const c_char) -> *mut c_char {
    let dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    let id = match c_string(device_id).and_then(|value| DeviceId::from_hex(&value).ok()) {
        Some(id) => id,
        None => return error_json("device id is invalid"),
    };
    match MessageStore::load(&dir) {
        Ok(store) => match store.get(&id) {
            Some(conversation) => trust_result(conversation),
            None => error_json("conversation not found"),
        },
        Err(error) => error_json(&error.user()),
    }
}


#[no_mangle]
pub extern "C" fn capsi_workplace_load(data_dir: *const c_char) -> *mut c_char {
    let dir = match c_path(data_dir) {
        Some(path) => path,
        None => return error_json("data directory is invalid"),
    };
    match capsi_core::workplace::WorkspaceStore::new(&dir).load() {
        Ok(Some(workspace)) => {
            let identity = match DeviceIdentity::load_or_create(&dir) {
                Ok(value) => value,
                Err(error) => return error_json(&error.user()),
            };
            let mut value = match serde_json::to_value(&workspace) {
                Ok(value) => value,
                Err(error) => return error_json(&error.user()),
            };
            if let Some(object) = value.as_object_mut() {
                object.insert("local_device_id".into(), serde_json::json!(identity.id().as_str()));
            }
            trust_result(value)
        }
        Ok(None) => into_c_string("null".into()),
        Err(error) => error_json(&error),
    }
}

#[no_mangle]
pub extern "C" fn capsi_workplace_create(
    data_dir: *const c_char,
    name: *const c_char,
) -> *mut c_char {
    let dir = match c_path(data_dir) {
        Some(path) => path,
        None => return error_json("data directory is invalid"),
    };
    let name = match c_string(name) {
        Some(value) if !value.trim().is_empty() => value,
        _ => return error_json("workplace name is invalid"),
    };

    let result = (|| -> Result<_, String> {
        let identity = DeviceIdentity::load_or_create(&dir).map_err(|e| e.to_string())?;
        let device_id = identity.id().as_str().to_string();
        let mut workspace = capsi_core::workplace::Workspace::new(name, device_id.clone());
        if let Some(owner) = workspace.members.iter_mut().find(|member| member.device_id == device_id) {
            owner.display_name = "This device".into();
        }

        // Existing trusted devices become workplace members when the owner
        // creates the workplace. This avoids an empty workspace when trust was
        // established before the workplace itself was created.
        if let Ok(trusted) = TrustStore::load(&dir) {
            for member in trusted.trusted() {
                workspace.add_member(
                    member.device_id.as_str(),
                    member.display_name(),
                    capsi_core::workplace::Role::Member,
                );
            }
        }

        capsi_core::workplace::WorkspaceStore::new(&dir).save(&workspace)?;
        let sync_status = sync_workplace_to_members(&dir, &identity, &workspace);
        let mut value = serde_json::to_value(&workspace).map_err(|e| e.to_string())?;
        if let Some(object) = value.as_object_mut() {
            object.insert("sync".into(), serde_json::to_value(sync_status).unwrap_or_default());
        }
        Ok(value)
    })();

    match result {
        Ok(value) => trust_result(value),
        Err(error) => error_json(&error),
    }
}

#[no_mangle]
pub extern "C" fn capsi_workplace_send_message(
    data_dir: *const c_char,
    group_id: *const c_char,
    body: *const c_char,
) -> *mut c_char {
    let dir = match c_path(data_dir) {
        Some(path) => path,
        None => return error_json("data directory is invalid"),
    };
    let group_id = match c_string(group_id).filter(|v| !v.trim().is_empty()) {
        Some(value) => value,
        None => return error_json("group id is invalid"),
    };
    let body = match c_string(body).filter(|v| !v.trim().is_empty()) {
        Some(value) => value,
        None => return error_json("message body is invalid"),
    };

    let result = (|| -> Result<serde_json::Value, String> {
        let identity = DeviceIdentity::load_or_create(&dir).map_err(|e| e.to_string())?;
        let local_id = identity.id().as_str().to_string();
        let store = capsi_core::workplace::WorkspaceStore::new(&dir);
        let mut workspace = store.load()?.ok_or_else(|| "workplace has not been created".to_string())?;

        if !workspace.permissions_for(&local_id).contains(&capsi_core::workplace::Permission::SendMessages) {
            return Err("device is not allowed to send workplace messages".into());
        }
        let message_id = workspace
            .append_message(&group_id, &local_id, body.clone())
            .ok_or_else(|| "device is not a member of this group".to_string())?;
        workspace.touch();

        let envelope = Envelope::new(Message::WorkplaceText(
            capsi_core::protocol::WorkplaceTextMessage::new(&group_id, &body)
                .map_err(|e| e.to_string())?,
        ));

        let trust = TrustStore::load(&dir).map_err(|e| e.to_string())?;
        let recipients: Vec<String> = workspace.groups.iter()
            .find(|group| group.id == group_id)
            .map(|group| group.member_ids.iter()
                .filter(|id| *id != &local_id)
                .filter(|id| workspace.members.iter().any(|member| &member.device_id == *id))
                .cloned()
                .collect())
            .unwrap_or_default();

        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_io()
            .enable_time()
            .build()
            .map_err(|e| format!("runtime: {e}"))?;

        let mut delivered = 0usize;
        let mut queued = 0usize;
        for recipient in &recipients {
            let Some(device_id) = DeviceId::from_hex(recipient).ok() else {
                queued += 1;
                continue;
            };
            let Some(device) = trust.get(&device_id).filter(|device| device.is_trusted()) else {
                queued += 1;
                continue;
            };
            let Some(address) = device.last_address.clone() else {
                workspace.queue_delivery(envelope.clone(), recipient.clone(), now_millis() as i64);
                queued += 1;
                continue;
            };
            let host = address.rsplit_once(':').map(|(host, _)| host).unwrap_or(&address);
            let socket = format!("{host}:{}", capsi_core::TCP_SERVICE_PORT);
            match runtime.block_on(async {
                capsi_core::transport::connect_and_send(&socket, &identity, &device_id, &envelope).await
            }) {
                Ok(()) => delivered += 1,
                Err(_) => {
                    workspace.queue_delivery(envelope.clone(), recipient.clone(), now_millis() as i64);
                    queued += 1;
                }
            }
        }

        store.save(&workspace).map_err(|e| e.to_string())?;
        Ok(serde_json::json!({
            "message_id": message_id,
            "group_id": group_id,
            "delivered": delivered,
            "queued": queued,
        }))
    })();

    match result {
        Ok(value) => trust_result(value),
        Err(error) => error_json(&error),
    }
}

#[no_mangle]
pub extern "C" fn capsi_workplace_create_group(
    data_dir: *const c_char,
    name: *const c_char,
) -> *mut c_char {
    workplace_mutate(data_dir, |workspace, identity| {
        if !workspace.permissions_for(identity.id().as_str()).contains(&capsi_core::workplace::Permission::ManageGroups) {
            return Err("device is not allowed to manage groups".into());
        }
        let name = c_string(name).filter(|v| !v.trim().is_empty()).ok_or_else(|| "group name is invalid".to_string())?;
        let group_id = workspace.create_group(name, "");
        if !workspace.add_to_group(&group_id, identity.id().as_str()) {
            return Err("group creator could not be added".into());
        }
        workspace.touch();
        Ok(())
    })
}

#[no_mangle]
pub extern "C" fn capsi_workplace_add_group_member(
    data_dir: *const c_char,
    group_id: *const c_char,
    device_id: *const c_char,
) -> *mut c_char {
    let dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    let group_id = match c_string(group_id).filter(|v| !v.trim().is_empty()) {
        Some(value) => value,
        None => return error_json("group id is invalid"),
    };
    let device_id = match c_string(device_id).filter(|v| !v.trim().is_empty()) {
        Some(value) => value,
        None => return error_json("device id is invalid"),
    };

    workplace_mutate_path(&dir, move |workspace, identity| {
        if !workspace.permissions_for(identity.id().as_str()).contains(&capsi_core::workplace::Permission::ManageGroups) {
            return Err("device is not allowed to manage groups".into());
        }
        if !workspace.add_to_group(&group_id, &device_id) {
            return Err("member or group not found".into());
        }
        workspace.touch();
        Ok(())
    })
}

#[no_mangle]
pub extern "C" fn capsi_workplace_create_department(
    data_dir: *const c_char,
    name: *const c_char,
) -> *mut c_char {
    workplace_mutate(data_dir, |workspace, identity| {
        if !workspace.permissions_for(identity.id().as_str()).contains(&capsi_core::workplace::Permission::ManageDepartments) {
            return Err("device is not allowed to manage departments".into());
        }
        let name = c_string(name).filter(|v| !v.trim().is_empty()).ok_or_else(|| "department name is invalid".to_string())?;
        workspace.create_department(name);
        workspace.touch();
        Ok(())
    })
}

#[no_mangle]
pub extern "C" fn capsi_workplace_create_broadcast(
    data_dir: *const c_char,
    title: *const c_char,
    body: *const c_char,
) -> *mut c_char {
    let dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    let closure_dir = dir.clone();
    workplace_mutate_path(&dir, move |workspace, identity| {
        if !workspace.permissions_for(identity.id().as_str()).contains(&capsi_core::workplace::Permission::SendBroadcasts) {
            return Err("device is not allowed to send broadcasts".into());
        }
        let title = c_string(title).filter(|v| !v.trim().is_empty()).ok_or_else(|| "broadcast title is invalid".to_string())?;
        let body = c_string(body).filter(|v| !v.trim().is_empty()).ok_or_else(|| "broadcast body is invalid".to_string())?;
        let broadcast_id = workspace.create_broadcast(title.as_str(), body.as_str(), identity.id().as_str().to_string(), None)
            .ok_or_else(|| "broadcast could not be created".to_string())?;

        // The workplace state sync carries broadcasts as well, but receivers
        // only apply a sync from an owner or admin. The direct envelope is
        // what makes a manager's announcement arrive, and it arrives without
        // waiting for the next full state sync.
        let envelope = Envelope::new(Message::WorkplaceBroadcast(
            capsi_core::protocol::WorkplaceBroadcastMessage {
                broadcast_id,
                title,
                body,
                department_id: None,
            },
        ));
        let local_id = identity.id().as_str().to_string();
        let recipients: Vec<String> = workspace.members.iter()
            .map(|member| member.device_id.clone())
            .filter(|id| *id != local_id)
            .collect();
        deliver_workplace_envelope(&closure_dir, workspace, identity, &envelope, &recipients);
        workspace.touch();
        Ok(())
    })
}

#[no_mangle]
pub extern "C" fn capsi_workplace_rename(
    data_dir: *const c_char,
    name: *const c_char,
) -> *mut c_char {
    let name = match c_string(name) { Some(value) => value, None => return error_json("workplace name is invalid") };
    workplace_mutate(data_dir, move |workspace, identity| {
        if !workspace.permissions_for(identity.id().as_str()).contains(&capsi_core::workplace::Permission::ManageWorkspace) {
            return Err("only the workplace owner can rename the workplace".into());
        }
        workspace.rename(&name)?;
        workspace.touch();
        Ok(())
    })
}

#[no_mangle]
pub extern "C" fn capsi_workplace_delete(data_dir: *const c_char) -> *mut c_char {
    let dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    let result = (|| -> Result<serde_json::Value, String> {
        let identity = DeviceIdentity::load_or_create(&dir).map_err(|e| e.to_string())?;
        let local_id = identity.id().as_str();
        let store = capsi_core::workplace::WorkspaceStore::new(&dir);
        let workspace = store.load()?.ok_or_else(|| "workplace has not been created".to_string())?;

        // Only the owner decides when a workplace stops existing; the owner
        // role is also what carries ManageWorkspace, and the explicit check
        // keeps that rule readable at the call site.
        if workspace.owner_device_id != local_id {
            return Err("only the workplace owner can delete the workplace".into());
        }
        if !workspace.permissions_for(local_id).contains(&capsi_core::workplace::Permission::ManageWorkspace) {
            return Err("device is not allowed to delete the workplace".into());
        }

        // Notify every member while the local store still exists (the tombstone
        // is built from it), then remove the workplace on this device. A member
        // that is offline keeps its copy until the owner contacts it again; the
        // deletion is deliberately local-first rather than queued forever.
        let sync = sync_state_to_members(&dir, &identity, &workspace, workspace.tombstone_state());
        store.delete()?;
        Ok(serde_json::json!({ "deleted": true, "sync": sync }))
    })();
    match result {
        Ok(value) => trust_result(value),
        Err(error) => error_json(&error),
    }
}

#[no_mangle]
pub extern "C" fn capsi_workplace_remove_group_member(
    data_dir: *const c_char,
    group_id: *const c_char,
    device_id: *const c_char,
) -> *mut c_char {
    let dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    let group_id = match c_string(group_id).filter(|v| !v.trim().is_empty()) {
        Some(value) => value,
        None => return error_json("group id is invalid"),
    };
    let device_id = match c_string(device_id).filter(|v| !v.trim().is_empty()) {
        Some(value) => value,
        None => return error_json("device id is invalid"),
    };

    workplace_mutate_path(&dir, move |workspace, identity| {
        if !workspace.permissions_for(identity.id().as_str()).contains(&capsi_core::workplace::Permission::ManageGroups) {
            return Err("device is not allowed to manage groups".into());
        }
        if !workspace.remove_from_group(&group_id, &device_id) {
            return Err("member is not in this group".into());
        }
        workspace.touch();
        Ok(())
    })
}

#[no_mangle]
pub extern "C" fn capsi_workplace_move_group_member(
    data_dir: *const c_char,
    from_group: *const c_char,
    to_group: *const c_char,
    device_id: *const c_char,
) -> *mut c_char {
    let dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    let from_group = match c_string(from_group).filter(|v| !v.trim().is_empty()) {
        Some(value) => value,
        None => return error_json("group id is invalid"),
    };
    let to_group = match c_string(to_group).filter(|v| !v.trim().is_empty()) {
        Some(value) => value,
        None => return error_json("group id is invalid"),
    };
    let device_id = match c_string(device_id).filter(|v| !v.trim().is_empty()) {
        Some(value) => value,
        None => return error_json("device id is invalid"),
    };

    workplace_mutate_path(&dir, move |workspace, identity| {
        if !workspace.permissions_for(identity.id().as_str()).contains(&capsi_core::workplace::Permission::ManageGroups) {
            return Err("device is not allowed to manage groups".into());
        }
        if from_group == to_group {
            return Err("source and destination group are the same".into());
        }
        // Remove first so the move cannot duplicate the member, then let the
        // lookup in add_to_group reject a destination that does not exist.
        if !workspace.remove_from_group(&from_group, &device_id) {
            return Err("member is not in that group".into());
        }
        if !workspace.add_to_group(&to_group, &device_id) {
            return Err("destination group not found".into());
        }
        workspace.touch();
        Ok(())
    })
}

#[derive(Debug, serde::Serialize)]
struct WorkplaceSyncStatus {
    attempted: usize,
    delivered: usize,
    failed: usize,
}

/// Promote or demote a member.
///
/// The role arrives as its wire spelling (`"Admin"`) rather than being guessed
/// from an ordinal, so a UI that reorders its list cannot silently hand out the
/// wrong permission. Every rule about who may assign what lives in
/// `Role::can_assign`; this only decodes the request and checks that the caller
/// even holds `ManageMembers` before touching the workspace.
#[no_mangle]
pub extern "C" fn capsi_workplace_set_member_role(
    data_dir: *const c_char,
    device_id: *const c_char,
    role: *const c_char,
) -> *mut c_char {
    let dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    let device_id = match c_string(device_id).filter(|v| !v.trim().is_empty()) {
        Some(value) => value,
        None => return error_json("device id is invalid"),
    };
    let role = match c_string(role).filter(|v| !v.trim().is_empty()) {
        Some(value) => value,
        None => return error_json("role is invalid"),
    };
    let Some(role) = capsi_core::workplace::Role::from_wire(&role) else {
        return error_json("role must be one of admin, manager or member");
    };

    workplace_mutate_path(&dir, move |workspace, identity| {
        if !workspace
            .permissions_for(identity.id().as_str())
            .contains(&capsi_core::workplace::Permission::ManageMembers)
        {
            return Err("device is not allowed to manage members".into());
        }
        workspace.set_member_role(identity.id().as_str(), &device_id, role)?;
        workspace.touch();
        Ok(())
    })
}

fn sync_workplace_to_members(
    dir: &Path,
    identity: &DeviceIdentity,
    workspace: &capsi_core::workplace::Workspace,
) -> WorkplaceSyncStatus {
    sync_state_to_members(dir, identity, workspace, workspace.network_state())
}

/// Push a workplace state to every other member that is currently trusted.
///
/// Kept separate from `Workspace::network_state` so a deletion tombstone takes
/// the exact same delivery path as an ordinary update.
fn sync_state_to_members(
    dir: &Path,
    identity: &DeviceIdentity,
    workspace: &capsi_core::workplace::Workspace,
    state: capsi_core::workplace::WorkspaceState,
) -> WorkplaceSyncStatus {
    let trust = match TrustStore::load(dir) {
        Ok(value) => value,
        Err(_) => return WorkplaceSyncStatus { attempted: 0, delivered: 0, failed: 0 },
    };

    let local_id = identity.id().as_str();
    let members: Vec<_> = workspace.members.iter()
        .filter(|member| member.device_id != local_id)
        .filter_map(|member| trust.get(&DeviceId::from_hex(&member.device_id).ok()?).filter(|device| device.is_trusted()).cloned())
        .collect();

    if members.is_empty() {
        return WorkplaceSyncStatus { attempted: 0, delivered: 0, failed: 0 };
    }

    let runtime = match tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .enable_time()
        .build()
    {
        Ok(runtime) => runtime,
        Err(_) => return WorkplaceSyncStatus { attempted: members.len(), delivered: 0, failed: members.len() },
    };

    let mut delivered = 0usize;
    let mut failed = 0usize;

    for device in members {
        let Some(address) = device.last_address.clone() else {
            failed += 1;
            continue;
        };
        let host = address.rsplit_once(':').map(|(host, _)| host).unwrap_or(&address);
        let socket = format!("{host}:{}", capsi_core::TCP_SERVICE_PORT);
        let peer_id = device.device_id;
        let envelope = Envelope::new(Message::WorkplaceSync(
            capsi_core::protocol::WorkplaceSyncMessage {
                actor_device_id: local_id.to_string(),
                state: state.clone(),
            },
        ));
        match runtime.block_on(async {
            capsi_core::transport::connect_and_send(&socket, identity, &peer_id, &envelope).await
        }) {
            Ok(()) => delivered += 1,
            Err(_) => failed += 1,
        }
    }

    WorkplaceSyncStatus {
        attempted: delivered + failed,
        delivered,
        failed,
    }
}

/// Send one workplace envelope to every recipient that is reachable now and
/// queue the rest, so a member that is offline still receives it later.
///
/// Recipients that can never be reached (an id that is not a device id, or a
/// member that is not a trusted device) are skipped rather than queued: trust
/// is what makes delivery possible at all, and the full state sync carries the
/// same content once that trust exists.
fn deliver_workplace_envelope(
    dir: &Path,
    workspace: &mut capsi_core::workplace::Workspace,
    identity: &DeviceIdentity,
    envelope: &Envelope,
    recipients: &[String],
) {
    let trust = TrustStore::load(dir).ok();
    let runtime = match tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .enable_time()
        .build()
    {
        Ok(runtime) => runtime,
        Err(_) => {
            for recipient in recipients {
                workspace.queue_delivery(envelope.clone(), recipient.clone(), now_millis() as i64);
            }
            return;
        }
    };

    for recipient in recipients {
        let Some(device_id) = DeviceId::from_hex(recipient).ok() else { continue };
        let Some(device) = trust.as_ref()
            .and_then(|trust| trust.get(&device_id))
            .filter(|device| device.is_trusted()) else { continue };
        let Some(address) = device.last_address.clone() else {
            workspace.queue_delivery(envelope.clone(), recipient.clone(), now_millis() as i64);
            continue;
        };
        let host = address.rsplit_once(':').map(|(host, _)| host).unwrap_or(&address);
        let socket = format!("{host}:{}", capsi_core::TCP_SERVICE_PORT);
        let reachable = runtime.block_on(async {
            capsi_core::transport::connect_and_send(&socket, identity, &device_id, envelope).await
        });
        if reachable.is_err() {
            workspace.queue_delivery(envelope.clone(), recipient.clone(), now_millis() as i64);
        }
    }
}

/// Retry workplace deliveries that are due.
///
/// `queue_delivery` only writes the entry; this is the loop that drains it, and
/// the message session calls it every few seconds so a group message or
/// broadcast queued while a member was offline goes out once the member is
/// reachable again. A recipient that stays unreachable is backed off instead of
/// being retried on every tick, and one that has become untrusted (or whose id
/// is not a device id at all) drops out of the queue instead of lingering.
async fn flush_workplace_deliveries(dir: &Path, identity: &DeviceIdentity) {
    let store = capsi_core::workplace::WorkspaceStore::new(dir);
    let Ok(Some(mut workspace)) = store.load() else { return };
    if workspace.pending_deliveries.is_empty() {
        return;
    }

    let now = now_millis() as i64;
    let due: Vec<(Envelope, String)> = workspace.pending_deliveries.iter()
        .filter(|pending| pending.next_attempt_at <= now)
        .map(|pending| (pending.envelope.clone(), pending.recipient_device_id.clone()))
        .collect();
    if due.is_empty() {
        return;
    }

    let trust = TrustStore::load(dir).ok();
    let mut changed = false;
    for (envelope, recipient) in due {
        let Some(device_id) = DeviceId::from_hex(&recipient).ok() else {
            workspace.remove_pending_delivery(&envelope.id, &recipient);
            changed = true;
            continue;
        };
        let Some(device) = trust.as_ref()
            .and_then(|trust| trust.get(&device_id))
            .filter(|device| device.is_trusted()) else {
            workspace.remove_pending_delivery(&envelope.id, &recipient);
            changed = true;
            continue;
        };
        let Some(address) = device.last_address.clone() else {
            continue; // still offline; keep the entry for the next pass.
        };
        let host = address.rsplit_once(':').map(|(host, _)| host).unwrap_or(&address);
        let socket = format!("{host}:{}", capsi_core::TCP_SERVICE_PORT);
        match capsi_core::transport::connect_and_send(&socket, identity, &device_id, &envelope).await {
            Ok(()) => {
                workspace.remove_pending_delivery(&envelope.id, &recipient);
                changed = true;
            }
            Err(_) => {
                // 30 seconds between attempts: frequent enough to notice a
                // device coming back, rare enough to keep a sleeping laptop's
                // radio quiet.
                workspace.reschedule_delivery(&envelope.id, &recipient, now + 30_000);
                changed = true;
            }
        }
    }

    if changed {
        let _ = store.save(&workspace);
    }
}

fn workplace_mutate<F>(data_dir: *const c_char, mutate: F) -> *mut c_char
where
    F: FnOnce(&mut capsi_core::workplace::Workspace, &DeviceIdentity) -> Result<(), String>,
{
    let dir = match c_path(data_dir) {
        Some(path) => path,
        None => return error_json("data directory is invalid"),
    };
    workplace_mutate_path(&dir, mutate)
}

fn workplace_mutate_path<F>(dir: &Path, mutate: F) -> *mut c_char
where
    F: FnOnce(&mut capsi_core::workplace::Workspace, &DeviceIdentity) -> Result<(), String>,
{
    let result = (|| -> Result<serde_json::Value, String> {
        let identity = DeviceIdentity::load_or_create(dir).map_err(|e| e.to_string())?;
        let store = capsi_core::workplace::WorkspaceStore::new(dir);
        let mut workspace = store.load()?.ok_or_else(|| "workplace has not been created".to_string())?;
        mutate(&mut workspace, &identity)?;
        store.save(&workspace).map_err(|e| e.to_string())?;
        let sync = sync_workplace_to_members(dir, &identity, &workspace);
        let mut value = serde_json::to_value(&workspace).map_err(|e| e.to_string())?;
        if let Some(object) = value.as_object_mut() {
            object.insert("sync".into(), serde_json::to_value(sync).unwrap_or_default());
        }
        Ok(value)
    })();
    match result {
        Ok(value) => trust_result(value),
        Err(error) => error_json(&error),
    }
}

/// Stable native boundary for the Flutter client.
///
/// Keep this API C-compatible. Higher-level Capsi operations should be backed
/// by the existing capsi-core implementation rather than reimplemented in Dart.
#[no_mangle]
pub extern "C" fn capsi_runtime_version() -> *const c_char {
    // The crate version is the single source of truth the release tooling bumps,
    // so the About dialog can never report a version the build did not produce.
    static VERSION: &[u8] = concat!(env!("CARGO_PKG_VERSION"), "\0").as_bytes();
    VERSION.as_ptr().cast()
}

/// Returns a non-zero value when the shared Rust core is linked and working.
///
/// The check is a real signing round-trip through the core rather than a
/// constant: a build that links the symbol but cannot perform the cryptography
/// the protocol depends on has to fail here, not at the first message.
#[no_mangle]
pub extern "C" fn capsi_core_linked() -> i32 {
    match core_round_trip() {
        Ok(()) => 1,
        Err(_) => 0,
    }
}

/// The signing round-trip shared by [`capsi_core_linked`] and the self-check.
fn core_round_trip() -> capsi_core::Result<()> {
    let identity = DeviceIdentity::generate()?;
    let probe = b"capsi core liveness probe";
    DeviceIdentity::verify_hex(&identity.verifying_key(), probe, &identity.sign_hex(probe))
}

/// Returns the Capsi protocol version used by the Rust core.
#[no_mangle]
pub extern "C" fn capsi_protocol_version() -> *const c_char {
    // Read from the core constant instead of repeating the literal, so the value
    // the client checks compatibility against cannot drift from the value the
    // core actually speaks.
    static VERSION: OnceLock<CString> = OnceLock::new();
    VERSION
        .get_or_init(|| {
            CString::new(capsi_core::PROTOCOL_VERSION)
                .expect("the protocol version never contains a NUL")
        })
        .as_ptr()
}

/// The TCP service port the core expects peers to dial.
///
/// Read from the core constant rather than repeated as a literal, so the port
/// the client starts its listener on and the port the startup self-check proves
/// bindable cannot drift apart.
#[no_mangle]
pub extern "C" fn capsi_service_port() -> u16 {
    capsi_core::TCP_SERVICE_PORT
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
    if name.is_null() {
        return error_json("device name is null");
    }
    let name = match c_string(name) {
        Some(value) => value,
        None => return error_json("device name is not valid UTF-8"),
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
        Err(error) => error_json(&error.user()),
    }
}

/// The Capsi startup self-check, run against the real engine.
///
/// Every step performs the operation the application depends on - a signing
/// round-trip through the core, a write into the data directory, the real trust
/// and message stores, and a real bind of the service port and the discovery
/// socket - so a green report is evidence that the engine works rather than that
/// a symbol resolved. The shell renders the steps verbatim and only leaves its
/// startup gate when every one of them passed.
///
/// The returned value is a UTF-8 JSON object. The caller owns it and must
/// release it with `capsi_free_string`.
#[no_mangle]
pub extern "C" fn capsi_self_test(
    data_dir: *const c_char,
    device_name: *const c_char,
    tcp_port: u16,
) -> *mut c_char {
    let dir = match c_path(data_dir) {
        Some(path) => path,
        None => return error_json("data directory is invalid"),
    };
    let name = match c_string(device_name) {
        Some(value) if !value.trim().is_empty() => value,
        _ => return error_json("device name is invalid"),
    };

    let mut steps: Vec<serde_json::Value> = Vec::with_capacity(6);

    // 1. The core is linked and its cryptography actually works.
    steps.push(match core_round_trip() {
        Ok(()) => serde_json::json!({ "name": "core_linked", "ok": true }),
        Err(error) => serde_json::json!({
            "name": "core_linked",
            "ok": false,
            "detail": error.user_message(),
        }),
    });

    // 2. The protocol version the core speaks, for the compatibility check.
    steps.push(serde_json::json!({
        "name": "protocol",
        "ok": true,
        "detail": capsi_core::PROTOCOL_VERSION,
    }));

    // 3. Local storage: the directory round-trips a write and both stores open.
    let storage = (|| -> capsi_core::Result<()> {
        std::fs::create_dir_all(&dir)?;
        let probe = dir.join(".capsi-self-test");
        std::fs::write(&probe, b"capsi")?;
        let read_back = std::fs::read(&probe)?;
        let _ = std::fs::remove_file(&probe);
        if read_back != b"capsi" {
            return Err(capsi_core::CapsiError::Io(
                "the data directory did not round-trip a write".into(),
            ));
        }
        TrustStore::load(&dir)?;
        MessageStore::load(&dir)?;
        Ok(())
    })();
    steps.push(match &storage {
        Ok(()) => serde_json::json!({ "name": "storage", "ok": true }),
        Err(error) => serde_json::json!({
            "name": "storage",
            "ok": false,
            "detail": error.user_message(),
        }),
    });

    // 4. Identity: the stored one is loaded, or a new one is created.
    let identity = DeviceIdentity::load_or_create(&dir);
    steps.push(match &identity {
        Ok(identity) => serde_json::json!({
            "name": "identity",
            "ok": true,
            "detail": format!("{} {}", identity.id().as_str(), identity.fingerprint().as_str()),
        }),
        Err(error) => serde_json::json!({
            "name": "identity",
            "ok": false,
            "detail": error.user_message(),
        }),
    });

    // 5 and 6. The service port and the discovery socket really bind. Both are
    // held at the same time, then released, so the check covers the ports the
    // running application takes a moment later.
    let (network, discovery) = network_ports_bind(&name, tcp_port);
    steps.push(network);
    steps.push(discovery);

    let ok = steps.iter().all(|step| step["ok"].as_bool() == Some(true));
    trust_result(serde_json::json!({
        "ok": ok,
        "runtime": env!("CARGO_PKG_VERSION"),
        "protocol": capsi_core::PROTOCOL_VERSION,
        "steps": steps,
    }))
}

/// Bind the service port and the discovery socket, report each, and release both.
///
/// The discovery socket goes through [`Discovery::bind`] so the check uses the
/// same socket options the running listener uses; a stricter probe would report
/// a failure on a machine that is already running a second Capsi.
fn network_ports_bind(name: &str, tcp_port: u16) -> (serde_json::Value, serde_json::Value) {
    let failed = |detail: String| {
        (
            serde_json::json!({ "name": "network_listener", "ok": false, "detail": detail }),
            serde_json::json!({ "name": "discovery", "ok": false, "detail": detail }),
        )
    };

    let runtime = match tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .enable_time()
        .build()
    {
        Ok(runtime) => runtime,
        Err(error) => return failed(error.to_string()),
    };

    let name = name.to_owned();
    runtime.block_on(async move {
        // The port the message listener will accept connections on.
        let listener = TcpListener::bind(("0.0.0.0", tcp_port)).await;
        let network = match &listener {
            Ok(socket) => serde_json::json!({
                "name": "network_listener",
                "ok": true,
                "detail": socket
                    .local_addr()
                    .map(|address| address.to_string())
                    .unwrap_or_else(|_| format!("0.0.0.0:{tcp_port}")),
            }),
            Err(error) => serde_json::json!({
                "name": "network_listener",
                "ok": false,
                "detail": error.to_string(),
            }),
        };

        // Bound while the service port is still held, so a port that is only
        // free because nothing holds it is caught here.
        let discovery = match DeviceIdentity::generate() {
            Ok(identity) => match Discovery::bind(Arc::new(identity), name, tcp_port).await {
                Ok(discovery) => serde_json::json!({
                    "name": "discovery",
                    "ok": true,
                    "detail": format!("udp 0.0.0.0:{}", discovery.local_port()),
                }),
                Err(error) => serde_json::json!({
                    "name": "discovery",
                    "ok": false,
                    "detail": error.user_message(),
                }),
            },
            Err(error) => serde_json::json!({
                "name": "discovery",
                "ok": false,
                "detail": error.user_message(),
            }),
        };

        // Both sockets are released here so the application's own listeners can
        // take the ports immediately afterwards.
        drop(listener);
        (network, discovery)
    })
}

/// Release a string returned by this FFI layer.
///
/// # Safety
///
/// `value` must either be null or a pointer previously returned by this
/// library that has not been freed yet. Passing any other pointer, or freeing
/// the same string twice, is undefined behaviour.
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
        assert_eq!(value.to_str().unwrap(), capsi_core::PROTOCOL_VERSION);
    }

    #[test]
    fn the_service_port_comes_from_the_core() {
        assert_eq!(capsi_service_port(), capsi_core::TCP_SERVICE_PORT);
    }

    #[test]
    fn core_reports_as_linked() {
        assert_eq!(capsi_core_linked(), 1);
    }

    /// Read a report the way the Flutter client does, and free it.
    fn self_test(dir: &Path, name: &str, tcp_port: u16) -> serde_json::Value {
        let dir_arg = CString::new(dir.to_string_lossy().into_owned()).unwrap();
        let name_arg = CString::new(name).unwrap();
        let raw = capsi_self_test(dir_arg.as_ptr(), name_arg.as_ptr(), tcp_port);
        assert!(!raw.is_null());
        let json = unsafe { CStr::from_ptr(raw).to_str().unwrap().to_owned() };
        unsafe { capsi_free_string(raw) };
        serde_json::from_str(&json).unwrap()
    }

    #[test]
    fn the_self_test_reports_every_step_as_passed() {
        let dir = std::env::temp_dir().join(format!("capsi-self-test-{}", std::process::id()));

        // Port 0 asks the OS for a free service port so the check never fights
        // the real one. The discovery socket still uses the standard port.
        let report = self_test(&dir, "self test device", 0);
        assert_eq!(report["ok"].as_bool(), Some(true), "report: {report}");
        assert_eq!(report["protocol"], capsi_core::PROTOCOL_VERSION);
        assert_eq!(report["runtime"], env!("CARGO_PKG_VERSION"));

        let steps = report["steps"].as_array().unwrap();
        let names: Vec<&str> = steps
            .iter()
            .map(|step| step["name"].as_str().unwrap())
            .collect();
        assert_eq!(
            names,
            ["core_linked", "protocol", "storage", "identity", "network_listener", "discovery"]
        );
        for step in steps {
            assert_eq!(step["ok"].as_bool(), Some(true), "step: {step}");
        }

        // The identity step has to name the device the stores will use.
        let identity = steps.iter().find(|step| step["name"] == "identity").unwrap();
        assert!(identity["detail"].as_str().unwrap().contains(' '));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_self_test_reports_a_failure_instead_of_a_pass() {
        // A data directory that cannot exist (its parent is a file) has to be
        // reported as a failed step rather than skipped or swallowed.
        let parent = std::env::temp_dir().join(format!("capsi-self-test-file-{}", std::process::id()));
        std::fs::write(&parent, b"not a directory").unwrap();

        let report = self_test(&parent.join("data"), "self test device", 0);
        assert_eq!(report["ok"].as_bool(), Some(false), "report: {report}");

        let storage = report["steps"]
            .as_array()
            .unwrap()
            .iter()
            .find(|step| step["name"] == "storage")
            .unwrap()
            .clone();
        assert_eq!(storage["ok"].as_bool(), Some(false));
        assert!(
            storage["detail"]
                .as_str()
                .is_some_and(|detail| !detail.is_empty()),
            "storage step carried no reason: {storage}"
        );

        let _ = std::fs::remove_file(&parent);
    }

    #[test]
    fn the_self_test_rejects_an_empty_device_name() {
        let dir_arg = CString::new("unused").unwrap();
        let name_arg = CString::new("   ").unwrap();
        let raw = capsi_self_test(dir_arg.as_ptr(), name_arg.as_ptr(), 0);
        let json = unsafe { CStr::from_ptr(raw).to_str().unwrap().to_owned() };
        unsafe { capsi_free_string(raw) };
        let report: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(report["error"], "device name is invalid");
    }
}
