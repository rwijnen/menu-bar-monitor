import Foundation
import Observation

/// Takes a reading on every tick and keeps a short history for the graphs.
@MainActor @Observable
final class MetricsStore {
    static let historyLength = 60
    static let menuBarHistoryLength = 20
    static let cpuHotThreshold = 85.0

    private(set) var cpu = CPUReading()
    private(set) var memory = MemoryReading()
    private(set) var network = NetworkReading()
    private(set) var cpuDetails = CPUDetails()
    private(set) var memoryDetails = MemoryDetails()
    private(set) var networkDetails = NetworkDetails()
    /// Whether macOS had a connection at each of the last ninety readings. Recorded all
    /// the time — it costs nothing — so the history is there when the dropdown opens.
    private(set) var connectionHistory = ConnectionHistory()
    /// Which kind of core each core is. Set from `sysctl` at launch; the screenshot
    /// generator replaces it with a fixed layout.
    var coreGroups = CoreLayout.current(coreCount: ProcessInfo.processInfo.processorCount)

    /// The metric whose dropdown is open. The readings only a dropdown shows are taken
    /// only while it is open, and straight away when it opens, so it is never blank.
    var detailMetric: Metric? {
        didSet {
            guard detailMetric != oldValue else { return }
            if detailMetric == .memory {
                memoryProcesses.reset()
                sampleMemoryDetails()
            }
            if detailMetric == .network {
                // Per-app rates are a difference between two nettop samples: take the
                // first now and the second a second later, not a whole interval later.
                processSampler.resetNetwork()
                sampleNetworkDetails()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard self?.detailMetric == .network else { return }
                    self?.sampleNetworkDetails()
                }
            }
            guard detailMetric == .cpu else { return }
            sampleCPUDetails()
            // The clock speed is a difference between two readings: take the second
            // one soon rather than a whole interval later.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard self?.detailMetric == .cpu else { return }
                self?.sampleCPUDetails(includingProcesses: false)
            }
        }
    }

    private(set) var cpuHistory: [Double] = []
    private(set) var memoryHistory: [Double] = []
    private(set) var downloadHistory: [Double] = []
    private(set) var uploadHistory: [Double] = []

    private(set) var downloadedToday: UInt64 = 0
    private(set) var uploadedToday: UInt64 = 0

    /// Called after every reading, used to keep the status item width in sync.
    @ObservationIgnored var onUpdate: (() -> Void)?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cpuSampler = CPUSampler()
    @ObservationIgnored private let memorySampler = MemorySampler()
    @ObservationIgnored private let networkSampler = NetworkSampler()
    @ObservationIgnored private let temperatureSampler = TemperatureSampler()
    @ObservationIgnored private let frequencySampler = FrequencySampler()
    @ObservationIgnored private let processSampler = ProcessSampler()
    /// `top` costs about 0.6 s of CPU a run, and footprints change slowly.
    @ObservationIgnored private var memoryProcesses = Throttle(interval: 10)
    @ObservationIgnored private let connection = ConnectionMonitor()
    @ObservationIgnored let wifi = WiFiName()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var todayKey: String
    @ObservationIgnored private var readingsSinceSave = 0

    init(settings: AppSettings, defaults: UserDefaults = .standard, now: Date = Date()) {
        self.settings = settings
        self.defaults = defaults
        todayKey = Self.dayKey(for: now)
        if defaults.string(forKey: "trafficDay") == todayKey {
            downloadedToday = UInt64(defaults.double(forKey: "downloadedToday"))
            uploadedToday = UInt64(defaults.double(forKey: "uploadedToday"))
        }
    }

    func start() {
        sample()
        scheduleNextSample()
    }

    /// The next delay is read from settings on every tick, so a new refresh
    /// interval takes effect without restarting anything.
    private func scheduleNextSample() {
        let timer = Timer(timeInterval: settings.refreshInterval,
                          repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sample()
                self?.scheduleNextSample()
            }
        }
        timer.tolerance = settings.refreshInterval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func sample() {
        record(cpu: cpuSampler.read(),
               memory: memorySampler.read(),
               network: networkSampler.read())
        if detailMetric == .cpu { sampleCPUDetails() }
        if detailMetric == .memory { sampleMemoryDetails() }
        if detailMetric == .network { sampleNetworkDetails() }
    }

    /// The network dropdown's extras: the connection as macOS sees it, the Wi-Fi name
    /// where allowed, and per-app traffic from `nettop`.
    private func sampleNetworkDetails() {
        var details = networkDetails
        details.isConnected = connection.isConnected
        details.connectionType = connection.connectionType
        details.wifi = wifi.state
        record(networkDetails: details)
        processSampler.readNetwork(limit: Self.processRowCount) { [weak self] apps in
            // Nil is the first sample, a baseline with nothing to compare against yet.
            guard let self, let apps else { return }
            var details = networkDetails
            details.processes = apps
            details.processesMeasured = true
            record(networkDetails: details)
        }
    }

    /// Asks for Location Services so the Wi-Fi name can be shown. Only ever from the
    /// button in the network dropdown.
    func requestWiFiNameAccess() {
        wifi.onChange = { [weak self] in
            guard let self else { return }
            var details = networkDetails
            details.wifi = wifi.state
            record(networkDetails: details)
        }
        wifi.requestAccess()
    }

    /// The memory dropdown's process list, from `top`: when the dropdown opens, then
    /// every ten seconds while it stays open.
    private func sampleMemoryDetails() {
        guard memoryProcesses.isDue() else { return }
        processSampler.read(.memory, limit: Self.processRowCount) { [weak self] apps in
            guard let self else { return }
            record(memoryDetails: MemoryDetails(processes: apps, processesMeasured: true))
        }
    }

    /// The CPU dropdown's extra readings. The process list comes from running `ps`,
    /// which arrives a moment later.
    private func sampleCPUDetails(includingProcesses: Bool = true) {
        var details = cpuDetails
        details.temperature = temperatureSampler.read()
        details.frequency = frequencySampler.read() ?? details.frequency
        details.loadAverage = SystemInfo.loadAverage()
        details.uptime = SystemInfo.uptime()
        record(cpuDetails: details)
        guard includingProcesses else { return }
        processSampler.read(.cpu, limit: Self.processRowCount) { [weak self] apps in
            guard let self else { return }
            var details = cpuDetails
            details.processes = apps
            details.processesMeasured = true
            record(cpuDetails: details)
        }
    }

    static let processRowCount = 8

    /// Applies one round of readings. Separate from `sample()` so the tests and
    /// the screenshot generator can feed it known values instead of live ones.
    ///
    /// - Parameter cpu: nil on the very first round, which has nothing to compare
    ///   against; the previous CPU reading is kept and no history point is added.
    func record(cpu cpuReading: CPUReading?, memory memoryReading: MemoryReading,
                network networkReading: NetworkReading, now: Date = Date()) {
        if let cpuReading {
            cpu = cpuReading
            Self.append(cpuReading.total, to: &cpuHistory)
        }

        memory = memoryReading
        Self.append(memoryReading.usedFraction * 100, to: &memoryHistory)

        network = networkReading
        Self.append(networkReading.downloadPerSecond, to: &downloadHistory)
        Self.append(networkReading.uploadPerSecond, to: &uploadHistory)
        connectionHistory.record(connection.isConnected)
        addTraffic(down: networkReading.downloadDelta, up: networkReading.uploadDelta, now: now)

        onUpdate?()
    }

    func record(cpuDetails details: CPUDetails) {
        cpuDetails = details
    }

    func record(memoryDetails details: MemoryDetails) {
        memoryDetails = details
    }

    func record(networkDetails details: NetworkDetails) {
        networkDetails = details
    }

    func record(connectionHistory history: ConnectionHistory) {
        connectionHistory = history
    }

    /// Upper bound for network graphs over the last `count` readings. The 10 KB/s
    /// floor keeps an idle connection from looking busy.
    func networkScale(last count: Int) -> Double {
        let peak = max(downloadHistory.suffix(count).max() ?? 0,
                       uploadHistory.suffix(count).max() ?? 0)
        return max(peak * 1.1, 10_000)
    }

    func saveTraffic() {
        defaults.set(todayKey, forKey: "trafficDay")
        defaults.set(Double(downloadedToday), forKey: "downloadedToday")
        defaults.set(Double(uploadedToday), forKey: "uploadedToday")
        readingsSinceSave = 0
    }

    private func addTraffic(down: UInt64, up: UInt64, now: Date) {
        let key = Self.dayKey(for: now)
        if key != todayKey {
            todayKey = key
            downloadedToday = 0
            uploadedToday = 0
        }
        downloadedToday += down
        uploadedToday += up
        readingsSinceSave += 1
        if readingsSinceSave >= 30 { saveTraffic() }
    }

    private static func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > historyLength {
            history.removeFirst(history.count - historyLength)
        }
    }

    static func dayKey(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
