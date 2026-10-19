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

    private var cpuSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: Metric.cpu.title, symbol: Metric.cpu.symbol) {
                Text(Format.percent(store.cpu.total))
                    .foregroundStyle(severity.cpuIsHot ? Palette.critical : .primary)
            }
            Sparkline(values: store.cpuHistory, maxValue: 100,
                      capacity: MetricsStore.historyLength,
                      color: severity.cpuColor)
                .frame(height: 36)
            VStack(spacing: 3) {
                let user = Format.percent(store.cpu.user)
                let system = Format.percent(store.cpu.system)
                DetailRow(label: "User / system", value: "\(user) / \(system)")
                // Always three rows, so the panel keeps the same height.
                ForEach(0..<3, id: \.self) { index in
                    if index < store.topApps.count {
                        AppRow(app: store.topApps[index])
                    } else {
                        DetailRow(label: index == 0 ? "Measuring apps…" : " ", value: "")
                    }
                }
            }
        }
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

private struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color?

    var body: some View {
        HStack {
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
