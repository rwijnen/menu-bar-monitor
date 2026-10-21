import AppKit

struct CPUReading {
    /// Percentages of total capacity across all cores (0–100).
    var total: Double = 0
    var user: Double = 0
    var system: Double = 0
    var coreCount: Int = ProcessInfo.processInfo.activeProcessorCount
    /// Each core's busy share (0–100), numbered as `host_processor_info` numbers them.
    var cores: [Double] = []
}

enum MemoryPressure {
    case normal, warning, critical

    var title: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Elevated"
        case .critical: "Critical"
        }
    }

    /// Where the pressure gauge's needle points, 0 at the left end to 1 at the right:
    /// the middle of the level's band. macOS reports three levels, not a number, so the
    /// needle does not pretend to more precision than that.
    var gaugeFraction: Double {
        switch self {
        case .normal: 1.0 / 6
        case .warning: 3.0 / 6
        case .critical: 5.0 / 6
        }
    }
}

struct MemoryReading {
    var total: UInt64 = ProcessInfo.processInfo.physicalMemory
    /// App + wired + compressed, the same figure Activity Monitor calls "Memory Used".
    var used: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var swapUsed: UInt64 = 0
    var pressure: MemoryPressure = .normal

    var usedFraction: Double { total > 0 ? min(Double(used) / Double(total), 1) : 0 }
    /// What is not counted as used, the "Free" Stats shows: it includes cached files,
    /// which macOS gives back the moment something needs the room.
    var free: UInt64 { total > used ? total - used : 0 }

    func fraction(of part: UInt64) -> Double {
        total > 0 ? Double(part) / Double(total) : 0
    }
}

struct NetworkReading {
    var downloadPerSecond: Double = 0
    var uploadPerSecond: Double = 0
    /// Bytes moved since the previous reading, used for the daily totals.
    var downloadDelta: UInt64 = 0
    var uploadDelta: UInt64 = 0
    var interfaceName: String?
    var interfaceDisplayName: String?
    var ipAddress: String?
    var hardwareAddress: String?
    /// Up and running, as `ifconfig` reports it.
    var isUp = false
    /// The interface's own counters, which start at zero when the Mac boots.
    var totalDownloaded: UInt64 = 0
    var totalUploaded: UInt64 = 0
}

struct AppUsage: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    /// In the CPU list, per core as Activity Monitor counts it: 100% is one core kept
    /// busy, so a busy app can pass 100% while the machine's total stays low. In the
    /// memory list, bytes of physical footprint.
    let value: Double
}

/// What the CPU dropdown shows beyond usage. Only read while that dropdown is open,
/// since nothing else shows it and part of it means running `ps`.
struct CPUDetails {
    /// Average of the CPU die sensors, in °C. Nil where the sensors cannot be read.
    var temperature: Double?
    /// Nil until two readings exist, or where the counters cannot be read.
    var frequency: FrequencyReading?
    /// Over the last 1, 5 and 15 minutes.
    var loadAverage: [Double] = []
    var uptime: TimeInterval = 0
    var processes: [AppUsage] = []
    /// False until the first process list arrives, so the dropdown can say so.
    var processesMeasured = false
}

/// What the memory dropdown shows beyond the breakdown. Only read while it is open.
struct MemoryDetails {
    var processes: [AppUsage] = []
    var processesMeasured = false
}

/// One app's network traffic since the previous reading.
struct NetworkAppUsage: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    let downloadPerSecond: Double
    let uploadPerSecond: Double
}

/// What the network dropdown shows beyond rates and totals.
struct NetworkDetails {
    /// Whether macOS has a usable path to the network, as it reports it. Passive: no
    /// traffic is sent to find out, so it cannot tell a dead router from a live one.
    var isConnected = false
    var connectionType: String?
    var wifi = WiFiName.State.notAsked
    var processes: [NetworkAppUsage] = []
    var processesMeasured = false
}

/// Says when something expensive is due again: at most once per `interval`.
struct Throttle {
    let interval: TimeInterval
    private var last: Date?

    init(interval: TimeInterval) { self.interval = interval }

    mutating func isDue(now: Date = Date()) -> Bool {
        if let last, now.timeIntervalSince(last) < interval { return false }
        last = now
        return true
    }

    /// The next `isDue` answers yes, whenever it is asked.
    mutating func reset() { last = nil }
}

/// Average clock speeds since the previous reading, in MHz.
struct FrequencyReading {
    struct Cluster: Equatable {
        /// Nil when no core in the cluster ran during the interval.
        var mhz: Double?
        var maxMHz: Double
        var coreCount: Int
    }

    var allCores: Double?
    /// Slowest kind of core first, as `CoreLayout` orders its groups.
    var clusters: [Cluster]

    var maxMHz: Double? { clusters.map(\.maxMHz).max() }

    /// Each core group's clock, where the clusters line up with the groups one to one.
    /// Otherwise there is no telling which is which, and only the total is shown.
    func byGroup(_ groups: [CoreGroup]) -> [(group: CoreGroup, mhz: Double?)] {
        guard clusters.count == groups.count,
              zip(clusters, groups).allSatisfy({ $0.coreCount == $1.range.count })
        else { return [] }
        return zip(groups, clusters).map { ($0, $1.mhz) }
    }
}
