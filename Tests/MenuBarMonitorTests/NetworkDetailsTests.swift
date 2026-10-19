import Foundation
import Network
import Testing

@testable import MenuBarMonitor

@Suite("Reading nettop")
struct NettopTests {

    /// nettop cuts names to fifteen characters and joins the process number with a dot,
    /// so the number is whatever follows the last one.
    @Test("each line is a name, a process number and bytes in and out")
    func parse() {
        let output = """
        ,bytes_in,bytes_out,
        Code Helper (Pl.67467,1285417,780756,
        com.apple.Web.12.88,3968674,431903,
        mDNSResponder.492,37706023,9991930,
        not a process line
        """
        let expected: [NetworkProcessList.Entry] = [
            .init(pid: 67467, name: "Code Helper (Pl", bytesIn: 1_285_417, bytesOut: 780_756),
            .init(pid: 88, name: "com.apple.Web.12", bytesIn: 3_968_674, bytesOut: 431_903),
            .init(pid: 492, name: "mDNSResponder", bytesIn: 37_706_023, bytesOut: 9_991_930),
        ]
        #expect(NetworkProcessList.parse(output) == expected)
    }

    @Test("rates come from processes present in both samples, per second")
    func rates() {
        let before: [pid_t: NetworkProcessList.Entry] = [
            1: .init(pid: 1, name: "Safari", bytesIn: 1_000, bytesOut: 500),
            2: .init(pid: 2, name: "Gone", bytesIn: 9_000, bytesOut: 9_000),
            3: .init(pid: 3, name: "Old name", bytesIn: 0, bytesOut: 0),
        ]
        let after: [pid_t: NetworkProcessList.Entry] = [
            1: .init(pid: 1, name: "Safari", bytesIn: 5_000, bytesOut: 700),
            3: .init(pid: 3, name: "Reused", bytesIn: 4_000, bytesOut: 0),
            4: .init(pid: 4, name: "New", bytesIn: 4_000, bytesOut: 0),
        ]
        let rates = NetworkProcessList.rates(from: before, to: after, seconds: 2)
        #expect(rates == [.init(pid: 1, name: "Safari", downloadPerSecond: 2_000,
                                uploadPerSecond: 100)])
        #expect(NetworkProcessList.rates(from: before, to: after, seconds: 0).isEmpty)
    }

    @Test("an app's processes are added up and the busiest come first, silent ones left out")
    func top() {
        let rates: [NetworkProcessList.Rate] = [
            .init(pid: 1, name: "Safari Networking", downloadPerSecond: 800, uploadPerSecond: 50),
            .init(pid: 2, name: "com.apple.WebKit.Ne", downloadPerSecond: 200, uploadPerSecond: 0),
            .init(pid: 3, name: "Music", downloadPerSecond: 0, uploadPerSecond: 2_000),
            .init(pid: 4, name: "idle", downloadPerSecond: 0, uploadPerSecond: 0),
        ]
        let usage = NetworkProcessList.top(rates, limit: 8) { rate in
            let app = rate.pid <= 2 ? "Safari" : rate.name
            return AppGroup(key: app, name: app, icon: nil)
        }
        #expect(usage.map(\.name) == ["Music", "Safari"])
        #expect(usage[1].downloadPerSecond == 1_000)
        #expect(usage[1].uploadPerSecond == 50)
    }

    @MainActor
    @Test("nettop on this machine takes a baseline first, then measures")
    func live() async throws {
        let sampler = ProcessSampler()
        func read() async -> [NetworkAppUsage]? {
            await withCheckedContinuation { (done: CheckedContinuation<[NetworkAppUsage]?, Never>) in
                sampler.readNetwork(limit: 50) { done.resume(returning: $0) }
            }
        }
        let first = await read()
        #expect(first == nil)
        try await Task.sleep(for: .milliseconds(300))
        let apps = try #require(await read())
        #expect(apps.allSatisfy { $0.downloadPerSecond >= 0 && $0.uploadPerSecond >= 0 })
    }
}

@Suite("Connection")
struct ConnectionTests {

    @Test("the history keeps the last ninety readings, oldest first")
    func history() {
        var history = ConnectionHistory()
        for index in 0..<100 { history.record(index % 10 != 0) }
        #expect(history.entries.count == ConnectionHistory.length)
        // The ten oldest readings, 0 to 9, have gone; reading 10 was disconnected.
        #expect(history.entries.first == false)
        #expect(history.entries.dropFirst().prefix(9).allSatisfy { $0 })
    }

    @Test("interface kinds have names")
    func typeNames() {
        #expect(ConnectionMonitor.typeName(.wifi) == "Wi-Fi")
        #expect(ConnectionMonitor.typeName(.wiredEthernet) == "Ethernet")
        #expect(ConnectionMonitor.typeName(nil) == nil)
    }

    @Test("this machine's primary interface has a name, a status and totals since boot")
    func liveInterface() {
        let reading = NetworkSampler().read()
        // A runner may have no network at all; when it does, the details must hang together.
        if let interface = reading.interfaceName {
            #expect(!interface.isEmpty)
            #expect(reading.interfaceDisplayName?.isEmpty == false)
            if reading.isUp { #expect(reading.totalDownloaded > 0) }
            if let hardware = reading.hardwareAddress {
                #expect(hardware.split(separator: ":").count == 6)
                #expect(hardware != "02:00:00:00:00:00")
            }
        }
    }
}
