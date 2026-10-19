import Foundation
import Testing

@testable import MenuBarMonitor

@Suite("Core layout")
struct CoreLayoutTests {

    /// sysctl lists the fastest kind first; the cores are numbered slowest first.
    @Test("an M5 Pro has ten Performance cores, then five Super cores")
    func m5Pro() {
        let groups = CoreLayout.groups(levels: [("Super", 5), ("Performance", 10)],
                                       coreCount: 15)
        #expect(groups == [CoreGroup(name: "Performance", range: 0..<10),
                           CoreGroup(name: "Super", range: 10..<15)])
    }

    @Test("an M1 has four Efficiency cores, then four Performance cores")
    func m1() {
        let groups = CoreLayout.groups(levels: [("Performance", 4), ("Efficiency", 4)],
                                       coreCount: 8)
        #expect(groups.map(\.name) == ["Efficiency", "Performance"])
        #expect(groups.map(\.range) == [0..<4, 4..<8])
    }

    @Test("without perflevels, or when they do not add up, all cores are one group",
          arguments: [[(String, Int)](), [("Performance", 8)], [("Super", 4), ("Performance", 3)]])
    func fallback(levels: [(String, Int)]) {
        let groups = CoreLayout.groups(levels: levels.map { (name: $0.0, count: $0.1) },
                                       coreCount: 8)
        #expect(groups == [CoreGroup(name: "Cores", range: 0..<8)])
    }

    @Test("a group's usage is the average of its own cores")
    func groupUsage() {
        let cores: [Double] = [10, 20, 30, 90, 100]
        #expect(CoreGroup(name: "a", range: 0..<3).usage(in: cores) == 20)
        #expect(CoreGroup(name: "b", range: 3..<5).usage(in: cores) == 95)
        #expect(CoreGroup(name: "c", range: 5..<8).usage(in: cores) == nil)
    }

    @Test("this machine's layout covers every core exactly once")
    func liveLayout() {
        let count = ProcessInfo.processInfo.processorCount
        let groups = CoreLayout.current(coreCount: count)
        #expect(groups.map(\.range.count).reduce(0, +) == count)
        #expect(groups.first?.range.lowerBound == 0)
        #expect(groups.last?.range.upperBound == count)
    }
}

@Suite("Temperature")
struct TemperatureTests {

    @Test("Apple silicon's die sensors are chosen over everything else")
    func prefersDieSensors() {
        let names = ["gas gauge battery", "PMU tcal", "PMU tdie1", "PMU tdev1", "PMU tdie2",
                     "NAND CH0 temp"]
        #expect(TemperatureMath.cpuSensorIndices(names: names) == [2, 4])
    }

    @Test("older chips' cluster sensors are used when there are no die sensors")
    func clusterSensors() {
        let names = ["pACC MTR Temp Sensor0", "gas gauge battery", "eACC MTR Temp Sensor1"]
        #expect(TemperatureMath.cpuSensorIndices(names: names) == [0, 2])
        #expect(TemperatureMath.cpuSensorIndices(names: ["gas gauge battery"]).isEmpty)
    }

    /// Switched-off sensors report thousands of degrees below zero.
    @Test("implausible readings are left out of the average")
    func average() {
        #expect(TemperatureMath.average([44, 46, -9201.1, 0, 4000]) == 45)
        #expect(TemperatureMath.average([-9201.1]) == nil)
        #expect(TemperatureMath.average([]) == nil)
    }

    @Test("this machine's CPU temperature, where it has sensors, is plausible")
    func live() {
        // A virtual machine, like a CI runner, has none; that is not a failure.
        if let celsius = TemperatureSampler().read() {
            #expect((10..<110).contains(celsius))
        }
    }
}

@Suite("Clock speed")
struct FrequencyTests {

    @Test("clock steps are read from their names; idle and off are not steps",
          arguments: [("V0P14", 0), ("V12P2", 12), ("V19P0", 19)])
    func stepIndex(name: String, index: Int) {
        #expect(FrequencyMath.stepIndex(name) == index)
    }

    @Test("names that are not clock steps", arguments: ["IDLE", "DOWN", "OFF", "", "VP"])
    func notSteps(name: String) {
        #expect(FrequencyMath.stepIndex(name) == nil)
    }

    private func table(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt32(800).littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// An M5 Pro's CPU tables are in kHz, its GPU's in Hz.
    @Test("tables in kHz and in Hz both come out in MHz")
    func decodeUnits() {
        #expect(DVFSTable.decode(table([1_344_000, 4_380_000])) == [1344, 4380])
        #expect(DVFSTable.decode(table([600_000_000, 3_204_000_000])) == [600, 3204])
        #expect(DVFSTable.decode(Data()).isEmpty)
    }

    @Test("a cluster gets the CPU table with as many entries as it has steps")
    func matchTable() {
        let tables: [String: [Double]] = [
            "voltage-states9-sram": [0, 338, 486],              // the GPU's: starts at 0
            "voltage-states22-sram": [1344, 2652, 4380],
            "voltage-states5-sram": [1308, 1980, 2880, 4608],
        ]
        #expect(DVFSTable.match(stepCount: 3, in: tables) == [1344, 2652, 4380])
        #expect(DVFSTable.match(stepCount: 4, in: tables) == [1308, 1980, 2880, 4608])
        #expect(DVFSTable.match(stepCount: 5, in: tables) == nil)
    }

    @Test("a cluster's clock is its cores' time at each step, weighted")
    func weightedAverage() throws {
        let tables = ["slow": [1000.0, 2000], "fast": [1500.0, 3000, 4500]]
        var slow = ClusterTotals()
        slow.add(states: [("IDLE", 900), ("V0P1", 30), ("V1P0", 10)], tables: tables)
        slow.add(states: [("IDLE", 990), ("V0P1", 0), ("V1P0", 0)], tables: tables)
        var fast = ClusterTotals()
        fast.add(states: [("DOWN", 50), ("V0P2", 0), ("V1P1", 0), ("V2P0", 0)],
                 tables: tables)

        let reading = try #require(FrequencyMath.reading(from: [fast, slow]))
        // (30 × 1000 + 10 × 2000) / 40
        #expect(reading.clusters.map(\.mhz) == [1250, nil])
        #expect(reading.clusters.map(\.coreCount) == [2, 1])
        #expect(reading.clusters.map(\.maxMHz) == [2000, 4500])
        #expect(reading.allCores == 1250)
    }

    @Test("clusters are named after the core groups only when they line up")
    func byGroup() {
        let reading = FrequencyReading(allCores: 1770, clusters: [
            .init(mhz: 1344, maxMHz: 4380, coreCount: 10),
            .init(mhz: 2623, maxMHz: 4608, coreCount: 5),
        ])
        let groups = [CoreGroup(name: "Performance", range: 0..<10),
                      CoreGroup(name: "Super", range: 10..<15)]
        #expect(reading.byGroup(groups).map(\.group.name) == ["Performance", "Super"])
        #expect(reading.byGroup(groups).map(\.mhz) == [1344, 2623])
        #expect(reading.byGroup([CoreGroup(name: "Cores", range: 0..<15)]).isEmpty)
        #expect(reading.maxMHz == 4608)
    }

    @Test("this machine's clock, where it can be read, is plausible")
    func live() {
        let sampler = FrequencySampler()
        #expect(sampler.read() == nil)
        Thread.sleep(forTimeInterval: 0.3)
        // A virtual machine has no IOReport CPU channels; that is not a failure.
        if let reading = sampler.read(), let mhz = reading.allCores {
            #expect((100...10_000).contains(mhz))
            #expect(mhz <= (reading.maxMHz ?? 0) + 1)
        }
    }
}

@Suite("Process list")
struct ProcessListTests {

    @Test("ps output is split into number, CPU and a name that may contain spaces")
    func parse() {
        let output = """
          414  58.2 WindowServer
        43420   8,0 Claude Helper (Renderer)
            0   3.1 kernel_task
        not a process line
        """
        #expect(ProcessList.parse(output) == [
            .init(pid: 414, cpu: 58.2, name: "WindowServer"),
            .init(pid: 43420, cpu: 8, name: "Claude Helper (Renderer)"),
            .init(pid: 0, cpu: 3.1, name: "kernel_task"),
        ])
    }

    @Test("an app's processes are added up, busiest app first, idle ones skipped")
    func top() {
        let entries: [ProcessList.Entry] = [
            .init(pid: 1, cpu: 6.9, name: "Claude Helper"),
            .init(pid: 2, cpu: 6.1, name: "Claude Helper (Renderer)"),
            .init(pid: 3, cpu: 47.9, name: "WindowServer"),
            .init(pid: 4, cpu: 0, name: "idle daemon"),
            .init(pid: 5, cpu: 2.0, name: "Claude"),
        ]
        var looked: [pid_t] = []
        let usage = ProcessList.top(entries, limit: 8) { entry in
            looked.append(entry.pid)
            let app = entry.name.hasPrefix("Claude") ? "Claude" : entry.name
            return AppGroup(key: app, name: app, icon: nil)
        }
        #expect(usage.map(\.name) == ["WindowServer", "Claude"])
        #expect(abs(usage[1].cpu - 15) < 0.001)
        #expect(!looked.contains(4))
    }

    @Test("only the busiest few are kept")
    func limit() {
        let entries = (1...20).map {
            ProcessList.Entry(pid: pid_t($0), cpu: Double($0), name: "p\($0)")
        }
        let usage = ProcessList.top(entries, limit: 8) {
            AppGroup(key: $0.name, name: $0.name, icon: nil)
        }
        #expect(usage.map(\.name) == (13...20).reversed().map { "p\($0)" })
    }

    /// The point of running ps: processes of other users are in the list.
    @MainActor
    @Test("ps on this machine lists system processes too")
    func live() async {
        // Held for the duration: the sampler lets go of a list nobody is waiting for.
        let sampler = ProcessSampler()
        let apps = await withCheckedContinuation { continuation in
            sampler.read(limit: 200) { continuation.resume(returning: $0) }
        }
        #expect(!apps.isEmpty)
        #expect(apps.allSatisfy { $0.cpu > 0 && !$0.name.isEmpty })
        #expect(apps.map(\.cpu) == apps.map(\.cpu).sorted(by: >))
    }
}

@Suite("System information")
struct SystemInfoTests {

    @Test("load averages come in threes, and uptime counts up from boot")
    func live() {
        let loads = SystemInfo.loadAverage()
        #expect(loads.count == 3)
        #expect(loads.allSatisfy { $0 >= 0 })
        #expect(SystemInfo.uptime() > 0)
        #expect(SystemInfo.uptime(now: Date().addingTimeInterval(60)) > SystemInfo.uptime())
    }

    @Test("every core gets its own usage, within 0 to 100")
    func cores() throws {
        let sampler = CPUSampler()
        _ = sampler.read()
        Thread.sleep(forTimeInterval: 0.2)
        let reading = try #require(sampler.read())
        #expect(reading.cores.count == reading.coreCount)
        #expect(reading.cores.allSatisfy { (0...100).contains($0) })
    }
}

@Suite("Formatting CPU details")
struct CPUFormatTests {

    @Test("temperature and clock speeds")
    func units() {
        #expect(Format.temperature(44.6) == "45°C")
        #expect(Format.temperature(nil) == "—")
        #expect(Format.megahertz(1769.6) == "1770 MHz")
        #expect(Format.megahertz(nil) == "—")
        #expect(Format.gigahertz(1770) == "1.77")
        #expect(Format.load(6.854) == "6.85")
    }

    static let uptimes: [(TimeInterval, String)] = [
        (0, "less than a minute"),
        (59, "less than a minute"),
        (60, "1 minute"),
        (1_020, "17 minutes"),
        (3_600, "1 hour"),
        (22_620, "6 hours, 17 minutes"),
        (90_060, "1 day, 1 hour"),
        (173_100, "2 days"),
    ]

    @Test("uptime shows its two largest units", arguments: uptimes)
    func uptime(seconds: TimeInterval, expected: String) {
        #expect(Format.uptime(seconds) == expected)
    }
}
