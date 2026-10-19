import Foundation
import Testing

@testable import MenuBarMonitor

@Suite("Memory details")
struct MemoryDetailsTests {

    private let gib: UInt64 = 1_073_741_824

    @Test("free is what is not used, never below zero")
    func free() {
        #expect(MemoryReading(total: 24 * gib, used: 18 * gib).free == 6 * gib)
        #expect(MemoryReading(total: 8 * gib, used: 9 * gib).free == 0)
    }

    @Test("each part of the breakdown is a fraction of what is installed")
    func fractions() {
        let memory = MemoryReading(total: 16 * gib, used: 12 * gib, app: 8 * gib,
                                   wired: 2 * gib, compressed: 2 * gib)
        #expect(memory.fraction(of: memory.app) == 0.5)
        #expect(memory.fraction(of: memory.wired) == 0.125)
        #expect(MemoryReading(total: 0).fraction(of: 5) == 0)
    }

    /// macOS reports three levels, so the needle sits in the middle of each band.
    @Test("the pressure needle points into the middle of its level's band")
    func gaugeFraction() {
        #expect(MemoryPressure.normal.gaugeFraction == 1.0 / 6)
        #expect(MemoryPressure.warning.gaugeFraction == 0.5)
        #expect(MemoryPressure.critical.gaugeFraction == 5.0 / 6)
    }

    static let sizes: [(Double, String)] = [
        (0, "0 KB"),
        (524_288, "512 KB"),
        (892_022_374, "850.7 MB"),
        (19_477_975_204, "18.14 GB"),
    ]

    @Test("memory sizes are written as Stats writes them", arguments: sizes)
    func memorySize(bytes: Double, expected: String) {
        #expect(Format.memory(bytes) == expected)
    }

    @Test("sizes switch from MB to GB at 1024 MB")
    func gigabyteBoundary() {
        let mib = 1_048_576.0
        #expect(Format.memory(1023.9 * mib) == "1023.9 MB")
        #expect(Format.memory(1024 * mib) == "1.00 GB")
    }
}

@Suite("Reading top")
struct TopOutputTests {

    static let topSizes: [(String, Double)] = [
        ("2013M", 2_110_783_488),
        ("883M+", 925_892_608),
        ("12K-", 12_288),
        ("2G", 2_147_483_648),
        ("512B", 512),
        ("1024", 1024),
    ]

    @Test("sizes are binary, with or without a direction marker", arguments: topSizes)
    func bytes(size: String, expected: Double) {
        #expect(ProcessList.bytes(size) == expected)
    }

    @Test("sizes that are not sizes", arguments: ["", "M", "abcM", "-"])
    func notSizes(size: String) {
        #expect(ProcessList.bytes(size) == nil)
    }

    /// top prints a block of totals before its table, and pads names to a column.
    @Test("the process table is read and the header block skipped")
    func parse() {
        let output = """
        Processes: 742 total, 4 running, 738 sleeping, 4891 threads
        Load Avg: 4.90, 3.56, 3.53
        PhysMem: 23G used (3581M wired, 9851M compressor), 367M unused.

        PID    MEM   COMMAND
        414    2013M WindowServer
        57263  1930M+ com.apple.Virtua
        67668  1874M Code Helper (Plu
        """
        let expected: [ProcessList.Entry] = [
            .init(pid: 414, value: 2_110_783_488, name: "WindowServer"),
            .init(pid: 57263, value: 2_023_751_680, name: "com.apple.Virtua"),
            .init(pid: 67668, value: 1_965_031_424, name: "Code Helper (Plu"),
        ]
        #expect(ProcessList.parseTop(output) == expected)
    }

    /// The point of running top: footprints of other users' processes are there too.
    @MainActor
    @Test("top on this machine lists apps by memory, largest first")
    func live() async {
        let sampler = ProcessSampler()
        let apps = await withCheckedContinuation { continuation in
            sampler.read(.memory, limit: 200) { continuation.resume(returning: $0) }
        }
        #expect(!apps.isEmpty)
        #expect(apps.allSatisfy { $0.value > 0 && !$0.name.isEmpty })
        #expect(apps.map(\.value) == apps.map(\.value).sorted(by: >))
        let total = apps.map(\.value).reduce(0, +)
        #expect(total < Double(ProcessInfo.processInfo.physicalMemory) * 2)
    }
}

@Suite("Throttle")
struct ThrottleTests {

    @Test("due at first, then not again until the interval has passed")
    func interval() {
        var throttle = Throttle(interval: 10)
        let start = Date(timeIntervalSince1970: 1_000)
        // isDue changes the throttle, so each answer is taken before it is checked.
        let answers = [0, 9.9, 10, 15].map { throttle.isDue(now: start.addingTimeInterval($0)) }
        #expect(answers == [true, false, true, false])
    }

    /// Reopening the memory dropdown must not show a list up to ten seconds old.
    @Test("a reset makes it due straight away")
    func reset() {
        var throttle = Throttle(interval: 10)
        let start = Date(timeIntervalSince1970: 1_000)
        _ = throttle.isDue(now: start)
        throttle.reset()
        let due = throttle.isDue(now: start.addingTimeInterval(1))
        #expect(due)
    }
}
