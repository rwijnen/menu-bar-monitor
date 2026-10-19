import AppKit

struct CPUReading {
    /// Percentages of total capacity across all cores (0–100).
    var total: Double = 0
    var user: Double = 0
    var system: Double = 0
    var coreCount: Int = ProcessInfo.processInfo.activeProcessorCount
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
    /// Percentage of total CPU capacity, comparable with `CPUReading.total`.
    let cpu: Double
}
