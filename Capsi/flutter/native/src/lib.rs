use std::ffi::{c_char, CStr, CString};
use std::time::Duration;
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
                let socket = format!("{host}:45892");
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


#[no_mangle]
pub extern "C" fn capsi_message_start(data_dir: *const c_char, tcp_port: u16) -> u64 {
    let data_dir = match c_path(data_dir) { Some(path) => path, None => return 0 };
    let stop = Arc::new(AtomicBool::new(false));
    let events = Arc::new(Mutex::new(VecDeque::new()));
    let thread_stop = Arc::clone(&stop);
    let thread_events = Arc::clone(&events);

    if std::thread::Builder::new().name("capsi-messages".into()).spawn(move || {
        let runtime = match tokio::runtime::Builder::new_current_thread().enable_io().enable_time().build() {
            Ok(runtime) => runtime,
            Err(_) => return,
        };
        runtime.block_on(async move {
            let identity = match DeviceIdentity::load_or_create(&data_dir) {
                Ok(identity) => Arc::new(identity),
                Err(_) => return,
            };
            let listener = match TcpListener::bind(("0.0.0.0", tcp_port)).await {
                Ok(listener) => listener,
                Err(error) => {
                    message_event(&thread_events, serde_json::json!({"error": error.to_string()}));
                    return;
                }
            };

            while !thread_stop.load(Ordering::Acquire) {
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
                            let socket = format!("{}:{}", addr.ip(), 45892);
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
                            workspace.messages.last_mut().map(|message| message.id = message_id.clone());
                            workspace.mark_received_message(&envelope.id);
                            workspace.touch();
                            if let Err(error) = store.save(&workspace) {
                                message_event(&thread_events, serde_json::json!({"error":error}));
                                continue;
                            }

                            let receipt = Envelope::new(Message::DeliveryReceipt(
                                capsi_core::protocol::DeliveryReceipt { message_id: envelope.id.clone() }
                            ));
                            let socket = format!("{}:{}", addr.ip(), 45892);
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
                        let socket = format!("{}:{}", addr.ip(), 45892);
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
        let socket = format!("{host}:45892");

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
        Err(error) => error_json(&error.to_string()),
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
        let socket = format!("{host}:45892");

        let metadata = std::fs::metadata(&file_path)?;
        if !metadata.is_file() {
            return Err(capsi_core::CapsiError::Invalid("selected path is not a file".into()));
        }
        let size = metadata.len();
        let digest = capsi_core::util::digest_file(&file_path)?;
        let chunk_size = capsi_core::TRANSFER_CHUNK_SIZE as u64;
        let chunks = if size == 0 { 0 } else { (size + chunk_size - 1) / chunk_size };
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
        Err(error) => error_json(&error.to_string()),
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
    let socket = format!("{host}:45892");
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
        Err(error) => error_json(&error.to_string()),
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
        Err(error) => error_json(&error.to_string()),
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
        Err(error) => error_json(&error.to_string()),
    }
}

#[no_mangle]
pub extern "C" fn capsi_conversations_list(data_dir: *const c_char) -> *mut c_char {
    let dir = match c_path(data_dir) { Some(path) => path, None => return error_json("data directory is invalid") };
    match MessageStore::load(&dir) {
        Ok(store) => trust_result(store.list()),
        Err(error) => error_json(&error.to_string()),
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
        Err(error) => error_json(&error.to_string()),
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
                Err(error) => return error_json(&error.to_string()),
            };
            let mut value = match serde_json::to_value(&workspace) {
                Ok(value) => value,
                Err(error) => return error_json(&error.to_string()),
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
                workspace.queue_delivery(envelope.clone(), recipient.clone(), now_millis());
                queued += 1;
                continue;
            };
            let host = address.rsplit_once(':').map(|(host, _)| host).unwrap_or(&address);
            let socket = format!("{host}:45892");
            match runtime.block_on(async {
                capsi_core::transport::connect_and_send(&socket, &identity, &device_id, &envelope).await
            }) {
                Ok(()) => delivered += 1,
                Err(error) => {
                    workspace.queue_delivery(envelope.clone(), recipient.clone(), now_millis());
                    let _ = error;
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
    workplace_mutate(data_dir, |workspace, identity| {
        if !workspace.permissions_for(identity.id().as_str()).contains(&capsi_core::workplace::Permission::SendBroadcasts) {
            return Err("device is not allowed to send broadcasts".into());
        }
        let title = c_string(title).filter(|v| !v.trim().is_empty()).ok_or_else(|| "broadcast title is invalid".to_string())?;
        let body = c_string(body).filter(|v| !v.trim().is_empty()).ok_or_else(|| "broadcast body is invalid".to_string())?;
        workspace.create_broadcast(title, body, identity.id().as_str().to_string(), None)
            .ok_or_else(|| "broadcast could not be created".to_string())?;
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

fn sync_workplace_to_members(
    dir: &Path,
    identity: &DeviceIdentity,
    workspace: &capsi_core::workplace::Workspace,
) -> WorkplaceSyncStatus {
    let trust = match TrustStore::load(dir) {
        Ok(value) => value,
        Err(_) => return WorkplaceSyncStatus { attempted: 0, delivered: 0, failed: 0 },
    };

    let local_id = identity.id().as_str();
    let members: Vec<_> = workspace.members.iter()
        .filter(|member| member.device_id != local_id)
        .filter_map(|member| trust.get(&DeviceId::from_hex(&member.device_id).ok()?).filter(|device| device.is_trusted()).map(|device| device.clone()))
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

    let state = workspace.network_state();
    let mut delivered = 0usize;
    let mut failed = 0usize;

    for device in members {
        let Some(address) = device.last_address.clone() else {
            failed += 1;
            continue;
        };
        let host = address.rsplit_once(':').map(|(host, _)| host).unwrap_or(&address);
        let socket = format!("{host}:45892");
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
