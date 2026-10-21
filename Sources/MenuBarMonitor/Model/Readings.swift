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
}

struct AppUsage: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    /// Per core, as Activity Monitor counts it: 100% is one core kept busy, so a busy
    /// app can pass 100% while the machine's total stays low.
    let cpu: Double
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
