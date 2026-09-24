use serde::Serialize;
use tauri::State;

use capsi_core::{identity::DeviceIdentity, workplace::{Permission, Role, Workspace, WorkspaceStore}};

use super::setup_app_data;

#[derive(Debug, Serialize)]
pub struct WorkplaceSnapshot {
    pub workspace: Option<Workspace>,
    pub permissions: Vec<String>,
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
    store.save(&workspace)?;
    Ok(workspace)
}

#[tauri::command]
pub fn create_workplace_broadcast<R: tauri::Runtime>(
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
    if !workspace.permissions_for(identity.id().as_str()).contains(&Permission::SendBroadcasts) {
        return Err("you do not have permission to send workplace broadcasts".into());
    }
    let author_device_id = identity.id().as_str().to_string();
    workspace
        .create_broadcast(title.trim(), body.trim(), author_device_id, department_id)
        .ok_or_else(|| "invalid broadcast author or department".to_string())?;
    store.save(&workspace)?;
    Ok(workspace)
}


/// Send a text message to every current member of a workplace group.
///
/// Each recipient receives the same signed group message over its existing
/// trusted-device transport. No server or central relay is introduced.
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

    let body = body.trim_end().to_string();
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

    let trust = capsi_core::identity::trust::TrustStore::load(&data_dir)
        .map_err(|e| e.to_string())?;
    let mut failures = Vec::new();

    for member_id in group.member_ids.iter().filter(|id| *id != &sender_id) {
        let peer_id = capsi_core::identity::DeviceId::from_hex(member_id)
            .map_err(|e| e.to_string())?;
        let peer = trust
            .get(&peer_id)
            .ok_or_else(|| format!("group member {} is not known to Capsi", peer_id.short()))?;
        if !peer.is_trusted() {
            failures.push(format!("{} is not trusted", peer_id.short()));
            continue;
        }
        let address = peer
            .last_address
            .as_deref()
            .ok_or_else(|| format!("no address known for {}", peer_id.short()))?;
        let mut socket = address
            .parse::<std::net::SocketAddr>()
            .map_err(|e| format!("invalid address for {}: {e}", peer_id.short()))?;
        socket.set_port(45892);

        if let Err(e) = capsi_core::transport::connect_and_send(
            &socket.to_string(),
            &identity,
            &peer_id,
            &envelope,
        )
        .await
        {
            failures.push(format!("{}: {e}", peer_id.short()));
        }
    }

    let message_id = workspace
        .append_message(&group_id, &sender_id, body)
        .ok_or_else(|| "could not store workplace message".to_string())?;
    store.save(&workspace)?;

    if failures.is_empty() {
        Ok(message_id)
    } else {
        Err(format!(
            "message stored locally, but delivery failed: {}",
            failures.join("; ")
        ))
    }
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
    store.save(&workspace)?;
    Ok(workspace)
}
