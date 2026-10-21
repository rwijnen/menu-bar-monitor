import SwiftUI

struct PanelActions {
    var openSettings: @MainActor () -> Void
    var openActivityMonitor: @MainActor () -> Void
    var quit: @MainActor () -> Void
}

/// The dropdown shown when one metric's menu bar item is clicked: that metric's
/// detail, and the app's actions underneath.
///
/// Styled after the first mock-up: quiet sections divided by hairlines, each led by a
/// heading with the figure that matters most, a graph without a frame, then rows of
/// label and value. One colour per metric — purple for CPU, teal for memory, coral and
/// grey for network — with tones of it where a breakdown needs more than one, and red
/// or amber only as warnings.
struct PanelView: View {
    static let width: CGFloat = 300

    let metric: Metric
    let store: MetricsStore
    let settings: AppSettings
    let actions: PanelActions

    private var severity: Severity { Severity(store: store, settings: settings) }

    var body: some View {
        VStack(spacing: 0) {
            switch metric {
            case .cpu: cpuSections
            case .memory: memorySections
            case .network: networkSections
            }
            Divider()
            footer
        }
        .frame(width: Self.width)
    }

    // MARK: - CPU

    @ViewBuilder
    private var cpuSections: some View {
        let cpu = store.cpu
        let details = store.cpuDetails
        let groups = store.coreGroups
        PanelSection {
            Heading(metric: .cpu) {
                Text(Format.percent(cpu.total))
                    .foregroundStyle(severity.cpuIsHot ? Palette.critical : .primary)
            }
            Sparkline(values: store.cpuHistory, maxValue: 100,
                      capacity: MetricsStore.historyLength, color: severity.cpuColor)
                .frame(height: 36)
            CoreBars(cores: cpu.cores, groups: groups)
                .frame(height: 18)
            Rows {
                Row(label: "User / system",
                    value: "\(Format.percent(cpu.user)) / \(Format.percent(cpu.system))")
                if groups.count > 1 {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        Row(label: "\(group.name) cores",
                            value: group.usage(in: cpu.cores).map(Format.percent) ?? "—",
                            key: Palette.coreGroup(index))
                    }
                }
            }
        }
        Divider()
        PanelSection {
            Rows {
                Row(label: "Temperature", value: Format.temperature(details.temperature),
                    valueColor: temperatureColor(details.temperature))
                // No time at any clock step means the cores were idle, not unknown.
                Row(label: "Clock speed",
                    value: details.frequency.map { $0.allCores.map(Format.megahertz) ?? "Idle" }
                        ?? "—")
                let clocks = details.frequency?.byGroup(groups) ?? []
                ForEach(Array(clocks.enumerated()), id: \.offset) { index, clock in
                    Row(label: "\(clock.group.name) cores",
                        value: clock.mhz.map(Format.megahertz) ?? "Idle",
                        key: Palette.coreGroup(index))
                }
                Row(label: "Load average",
                    value: details.loadAverage.map(Format.load).joined(separator: "  "))
                Row(label: "Uptime", value: Format.uptime(details.uptime))
                if let chip = SystemInfo.chipName { Row(label: "Chip", value: chip) }
            }
        }
        Divider()
        PanelSection {
            GroupTitle("Busiest apps")
            processRows(details.processes, measured: details.processesMeasured) {
                Format.finePercent($0.value)
            }
        }
    }

    private func temperatureColor(_ celsius: Double?) -> Color? {
        guard settings.colorWarnings, let celsius else { return nil }
        return celsius > 95 ? Palette.critical : celsius > 80 ? Palette.warning : nil
    }

    // MARK: - Memory

    @ViewBuilder
    private var memorySections: some View {
        let memory = store.memory
        let details = store.memoryDetails
        let installed = Int((Double(memory.total) / 1_073_741_824).rounded())
        PanelSection {
            Heading(metric: .memory) {
                Text("\(Format.gigabytes(memory.used)) / \(installed) GB")
            }
            StackedBar(parts: [
                .init(fraction: memory.fraction(of: memory.app), color: Palette.appMemory),
                .init(fraction: memory.fraction(of: memory.wired), color: Palette.wiredMemory),
                .init(fraction: memory.fraction(of: memory.compressed),
                      color: Palette.compressedMemory),
            ])
            Sparkline(values: store.memoryHistory, maxValue: 100,
                      capacity: MetricsStore.historyLength, color: severity.memoryColor)
                .frame(height: 36)
            Rows {
                Row(label: "Pressure", value: memory.pressure.title,
                    valueColor: severity.memoryWarningColor)
                Row(label: "App", value: Format.memory(memory.app), key: Palette.appMemory)
                Row(label: "Wired", value: Format.memory(memory.wired),
                    key: Palette.wiredMemory)
                Row(label: "Compressed", value: Format.memory(memory.compressed),
                    key: Palette.compressedMemory)
                Row(label: "Free", value: Format.memory(memory.free))
                Row(label: "Swap used", value: Format.memory(memory.swapUsed))
            }
        }
        Divider()
        PanelSection {
            GroupTitle("Busiest apps")
            processRows(details.processes, measured: details.processesMeasured) {
                Format.memory($0.value)
            }
        }
    }

    // MARK: - Network

    @ViewBuilder
    private var networkSections: some View {
        let network = store.network
        let details = store.networkDetails
        PanelSection {
            Heading(metric: .network) {
                HStack(spacing: 8) {
                    rate("↓", network.downloadPerSecond, color: Palette.download)
                    rate("↑", network.uploadPerSecond, color: Palette.upload)
                }
                .font(.system(size: 14, weight: .medium).monospacedDigit())
            }
            ZStack {
                let scale = store.networkScale(last: MetricsStore.historyLength)
                Sparkline(values: store.downloadHistory, maxValue: scale,
                          capacity: MetricsStore.historyLength, color: Palette.download)
                Sparkline(values: store.uploadHistory, maxValue: scale,
                          capacity: MetricsStore.historyLength, color: Palette.upload,
                          filled: false)
            }
            .frame(height: 36)
            Rows {
                if let interface = network.interfaceName {
                    Row(label: "\(network.interfaceDisplayName ?? interface) (\(interface))",
                        value: network.ipAddress ?? "No IPv4 address")
                } else {
                    Row(label: "Not connected", value: "")
                }
                Row(label: "Today", value: "↓ \(Format.traffic(store.downloadedToday))  "
                        + "↑ \(Format.traffic(store.uploadedToday))")
                Row(label: "Since the Mac started",
                    value: "↓ \(Format.traffic(network.totalDownloaded))  "
                        + "↑ \(Format.traffic(network.totalUploaded))")
            }
        }
        Divider()
        PanelSection {
            GroupTitle("Connection history")
            ConnectionGrid(entries: store.connectionHistory.entries,
                           capacity: ConnectionHistory.length)
            HStack {
                let span = Double(ConnectionHistory.length) * settings.refreshInterval
                Text("\(Format.uptime(span)) ago")
                Spacer()
                Text("Now")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            Rows {
                Row(label: "Connection",
                    value: details.isConnected
                        ? details.connectionType.map { "Via \($0)" } ?? "Connected" : "None",
                    valueColor: details.isConnected ? nil : Palette.critical)
                let isUp = network.interfaceName != nil && network.isUp
                Row(label: "Interface", value: isUp ? "Up" : "Down",
                    valueColor: isUp ? nil : Palette.critical)
                Row(label: "Hardware address", value: network.hardwareAddress ?? "—")
                wifiRow(details.wifi)
            }
        }
        Divider()
        PanelSection {
            HStack {
                GroupTitle("Busiest apps")
                Spacer()
                Text("↓").foregroundStyle(Palette.download)
                    .frame(width: 64, alignment: .trailing)
                Text("↑").foregroundStyle(Palette.upload)
                    .frame(width: 64, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            Rows {
                ForEach(0..<MetricsStore.processRowCount, id: \.self) { index in
                    if index < details.processes.count {
                        NetworkAppRow(app: details.processes[index])
                    } else {
                        Row(label: index > 0 ? " "
                                : details.processesMeasured ? "No app is using the network"
                                : "Measuring…",
                            value: "")
                    }
                }
            }
        }
    }

    private func rate(_ arrow: String, _ value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(arrow).foregroundStyle(color)
            Text(Format.rate(value))
        }
    }

    @ViewBuilder
    private func wifiRow(_ wifi: WiFiName.State) -> some View {
        switch wifi {
        case .name(let name):
            Row(label: "Wi-Fi network", value: name)
        case .notOnWiFi:
            EmptyView()
        case .denied:
            Row(label: "Wi-Fi network", value: "Location Services off")
        case .notAsked:
            HStack {
                Text("Wi-Fi network").foregroundStyle(.secondary)
                Spacer()
                Button("Show the name…") { store.requestWiFiNameAccess() }
                    .buttonStyle(.link)
            }
            .font(.system(size: 12))
        }
    }

    // MARK: - Shared

    /// Always the same number of rows, so a dropdown keeps its height while the list
    /// arrives and as it changes.
    private func processRows(_ apps: [AppUsage], measured: Bool,
                             value: @escaping (AppUsage) -> String) -> some View {
        Rows {
            ForEach(0..<MetricsStore.processRowCount, id: \.self) { index in
                if index < apps.count {
                    AppRow(icon: apps[index].icon, name: apps[index].name) {
                        Text(value(apps[index]))
                    }
                } else {
                    Row(label: index == 0 && !measured ? "Measuring…" : " ", value: "")
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            FooterButton(title: "Settings", symbol: "gearshape", action: actions.openSettings)
                .keyboardShortcut(",", modifiers: .command)
            Spacer(minLength: 0)
            FooterButton(title: "Open Activity Monitor", action: actions.openActivityMonitor)
            Spacer(minLength: 0)
            FooterButton(title: "Quit", action: actions.quit)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }
}

// MARK: - Pieces

/// One section between hairlines, with the mock-up's padding.
private struct PanelSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }
}

/// The metric's name on the left and its headline figure on the right.
private struct Heading<Value: View>: View {
    let metric: Metric
    @ViewBuilder let value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(metric.title, systemImage: metric.symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            value.font(.system(size: 18, weight: .medium).monospacedDigit())
        }
    }
}

/// A quiet name for a group of rows, in sentence case like everything else.
private struct GroupTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

private struct Rows<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 3) { content }
    }
}

private struct Row: View {
    let label: String
    let value: String
    var valueColor: Color?
    /// A small colour key, matching the bar or graph part the row describes.
    var key: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let key {
                Circle().fill(key).frame(width: 6, height: 6)
            }
            Text(label).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text(value).foregroundStyle(valueColor ?? .primary).monospacedDigit().lineLimit(1)
        }
        .font(.system(size: 12))
    }
}

private struct AppRow<Values: View>: View {
    let icon: NSImage?
    let name: String
    @ViewBuilder let values: Values

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "gearshape.2").resizable().scaledToFit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 14, height: 14)
            Text(name).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer()
            values
        }
        .monospacedDigit()
        .font(.system(size: 12))
    }
}

private struct NetworkAppRow: View {
    let app: NetworkAppUsage

    var body: some View {
        AppRow(icon: app.icon, name: app.name) {
            Text(Format.rate(app.downloadPerSecond)).frame(width: 64, alignment: .trailing)
            Text(Format.rate(app.uploadPerSecond)).frame(width: 64, alignment: .trailing)
        }
    }
}

private struct FooterButton: View {
    let title: String
    var symbol: String?
    let action: @MainActor () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.system(size: 12))
            .foregroundStyle(isHovering ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
