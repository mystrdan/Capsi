//! Finding other Capsi devices on the local network.
//!
//! ```text
//! discovery/
//!   beacon   - the signed UDP announcement, and the table of peers we have seen
//!   service  - the socket loop: announce, listen, forget peers that go quiet
//! ```
//!
//! There is no server and no directory: a device shouts its name on the network
//! every few seconds, and everyone else listens. Because the shout is signed with
//! the sender's Ed25519 key, a name or port cannot be spoofed - the receiver
//! checks the signature against the device id that the trust list pins.

pub mod beacon;
pub mod service;

pub use beacon::{Beacon, Peer, PeerTable};
pub use service::{Discovery, DiscoveryEvent};