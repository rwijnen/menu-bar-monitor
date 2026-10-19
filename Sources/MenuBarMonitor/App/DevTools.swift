import AppKit
import SwiftUI

/// Command-line helpers for checking readings and layouts without clicking
/// through the menu bar, and without screen-recording permission:
///
///   MenuBarMonitor --sample            prints a few live readings and exits
///   MenuBarMonitor --snapshot <dir>    renders every view to PNG, from demo data
@MainActor
enum DevTools {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if args.contains("--sample") {
            printSamples()
            return true
        }
        if let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count {
            snapshot(to: URL(fileURLWithPath: args[index + 1], isDirectory: true))
            return true
        }
        return false
    }

    // MARK: - Live readings

    /// For comparing against `top -l 2`, `vm_stat`, `sysctl vm.swapusage`, `uptime` and
    /// Stats or Activity Monitor. The first round has no CPU, clock or network figures
    /// yet, since all three are differences between two readings. Waits by running the
    /// run loop rather than sleeping, because the process list arrives on it.
    private static func printSamples() {
        let store = MetricsStore(settings: AppSettings())
        defer { printMemoryProcesses(store) }
        store.detailMetric = .cpu
        for _ in 0..<4 {
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            store.sample()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            let cpu = store.cpu, memory = store.memory, network = store.network
            let details = store.cpuDetails
            let groups = store.coreGroups.map { group in
                "\(group.name) \(group.usage(in: cpu.cores).map(Format.percent) ?? "-")"
            }
            let clocks = (details.frequency?.byGroup(store.coreGroups) ?? []).map {
                "\($0.group.name) \(Format.megahertz($0.mhz))"
            }
            print("""
            cpu \(Format.percent(cpu.total)) (user \(Format.percent(cpu.user)), \
            system \(Format.percent(cpu.system)), \(cpu.coreCount) cores: \
            \(groups.joined(separator: ", ")))
            cpu temperature \(Format.temperature(details.temperature)), \
            clock \(Format.megahertz(details.frequency?.allCores)) \
            (\(clocks.joined(separator: ", "))), \
            load \(details.loadAverage.map(Format.load).joined(separator: " ")), \
            up \(Format.uptime(details.uptime))
            mem \(Format.gigabytes(memory.used))/\(Format.gigabytes(memory.total)) GB  \
            app \(Format.gigabytes(memory.app)) wired \(Format.gigabytes(memory.wired)) \
            compressed \(Format.gigabytes(memory.compressed)) \
            swap \(Format.gigabytes(memory.swapUsed)) pressure \(memory.pressure.title)
            net \(network.interfaceDisplayName ?? "-") (\(network.interfaceName ?? "-")) \
            \(network.ipAddress ?? "-")  ↓ \(Format.rate(network.downloadPerSecond)) \
            ↑ \(Format.rate(network.uploadPerSecond))
            apps \(details.processes.map { "\($0.name) \(Format.finePercent($0.value))" }
                .joined(separator: ", "))
            ---
            """)
        }
    }

    /// The memory dropdown's list, which comes from `top` and takes about a second.
    private static func printMemoryProcesses(_ store: MetricsStore) {
        store.detailMetric = .memory
        let deadline = Date().addingTimeInterval(5)
        while !store.memoryDetails.processesMeasured && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        let apps = store.memoryDetails.processes.map { "\($0.name) \(Format.memory($0.value))" }
        print("memory apps \(apps.joined(separator: ", "))")
    }

    // MARK: - Screenshots

    /// Writes the images used in the README. They come from demo data rather than
    /// this machine's, so they are the same wherever they are generated and show
    /// nobody's real address or apps.
    private static func snapshot(to directory: URL) {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let suite = "MenuBarMonitor.snapshot"
        UserDefaults().removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite)!
        let store = demoStore(defaults: defaults)
        let settings = AppSettings(defaults: defaults)

        let actions = PanelActions(openSettings: {}, openActivityMonitor: {}, quit: {})
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "light" : "dark"
            let appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)!
            // Roughly the menu bar's own tint over a neutral wallpaper.
            let menuBar = scheme == .light ? Color(white: 0.93) : Color(white: 0.16)
            for style in MenuBarStyle.allCases {
                let file = "menubar-\(style.rawValue)-\(name).png"
                render(MenuBarLabel(store: store, settings: settings, style: style).padding(4),
                       scheme: scheme, background: menuBar,
                       to: directory.appendingPathComponent(file))
            }
            for metric in Metric.allCases {
                let dropdown = PanelView(metric: metric, store: store, settings: settings,
                                         actions: actions)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                let file = "dropdown-\(metric.rawValue)-\(name).png"
                renderAppKit(dropdown, appearance: appearance,
                             to: directory.appendingPathComponent(file))
            }
            renderAppKit(SettingsView(settings: settings, store: store), appearance: appearance,
                         to: directory.appendingPathComponent("settings-\(name).png"))
        }
        UserDefaults().removePersistentDomain(forName: suite)
        print("Snapshots written to \(directory.path)")
    }

    /// A minute of made-up readings: moderate CPU on an M5 Pro's fifteen cores, memory at
    /// about 60% with no pressure, and a download in progress.
    private static func demoStore(defaults: UserDefaults) -> MetricsStore {
        let now = Date()
        let gib: UInt64 = 1_073_741_824
        defaults.set(MetricsStore.dayKey(for: now), forKey: "trafficDay")
        defaults.set(2.1e9, forKey: "downloadedToday")
        defaults.set(3.4e8, forKey: "uploadedToday")
        let store = MetricsStore(settings: AppSettings(defaults: defaults), defaults: defaults,
                                 now: now)

        // An M5 Pro's layout: ten Performance cores, then five Super cores.
        store.coreGroups = [CoreGroup(name: "Performance", range: 0..<10),
                            CoreGroup(name: "Super", range: 10..<15)]

        for index in 0..<MetricsStore.historyLength {
            let t = Double(index)
            let cpu = 24 + 8 * sin(t / 4) + 4 * sin(t * 1.7)
            let used = UInt64((0.61 + 0.015 * sin(t / 9)) * Double(16 * gib))
            let down = max(0, 1_100_000 + 600_000 * sin(t / 3) + 250_000 * sin(t * 2.3))
            let up = max(0, 110_000 + 50_000 * sin(t / 2.5 + 1))
            // Typed and split up: Xcode 26's compiler gives up inferring this as one
            // expression, though newer ones manage.
            let cores: [Double] = (0..<15).map { (core: Int) -> Double in
                let share: Double = core < 10 ? 0.6 : 1.8
                let wave: Double = 9 * sin(t / 3 + Double(core) * 1.3)
                return max(0, min(100, cpu * share + wave))
            }
            store.record(
                cpu: CPUReading(total: cpu, user: cpu * 0.62, system: cpu * 0.38,
                                coreCount: 15, cores: cores),
                memory: MemoryReading(total: 16 * gib, used: used, app: used - 4 * gib,
                                      wired: 2 * gib + gib / 5,
                                      compressed: 1 * gib + gib * 4 / 5,
                                      swapUsed: gib * 2 / 5, pressure: .normal),
                network: NetworkReading(downloadPerSecond: down, uploadPerSecond: up,
                                        interfaceName: "en0", interfaceDisplayName: "Wi-Fi",
                                        ipAddress: "192.168.1.20"),
                now: now)
        }

        let processes = [
            ("WindowServer", nil, 47.9), ("Safari", "/Applications/Safari.app", 31.2),
            ("Xcode", "/Applications/Xcode.app", 18.6),
            ("Music", "/System/Applications/Music.app", 6.4),
            ("Mail", "/System/Applications/Mail.app", 4.1), ("kernel_task", nil, 3.8),
            ("Finder", "/System/Library/CoreServices/Finder.app", 2.2),
            ("mds_stores", nil, 1.5),
        ].map { name, path, cpu in
            AppUsage(id: name, name: name,
                     icon: path.map { NSWorkspace.shared.icon(forFile: $0) }, value: cpu)
        }
        store.record(cpuDetails: CPUDetails(
            temperature: 45,
            frequency: FrequencyReading(allCores: 1770, clusters: [
                .init(mhz: 1344, maxMHz: 4380, coreCount: 10),
                .init(mhz: 2623, maxMHz: 4608, coreCount: 5),
            ]),
            loadAverage: [6.85, 5.5, 4.03],
            uptime: 6 * 3600 + 17 * 60,
            processes: processes,
            processesMeasured: true))

        let mib = 1_048_576.0
        let memoryHogs = [
            ("WindowServer", nil, 2068.5), ("Xcode", "/Applications/Xcode.app", 1802.3),
            ("Safari", "/Applications/Safari.app", 1640.9),
            ("Music", "/System/Applications/Music.app", 912.4),
            ("Mail", "/System/Applications/Mail.app", 650.7),
            ("Finder", "/System/Library/CoreServices/Finder.app", 301.2),
            ("mds_stores", nil, 214.8), ("kernel_task", nil, 156.0),
        ].map { name, path, size in
            AppUsage(id: name, name: name,
                     icon: path.map { NSWorkspace.shared.icon(forFile: $0) }, value: size * mib)
        }
        store.record(memoryDetails: MemoryDetails(processes: memoryHogs, processesMeasured: true))
        return store
    }

    private static func render<V: View>(_ view: V, scheme: ColorScheme, background: Color,
                                        to url: URL) {
        let content = view.background(background).environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        write(NSBitmapImageRep(cgImage: image), to: url)
    }

    /// Forms use AppKit controls, which ImageRenderer cannot draw, so these go
    /// through an offscreen window instead.
    ///
    /// The dropdowns go this way too, on a plain background: their material blurs what
    /// is on screen behind them, and offscreen there is nothing.
    private static func renderAppKit<V: View>(_ view: V, appearance: NSAppearance,
                                              to url: URL) {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        hosting.frame.size = hosting.fittingSize
        hosting.layoutSubtreeIfNeeded()
        hosting.display()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        write(rep, to: url)
    }

    private static func write(_ rep: NSBitmapImageRep, to url: URL) {
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
