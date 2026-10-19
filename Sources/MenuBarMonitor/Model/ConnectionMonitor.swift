import Foundation
import Network

/// Whether macOS has a usable path to the network, and over what.
///
/// This is the system's own view, delivered by `NWPathMonitor` as it changes. It sends
/// nothing — the app does not go online, so it cannot measure latency or prove that a
/// server out there answers; a Wi-Fi network with a dead router still counts as
/// connected. Stats pings a server for that, which this app deliberately does not.
@MainActor
final class ConnectionMonitor {
    private(set) var isConnected = false
    private(set) var connectionType: String?
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            MainActor.assumeIsolated { self?.update(path) }
        }
        monitor.start(queue: .main)
    }

    deinit {
        monitor.cancel()
    }

    private func update(_ path: NWPath) {
        isConnected = path.status == .satisfied
        connectionType = Self.typeName(path.availableInterfaces.first?.type)
    }

    nonisolated static func typeName(_ type: NWInterface.InterfaceType?) -> String? {
        switch type {
        case .wifi: "Wi-Fi"
        case .wiredEthernet: "Ethernet"
        case .cellular: "Cellular"
        case .loopback: "Loopback"
        case .other: "Other"
        case nil: nil
        @unknown default: "Other"
        }
    }
}

/// A rolling record of whether the Mac was connected at each reading, oldest first.
struct ConnectionHistory {
    static let length = 90
    private(set) var entries: [Bool] = []

    mutating func record(_ connected: Bool) {
        entries.append(connected)
        if entries.count > Self.length { entries.removeFirst(entries.count - Self.length) }
    }
}
