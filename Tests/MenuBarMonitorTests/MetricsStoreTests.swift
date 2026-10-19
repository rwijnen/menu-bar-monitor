import Foundation
import Testing

@testable import MenuBarMonitor

@MainActor
@Suite("Metrics store")
struct MetricsStoreTests {

    /// Each test gets its own defaults domain, so nothing leaks between tests or
    /// into the installed app's settings.
    private func makeDefaults() -> UserDefaults {
        let suite = "MenuBarMonitorTests.\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    private func makeStore(defaults: UserDefaults, now: Date = Date()) -> MetricsStore {
        MetricsStore(settings: AppSettings(defaults: defaults), defaults: defaults, now: now)
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day,
                                                   hour: hour, minute: minute))!
    }

    private func record(_ store: MetricsStore, cpu: Double? = 10, down: Double = 0,
                        downloaded: UInt64 = 0, uploaded: UInt64 = 0, now: Date = Date()) {
        store.record(cpu: cpu.map { CPUReading(total: $0, user: $0, system: 0) },
                     memory: MemoryReading(total: 100, used: 50),
                     network: NetworkReading(downloadPerSecond: down, uploadPerSecond: 0,
                                             downloadDelta: downloaded, uploadDelta: uploaded),
                     apps: [], now: now)
    }

    @Test("history keeps the last minute of readings")
    func historyIsCapped() {
        let store = makeStore(defaults: makeDefaults())
        let extra = 15
        for index in 0..<(MetricsStore.historyLength + extra) {
            record(store, cpu: Double(index))
        }
        #expect(store.cpuHistory.count == MetricsStore.historyLength)
        #expect(store.cpuHistory.first == Double(extra))
        #expect(store.cpuHistory.last == Double(MetricsStore.historyLength + extra - 1))
        #expect(store.memoryHistory.count == MetricsStore.historyLength)
        #expect(store.downloadHistory.count == MetricsStore.historyLength)
        #expect(store.uploadHistory.count == MetricsStore.historyLength)
    }

    /// The first CPU reading is always missing, since usage is the difference
    /// between two. That round must not put a zero at the start of the graph.
    @Test("a round without CPU figures adds no CPU point")
    func missingCPUReading() {
        let store = makeStore(defaults: makeDefaults())
        record(store, cpu: nil)
        #expect(store.cpuHistory.isEmpty)
        #expect(store.memoryHistory == [50])
        record(store, cpu: 30)
        #expect(store.cpuHistory == [30])
        #expect(store.cpu.total == 30)
    }

    @Test("memory history is a percentage of what is installed")
    func memoryHistoryIsPercent() {
        let store = makeStore(defaults: makeDefaults())
        record(store)
        #expect(store.memoryHistory == [50])
    }

    @Test("network graphs never scale below 10 KB/s, and only look at the window shown")
    func networkScale() {
        let store = makeStore(defaults: makeDefaults())
        record(store, down: 100)
        #expect(store.networkScale(last: 20) == 10_000)

        record(store, down: 1_000_000)
        #expect(abs(store.networkScale(last: 20) - 1_100_000) < 0.001)

        for _ in 0..<20 { record(store, down: 100) }
        #expect(store.networkScale(last: 20) == 10_000)
        #expect(abs(store.networkScale(last: 60) - 1_100_000) < 0.001)
    }

    @Test("today's traffic adds up, and starts again at midnight")
    func trafficRollsOver() {
        let store = makeStore(defaults: makeDefaults(), now: date(19, 9))
        record(store, downloaded: 1_000, uploaded: 500, now: date(19, 9))
        record(store, downloaded: 1_000, uploaded: 500, now: date(19, 23, 59))
        #expect(store.downloadedToday == 2_000)
        #expect(store.uploadedToday == 1_000)

        record(store, downloaded: 300, uploaded: 30, now: date(20, 0, 1))
        #expect(store.downloadedToday == 300)
        #expect(store.uploadedToday == 30)
    }

    @Test("today's traffic survives a restart that day, but not the next")
    func trafficIsRestored() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults, now: date(19, 9))
        record(store, downloaded: 5_000, uploaded: 700, now: date(19, 9))
        store.saveTraffic()

        let laterThatDay = makeStore(defaults: defaults, now: date(19, 18))
        #expect(laterThatDay.downloadedToday == 5_000)
        #expect(laterThatDay.uploadedToday == 700)

        let nextDay = makeStore(defaults: defaults, now: date(20, 8))
        #expect(nextDay.downloadedToday == 0)
        #expect(nextDay.uploadedToday == 0)
    }

    @Test("every reading tells the status item to resize")
    func notifiesOnUpdate() {
        let store = makeStore(defaults: makeDefaults())
        var updates = 0
        store.onUpdate = { updates += 1 }
        record(store)
        record(store)
        #expect(updates == 2)
    }
}
