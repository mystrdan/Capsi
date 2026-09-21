//! The trust list: which devices this machine has agreed to talk to.
//!
//! Capsi shows every device it can see on the network, but a device only becomes
//! a *contact* after a human presses **Accept**. Everything else stays in the
//! "Nearby" list or is **Ignored**, and this store is the single source of truth
//! for those decisions - the UI never decides on its own.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::error::{CapsiError, Result};
use crate::identity::device::{now_secs, write_private, DeviceId, Fingerprint};

/// The three states a device can be in.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TrustState {
    /// Seen on the network, waiting for the user to Accept or Ignore.
    Pending,
    /// Accepted: messages and files may flow in both directions.
    Trusted,
    /// Ignored/Blocked: the device is still listed, but nothing is accepted.
    Blocked,
}

/// A device the user has made a decision about (or is being asked about).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KnownDevice {
    /// The peer's device id (also its Ed25519 public key, hex).
    pub device_id: DeviceId,
    /// Display name the peer advertised.
    pub name: String,
    /// User-set local label, e.g. "Dad's laptop". Falls back to `name`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub alias: Option<String>,
    pub state: TrustState,
    /// Cached short fingerprint for the UI.
    pub fingerprint: Fingerprint,
    pub first_seen: i64,
    pub last_seen: i64,
    /// Last address we saw this peer at (`ip:port`), purely cosmetic.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_address: Option<String>,
}

impl KnownDevice {
    /// What the UI should print for this contact.
    pub fn display_name(&self) -> &str {
        self.alias.as_deref().unwrap_or(&self.name)
    }

    pub fn is_trusted(&self) -> bool {
        self.state == TrustState::Trusted
    }
}

/// On-disk shape of the trust list.
#[derive(Debug, Serialize, Deserialize)]
struct TrustFile {
    version: u32,
    #[serde(default)]
    devices: Vec<KnownDevice>,
}

/// Every trust decision this machine has made, keyed by device id.
#[derive(Debug, Default)]
pub struct TrustStore {
    devices: BTreeMap<DeviceId, KnownDevice>,
    dirty: bool,
}

impl TrustStore {
    /// `…/trust.json` inside the Capsi data directory.
    pub fn path(dir: &Path) -> PathBuf {
        dir.join("trust.json")
    }

    /// Load the trust list, or start an empty one on first launch.
    pub fn load(dir: &Path) -> Result<Self> {
        let path = Self::path(dir);
        if !path.exists() {
            return Ok(Self::default());
        }
        let raw = fs::read_to_string(&path)?;
        let file: TrustFile = match serde_json::from_str(&raw) {
            Ok(file) => file,
            Err(e) => {
                // Losing the trust list is annoying but recoverable; refusing to
                // start would not be, so keep the file aside and begin fresh.
                let backup = path.with_extension(format!("corrupt-{}.bak", now_secs()));
                let _ = fs::rename(&path, backup);
                log::warn!("capsi trust list unreadable ({e}); starting a new one");
                return Ok(Self::default());
            }
        };
        Ok(Self {
            devices: file
                .devices
                .into_iter()
                .map(|d| (d.device_id.clone(), d))
                .collect(),
            dirty: false,
        })
    }

    /// Write the trust list back to disk.
    pub fn save(&self, dir: &Path) -> Result<()> {
        fs::create_dir_all(dir)?;
        let file = TrustFile {
            version: 1,
            devices: self.devices.values().cloned().collect(),
        };
        write_private(&Self::path(dir), &serde_json::to_vec_pretty(&file)?)
    }

    /// Persist only when something changed since the last save.
    pub fn save_if_dirty(&mut self, dir: &Path) -> Result<()> {
        if self.dirty {
            self.save(dir)?;
            self.dirty = false;
        }
        Ok(())
    }
}

impl TrustStore {
    /// Everyone we know about, alphabetically by display name.
    pub fn all(&self) -> Vec<KnownDevice> {
        let mut list: Vec<KnownDevice> = self.devices.values().cloned().collect();
        list.sort_by(|a, b| {
            a.display_name()
                .to_lowercase()
                .cmp(&b.display_name().to_lowercase())
        });
        list
    }

    /// Only the accepted contacts.
    pub fn trusted(&self) -> Vec<KnownDevice> {
        self.all().into_iter().filter(|d| d.is_trusted()).collect()
    }

    /// Devices waiting for a decision (drives the "Requests" badge).
    pub fn pending(&self) -> Vec<KnownDevice> {
        self.all()
            .into_iter()
            .filter(|d| d.state == TrustState::Pending)
            .collect()
    }

    pub fn get(&self, id: &DeviceId) -> Option<&KnownDevice> {
        self.devices.get(id)
    }

    /// Is this device allowed to send us payloads right now?
    pub fn is_trusted(&self, id: &DeviceId) -> bool {
        self.devices.get(id).map(|d| d.is_trusted()).unwrap_or(false)
    }

    pub fn is_blocked(&self, id: &DeviceId) -> bool {
        self.devices
            .get(id)
            .map(|d| d.state == TrustState::Blocked)
            .unwrap_or(false)
    }
}

impl TrustStore {
    /// Record a sighting of a peer.
    ///
    /// Unknown devices become [`TrustState::Pending`] so the user gets asked;
    /// known devices only get their name / address / last-seen refreshed, so an
    /// accepted contact is never silently downgraded by a later beacon.
    pub fn observe(&mut self, device_id: &DeviceId, name: &str, address: &str) -> TrustState {
        use std::collections::btree_map::Entry;
        let now = now_secs();
        match self.devices.entry(device_id.clone()) {
            Entry::Occupied(mut occ) => {
                let d = occ.get_mut();
                if d.name != name || d.last_address.as_deref() != Some(address) {
                    self.dirty = true;
                }
                d.name = name.to_string();
                d.last_address = Some(address.to_string());
                d.last_seen = now;
                d.state
            }
            Entry::Vacant(vac) => {
                vac.insert(KnownDevice {
                    device_id: device_id.clone(),
                    name: name.to_string(),
                    alias: None,
                    state: TrustState::Pending,
                    fingerprint: device_id.fingerprint(),
                    first_seen: now,
                    last_seen: now,
                    last_address: Some(address.to_string()),
                });
                self.dirty = true;
                TrustState::Pending
            }
        }
    }

    /// Accept a device ("Accept" in the UI), optionally storing a local label.
    pub fn accept(&mut self, device_id: &DeviceId, alias: Option<String>) -> Result<KnownDevice> {
        let (snapshot, changed) = {
            let entry = self.device_mut(device_id)?;
            let mut changed = false;
            if entry.state != TrustState::Trusted {
                entry.state = TrustState::Trusted;
                changed = true;
            }
            if let Some(alias) = alias.filter(|a| !a.trim().is_empty()) {
                entry.alias = Some(alias);
                changed = true;
            }
            (entry.clone(), changed)
        };
        self.dirty |= changed;
        Ok(snapshot)
    }

    /// Ignore / block a device ("Ignore" in the UI).
    ///
    /// The device stays in the list, so pressing Ignore twice is a no-op rather
    /// than a fresh request, and its history survives if the user changes mind.
    pub fn ignore(&mut self, device_id: &DeviceId) -> Result<KnownDevice> {
        let (snapshot, changed) = {
            let entry = self.device_mut(device_id)?;
            let changed = entry.state != TrustState::Blocked;
            entry.state = TrustState::Blocked;
            (entry.clone(), changed)
        };
        self.dirty |= changed;
        Ok(snapshot)
    }

    /// Set (or clear) the local label shown for a contact.
    pub fn rename(&mut self, device_id: &DeviceId, alias: Option<String>) -> Result<KnownDevice> {
        let snapshot = {
            let entry = self.device_mut(device_id)?;
            entry.alias = alias.filter(|a| !a.trim().is_empty());
            entry.clone()
        };
        self.dirty = true;
        Ok(snapshot)
    }

    /// Forget a device completely (removes trust *and* its cached address).
    pub fn forget(&mut self, device_id: &DeviceId) -> Result<()> {
        if self.devices.remove(device_id).is_some() {
            self.dirty = true;
        }
        Ok(())
    }

    /// Borrow one device, or explain which one was unknown.
    fn device_mut(&mut self, device_id: &DeviceId) -> Result<&mut KnownDevice> {
        let short = device_id.short();
        self.devices
            .get_mut(device_id)
            .ok_or_else(|| CapsiError::NotFound(format!("no nearby device {short}")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::identity::DeviceIdentity;
    use crate::util::now_ms;

    fn temp_dir(tag: &str) -> PathBuf {
        std::env::temp_dir().join(format!("capsi-trust-{tag}-{}", now_ms()))
    }

    /// A deterministic peer identity, so tests never depend on the CSPRNG.
    fn peer(seed: u8) -> DeviceId {
        DeviceIdentity::from_secrets(&[seed; 32], &[seed.wrapping_add(7); 32])
            .id()
            .clone()
    }

    #[test]
    fn unknown_devices_start_pending() {
        let id = peer(1);
        let mut store = TrustStore::default();
        assert_eq!(
            store.observe(&id, "Kitchen PC", "192.168.0.9:45893"),
            TrustState::Pending
        );
        assert!(!store.is_trusted(&id));
        assert_eq!(store.pending().len(), 1);
        assert_eq!(store.trusted().len(), 0);
    }

    #[test]
    fn accepting_promotes_without_losing_the_advertised_name() {
        let id = peer(2);
        let mut store = TrustStore::default();
        store.observe(&id, "Kitchen PC", "192.168.0.9:45893");
        let accepted = store.accept(&id, Some("Mum".into())).unwrap();
        assert_eq!(accepted.state, TrustState::Trusted);
        assert_eq!(accepted.display_name(), "Mum");
        assert_eq!(accepted.name, "Kitchen PC");
        assert!(store.is_trusted(&id));
    }

    #[test]
    fn an_accepted_contact_is_never_downgraded_by_a_later_sighting() {
        let id = peer(3);
        let mut store = TrustStore::default();
        store.observe(&id, "Old Name", "192.168.0.9:45893");
        store.accept(&id, None).unwrap();
        store.observe(&id, "New Name", "192.168.0.44:45893");
        assert!(store.is_trusted(&id));
        let known = store.get(&id).unwrap();
        assert_eq!(known.name, "New Name");
        assert_eq!(known.last_address.as_deref(), Some("192.168.0.44:45893"));
    }

    #[test]
    fn ignoring_keeps_the_device_but_stops_payloads() {
        let id = peer(4);
        let mut store = TrustStore::default();
        store.observe(&id, "Noisy TV", "192.168.0.9:45893");
        store.ignore(&id).unwrap();
        assert!(store.is_blocked(&id));
        assert!(!store.is_trusted(&id));
        assert!(store.pending().is_empty());
        assert_eq!(store.all().len(), 1);
    }

    #[test]
    fn acting_on_an_unknown_device_is_an_error() {
        let id = peer(5);
        let mut store = TrustStore::default();
        assert!(store.accept(&id, None).is_err());
        assert!(store.ignore(&id).is_err());
        assert!(store.rename(&id, Some("x".into())).is_err());
    }

    #[test]
    fn decisions_survive_a_round_trip_on_disk() {
        let dir = temp_dir("disk");
        let a = peer(6);
        let b = peer(7);
        let waiting = peer(9);
        let mut store = TrustStore::load(&dir).unwrap();
        store.observe(&a, "Studio Mac", "10.0.0.5:45893");
        store.accept(&a, Some("Design Mac".into())).unwrap();
        store.observe(&b, "Unknown", "10.0.0.6:45893");
        store.ignore(&b).unwrap();
        store.observe(&waiting, "Waiting", "10.0.0.8:45893");
        store.save(&dir).unwrap();

        let reloaded = TrustStore::load(&dir).unwrap();
        assert!(reloaded.is_trusted(&a));
        assert!(reloaded.is_blocked(&b));
        assert_eq!(reloaded.pending().len(), 1);
        assert_eq!(reloaded.all().len(), 3);
        assert_eq!(reloaded.get(&a).unwrap().display_name(), "Design Mac");
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn saving_is_skipped_when_nothing_changed() {
        let dir = temp_dir("dirty");
        let mut store = TrustStore::load(&dir).unwrap();
        store.save_if_dirty(&dir).unwrap();
        assert!(!TrustStore::path(&dir).exists(), "a clean store writes nothing");

        store.observe(&peer(10), "Laptop", "10.0.0.9:45893");
        store.save_if_dirty(&dir).unwrap();
        assert!(TrustStore::path(&dir).exists());
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn forgetting_removes_the_entry() {
        let id = peer(8);
        let mut store = TrustStore::default();
        store.observe(&id, "Temp", "10.0.0.7:45893");
        store.forget(&id).unwrap();
        assert!(store.get(&id).is_none());
        assert!(store.all().is_empty());
    }

    #[test]
    fn contacts_are_listed_alphabetically_by_display_name() {
        let mut store = TrustStore::default();
        store.observe(&peer(11), "Zeta", "10.0.0.1:1");
        store.observe(&peer(12), "alpha", "10.0.0.2:1");
        let names: Vec<String> = store.all().iter().map(|d| d.display_name().into()).collect();
        assert_eq!(names, ["alpha", "Zeta"]);
    }

    #[test]
    fn a_corrupt_trust_file_is_set_aside_not_fatal() {
        let dir = temp_dir("corrupt");
        fs::create_dir_all(&dir).unwrap();
        fs::write(TrustStore::path(&dir), b"{ oh no").unwrap();
        let store = TrustStore::load(&dir).unwrap();
        assert!(store.all().is_empty());
        // The broken file is kept for support rather than silently destroyed.
        let backups: Vec<_> = fs::read_dir(&dir)
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().contains("corrupt"))
            .collect();
        assert_eq!(backups.len(), 1);
        fs::remove_dir_all(&dir).ok();
    }
}