import Foundation
import Observation

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case sparklines
    case miniBars
    case iconsAndNumbers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sparklines: "Sparklines"
        case .miniBars: "Mini bars"
        case .iconsAndNumbers: "Icons and numbers"
        }
    }

    var subtitle: String {
        switch self {
        case .sparklines: "Live graphs of the last 20 readings"
        case .miniBars: "Small level meters, the most compact option"
        case .iconsAndNumbers: "Exact values at a glance"
        }
    }
}

@MainActor @Observable
final class AppSettings {
    private enum Key {
        static let style = "menuBarStyle"
        static let showCPU = "showCPU"
        static let showMemory = "showMemory"
        static let showNetwork = "showNetwork"
        static let refreshInterval = "refreshInterval"
        static let colorWarnings = "colorWarnings"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var style: MenuBarStyle { didSet { defaults.set(style.rawValue, forKey: Key.style) } }
    var showCPU: Bool { didSet { defaults.set(showCPU, forKey: Key.showCPU) } }
    var showMemory: Bool { didSet { defaults.set(showMemory, forKey: Key.showMemory) } }
    var showNetwork: Bool { didSet { defaults.set(showNetwork, forKey: Key.showNetwork) } }
    /// Seconds between readings.
    var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }
    /// Turns CPU red above 85%, and memory amber or red under pressure.
    var colorWarnings: Bool {
        didSet { defaults.set(colorWarnings, forKey: Key.colorWarnings) }
    }

    var visibleMetricCount: Int { [showCPU, showMemory, showNetwork].filter { $0 }.count }

    /// The metrics with an item in the menu bar, in reading order.
    var visibleMetrics: [Metric] { Metric.allCases.filter(isVisible) }

    func isVisible(_ metric: Metric) -> Bool {
        switch metric {
        case .cpu: showCPU
        case .memory: showMemory
        case .network: showNetwork
        }
    }

    /// Whether `metric` could be switched off. The last visible one cannot: with no
    /// item left in the menu bar there would be no way back into Settings.
    func canHide(_ metric: Metric) -> Bool {
        !isVisible(metric) || visibleMetricCount > 1
    }

    /// Shows or hides `metric`'s item. Hiding the last visible one is ignored.
    func setVisible(_ metric: Metric, _ visible: Bool) {
        guard visible || canHide(metric) else { return }
        switch metric {
        case .cpu: showCPU = visible
        case .memory: showMemory = visible
        case .network: showNetwork = visible
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        style = defaults.string(forKey: Key.style).flatMap(MenuBarStyle.init(rawValue:))
            ?? .sparklines
        showCPU = defaults.object(forKey: Key.showCPU) as? Bool ?? true
        showMemory = defaults.object(forKey: Key.showMemory) as? Bool ?? true
        showNetwork = defaults.object(forKey: Key.showNetwork) as? Bool ?? true
        refreshInterval = defaults.object(forKey: Key.refreshInterval) as? Double ?? 2
        colorWarnings = defaults.object(forKey: Key.colorWarnings) as? Bool ?? true
    }
}
