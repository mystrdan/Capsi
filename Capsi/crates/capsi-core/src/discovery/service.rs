//! The discovery socket loop: shout, listen, forget.
//!
//! One UDP socket does both jobs. It is bound with `SO_REUSEADDR` (and
//! `SO_REUSEPORT` where it exists) so several Capsi instances - or several user
//! sessions - can share the well-known port, and broadcasting is enabled so the
//! announcement reaches every machine on the network without a server.

use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::sync::Arc;

use tokio::net::UdpSocket;
use tokio::sync::{mpsc, Mutex};

use crate::discovery::beacon::{Beacon, Peer, PeerTable};
use crate::error::{CapsiError, Result};
use crate::identity::{DeviceId, DeviceIdentity};
use crate::util::is_lan_address;
use crate::{ANNOUNCE_INTERVAL_SECS, DISCOVERY_PORT};

/// Something the UI cares about.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DiscoveryEvent {
    /// A peer appeared, or its details changed.
    PeerFound(Peer),
    /// A peer went quiet and was dropped.
    PeerLost(DeviceId),
}

/// Runs LAN discovery for one device.
pub struct Discovery {
    socket: Arc<UdpSocket>,
    identity: Arc<DeviceIdentity>,
    device_name: String,
    tcp_port: u16,
    table: Arc<Mutex<PeerTable>>,
    /// Where announcements go. The limited broadcast address is the default;
    /// extra targets let a network that blocks it still work.
    targets: Vec<SocketAddr>,
}

impl Discovery {
    /// Bind the discovery socket on the standard Capsi port.
    pub async fn bind(
        identity: Arc<DeviceIdentity>,
        device_name: impl Into<String>,
        tcp_port: u16,
    ) -> Result<Self> {
        Self::bind_on(identity, device_name, tcp_port, DISCOVERY_PORT).await
    }

    /// Bind on a specific port.
    ///
    /// `0` asks the OS for a free port, which is what the tests use so they never
    /// fight over the real one.
    pub async fn bind_on(
        identity: Arc<DeviceIdentity>,
        device_name: impl Into<String>,
        tcp_port: u16,
        port: u16,
    ) -> Result<Self> {
        let name = crate::util::validate_device_name(&device_name.into())?;
        let socket = bind_shared_socket(port)?;
        socket
            .set_broadcast(true)
            .map_err(|e| CapsiError::Network(format!("cannot enable broadcast: {e}")))?;

        let actual_port = socket
            .local_addr()
            .map_err(|e| CapsiError::Network(e.to_string()))?
            .port();

        Ok(Self {
            socket: Arc::new(socket),
            identity,
            device_name: name,
            tcp_port,
            table: Arc::new(Mutex::new(PeerTable::new())),
            targets: vec![SocketAddr::new(IpAddr::V4(Ipv4Addr::BROADCAST), actual_port)],
        })
    }

    /// The port actually bound (useful when `0` was requested).
    pub fn local_port(&self) -> u16 {
        self.socket.local_addr().map(|a| a.port()).unwrap_or(0)
    }

    /// Replace the announcement targets.
    ///
    /// Needed for networks that block the limited broadcast address, and for
    /// tests, which point two instances straight at each other.
    pub fn set_targets(&mut self, targets: Vec<SocketAddr>) {
        self.targets = targets;
    }

    /// Everyone we can currently see.
    pub async fn peers(&self) -> Vec<Peer> {
        self.table.lock().await.online()
    }

    /// Build this device's announcement.
    pub fn beacon(&self) -> Result<Beacon> {
        Beacon::create(&self.identity, &self.device_name, self.tcp_port)
    }

    /// Send one announcement to every target, returning how many went out.
    pub async fn announce(&self) -> Result<usize> {
        let datagram = self.beacon()?.encode()?;
        let mut sent = 0;
        for target in &self.targets {
            match self.socket.send_to(&datagram, target).await {
                Ok(_) => sent += 1,
                // A network that refuses broadcast is a normal situation, not a
                // fatal one: the other targets may still work.
                Err(e) => log::debug!("capsi: announcement to {target} failed: {e}"),
            }
        }
        Ok(sent)
    }

    /// Receive and verify at most one datagram, updating the peer table.
    ///
    /// Returns the peer when the datagram was a valid beacon from someone else.
    pub async fn receive_once(&self) -> Result<Option<Peer>> {
        let mut buffer = vec![0u8; 2048];
        let (len, from) = self
            .socket
            .recv_from(&mut buffer)
            .await
            .map_err(|e| CapsiError::Network(e.to_string()))?;

        Ok(self.absorb(&buffer[..len], from).await)
    }

    /// Verify a received datagram and record it. Split out from the socket read so
    /// the whole decision path is testable without a network.
    pub async fn absorb(&self, datagram: &[u8], from: SocketAddr) -> Option<Peer> {
        // Beacons are only meaningful from another machine on this network.
        if !is_lan_address(&from.ip()) {
            log::debug!("capsi: ignoring beacon from non-LAN address {from}");
            return None;
        }
        let beacon = match Beacon::decode(datagram) {
            Ok(beacon) => beacon,
            // An unverifiable datagram is dropped without ceremony: it is either
            // a different app on this port or someone probing.
            Err(e) => {
                log::debug!("capsi: ignoring invalid beacon from {from}: {e}");
                return None;
            }
        };
        // Our own broadcast comes back to us; never list ourselves.
        if beacon.device_id == *self.identity.id() || !beacon.is_fresh(60) {
            return None;
        }
        let mut table = self.table.lock().await;
        table.observe(&beacon, from);
        table.get(&beacon.device_id).cloned()
    }

    /// Drop peers that have gone quiet, reporting which ones.
    pub async fn prune(&self) -> Vec<DeviceId> {
        self.table.lock().await.prune()
    }

    /// Run discovery forever, reporting changes on `events`.
    ///
    /// This is the only method that loops; everything else is a single step, so
    /// the behaviour can be tested and driven from the Tauri command layer.
    pub async fn run(self, events: mpsc::Sender<DiscoveryEvent>) {
        // Announcements run on their own timer, so a burst of incoming beacons
        // can never delay (or starve) our own presence.
        let announcer = self.socket.clone();
        let identity = self.identity.clone();
        let name = self.device_name.clone();
        let tcp_port = self.tcp_port;
        let targets = self.targets.clone();
        tokio::spawn(async move {
            loop {
                match Beacon::create(&identity, &name, tcp_port).and_then(|b| b.encode()) {
                    Ok(datagram) => {
                        for target in &targets {
                            let _ = announcer.send_to(&datagram, target).await;
                        }
                    }
                    Err(e) => log::warn!("capsi: could not build announcement: {e}"),
                }
                tokio::time::sleep(std::time::Duration::from_secs(ANNOUNCE_INTERVAL_SECS)).await;
            }
        });

        let mut buffer = vec![0u8; 2048];
        loop {
            // Wake up regularly even on a silent network, so peers that have gone
            // away are noticed promptly.
            let received = tokio::time::timeout(
                std::time::Duration::from_secs(ANNOUNCE_INTERVAL_SECS),
                self.socket.recv_from(&mut buffer),
            )
            .await;

            match received {
                Ok(Ok((len, from))) => {
                    if let Some(peer) = self.absorb(&buffer[..len], from).await {
                        if events.send(DiscoveryEvent::PeerFound(peer)).await.is_err() {
                            return; // the app is shutting down
                        }
                    }
                }
                Ok(Err(e)) => log::warn!("capsi: discovery socket error: {e}"),
                Err(_) => { /* idle tick */ }
            }

            for id in self.prune().await {
                if events.send(DiscoveryEvent::PeerLost(id)).await.is_err() {
                    return;
                }
            }
        }
    }
}

/// Bind a UDP socket that other Capsi instances can share.
///
/// Both `SO_REUSEADDR` and `SO_REUSEPORT` are requested where the platform has
/// them: without them a second instance on the same machine could not start. If
/// the well-known port is taken by something else entirely, we fall back to an
/// ephemeral port and log it - losing discovery beats failing to launch.
fn bind_shared_socket(port: u16) -> Result<UdpSocket> {
    let addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), port);
    match bind_with_reuse(addr) {
        Ok(socket) => Ok(socket),
        Err(e) => {
            if port == 0 {
                return Err(e);
            }
            log::warn!("capsi: cannot bind UDP {port} ({e}); using an ephemeral port");
            bind_with_reuse(SocketAddr::new(addr.ip(), 0))
        }
    }
}

/// Bind with the sharing flags set, then hand the socket to tokio.
fn bind_with_reuse(addr: SocketAddr) -> Result<UdpSocket> {
    use socket2::{Domain, Protocol, Socket, Type};

    let socket = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))
        .map_err(|e| CapsiError::Network(format!("cannot create discovery socket: {e}")))?;
    socket
        .set_reuse_address(true)
        .map_err(|e| CapsiError::Network(format!("SO_REUSEADDR failed: {e}")))?;
    // SO_REUSEPORT does not exist on Windows; SO_REUSEADDR is what matters there,
    // and on unix the extra option lets several instances share the port cleanly.
    #[cfg(unix)]
    if let Err(e) = socket.set_reuse_port(true) {
        log::debug!("capsi: SO_REUSEPORT unavailable ({e}); continuing with SO_REUSEADDR");
    }
    socket
        .set_nonblocking(true)
        .map_err(|e| CapsiError::Network(e.to_string()))?;
    socket
        .bind(&addr.into())
        .map_err(|e| CapsiError::Network(format!("cannot bind UDP {addr}: {e}")))?;

    let std_socket: std::net::UdpSocket = socket.into();
    UdpSocket::from_std(std_socket).map_err(|e| CapsiError::Network(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn identity() -> Arc<DeviceIdentity> {
        Arc::new(DeviceIdentity::generate().unwrap())
    }

    /// A discovery instance on an ephemeral port, with no broadcast traffic.
    async fn instance(name: &str) -> Discovery {
        let mut discovery = Discovery::bind_on(identity(), name, 45_893, 0).await.unwrap();
        // Point it nowhere: the tests drive announcements explicitly.
        discovery.set_targets(Vec::new());
        discovery
    }

    #[tokio::test]
    async fn an_instance_binds_and_reports_its_port() {
        let discovery = instance("Office-PC").await;
        assert_ne!(discovery.local_port(), 0);
        assert!(discovery.peers().await.is_empty());
        assert_eq!(discovery.beacon().unwrap().name, "Office-PC");
    }

    #[tokio::test]
    async fn two_instances_find_each_other_over_the_loopback() {
        let mut alice = Discovery::bind_on(identity(), "Alice", 45_893, 0)
            .await
            .unwrap();
        let mut bob = Discovery::bind_on(identity(), "Bob", 45_894, 0)
            .await
            .unwrap();

        // Aim each at the other, the way broadcast would on a real network.
        let alice_addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), alice.local_port());
        let bob_addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), bob.local_port());
        alice.set_targets(vec![bob_addr]);
        bob.set_targets(vec![alice_addr]);

        assert_eq!(alice.announce().await.unwrap(), 1);
        let seen_by_bob = bob.receive_once().await.unwrap().expect("bob sees alice");
        assert_eq!(seen_by_bob.name, "Alice");
        assert_eq!(seen_by_bob.port, 45_893);

        assert_eq!(bob.announce().await.unwrap(), 1);
        let seen_by_alice = alice.receive_once().await.unwrap().expect("alice sees bob");
        assert_eq!(seen_by_alice.name, "Bob");
        assert_eq!(seen_by_alice.port, 45_894);

        // Each side ends up with exactly one peer, and never itself.
        assert_eq!(bob.peers().await.len(), 1);
        assert_eq!(alice.peers().await.len(), 1);
    }

    #[tokio::test]
    async fn our_own_beacon_is_ignored() {
        let discovery = instance("Office-PC").await;
        let own = discovery.beacon().unwrap().encode().unwrap();
        let from = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(192, 168, 0, 5)), 1234);
        assert!(discovery.absorb(&own, from).await.is_none());
        assert!(discovery.peers().await.is_empty());
    }

    #[tokio::test]
    async fn a_forged_beacon_is_ignored() {
        let discovery = instance("Office-PC").await;
        let attacker = DeviceIdentity::generate().unwrap();
        let mut beacon = Beacon::create(&attacker, "Totally Trustworthy", 1234).unwrap();
        beacon.name = "Bank of Capsi".into();
        let datagram = serde_json::to_vec(&beacon).unwrap();
        let from = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(192, 168, 0, 6)), 1234);
        assert!(discovery.absorb(&datagram, from).await.is_none());
        assert!(discovery.peers().await.is_empty());
    }

    #[tokio::test]
    async fn beacons_from_outside_the_local_network_are_ignored() {
        let discovery = instance("Office-PC").await;
        let peer = DeviceIdentity::generate().unwrap();
        let datagram = Beacon::create(&peer, "Somewhere", 1234)
            .unwrap()
            .encode()
            .unwrap();
        // A public address: a router forwarded this, so we do not trust it.
        let from = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(203, 0, 113, 5)), 1234);
        assert!(discovery.absorb(&datagram, from).await.is_none());
        assert!(discovery.peers().await.is_empty());
    }

    #[tokio::test]
    async fn a_fresh_peer_is_reported_and_not_pruned() {
        let discovery = instance("Office-PC").await;
        let peer = DeviceIdentity::generate().unwrap();
        let datagram = Beacon::create(&peer, "Brief", 1234)
            .unwrap()
            .encode()
            .unwrap();
        let from = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(192, 168, 0, 7)), 1234);
        assert!(discovery.absorb(&datagram, from).await.is_some());
        assert_eq!(discovery.peers().await.len(), 1);
        assert!(discovery.prune().await.is_empty());
    }

    #[tokio::test]
    async fn a_device_name_is_required() {
        let result = Discovery::bind_on(identity(), "   ", 45_893, 0).await;
        assert!(result.is_err());
    }
}