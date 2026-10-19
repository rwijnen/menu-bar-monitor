import Darwin
import Foundation
import SystemConfiguration

/// Measures throughput on the primary interface (the one macOS routes traffic
/// through), so VPN tunnels and their underlying Wi-Fi aren't counted twice.
final class NetworkSampler {
    private typealias Counters = (received: UInt64, sent: UInt64)

    private var previous: (interface: String, counters: Counters, time: UInt64)?
    private let store = SCDynamicStoreCreate(nil, "MenuBarMonitor" as CFString, nil, nil)
    private var names: [String: (display: String, hardware: String?)] = [:]

    func read() -> NetworkReading {
        let now = DispatchTime.now().uptimeNanoseconds
        var reading = NetworkReading()
        guard let primary = primaryInterface() else {
            previous = nil
            return reading
        }
        reading.interfaceName = primary
        let name = names(for: primary)
        reading.interfaceDisplayName = name.display
        reading.hardwareAddress = name.hardware
        let info = Self.interfaceInfo(for: primary)
        reading.ipAddress = info.ipv4
        reading.isUp = info.isUp

        guard let counters = Self.counters(for: primary) else { return reading }
        reading.totalDownloaded = counters.received
        reading.totalUploaded = counters.sent
        defer { previous = (primary, counters, now) }

        // A different interface than last time (Wi-Fi to Ethernet, say) has its own
        // counters; comparing them would make up a burst of traffic.
        guard let previous, previous.interface == primary, now > previous.time
        else { return reading }
        let elapsed = Double(now - previous.time) / 1_000_000_000
        let old = previous.counters
        // Counters reset when an interface goes down; treat that as no traffic.
        reading.downloadDelta = counters.received >= old.received
            ? counters.received - old.received : 0
        reading.uploadDelta = counters.sent >= old.sent ? counters.sent - old.sent : 0
        reading.downloadPerSecond = Double(reading.downloadDelta) / elapsed
        reading.uploadPerSecond = Double(reading.uploadDelta) / elapsed
        return reading
    }

    /// 64-bit byte counters for one interface, from the interface MIB — the source
    /// `netstat -ib` uses. `getifaddrs` only has 32-bit counters, and so, in practice,
    /// does `NET_RT_IFLIST2`: its `if_data64` has 64-bit fields, but on an M5 Pro under
    /// macOS 27 the Wi-Fi download counter in it still wrapped at 4 GB, reading 1.16 GB
    /// where `netstat` said 5.46.
    private static func counters(for interface: String) -> Counters? {
        let index = if_nametoindex(interface)
        guard index > 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA,
                            Int32(index), IFDATA_GENERAL]
        var data = ifmibdata()
        var size = MemoryLayout<ifmibdata>.size
        guard sysctl(&mib, UInt32(mib.count), &data, &size, nil, 0) == 0 else { return nil }
        return (data.ifmd_data.ifi_ibytes, data.ifmd_data.ifi_obytes)
    }

    private func primaryInterface() -> String? {
        guard let store,
              let global = SCDynamicStoreCopyValue(
                  store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return global["PrimaryInterface"] as? String
    }

    /// The interface's name as System Settings shows it, and its hardware address.
    /// The address comes from System Configuration because `getifaddrs` hands ordinary
    /// apps a placeholder, 02:00:00:00:00:00. It is the address the hardware was made
    /// with; with a private Wi-Fi address on, the network sees a different one.
    private func names(for bsdName: String) -> (display: String, hardware: String?) {
        if let cached = names[bsdName] { return cached }
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        for interface in interfaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            let display = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? bsd
            let hardware = SCNetworkInterfaceGetHardwareAddressString(interface) as String?
            names[bsd] = (display, hardware)
        }
        let found = names[bsdName] ?? (bsdName.hasPrefix("utun") ? "VPN" : bsdName, nil)
        names[bsdName] = found
        return found
    }

    /// The interface's IPv4 address and whether it is up and running, from one walk of
    /// `getifaddrs` — a local list, so cheap enough for every reading.
    static func interfaceInfo(for interface: String) -> (ipv4: String?, isUp: Bool) {
        var ipv4: String?, isUp = false
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (nil, false) }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = entry.pointee
            guard String(cString: ifa.ifa_name) == interface, let addr = ifa.ifa_addr
            else { continue }
            let flags = Int32(ifa.ifa_flags)
            isUp = isUp || (flags & IFF_UP != 0 && flags & IFF_RUNNING != 0)
            guard ipv4 == nil, Int32(addr.pointee.sa_family) == AF_INET else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host,
                           socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                ipv4 = String(cString: host)
            }
        }
        return (ipv4, isUp)
    }
}
