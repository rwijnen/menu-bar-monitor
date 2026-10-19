import Darwin
import Foundation
import SystemConfiguration

/// Measures throughput on the primary interface (the one macOS routes traffic
/// through), so VPN tunnels and their underlying Wi-Fi aren't counted twice.
final class NetworkSampler {
    private var previousCounters: [String: (received: UInt64, sent: UInt64)] = [:]
    private var previousTime: UInt64 = 0
    private let store = SCDynamicStoreCreate(nil, "MenuBarMonitor" as CFString, nil, nil)
    private var displayNames: [String: String] = [:]
    private var cachedAddress: (interface: String, address: String?, time: UInt64)?

    func read() -> NetworkReading {
        let now = DispatchTime.now().uptimeNanoseconds
        let counters = readCounters()
        let primary = primaryInterface()
        defer {
            previousCounters = counters
            previousTime = now
        }

        var reading = NetworkReading()
        reading.interfaceName = primary
        guard let primary else { return reading }

        reading.interfaceDisplayName = displayName(for: primary)
        reading.ipAddress = ipAddress(for: primary, now: now)

        guard previousTime > 0, let old = previousCounters[primary],
              let new = counters[primary] else { return reading }
        let elapsed = Double(now - previousTime) / 1_000_000_000
        guard elapsed > 0 else { return reading }
        // Counters reset when an interface goes down; treat that as no traffic.
        reading.downloadDelta = new.received >= old.received ? new.received - old.received : 0
        reading.uploadDelta = new.sent >= old.sent ? new.sent - old.sent : 0
        reading.downloadPerSecond = Double(reading.downloadDelta) / elapsed
        reading.uploadPerSecond = Double(reading.uploadDelta) / elapsed
        return reading
    }

    /// 64-bit byte counters per interface. `getifaddrs` only exposes 32-bit
    /// counters, which wrap every 4 GB.
    private func readCounters() -> [String: (received: UInt64, sent: UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0,
              length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return [:] }

        var result: [String: (received: UInt64, sent: UInt64)] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(info.ifm_index), &name) != nil {
                        result[String(cString: name)] =
                            (info.ifm_data.ifi_ibytes, info.ifm_data.ifi_obytes)
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return result
    }

    private func primaryInterface() -> String? {
        guard let store,
              let global = SCDynamicStoreCopyValue(
                  store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return global["PrimaryInterface"] as? String
    }

    private func displayName(for bsdName: String) -> String {
        if let cached = displayNames[bsdName] { return cached }
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        for interface in interfaces {
            if let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
               let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
                displayNames[bsd] = name
            }
        }
        let name = displayNames[bsdName] ?? (bsdName.hasPrefix("utun") ? "VPN" : bsdName)
        displayNames[bsdName] = name
        return name
    }

    /// The address rarely changes, so it's looked up at most every 10 seconds.
    private func ipAddress(for interface: String, now: UInt64) -> String? {
        if let cached = cachedAddress, cached.interface == interface,
           now - cached.time < 10_000_000_000 {
            return cached.address
        }
        var address: String?
        var list: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&list) == 0, let first = list {
            for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
                let ifa = entry.pointee
                guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                      String(cString: ifa.ifa_name) == interface else { continue }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host,
                               socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    address = String(cString: host)
                    break
                }
            }
            freeifaddrs(list)
        }
        cachedAddress = (interface, address, now)
        return address
    }
}
