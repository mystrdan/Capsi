use serde::Serialize;
use tauri::State;

use capsi_core::{identity::DeviceIdentity, workplace::{Permission, Role, Workspace, WorkspaceStore}};

use super::setup_app_data;

#[derive(Debug, Serialize)]
pub struct WorkplaceSnapshot {
    pub workspace: Option<Workspace>,
    pub permissions: Vec<String>,
}

fn queue_workspace_sync(
    workspace: &mut Workspace,
    actor_device_id: &str,
    extra_recipients: &[String],
) -> Result<(), String> {
    let envelope = capsi_core::protocol::Envelope::new(
        capsi_core::protocol::Message::WorkplaceSync(
            capsi_core::protocol::WorkplaceSyncMessage {
                actor_device_id: actor_device_id.to_string(),
                state: workspace.network_state(),
            },
        ),
    );
    let mut recipients = std::collections::BTreeSet::new();
    recipients.extend(workspace.members.iter().map(|m| m.device_id.clone()));
    recipients.extend(extra_recipients.iter().cloned());
    recipients.remove(actor_device_id);
    for recipient in recipients {
        workspace.queue_delivery(envelope.clone(), recipient, unix_now());
    }
    Ok(())
}

fn store<R: tauri::Runtime>(app: &tauri::AppHandle<R>) -> Result<WorkspaceStore, String> {
    Ok(WorkspaceStore::new(&setup_app_data(app)?))
}

#[tauri::command]
pub fn get_workplace<R: tauri::Runtime>(app: tauri::AppHandle<R>) -> Result<WorkplaceSnapshot, String> {
    let store = store(&app)?;
    let workspace = store.load()?;
    let permissions = workspace
        .as_ref()
        .and_then(|w| {
            let data_dir = setup_app_data(&app).ok()?;
            let identity = DeviceIdentity::load_or_create(&data_dir).ok()?;
            Some(w.permissions_for(identity.id().as_str()))
        })
        .unwrap_or_default()
        .into_iter()
        .map(|p| format!("{p:?}"))
        .collect();
    Ok(WorkplaceSnapshot { workspace, permissions })
}

/// Creates the local workspace model only. Network synchronization is intentionally
/// not part of this skeleton yet.
#[tauri::command]
pub fn create_workplace<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    name: String,
) -> Result<Workspace, String> {
    let store = store(&app)?;
    if store.load()?.is_some() {
        return Err("a workspace already exists on this device".into());
    }
    let data_dir = setup_app_data(&app)?;
    let identity = DeviceIdentity::load_or_create(&data_dir).map_err(|e| e.to_string())?;
    let device_name = super::load_device_name(&data_dir)
        .map_err(|e| e.to_string())?
        .unwrap_or_else(|| identity.id().short());
    let mut workspace = Workspace::new(name.trim(), identity.id().as_str());
    if let Some(owner) = workspace.members.first_mut() {
        owner.display_name = device_name;
    }
    store.save(&workspace)?;
    Ok(workspace)
}

#[tauri::command]
pub fn add_workplace_member<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    device_id: String,
    display_name: String,
    role: Option<Role>,
) -> Result<Workspace, String> {
    let store = store(&app)?;
    let mut workspace = store.load()?.ok_or_else(|| "no workplace exists".to_string())?;
    let data_dir = setup_app_data(&app)?;
    let identity = DeviceIdentity::load_or_create(&data_dir).map_err(|e| e.to_string())?;
    if !workspace.permissions_for(identity.id().as_str()).contains(&Permission::ManageMembers) {
        return Err("you do not have permission to manage workplace members".into());
    }
    let trust = capsi_core::identity::trust::TrustStore::load(&data_dir).map_err(|e| e.to_string())?;
    let peer_id = capsi_core::identity::DeviceId::from_hex(&device_id).map_err(|e| e.to_string())?;
    let peer = trust.get(&peer_id).ok_or_else(|| "device is not known to Capsi".to_string())?;
    if !peer.is_trusted() {
        return Err("device must be trusted before it can join the workplace".into());
    }
    let role = role.unwrap_or(Role::Member);
    if matches!(role, Role::Owner | Role::Admin) && !matches!(workspace.members.iter().find(|m| m.device_id == identity.id().as_str()).map(|m| &m.role), Some(Role::Owner)) {
        return Err("only the workplace owner can add an admin or owner".into());
    }
    workspace.add_member(device_id, if display_name.trim().is_empty() { peer.display_name() } else { display_name.trim() }, role);
    queue_workspace_sync(&mut workspace, identity.id().as_str(), &[])?;
    store.save(&workspace)?;
    Ok(workspace)
}

#[tauri::command]
pub fn remove_workplace_member<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    device_id: String,
) -> Result<Workspace, String> {
    let store = store(&app)?;
    let mut workspace = store.load()?.ok_or_else(|| "no workplace exists".to_string())?;
    let data_dir = setup_app_data(&app)?;
    let identity = DeviceIdentity::load_or_create(&data_dir).map_err(|e| e.to_string())?;
    if !workspace.permissions_for(identity.id().as_str()).contains(&Permission::ManageMembers) {
        return Err("you do not have permission to manage workplace members".into());
    }
    if device_id == workspace.owner_device_id {
        return Err("the workplace owner cannot be removed".into());
    }
    workspace.members.retain(|m| m.device_id != device_id);
    for group in &mut workspace.groups {
        group.member_ids.retain(|id| id != &device_id);
    }
    for department in &mut workspace.departments {
        department.member_ids.retain(|id| id != &device_id);
    }
    workspace.touch();
    queue_workspace_sync(&mut workspace, identity.id().as_str(), &[device_id.clone()])?;
    store.save(&workspace)?;
    Ok(workspace)
}

#[tauri::command]
pub fn create_workplace_department<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    name: String,
) -> Result<Workspace, String> {
    let store = store(&app)?;
    let mut workspace = store.load()?.ok_or_else(|| "no workplace exists".to_string())?;
    let data_dir = setup_app_data(&app)?;
    let identity = DeviceIdentity::load_or_create(&data_dir).map_err(|e| e.to_string())?;
    if !workspace.permissions_for(identity.id().as_str()).contains(&Permission::ManageDepartments) {
        return Err("you do not have permission to manage workplace departments".into());
    }
    if name.trim().is_empty() { return Err("department name cannot be empty".into()); }
    workspace.create_department(name.trim());
    workspace.touch();
    queue_workspace_sync(&mut workspace, identity.id().as_str(), &[])?;
    store.save(&workspace)?;
    Ok(workspace)
}

#[tauri::command]
pub fn create_workplace_group<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    name: String,
    description: String,
) -> Result<Workspace, String> {
    let store = store(&app)?;
    let mut workspace = store.load()?.ok_or_else(|| "no workplace exists".to_string())?;
    let data_dir = setup_app_data(&app)?;
    let identity = DeviceIdentity::load_or_create(&data_dir).map_err(|e| e.to_string())?;
    if !workspace.permissions_for(identity.id().as_str()).contains(&Permission::ManageGroups) {
        return Err("you do not have permission to manage workplace groups".into());
    }
    if name.trim().is_empty() { return Err("group name cannot be empty".into()); }
    workspace.create_group(name.trim(), description.trim());
    workspace.touch();
    queue_workspace_sync(&mut workspace, identity.id().as_str(), &[])?;
    store.save(&workspace)?;
    Ok(workspace)
}

#[tauri::command]
pub async fn create_workplace_broadcast<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    title: String,
    body: String,
    author_device_id: String,
    department_id: Option<String>,
) -> Result<Workspace, String> {
    let store = store(&app)?;
    let mut workspace = store.load()?.ok_or_else(|| "no workplace exists".to_string())?;
    let data_dir = setup_app_data(&app)?;
    let identity = DeviceIdentity::load_or_create(&data_dir).map_err(|e| e.to_string())?;
    let sender_id = identity.id().as_str().to_string();
    if !workspace.permissions_for(&sender_id).contains(&Permission::SendBroadcasts) {
        return Err("you do not have permission to send workplace broadcasts".into());
    }
    let broadcast_id = workspace
        .create_broadcast(title.trim(), body.trim(), sender_id.clone(), department_id.clone())
        .ok_or_else(|| "invalid broadcast author or department".to_string())?;
    let broadcast = workspace.broadcasts.iter().find(|b| b.id == broadcast_id)
        .cloned().ok_or_else(|| "broadcast was not stored".to_string())?;
    let envelope = capsi_core::protocol::Envelope::new(
        capsi_core::protocol::Message::WorkplaceBroadcast(
            capsi_core::protocol::WorkplaceBroadcastMessage {
                broadcast_id: broadcast.id,
                title: broadcast.title,
                body: broadcast.body,
                department_id: broadcast.department_id,
            }
        )
    );
    let recipients: Vec<String> = if let Some(dept_id) = &broadcast.department_id {
        workspace.departments.iter().find(|d| &d.id == dept_id)
            .map(|d| d.member_ids.iter().filter(|id| *id != &sender_id).cloned().collect())
            .unwrap_or_default()
    } else {
        workspace.members.iter().map(|m| m.device_id.clone()).filter(|id| id != &sender_id).collect()
    };
    for member_id in recipients {
        workspace.queue_delivery(envelope.clone(), member_id, unix_now());
    }
    workspace.touch();
    queue_workspace_sync(&mut workspace, sender_id.as_str(), &[])?;
    store.save(&workspace)?;
    retry_workplace_deliveries(app.clone()).await?;
    Ok(store.load()?.ok_or_else(|| "no workplace exists".to_string())?)
}



/// Send a text message to every current member of a workplace group.
///
/// Delivery is store-first: the local message is persisted immediately and each
/// remote recipient gets a durable pending-delivery record. A background retry
/// loop can therefore finish delivery after a peer comes back online without
/// creating duplicate messages.
#[tauri::command]
pub async fn send_workplace_group_message<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    group_id: String,
    body: String,
) -> Result<String, String> {
    let store = store(&app)?;
    let mut workspace = store.load()?.ok_or_else(|| "no workplace exists".to_string())?;
    let data_dir = setup_app_data(&app)?;
    let identity = DeviceIdentity::load_or_create(&data_dir).map_err(|e| e.to_string())?;
    let sender_id = identity.id().as_str().to_string();

    if !workspace.permissions_for(&sender_id).contains(&Permission::SendMessages) {
        return Err("you do not have permission to send workplace messages".into());
    }

    let group = workspace
        .groups
        .iter()
        .find(|g| g.id == group_id)
        .ok_or_else(|| "group not found".to_string())?
        .clone();
    if !group.member_ids.iter().any(|id| id == &sender_id) {
        return Err("you are not a member of this group".into());
    }

    let message = capsi_core::protocol::WorkplaceTextMessage::new(&group_id, &body)
        .map_err(|e| e.to_string())?;
    let envelope = capsi_core::protocol::Envelope::new(
        capsi_core::protocol::Message::WorkplaceText(message),
    );
    let envelope_id = envelope.id.clone();

    let clean_body = match &envelope.message {
        capsi_core::protocol::Message::WorkplaceText(message) => message.body.clone(),
        _ => unreachable!(),
    };
    let message_id = workspace
        .append_message(&group_id, &sender_id, clean_body)
        .ok_or_else(|| "could not store workplace message".to_string())?;

    let next_attempt_at = unix_now();
    for member_id in group.member_ids.iter().filter(|id| *id != &sender_id) {
        workspace.queue_delivery(envelope.clone(), member_id.clone(), next_attempt_at);
    }
    store.save(&workspace)?;

    // Make the first delivery attempt immediately; the durable queue remains
    // available for the background retry loop if any recipient is unavailable.
    retry_workplace_deliveries(app.clone()).await?;

    // The message id is returned once it is durably stored locally. Delivery
    // may still be pending while a recipient is offline or while its receipt is
    // in flight.
    Ok(message_id)
}

/// Retry due workplace deliveries. This is intentionally platform-neutral at
/// the protocol level: the Tauri shell only supplies the local identity, trust
/// store and app-data path.
pub async fn retry_workplace_deliveries<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
) -> Result<usize, String> {
    let store = store(&app)?;
    let mut workspace = match store.load()? {
        Some(workspace) => workspace,
        None => return Ok(0),
    };
    let data_dir = setup_app_data(&app)?;
    let identity = DeviceIdentity::load_or_create(&data_dir).map_err(|e| e.to_string())?;
    let trust = capsi_core::identity::trust::TrustStore::load(&data_dir)
        .map_err(|e| e.to_string())?;
    let now = unix_now();
    let due: Vec<_> = workspace
        .pending_deliveries
        .iter()
        .filter(|p| p.next_attempt_at <= now)
        .cloned()
        .collect();

    let mut delivered = 0usize;
    for pending in due {
        let peer_id = match capsi_core::identity::DeviceId::from_hex(&pending.recipient_device_id) {
            Ok(id) => id,
            Err(e) => {
                mark_delivery_failure(&mut workspace, &pending.envelope.id, &pending.recipient_device_id, e.to_string(), now);
                continue;
            }
        };

        let result = async {
            let peer = trust
                .get(&peer_id)
                .ok_or_else(|| "device is not known to Capsi".to_string())?;
            if !peer.is_trusted() {
                return Err("device is not trusted".to_string());
            }
            let address = peer
                .last_address
                .as_deref()
                .ok_or_else(|| "no current network address".to_string())?;
            let mut socket = address
                .parse::<std::net::SocketAddr>()
                .map_err(|e| format!("invalid network address: {e}"))?;
            socket.set_port(45892);
            capsi_core::transport::connect_and_send(
                &socket.to_string(),
                &identity,
                &peer_id,
                &pending.envelope,
            )
            .await
            .map_err(|e| e.to_string())
        }
        .await;

        match result {
            Ok(()) => {
                // Transport success is not delivery confirmation. Keep the
                // durable entry until the recipient sends DeliveryReceipt.
                if let Some(item) = workspace.pending_deliveries.iter_mut().find(|p| {
                    p.envelope.id == pending.envelope.id &&
                    p.recipient_device_id == pending.recipient_device_id
                }) {
                    item.attempts = item.attempts.saturating_add(1);
                    item.next_attempt_at = now + 60;
                    item.last_error = Some("awaiting delivery receipt".into());
                }
                delivered += 1;
            }
            Err(error) => {
                mark_delivery_failure(
                    &mut workspace,
                    &pending.envelope.id,
                    &pending.recipient_device_id,
                    error,
                    now,
                );
            }
        }
    }

    if !due.is_empty() {
        store.save(&workspace)?;
    }
    Ok(delivered)
}

fn mark_delivery_failure(
    workspace: &mut Workspace,
    envelope_id: &str,
    recipient_device_id: &str,
    error: String,
    now: i64,
) {
    if let Some(pending) = workspace.pending_deliveries.iter_mut().find(|p| {
        p.envelope.id == envelope_id && p.recipient_device_id == recipient_device_id
    }) {
        pending.attempts = pending.attempts.saturating_add(1);
        let delay = 2_i64.saturating_pow(pending.attempts.min(5)).min(60);
        pending.next_attempt_at = now + delay;
        pending.last_error = Some(error);
    }
}

pub async fn mark_workplace_delivery_delivered<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    peer_id: &capsi_core::identity::DeviceId,
    envelope_id: &str,
) -> Result<(), String> {
    let store = store(&app)?;
    let mut workspace = store.load()?.ok_or_else(|| "no workplace exists".to_string())?;
    if workspace.mark_delivery_delivered(envelope_id, peer_id.as_str()) {
        store.save(&workspace)?;
        let _ = app.emit("workplace-message-delivered", envelope_id);
    }
    Ok(())
}

fn unix_now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or_default()
}


pub fn _permission_marker(_: Permission) {}


#[tauri::command]
pub fn add_workplace_group_member<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    group_id: String,
    device_id: String,
) -> Result<Workspace, String> {
    let store = store(&app)?;
    let mut workspace = store.load()?.ok_or_else(|| "no workplace exists".to_string())?;
    let data_dir = setup_app_data(&app)?;
    let identity = DeviceIdentity::load_or_create(&data_dir).map_err(|e| e.to_string())?;
    if !workspace.permissions_for(identity.id().as_str()).contains(&Permission::ManageGroups) {
        return Err("you do not have permission to manage workplace groups".into());
    }
    if !workspace.add_to_group(&group_id, &device_id) {
        return Err("group or workplace member not found".into());
    }
    workspace.touch();
    queue_workspace_sync(&mut workspace, identity.id().as_str(), &[])?;
    store.save(&workspace)?;
    Ok(workspace)
}

#[tauri::command]
pub fn remove_workplace_group_member<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    group_id: String,
    device_id: String,
) -> Result<Workspace, String> {
    let store = store(&app)?;
    let mut workspace = store.load()?.ok_or_else(|| "no workplace exists".to_string())?;
    let data_dir = setup_app_data(&app)?;
    let identity = DeviceIdentity::load_or_create(&data_dir).map_err(|e| e.to_string())?;
    if !workspace.permissions_for(identity.id().as_str()).contains(&Permission::ManageGroups) {
        return Err("you do not have permission to manage workplace groups".into());
    }
    let Some(group) = workspace.groups.iter_mut().find(|g| g.id == group_id) else {
        return Err("group not found".into());
    };
    group.member_ids.retain(|id| id != &device_id);
    workspace.touch();
    queue_workspace_sync(&mut workspace, identity.id().as_str(), &[])?;
    store.save(&workspace)?;
    Ok(workspace)
}

#[tauri::command]
pub fn delete_workplace_group<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    group_id: String,
) -> Result<Workspace, String> {
    let store = store(&app)?;
    let mut workspace = store.load()?.ok_or_else(|| "no workplace exists".to_string())?;
    let data_dir = setup_app_data(&app)?;
    let identity = DeviceIdentity::load_or_create(&data_dir).map_err(|e| e.to_string())?;
    if !workspace.permissions_for(identity.id().as_str()).contains(&Permission::ManageGroups) {
        return Err("you do not have permission to manage workplace groups".into());
    }
    if !workspace.delete_group(&group_id) {
        return Err("group not found".into());
    }
    workspace.touch();
    queue_workspace_sync(&mut workspace, identity.id().as_str(), &[])?;
    store.save(&workspace)?;
    Ok(workspace)
}


#[tauri::command]
pub fn assign_workplace_department<R: tauri::Runtime>(
    app: tauri::AppHandle<R>,
    department_id: String,
    device_id: String,
) -> Result<Workspace, String> {
    let store = store(&app)?;
    let mut workspace = store.load()?.ok_or_else(|| "no workplace exists".to_string())?;
    let data_dir = setup_app_data(&app)?;
    let identity = DeviceIdentity::load_or_create(&data_dir).map_err(|e| e.to_string())?;
    if !workspace.permissions_for(identity.id().as_str()).contains(&Permission::ManageDepartments) {
        return Err("you do not have permission to manage workplace departments".into());
    }
    if !workspace.assign_department(&department_id, &device_id) {
        return Err("department or workplace member not found".into());
    }
    workspace.touch();
    queue_workspace_sync(&mut workspace, identity.id().as_str(), &[])?;
    store.save(&workspace)?;
    Ok(workspace)
}
