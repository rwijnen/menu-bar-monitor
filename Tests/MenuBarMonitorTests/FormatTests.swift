import Foundation
import Testing

@testable import MenuBarMonitor

@Suite("Formatting")
struct FormatTests {

    @Test("percentages round to whole numbers")
    func percent() {
        #expect(Format.percent(0) == "0%")
        #expect(Format.percent(23.4) == "23%")
        #expect(Format.percent(23.5) == "24%")
        #expect(Format.percent(100) == "100%")
    }

    @Test("app shares keep one decimal below ten per cent")
    func finePercent() {
        #expect(Format.finePercent(0.04) == "0.0%")
        #expect(Format.finePercent(2.46) == "2.5%")
        #expect(Format.finePercent(9.94) == "9.9%")
        #expect(Format.finePercent(9.96) == "10%")
        #expect(Format.finePercent(31.2) == "31%")
    }

    @Test("rates switch unit at each boundary", arguments: [
        (0.0, "0 KB/s"),
        (499.0, "0 KB/s"),
        (120_000.0, "120 KB/s"),
        (999_400.0, "999 KB/s"),
        (999_600.0, "1.0 MB/s"),
        (1_400_000.0, "1.4 MB/s"),
        (99_940_000.0, "99.9 MB/s"),
        (99_960_000.0, "100 MB/s"),
        (999_400_000.0, "999 MB/s"),
        (1_260_000_000.0, "1.3 GB/s"),
        (150_000_000_000.0, "150 GB/s"),
    ])
    func rate(bytesPerSecond: Double, expected: String) {
        #expect(Format.rate(bytesPerSecond) == expected)
    }

    /// The menu bar reserves the width of "99.9 MB/s" for each network line, so a
    /// wider value would push the whole item sideways every time it appeared.
    @Test("no rate is wider than the menu bar reserves")
    func rateWidth() {
        let reserved = "99.9 MB/s".count
        var value = 1.0
        while value < 1e13 {
            #expect(Format.rate(value).count <= reserved, "\(value) → \(Format.rate(value))")
            value *= 1.37
        }
    }

    @Test("memory is reported in binary gigabytes")
    func gigabytes() {
        #expect(Format.gigabytes(0) == "0.0")
        #expect(Format.gigabytes(16 * 1_073_741_824) == "16.0")
        #expect(Format.gigabytes(1_610_612_736) == "1.5")
    }

    /// Pinned exactly, including the decimal point: every other number in the
    /// dropdown uses one whatever the locale, so this must too.
    @Test("daily traffic uses decimal units, as the network tab does", arguments: [
        (UInt64(0), "0 B"),
        (999, "999 B"),
        (1_500, "1.5 KB"),
        (340_000_000, "340 MB"),
        (2_100_000_000, "2.1 GB"),
        (999_600_000_000, "1.0 TB"),
    ])
    func traffic(bytes: UInt64, expected: String) {
        #expect(Format.traffic(bytes) == expected)
    }
}
