/// One of the things the app measures. Each has its own menu bar item and its own
/// dropdown, so it can be clicked, moved and hidden on its own.
enum Metric: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case network

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "arrow.up.arrow.down"
        }
    }

    /// macOS places a new status item to the left of those created before it, so
    /// creating them in reverse leaves them in reading order: CPU, memory, network.
    static var creationOrder: [Metric] { allCases.reversed() }

    /// Where macOS remembers the item's position after it is ⌘-dragged. Stored in
    /// the user's defaults, so never rename one.
    var autosaveName: String { "MenuBarMonitor.\(rawValue)" }
}

/// Which metric's dropdown is open. At most one is, as with menus: clicking a second
/// item moves the dropdown there, and clicking the open one closes it.
struct DropdownState {
    private(set) var open: Metric?

    /// What a click on `metric`'s item should close and open.
    mutating func click(_ metric: Metric) -> (close: Metric?, open: Metric?) {
        if open == metric {
            open = nil
            return (metric, nil)
        }
        let previous = open
        open = metric
        return (previous, metric)
    }

    /// A click elsewhere, Escape, or the open item being hidden. Returns what to close.
    mutating func dismiss() -> Metric? {
        defer { open = nil }
        return open
    }
}
