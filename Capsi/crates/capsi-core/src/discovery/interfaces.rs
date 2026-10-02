//! Working out *where* an announcement should be sent.
//!
//! A datagram addressed to the limited broadcast address `255.255.255.255`
//! leaves the machine through exactly one interface: whichever one the routing
//! table happens to pick for that address. On a machine with more than one
//! interface that is often not the one the other Capsi device is on, and on a
//! phone sharing its own hotspot it is the mobile connection - so the
//! announcement is handed to the carrier and disappears. In both cases the
//! other device simply never hears us, even though every setting is correct.
//!
//! So instead of one address we announce to the *subnet-directed* broadcast
//! address of every interface this machine is on: `192.168.43.255` for a phone
//! tethering on `192.168.43.0/24`, `10.7.255.255` for a `10.7.0.0/16`, and so
//! on. Those addresses belong to a directly connected network, so the routing
//! table sends each one out of its own interface and every network we are
//! attached to actually receives the announcement.
//!
//! The limited broadcast address is kept at the end of the list as well: it is
//! the traditional fallback for networks that cannot be described by an address
//! and a netmask (and for the platforms whose interfaces we cannot read).

use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4};

/// Every address a Capsi announcement should be sent to on `port`.
///
/// The list is deduplicated, and always ends with the limited broadcast address
/// so that a machine whose interfaces cannot be read still announces the
/// original way.
pub fn announce_targets(port: u16) -> Vec<SocketAddr> {
    let mut targets: Vec<SocketAddr> = Vec::new();
    for address in local_broadcasts() {
        let target = SocketAddr::V4(SocketAddrV4::new(address, port));
        if !targets.contains(&target) {
            targets.push(target);
        }
    }
    let limited = SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::BROADCAST, port));
    if !targets.contains(&limited) {
        targets.push(limited);
    }
    targets
}

/// The broadcast address of the network an address/netmask pair describes.
///
/// `None` when the pair does not describe a network that has a broadcast
/// address: the loopback interface, an address that has not been assigned yet,
/// or a point-to-point link (`/31` and `/32`, RFC 3021), which has none.
fn directed_broadcast(address: Ipv4Addr, netmask: Ipv4Addr) -> Option<Ipv4Addr> {
    if address.is_loopback() || address.is_unspecified() {
        return None;
    }
    // A mask that covers the address itself leaves no room for a broadcast
    // address. Testing the mask rather than the result also covers a /31, where
    // the "broadcast" would collide with the other end of the link.
    if u32::from(netmask).count_ones() >= 31 {
        return None;
    }
    Some(Ipv4Addr::from(u32::from(address) | !u32::from(netmask)))
}

/// The broadcast address of every interface this machine is attached to.
///
/// `getifaddrs` is the POSIX way to ask, so Linux, Android, macOS and iOS all
/// take this path.
#[cfg(unix)]
fn local_broadcasts() -> Vec<Ipv4Addr> {
    let mut found = Vec::new();
    // SAFETY: `getifaddrs` fills in a list of nodes that we own. We only read
    // from it while it is alive, and free it exactly once at the end.
    unsafe {
        let mut head: *mut libc::ifaddrs = std::ptr::null_mut();
        if libc::getifaddrs(&mut head) != 0 {
            return found;
        }
        let mut entry = head;
        while !entry.is_null() {
            if let Some(broadcast) = interface_broadcast(entry) {
                found.push(broadcast);
            }
            entry = (*entry).ifa_next;
        }
        libc::freeifaddrs(head);
    }
    found
}

/// The broadcast address of one `getifaddrs` entry, if it is one we should
/// announce on.
///
/// Interfaces that are down, have no broadcast address of their own (a tunnel,
/// or a point-to-point link) and the loopback interface are skipped: a datagram
/// sent to any of them can never reach another device.
///
/// # Safety
///
/// `entry` must be a node from a live `getifaddrs` list.
#[cfg(unix)]
unsafe fn interface_broadcast(entry: *const libc::ifaddrs) -> Option<Ipv4Addr> {
    let entry = &*entry;
    let flags = entry.ifa_flags as libc::c_int;
    let announceable = flags & libc::IFF_UP != 0
        && flags & libc::IFF_BROADCAST != 0
        && flags & libc::IFF_LOOPBACK == 0;
    if !announceable || entry.ifa_addr.is_null() || entry.ifa_netmask.is_null() {
        return None;
    }
    if (*entry.ifa_addr).sa_family != libc::AF_INET as libc::sa_family_t {
        return None;
    }
    let address = sockaddr_to_ipv4(entry.ifa_addr);
    let netmask = sockaddr_to_ipv4(entry.ifa_netmask);
    directed_broadcast(address, netmask)
}

/// The IPv4 address stored inside a `sockaddr`.
///
/// # Safety
///
/// `address` must point at a `sockaddr_in`.
#[cfg(unix)]
unsafe fn sockaddr_to_ipv4(address: *const libc::sockaddr) -> Ipv4Addr {
    let address = &*(address as *const libc::sockaddr_in);
    // `s_addr` is kept in network byte order, so it is swapped back before it
    // can be read as a number.
    Ipv4Addr::from(u32::from_be(address.sin_addr.s_addr))
}

/// The broadcast address of every interface this machine is attached to.
///
/// This reads the Windows IPv4 address table, which lists an address and a
/// netmask for each interface - exactly the pair we need.
#[cfg(windows)]
fn local_broadcasts() -> Vec<Ipv4Addr> {
    use windows_sys::Win32::Foundation::{
        ERROR_BUFFER_OVERFLOW, ERROR_INSUFFICIENT_BUFFER, ERROR_SUCCESS,
    };
    use windows_sys::Win32::NetworkManagement::IpHelper::{GetIpAddrTable, MIB_IPADDRTABLE};

    let mut found = Vec::new();

    // A null table asks the call to report how much room the real one needs; it
    // says so by failing. Which code it uses is not consistent between the IP
    // helper calls - this one documents ERROR_INSUFFICIENT_BUFFER, while
    // GetAdaptersAddresses uses ERROR_BUFFER_OVERFLOW - so both are accepted.
    let mut size: u32 = 0;
    // SAFETY: a null table with a size output is the documented way to measure.
    let probe = unsafe { GetIpAddrTable(std::ptr::null_mut(), &mut size, 0) };
    let wants_room = probe == ERROR_INSUFFICIENT_BUFFER || probe == ERROR_BUFFER_OVERFLOW;
    if !wants_room || size < std::mem::size_of::<u32>() as u32 {
        log::debug!("capsi: cannot measure the IPv4 address table (error {probe})");
        return found;
    }

    // The row type wants four-byte alignment, which `Vec<u32>` gives us. The
    // extra word covers the division rounding the requested size down.
    let mut room = vec![0u32; size as usize / 4 + 1];
    let mut size = (room.len() * std::mem::size_of::<u32>()) as u32;
    let table = room.as_mut_ptr() as *mut MIB_IPADDRTABLE;
    // SAFETY: `table` points at `room.len() * 4` bytes, which is at least the
    // size the probe above asked for.
    if unsafe { GetIpAddrTable(table, &mut size, 0) } != ERROR_SUCCESS {
        return found;
    }

    // SAFETY: the call succeeded, so the header and the `dwNumEntries` rows
    // that follow it are filled in and inside the buffer we allocated.
    let rows = unsafe {
        let count = (*table).dwNumEntries as usize;
        std::slice::from_raw_parts((*table).table.as_ptr(), count)
    };
    for row in rows {
        // Both fields are in network byte order.
        let address = Ipv4Addr::from(u32::from_be(row.dwAddr));
        let netmask = Ipv4Addr::from(u32::from_be(row.dwMask));
        if let Some(broadcast) = directed_broadcast(address, netmask) {
            found.push(broadcast);
        }
    }
    found
}

/// A platform whose interfaces we cannot read still gets the limited broadcast
/// address, which `announce_targets` always adds.
#[cfg(not(any(unix, windows)))]
fn local_broadcasts() -> Vec<Ipv4Addr> {
    Vec::new()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ip(text: &str) -> Ipv4Addr {
        text.parse().unwrap()
    }

    #[test]
    fn a_home_network_becomes_its_subnet_broadcast() {
        assert_eq!(
            directed_broadcast(ip("192.168.1.24"), ip("255.255.255.0")),
            Some(ip("192.168.1.255"))
        );
    }

    #[test]
    fn a_phone_hotspot_is_announced_on() {
        // Android tethering hands out 192.168.43.0/24 on most phones and
        // 192.168.232.0/24 on others.
        assert_eq!(
            directed_broadcast(ip("192.168.43.5"), ip("255.255.255.0")),
            Some(ip("192.168.43.255"))
        );
        assert_eq!(
            directed_broadcast(ip("192.168.232.42"), ip("255.255.255.0")),
            Some(ip("192.168.232.255"))
        );
    }

    #[test]
    fn a_slash_sixteen_keeps_everything_the_mask_does_not_cover() {
        assert_eq!(
            directed_broadcast(ip("10.7.3.9"), ip("255.255.0.0")),
            Some(ip("10.7.255.255"))
        );
    }

    #[test]
    fn an_uneven_mask_is_handled_bit_by_bit() {
        assert_eq!(
            directed_broadcast(ip("172.16.5.9"), ip("255.255.252.0")),
            Some(ip("172.16.7.255"))
        );
    }

    #[test]
    fn a_point_to_point_link_has_no_broadcast_address() {
        // /31: the "broadcast" would be the other end of the link (RFC 3021).
        assert_eq!(
            directed_broadcast(ip("10.0.0.1"), ip("255.255.255.254")),
            None
        );
        // /32: a single host.
        assert_eq!(
            directed_broadcast(ip("10.0.0.1"), ip("255.255.255.255")),
            None
        );
    }

    #[test]
    fn loopback_and_unassigned_addresses_are_never_announced_on() {
        assert_eq!(directed_broadcast(ip("127.0.0.1"), ip("255.0.0.0")), None);
        assert_eq!(directed_broadcast(ip("0.0.0.0"), ip("0.0.0.0")), None);
    }

    #[test]
    fn the_limited_broadcast_address_is_always_a_target() {
        let targets = announce_targets(45_893);
        assert!(targets.contains(&SocketAddr::from((Ipv4Addr::BROADCAST, 45_893))));
    }

    #[test]
    fn targets_are_unique_and_carry_the_requested_port() {
        let mut seen: Vec<SocketAddr> = Vec::new();
        for target in announce_targets(1234) {
            assert!(!seen.contains(&target), "{target} appears twice");
            assert_eq!(target.port(), 1234);
            seen.push(target);
        }
    }

    #[test]
    fn no_interface_is_announced_on_through_loopback_or_unassigned_addresses() {
        for target in announce_targets(45_893) {
            let SocketAddr::V4(v4) = target else {
                panic!("{target} is not an IPv4 target");
            };
            let address = *v4.ip();
            if address == Ipv4Addr::BROADCAST {
                continue;
            }
            assert!(!address.is_loopback(), "{target} is a loopback address");
            assert!(!address.is_unspecified(), "{target} is an unassigned address");
        }
    }
}