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
    workspace.create_department(name);
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
    workspace.create_group(name, description);
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
    workspace
        .create_broadcast(title, body, author_device_id, department_id)
        .ok_or_else(|| "invalid broadcast author or department".to_string())?;
    store.save(&workspace)?;
    Ok(workspace)
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