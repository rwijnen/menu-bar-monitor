import SwiftUI

/// What sits in one metric's menu bar item. `style` overrides the saved setting, so
/// the settings window can preview all three styles side by side.
struct MetricLabel: View {
    let metric: Metric
    let store: MetricsStore
    let settings: AppSettings
    var style: MenuBarStyle?

    private var activeStyle: MenuBarStyle { style ?? settings.style }
    private var severity: Severity { Severity(store: store, settings: settings) }
    private let graphSize = CGSize(width: 32, height: 16)

    var body: some View {
        Group {
            switch metric {
            case .cpu: cpu
            case .memory: memory
            case .network: network
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 22)
        .fixedSize()
    }

    private var cpu: some View {
        HStack(spacing: 3) {
            symbol(.cpu,
                   tint: activeStyle == .iconsAndNumbers && severity.cpuIsHot
                       ? Palette.critical : nil)
            switch activeStyle {
            case .sparklines:
                Sparkline(values: store.cpuHistory, maxValue: 100,
                          capacity: MetricsStore.menuBarHistoryLength,
                          color: severity.cpuColor, lineWidth: 1.2)
                    .frame(width: graphSize.width, height: graphSize.height)
            case .miniBars:
                MiniBar(fraction: store.cpu.total / 100, color: severity.cpuColor)
            case .iconsAndNumbers:
                fixedWidthText(Format.percent(store.cpu.total), template: "100%",
                               color: severity.cpuIsHot ? Palette.critical : .primary)
            }
        }
    }

    private var memory: some View {
        HStack(spacing: 3) {
            symbol(.memory,
                   tint: activeStyle == .iconsAndNumbers ? severity.memoryWarningColor : nil)
            switch activeStyle {
            case .sparklines:
                Sparkline(values: store.memoryHistory, maxValue: 100,
                          capacity: MetricsStore.menuBarHistoryLength,
                          color: severity.memoryColor, lineWidth: 1.2)
                    .frame(width: graphSize.width, height: graphSize.height)
            case .miniBars:
                MiniBar(fraction: store.memory.usedFraction, color: severity.memoryColor)
            case .iconsAndNumbers:
                fixedWidthText(Format.percent(store.memory.usedFraction * 100),
                               template: "100%",
                               color: severity.memoryWarningColor ?? .primary)
            }
        }
    }

    private var network: some View {
        HStack(spacing: 3) {
            switch activeStyle {
            case .sparklines:
                let scale = store.networkScale(last: MetricsStore.menuBarHistoryLength)
                ZStack {
                    Sparkline(values: store.downloadHistory, maxValue: scale,
                              capacity: MetricsStore.menuBarHistoryLength,
                              color: Palette.download, lineWidth: 1.2)
                    Sparkline(values: store.uploadHistory, maxValue: scale,
                              capacity: MetricsStore.menuBarHistoryLength,
                              color: Palette.upload, lineWidth: 1.2,
                              filled: false)
                }
                .frame(width: graphSize.width, height: graphSize.height)
            case .miniBars:
                EmptyView()
            case .iconsAndNumbers:
                symbol(.network)
            }
            VStack(alignment: .leading, spacing: -1) {
                fixedWidthText("↑ " + Format.rate(store.network.uploadPerSecond),
                               template: "↑ 99.9 MB/s", size: 9, alignment: .leading)
                fixedWidthText("↓ " + Format.rate(store.network.downloadPerSecond),
                               template: "↓ 99.9 MB/s", size: 9, alignment: .leading)
            }
        }
    }

    private func symbol(_ metric: Metric, tint: Color? = nil) -> some View {
        Image(systemName: metric.symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint ?? .primary)
    }

    /// Sizes the text to its widest possible value so the menu bar item doesn't
    /// shift every time a number changes.
    private func fixedWidthText(_ text: String, template: String, size: CGFloat = 12,
                                alignment: Alignment = .trailing,
                                color: Color = .primary) -> some View {
        Text(template)
            .hidden()
            .overlay(alignment: alignment) {
                Text(text).foregroundStyle(color)
            }
            .font(.system(size: size, weight: .medium).monospacedDigit())
            .lineLimit(1)
    }
}

/// All the visible items side by side, as they look in the menu bar. The app itself
/// gives each metric a status item of its own; this is for the style previews in
/// Settings and the screenshots.
struct MenuBarLabel: View {
    let store: MetricsStore
    let settings: AppSettings
    var style: MenuBarStyle?

    var body: some View {
        // About the gap macOS leaves between neighbouring status items.
        HStack(spacing: 4) {
            ForEach(settings.visibleMetrics) { metric in
                MetricLabel(metric: metric, store: store, settings: settings, style: style)
            }
        }
        .fixedSize()
    }
}
