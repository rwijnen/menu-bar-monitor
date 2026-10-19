import SwiftUI

struct PanelActions {
    var openSettings: @MainActor () -> Void
    var openActivityMonitor: @MainActor () -> Void
    var quit: @MainActor () -> Void
}

/// The dropdown shown when one metric's menu bar item is clicked: that metric's
/// detail, and the app's actions underneath.
struct PanelView: View {
    static let width: CGFloat = 300

    let metric: Metric
    let store: MetricsStore
    let settings: AppSettings
    let actions: PanelActions

    private var severity: Severity { Severity(store: store, settings: settings) }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch metric {
                case .cpu: cpuSection
                case .memory: memorySection
                case .network: networkSection
                }
            }
            .sectionPadding()
            Divider()
            footer
        }
        .frame(width: Self.width)
    }

    // MARK: - CPU

    private var cpuSection: some View {
        let details = store.cpuDetails
        let groupFrequencies = details.frequency?.byGroup(store.coreGroups) ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(Metric.cpu.title, systemImage: Metric.cpu.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(SystemInfo.chipName ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            cpuGauges(details)

            SectionTitle("Usage history")
            Sparkline(values: store.cpuHistory, maxValue: 100,
                      capacity: MetricsStore.historyLength, color: severity.cpuColor)
                .frame(height: 48)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05)))
            CoreBars(cores: store.cpu.cores, groups: store.coreGroups)

            SectionTitle("Details")
            VStack(spacing: 3) {
                DetailRow(label: "System", value: Format.percent(store.cpu.system),
                          dot: Palette.system)
                DetailRow(label: "User", value: Format.percent(store.cpu.user),
                          dot: Palette.cpu)
                DetailRow(label: "Idle", value: Format.percent(100 - store.cpu.total),
                          dot: Color.primary.opacity(0.25))
                if store.coreGroups.count > 1 {
                    ForEach(Array(store.coreGroups.enumerated()), id: \.offset) { index, group in
                        DetailRow(label: "\(group.name) cores",
                                  value: group.usage(in: store.cpu.cores)
                                    .map(Format.percent) ?? "—",
                                  dot: Palette.coreGroup(index))
                    }
                }
                DetailRow(label: "Uptime", value: Format.uptime(details.uptime))
            }

            SectionTitle("Average load")
            VStack(spacing: 3) {
                ForEach(Array(zip(["1 minute", "5 minutes", "15 minutes"],
                                  details.loadAverage).enumerated()), id: \.offset) { _, row in
                    DetailRow(label: row.0, value: Format.load(row.1))
                }
            }

            SectionTitle("Frequency")
            VStack(spacing: 3) {
                // No time at any clock step means the cores were idle, not unknown.
                DetailRow(label: "All cores",
                          value: details.frequency.map { $0.allCores.map(Format.megahertz)
                                                            ?? "Idle" } ?? "—")
                ForEach(Array(groupFrequencies.enumerated()), id: \.offset) { index, row in
                    DetailRow(label: "\(row.group.name) cores",
                              value: row.mhz.map(Format.megahertz) ?? "Idle",
                              dot: Palette.coreGroup(index))
                }
            }

            SectionTitle("Top processes")
            VStack(spacing: 3) {
                // Always the same number of rows, so the dropdown keeps its height.
                ForEach(0..<MetricsStore.processRowCount, id: \.self) { index in
                    if index < details.processes.count {
                        AppRow(app: details.processes[index])
                    } else {
                        DetailRow(label: index == 0 && !details.processesMeasured
                                    ? "Measuring…" : " ",
                                  value: "")
                    }
                }
            }
        }
    }

    private func cpuGauges(_ details: CPUDetails) -> some View {
        let temperature = details.temperature
        let hot = settings.colorWarnings && (temperature ?? 0) > 95
        let warm = settings.colorWarnings && (temperature ?? 0) > 80
        let frequency = details.frequency
        // Bottom-aligned, so the three captions share a line under rings of two sizes.
        return HStack(alignment: .bottom) {
            RingGauge(segments: [.init(fraction: (temperature ?? 0) / 100,
                                       color: hot ? Palette.critical
                                           : warm ? Palette.warning : Palette.gauge)],
                      value: Format.temperature(temperature), caption: "Temperature")
            Spacer()
            RingGauge(segments: [.init(fraction: store.cpu.system / 100, color: Palette.system),
                                 .init(fraction: store.cpu.user / 100,
                                       color: severity.cpuIsHot ? Palette.critical
                                           : Palette.cpu)],
                      value: Format.percent(store.cpu.total), caption: "Usage",
                      diameter: 80, lineWidth: 8)
            Spacer()
            RingGauge(segments: [.init(fraction: (frequency?.allCores ?? 0)
                                          / (frequency?.maxMHz ?? 1),
                                       color: Palette.gauge)],
                      value: Format.gigahertz(frequency?.allCores),
                      unit: frequency?.allCores == nil ? nil : "GHz", caption: "Frequency")
        }
        .padding(.horizontal, 6)
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: Metric.memory.title, symbol: Metric.memory.symbol) {
                let used = Format.gigabytes(store.memory.used)
                let total = Format.gigabytes(store.memory.total)
                Text("\(used) / \(total) GB")
            }
            UsageBar(fraction: store.memory.usedFraction, color: severity.memoryColor)
                .padding(.vertical, 2)
            VStack(spacing: 3) {
                DetailRow(label: "Pressure", value: store.memory.pressure.title,
                          valueColor: severity.memoryWarningColor)
                let app = Format.gigabytes(store.memory.app)
                let wired = Format.gigabytes(store.memory.wired)
                let compressed = Format.gigabytes(store.memory.compressed)
                DetailRow(label: "App / wired / compressed",
                          value: "\(app) / \(wired) / \(compressed) GB")
                DetailRow(label: "Swap used",
                          value: "\(Format.gigabytes(store.memory.swapUsed)) GB")
            }
        }
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: Metric.network.title, symbol: Metric.network.symbol) {
                HStack(spacing: 8) {
                    rate("↓", store.network.downloadPerSecond, color: Palette.download)
                    rate("↑", store.network.uploadPerSecond, color: Palette.upload)
                }
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
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
            VStack(spacing: 3) {
                if let interface = store.network.interfaceName {
                    let name = store.network.interfaceDisplayName ?? interface
                    DetailRow(label: "\(name) (\(interface))",
                              value: store.network.ipAddress ?? "No IPv4 address")
                } else {
                    DetailRow(label: "Not connected", value: "")
                }
                let down = Format.traffic(store.downloadedToday)
                let up = Format.traffic(store.uploadedToday)
                DetailRow(label: "Today", value: "↓ \(down)  ↑ \(up)")
            }
        }
    }

    private func rate(_ arrow: String, _ value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(arrow).foregroundStyle(color)
            Text(Format.rate(value))
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

private extension View {
    func sectionPadding() -> some View {
        padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct SectionHeader<Value: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            value
                .font(.system(size: 18, weight: .semibold).monospacedDigit())
        }
    }
}

private struct SectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color?
    /// A colour key, matching the gauge or bars the row describes.
    var dot: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let dot {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(dot)
                    .frame(width: 8, height: 8)
            }
            Text(label).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text(value).foregroundStyle(valueColor ?? .primary).monospacedDigit().lineLimit(1)
        }
        .font(.system(size: 12))
    }
}

private struct AppRow: View {
    let app: AppUsage

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "gearshape.2").resizable().scaledToFit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 14, height: 14)
            Text(app.name).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(Format.finePercent(app.cpu)).monospacedDigit()
        }
        .font(.system(size: 12))
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
