//! The signed UDP beacon, and the table of peers built from beacons.
//!
//! A beacon is one datagram - deliberately tiny and stateless, because it is
//! broadcast several times a second and dropped by everyone who does not care.

use std::collections::BTreeMap;
use std::net::SocketAddr;

use serde::{Deserialize, Serialize};

use crate::error::{CapsiError, Result};
use crate::identity::{DeviceId, DeviceIdentity, Fingerprint};
use crate::util::now;
use crate::{PEER_TIMEOUT_SECS, PROTOCOL_VERSION};

/// Domain-separation label for the beacon signature.
const BEACON_LABEL: &[u8] = b"capsi/1/beacon";

/// "I am here" - broadcast on the local network.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Beacon {
    /// Protocol version, so an incompatible peer is ignored rather than guessed at.
    #[serde(rename = "capsi")]
    pub version: String,
    /// Who is speaking (also the Ed25519 public key).
    pub device_id: DeviceId,
    /// The human-readable name the user chose, e.g. "Office-PC".
    pub name: String,
    /// The TCP port this device listens on for messages and files.
    pub port: u16,
    /// Unix seconds, used to ignore replays of an old announcement.
    pub sent_at: i64,
    /// Ed25519 signature over [`Self::signed_bytes`].
    pub signature: String,
}

impl Beacon {
    /// Build and sign a beacon for this device.
    pub fn create(identity: &DeviceIdentity, name: &str, port: u16) -> Result<Self> {
        let name = crate::util::validate_device_name(name)?;
        let mut beacon = Self {
            version: PROTOCOL_VERSION.to_string(),
            device_id: identity.id().clone(),
            name,
            port,
            sent_at: now(),
            signature: String::new(),
        };
        beacon.signature = identity.sign_hex(&beacon.signed_bytes());
        Ok(beacon)
    }

    /// The exact bytes covered by the signature.
    ///
    /// Field order is fixed and every field is included, so a peer cannot keep
    /// the signature while changing the port or the name.
    pub fn signed_bytes(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(160);
        out.extend_from_slice(BEACON_LABEL);
        out.extend_from_slice(b"|");
        out.extend_from_slice(self.device_id.as_str().as_bytes());
        out.extend_from_slice(b"|");
        out.extend_from_slice(self.name.as_bytes());
        out.extend_from_slice(b"|");
        out.extend_from_slice(self.port.to_string().as_bytes());
        out.extend_from_slice(b"|");
        out.extend_from_slice(self.sent_at.to_string().as_bytes());
        out
    }

    /// Verify the signature against the device id the beacon claims.
    pub fn verify(&self) -> Result<()> {
        if self.version != PROTOCOL_VERSION {
            return Err(CapsiError::Protocol(format!(
                "beacon speaks {} but this is {PROTOCOL_VERSION}",
                self.version
            )));
        }
        // A port of 0 is not something anyone can connect to.
        if self.port == 0 {
            return Err(CapsiError::Protocol("beacon advertised port 0".into()));
        }
        crate::util::validate_device_name(&self.name)?;
        let key = DeviceIdentity::peer_verifying_key(&self.device_id)?;
        DeviceIdentity::verify_hex(&key, &self.signed_bytes(), &self.signature)
    }

    /// True when the announcement is fresh enough to act on.
    ///
    /// A beacon from the future is treated as stale too: that means clock skew or
    /// a replay, and neither should make a peer appear permanently online.
    pub fn is_fresh(&self, tolerance_secs: i64) -> bool {
        let age = now() - self.sent_at;
        let horizon = PEER_TIMEOUT_SECS as i64 + tolerance_secs.max(0);
        (-tolerance_secs..=horizon).contains(&age)
    }

    /// Parse and fully verify a datagram. Anything else is dropped silently.
    pub fn decode(bytes: &[u8]) -> Result<Self> {
        let beacon: Self = serde_json::from_slice(bytes)?;
        beacon.verify()?;
        Ok(beacon)
    }

    /// Serialise for broadcast.
    pub fn encode(&self) -> Result<Vec<u8>> {
        Ok(serde_json::to_vec(self)?)
    }
}

/// Another Capsi device we can currently see.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Peer {
    /// The peer's device id.
    pub device_id: DeviceId,
    /// Name it advertised.
    pub name: String,
    /// Where the beacon came from (used for diagnostics and the UI).
    pub address: SocketAddr,
    /// The port it listens on for connections.
    pub port: u16,
    /// Short fingerprint for the "Accept" prompt.
    pub fingerprint: Fingerprint,
    /// Unix seconds of the most recent beacon.
    pub last_seen: i64,
}

impl Peer {
    /// `192.168.0.9:45893` - the TCP address to dial.
    pub fn tcp_address(&self) -> String {
        format!("{}:{}", self.address.ip(), self.port)
    }

    /// Has this peer gone quiet for longer than [`PEER_TIMEOUT_SECS`]?
    pub fn is_stale(&self, now: i64) -> bool {
        now - self.last_seen > PEER_TIMEOUT_SECS as i64
    }
}

/// The set of peers currently visible, keyed by device id.
///
/// Keying on the device id (not the IP) is what makes a laptop that moves between
/// Wi-Fi and ethernet stay one contact instead of becoming two.
#[derive(Debug, Default)]
pub struct PeerTable {
    peers: BTreeMap<DeviceId, Peer>,
}

impl PeerTable {
    pub fn new() -> Self {
        Self::default()
    }

    /// Apply a verified beacon.
    ///
    /// Returns `true` when this is a peer we had not seen before, which is what
    /// the UI uses to know it should raise a notification.
    pub fn observe(&mut self, beacon: &Beacon, from: SocketAddr) -> bool {
        let is_new = !self.peers.contains_key(&beacon.device_id);
        let entry = Peer {
            device_id: beacon.device_id.clone(),
            name: beacon.name.clone(),
            address: from,
            port: beacon.port,
            fingerprint: beacon.device_id.fingerprint(),
            last_seen: now(),
        };
        self.peers.insert(beacon.device_id.clone(), entry);
        is_new
    }

    /// Drop peers that have gone quiet; returns the ids that were forgotten.
    pub fn prune(&mut self) -> Vec<DeviceId> {
        let now = now();
        let stale: Vec<DeviceId> = self
            .peers
            .iter()
            .filter(|(_, peer)| peer.is_stale(now))
            .map(|(id, _)| id.clone())
            .collect();
        for id in &stale {
            self.peers.remove(id);
        }
        stale
    }

    pub fn get(&self, id: &DeviceId) -> Option<&Peer> {
        self.peers.get(id)
    }

    /// Everyone currently visible, newest sighting first.
    pub fn online(&self) -> Vec<Peer> {
        let mut list: Vec<Peer> = self.peers.values().cloned().collect();
        list.sort_by(|a, b| {
            b.last_seen
                .cmp(&a.last_seen)
                .then_with(|| a.name.cmp(&b.name))
        });
        list
    }

    pub fn len(&self) -> usize {
        self.peers.len()
    }

    pub fn is_empty(&self) -> bool {
        self.peers.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{IpAddr, Ipv4Addr};

    fn addr(port: u16) -> SocketAddr {
        SocketAddr::new(IpAddr::V4(Ipv4Addr::new(192, 168, 0, 9)), port)
    }

    fn identity() -> DeviceIdentity {
        DeviceIdentity::generate().unwrap()
    }

    #[test]
    fn a_beacon_verifies_against_its_own_device_id() {
        let id = identity();
        let beacon = Beacon::create(&id, "Office-PC", 45893).unwrap();
        assert!(beacon.verify().is_ok());
        assert_eq!(beacon.version, PROTOCOL_VERSION);
        assert_eq!(beacon.device_id, *id.id());
        // And it survives the round trip through a datagram.
        let decoded = Beacon::decode(&beacon.encode().unwrap()).unwrap();
        assert_eq!(decoded, beacon);
    }

    #[test]
    fn a_beacon_with_a_changed_name_or_port_is_rejected() {
        let id = identity();
        let mut renamed = Beacon::create(&id, "Office-PC", 45893).unwrap();
        renamed.name = "Evil-PC".into();
        assert!(renamed.verify().is_err());

        let mut port_swap = Beacon::create(&id, "Office-PC", 45893).unwrap();
        port_swap.port = 1;
        assert!(port_swap.verify().is_err());
    }

    #[test]
    fn a_beacon_from_an_unknown_key_is_rejected() {
        let real = identity();
        let attacker = identity();
        let mut beacon = Beacon::create(&attacker, "Attacker", 1234).unwrap();
        // Claim to be the real device while signing with our own key.
        beacon.device_id = real.id().clone();
        assert!(beacon.verify().is_err());
    }

    #[test]
    fn malformed_beacons_are_refused() {
        let id = identity();

        let mut no_port = Beacon::create(&id, "Office-PC", 45893).unwrap();
        no_port.port = 0;
        assert!(no_port.verify().is_err());

        let mut wrong_version = Beacon::create(&id, "Office-PC", 45893).unwrap();
        wrong_version.version = "capsi/2".into();
        assert!(wrong_version.verify().is_err());

        let mut blank_name = Beacon::create(&id, "Office-PC", 45893).unwrap();
        blank_name.name = "   ".into();
        assert!(blank_name.verify().is_err());

        // Not JSON at all.
        assert!(Beacon::decode(b"\x00\x01\x02").is_err());
    }

    #[test]
    fn beacon_names_are_validated_when_created() {
        let id = identity();
        assert!(Beacon::create(&id, "", 1000).is_err());
        assert!(Beacon::create(&id, &"x".repeat(40), 1000).is_err());
        assert_eq!(
            Beacon::create(&id, "  Kitchen  ", 1000).unwrap().name,
            "Kitchen"
        );
    }

    #[test]
    fn freshness_rejects_ancient_and_future_beacons() {
        let id = identity();
        let mut beacon = Beacon::create(&id, "Office-PC", 45893).unwrap();
        assert!(beacon.is_fresh(5));

        beacon.sent_at = now() - 3600;
        assert!(!beacon.is_fresh(5));

        beacon.sent_at = now() + 3600;
        assert!(!beacon.is_fresh(5));
    }

    #[test]
    fn a_table_remembers_peers_and_prunes_the_quiet_ones() {
        let id = identity();
        let beacon = Beacon::create(&id, "Kitchen PC", 4444).unwrap();
        let mut table = PeerTable::new();
        assert!(table.observe(&beacon, addr(4444)), "first sighting is new");
        assert!(!table.observe(&beacon, addr(4444)), "second sighting is not");
        assert_eq!(table.len(), 1);

        let peer = table.get(id.id()).unwrap();
        assert_eq!(peer.name, "Kitchen PC");
        assert_eq!(peer.tcp_address(), "192.168.0.9:4444");
        assert!(!peer.is_stale(now()));
    }

    #[test]
    fn a_peer_that_goes_quiet_is_forgotten() {
        let id = identity();
        let beacon = Beacon::create(&id, "Kitchen PC", 4444).unwrap();
        let mut table = PeerTable::new();
        table.observe(&beacon, addr(4444));
        // Age the peer as if it had gone away.
        table.peers.get_mut(id.id()).unwrap().last_seen = now() - PEER_TIMEOUT_SECS as i64 - 1;
        let forgotten = table.prune();
        assert_eq!(forgotten.len(), 1);
        assert!(table.is_empty());
    }

    #[test]
    fn a_peer_that_moves_keeps_one_identity() {
        let id = identity();
        let beacon = Beacon::create(&id, "Laptop", 45893).unwrap();
        let mut table = PeerTable::new();
        table.observe(&beacon, addr(45893));
        // Same device seen again from the same place.
        table.observe(&beacon, addr(45893));
        assert_eq!(table.len(), 1);
    }

    #[test]
    fn online_peers_are_sorted_newest_first() {
        let a = identity();
        let b = identity();
        let mut table = PeerTable::new();
        table.observe(&Beacon::create(&a, "Alpha", 1).unwrap(), addr(1));
        table.observe(&Beacon::create(&b, "Beta", 2).unwrap(), addr(2));
        table.peers.get_mut(a.id()).unwrap().last_seen = now() - 5;
        let online = table.online();
        assert_eq!(online.len(), 2);
        assert_eq!(online[0].name, "Beta");
    }
}