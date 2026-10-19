import Foundation

/// How every number on screen is written. Kept apart from the views so the
/// rounding and unit boundaries can be tested.
enum Format {
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// One decimal below 10%, for per-app shares of a many-core CPU — on a
    /// 15-core machine a busy app is often under 3% of the whole.
    static func finePercent(_ value: Double) -> String {
        value < 9.95 ? String(format: "%.1f%%", value) : percent(value)
    }

    /// Decimal units, matching Activity Monitor's network tab. Never more than
    /// four characters before the unit, so the menu bar item keeps its width.
    static func rate(_ bytesPerSecond: Double) -> String {
        let kb = bytesPerSecond / 1000
        if kb < 999.5 { return "\(Int(kb.rounded())) KB/s" }
        let mb = kb / 1000
        if mb < 99.95 { return String(format: "%.1f MB/s", mb) }
        if mb < 999.5 { return "\(Int(mb.rounded())) MB/s" }
        let gb = mb / 1000
        if gb < 99.95 { return String(format: "%.1f GB/s", gb) }
        return "\(Int(gb.rounded())) GB/s"
    }

    /// Binary gigabytes, matching how macOS reports installed memory.
    static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }

    /// Decimal units like `rate`, written the same way. ByteCountFormatter would
    /// follow the locale's decimal separator and print "2,1 GB" beside "9.8 GB".
    static func traffic(_ bytes: UInt64) -> String {
        var value = Double(bytes) / 1000
        if value < 1 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var unit = 0
        while value >= 999.5 && unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let number = value < 99.95 ? String(format: "%.1f", value) : "\(Int(value.rounded()))"
        return "\(number) \(units[unit])"
    }

    static func temperature(_ celsius: Double?) -> String {
        celsius.map { "\(Int($0.rounded()))°C" } ?? "—"
    }

    static func megahertz(_ mhz: Double?) -> String {
        mhz.map { "\(Int($0.rounded())) MHz" } ?? "—"
    }

    /// For the frequency gauge, where "1770 MHz" would not fit.
    static func gigahertz(_ mhz: Double?) -> String {
        mhz.map { String(format: "%.2f", $0 / 1000) } ?? "—"
    }

    static func load(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// "6 hours, 17 minutes": the two largest units, as Stats and `uptime` put it. In
    /// English whatever the locale, like the rest of the interface.
    static func uptime(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(seconds, 0)) / 60
        let parts = [(minutes / 1440, "day"), (minutes / 60 % 24, "hour"),
                     (minutes % 60, "minute")]
        let shown = parts.drop { $0.0 == 0 }.prefix(2).filter { $0.0 > 0 }
        guard !shown.isEmpty else { return "less than a minute" }
        return shown.map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }.joined(separator: ", ")
    }
}
