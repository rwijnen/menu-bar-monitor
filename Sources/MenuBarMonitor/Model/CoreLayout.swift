import Darwin
import Foundation

/// One kind of core, and which of the numbered cores are that kind.
struct CoreGroup: Equatable, Identifiable {
    let name: String
    /// Core numbers as `host_processor_info` reports them.
    let range: Range<Int>

    var id: String { name }

    /// Average busy share of this group's cores.
    func usage(in cores: [Double]) -> Double? {
        let mine = range.filter { $0 < cores.count }.map { cores[$0] }
        return mine.isEmpty ? nil : mine.reduce(0, +) / Double(mine.count)
    }
}

/// Which cores are which kind — on an M5 Pro, ten Performance cores then five Super
/// cores; on an M1, four Efficiency cores then four Performance cores.
enum CoreLayout {
    /// `sysctl` lists the kinds fastest first (perflevel0), while the cores are numbered
    /// slowest first, so the levels are taken in reverse. Anything that does not add up
    /// — an Intel Mac has no perflevels at all — is shown as one group.
    static func groups(levels: [(name: String, count: Int)], coreCount: Int) -> [CoreGroup] {
        let fallback = [CoreGroup(name: "Cores", range: 0..<coreCount)]
        guard levels.count > 1, levels.map(\.count).reduce(0, +) == coreCount,
              levels.allSatisfy({ $0.count > 0 && !$0.name.isEmpty })
        else { return fallback }

        var start = 0
        return levels.reversed().map { level in
            defer { start += level.count }
            return CoreGroup(name: level.name, range: start..<(start + level.count))
        }
    }

    static func current(coreCount: Int) -> [CoreGroup] {
        let levelCount = SystemInfo.integer("hw.nperflevels") ?? 0
        let levels = (0..<max(levelCount, 0)).map { index in
            (name: SystemInfo.string("hw.perflevel\(index).name") ?? "",
             count: SystemInfo.integer("hw.perflevel\(index).logicalcpu") ?? 0)
        }
        return groups(levels: levels, coreCount: coreCount)
    }
}

enum SystemInfo {
    /// Over the last 1, 5 and 15 minutes, as `uptime` prints them.
    static func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) == 3 ? loads : []
    }

    static func uptime(now: Date = Date()) -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return 0 }
        let booted = Date(timeIntervalSince1970: TimeInterval(boot.tv_sec)
                          + TimeInterval(boot.tv_usec) / 1_000_000)
        return max(now.timeIntervalSince(booted), 0)
    }

    /// "Apple M5 Pro", or the Intel brand string.
    static var chipName: String? { string("machdep.cpu.brand_string") }

    static func integer(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
