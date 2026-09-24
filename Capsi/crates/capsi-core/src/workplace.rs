//! Local workplace/workspace model.
//!
//! Skeleton for Capsi's next product layer:
//! people -> groups -> departments -> broadcasts -> permissions.
//!
//! The model is local for now. It does not add accounts, cloud services, or an
//! organization server. Network propagation can be layered onto the existing
//! trusted-device protocol later.

use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

fn now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or_default()
}

fn id(prefix: &str, counter: usize) -> String {
    format!("{prefix}-{}-{counter}", now())
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum Role { Owner, Admin, Manager, Member }

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub enum Permission {
    ManageWorkspace,
    ManageMembers,
    ManageGroups,
    ManageDepartments,
    SendBroadcasts,
    SendMessages,
    TransferFiles,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Member {
    pub device_id: String,
    pub display_name: String,
    pub role: Role,
    pub department_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Group {
    pub id: String,
    pub name: String,
    pub description: String,
    pub member_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Department {
    pub id: String,
    pub name: String,
    pub member_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Broadcast {
    pub id: String,
    pub title: String,
    pub body: String,
    pub author_device_id: String,
    pub department_id: Option<String>,
    pub created_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Workspace {
    pub id: String,
    pub name: String,
    pub created_at: i64,
    pub owner_device_id: String,
    pub members: Vec<Member>,
    pub groups: Vec<Group>,
    pub departments: Vec<Department>,
    pub broadcasts: Vec<Broadcast>,
}

impl Workspace {
    pub fn new(name: impl Into<String>, owner_device_id: impl Into<String>) -> Self {
        let owner = owner_device_id.into();
        Self {
            id: format!("workspace-{}", now()),
            name: name.into(),
            created_at: now(),
            owner_device_id: owner.clone(),
            members: vec![Member {
                device_id: owner,
                display_name: String::new(),
                role: Role::Owner,
                department_id: None,
            }],
            groups: Vec::new(),
            departments: Vec::new(),
            broadcasts: Vec::new(),
        }
    }

    pub fn add_member(&mut self, device_id: impl Into<String>, display_name: impl Into<String>, role: Role) {
        let device_id = device_id.into();
        if self.members.iter().any(|m| m.device_id == device_id) { return; }
        self.members.push(Member { device_id, display_name: display_name.into(), role, department_id: None });
    }

    pub fn create_department(&mut self, name: impl Into<String>) -> String {
        let id = id("department", self.departments.len());
        self.departments.push(Department { id: id.clone(), name: name.into(), member_ids: Vec::new() });
        id
    }

    pub fn create_group(&mut self, name: impl Into<String>, description: impl Into<String>) -> String {
        let id = id("group", self.groups.len());
        self.groups.push(Group { id: id.clone(), name: name.into(), description: description.into(), member_ids: Vec::new() });
        id
    }

    pub fn add_to_group(&mut self, group_id: &str, device_id: &str) -> bool {
        if !self.members.iter().any(|m| m.device_id == device_id) { return false; }
        let Some(group) = self.groups.iter_mut().find(|g| g.id == group_id) else { return false; };
        if !group.member_ids.iter().any(|id| id == device_id) { group.member_ids.push(device_id.to_string()); }
        true
    }

    pub fn remove_from_group(&mut self, group_id: &str, device_id: &str) -> bool {
        let Some(group) = self.groups.iter_mut().find(|g| g.id == group_id) else { return false; };
        let before = group.member_ids.len();
        group.member_ids.retain(|id| id != device_id);
        before != group.member_ids.len()
    }

    pub fn delete_group(&mut self, group_id: &str) -> bool {
        let before = self.groups.len();
        self.groups.retain(|g| g.id != group_id);
        before != self.groups.len()
    }

    pub fn assign_department(&mut self, department_id: &str, device_id: &str) -> bool {
        if !self.departments.iter().any(|d| d.id == department_id) { return false; }
        let Some(member) = self.members.iter_mut().find(|m| m.device_id == device_id) else { return false; };
        member.department_id = Some(department_id.to_string());
        if let Some(department) = self.departments.iter_mut().find(|d| d.id == department_id) {
            if !department.member_ids.iter().any(|id| id == device_id) { department.member_ids.push(device_id.to_string()); }
        }
        true
    }

    pub fn create_broadcast(&mut self, title: impl Into<String>, body: impl Into<String>, author_device_id: impl Into<String>, department_id: Option<String>) -> Option<String> {
        let author = author_device_id.into();
        if !self.members.iter().any(|m| m.device_id == author) { return None; }
        if let Some(ref id) = department_id {
            if !self.departments.iter().any(|d| &d.id == id) { return None; }
        }
        let id = id("broadcast", self.broadcasts.len());
        self.broadcasts.push(Broadcast { id: id.clone(), title: title.into(), body: body.into(), author_device_id: author, department_id, created_at: now() });
        Some(id)
    }

    pub fn permissions_for(&self, device_id: &str) -> BTreeSet<Permission> {
        match self.members.iter().find(|m| m.device_id == device_id).map(|m| &m.role) {
            Some(Role::Owner) => [Permission::ManageWorkspace, Permission::ManageMembers, Permission::ManageGroups, Permission::ManageDepartments, Permission::SendBroadcasts, Permission::SendMessages, Permission::TransferFiles].into_iter().collect(),
            Some(Role::Admin) => [Permission::ManageMembers, Permission::ManageGroups, Permission::ManageDepartments, Permission::SendBroadcasts, Permission::SendMessages, Permission::TransferFiles].into_iter().collect(),
            Some(Role::Manager) => [Permission::ManageGroups, Permission::SendBroadcasts, Permission::SendMessages, Permission::TransferFiles].into_iter().collect(),
            Some(Role::Member) => [Permission::SendMessages, Permission::TransferFiles].into_iter().collect(),
            None => BTreeSet::new(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct WorkspaceStore { path: PathBuf }

impl WorkspaceStore {
    pub fn new(data_dir: &Path) -> Self { Self { path: data_dir.join("workspace.json") } }

    pub fn load(&self) -> Result<Option<Workspace>, String> {
        if !self.path.exists() { return Ok(None); }
        let bytes = fs::read(&self.path).map_err(|e| format!("cannot read workspace: {e}"))?;
        serde_json::from_slice(&bytes).map(Some).map_err(|e| format!("cannot parse workspace: {e}"))
    }

    pub fn save(&self, workspace: &Workspace) -> Result<(), String> {
        let bytes = serde_json::to_vec_pretty(workspace).map_err(|e| format!("cannot encode workspace: {e}"))?;
        fs::write(&self.path, bytes).map_err(|e| format!("cannot save workspace: {e}"))
    }

    pub fn delete(&self) -> Result<(), String> {
        if self.path.exists() { fs::remove_file(&self.path).map_err(|e| format!("cannot delete workspace: {e}"))?; }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn member_permissions_follow_role() {
        let workspace = Workspace::new("Test", "owner");
        assert!(workspace.permissions_for("owner").contains(&Permission::ManageWorkspace));
    }

    #[test]
    fn groups_and_departments_reference_known_members() {
        let mut workspace = Workspace::new("Test", "owner");
        workspace.add_member("alice", "Alice", Role::Member);
        let department = workspace.create_department("Finance");
        let group = workspace.create_group("Finance Team", "Finance staff");
        assert!(workspace.assign_department(&department, "alice"));
        assert!(workspace.add_to_group(&group, "alice"));
        assert!(workspace.remove_from_group(&group, "alice"));
        assert!(workspace.add_to_group(&group, "alice"));
        assert!(workspace.delete_group(&group));
    }

    #[test]
    fn broadcasts_require_known_author_and_department() {
        let mut workspace = Workspace::new("Test", "owner");
        let department = workspace.create_department("General");
        assert!(workspace.create_broadcast("Hello", "Welcome", "owner", Some(department)).is_some());
    }
}
