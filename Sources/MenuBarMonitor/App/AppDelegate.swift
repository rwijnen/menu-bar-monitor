import AppKit
import Observation
import SwiftUI

/// Hosts the SwiftUI label inside the status bar button. Clicks pass through to
/// the button, and size changes are reported so the item can resize.
private final class StatusLabelHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onSizeChange?() }
    }
}

/// One metric's menu bar item and its dropdown. Separate items, rather than one
/// item with three parts, give each its own click target, highlight, place in the
/// menu bar (⌘-drag) and accessibility element — the way the system's own items
/// behave.
@MainActor
private final class StatusItemController {
    let metric: Metric
    private let item: NSStatusItem
    private let label: StatusLabelHostingView<MetricLabel>
    private let makePanelView: () -> PanelView
    private var panel: DropdownPanel?

    init(metric: Metric, store: MetricsStore, settings: AppSettings,
         makePanelView: @escaping () -> PanelView,
         target: AnyObject, action: Selector) {
        self.metric = metric
        self.makePanelView = makePanelView
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = metric.autosaveName
        label = StatusLabelHostingView(
            rootView: MetricLabel(metric: metric, store: store, settings: settings))

        guard let button = item.button else { return }
        button.target = target
        button.action = action
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.setAccessibilityLabel(metric.title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.onSizeChange = { [weak self] in self?.updateLength() }
        button.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
    }

    func owns(_ sender: Any?) -> Bool {
        (sender as? NSStatusBarButton) === item.button
    }

    var isVisible: Bool {
        get { item.isVisible }
        set { if item.isVisible != newValue { item.isVisible = newValue } }
    }

    func updateLength() {
        let width = ceil(label.fittingSize.width)
        if item.length != width { item.length = width }
    }

    func showPanel() {
        guard let button = item.button, let buttonWindow = button.window else { return }
        let panel = self.panel ?? DropdownPanel(rootView: makePanelView())
        self.panel = panel
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        panel.show(below: anchor)
        button.highlight(true)
    }

    func hidePanel() {
        panel?.orderOut(nil)
        item.button?.highlight(false)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    private(set) lazy var store = MetricsStore(settings: settings)

    private var items: [Metric: StatusItemController] = [:]
    private var dropdown = DropdownState()
    private var settingsWindow: NSWindow?
    private var eventMonitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        for metric in Metric.creationOrder {
            items[metric] = StatusItemController(
                metric: metric, store: store, settings: settings,
                makePanelView: { [unowned self] in
                    PanelView(metric: metric, store: store, settings: settings,
                              actions: panelActions)
                },
                target: self, action: #selector(statusItemClicked(_:)))
        }
        applyVisibility()
        observeVisibility()

        store.onUpdate = { [weak self] in self?.updateLengths() }
        store.start()
        updateLengths()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveTraffic()
    }

    private func updateLengths() {
        items.values.forEach { $0.updateLength() }
    }

    // MARK: - Which items are shown

    private func applyVisibility() {
        for (metric, item) in items {
            let visible = settings.isVisible(metric)
            if !visible, dropdown.open == metric { closeDropdown() }
            item.isVisible = visible
        }
    }

    /// Re-applies visibility whenever a Show in menu bar toggle changes. Observation
    /// fires once per registration, so each change registers again.
    private func observeVisibility() {
        withObservationTracking {
            for metric in Metric.allCases { _ = settings.isVisible(metric) }
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyVisibility()
                self?.observeVisibility()
            }
        }
    }

    // MARK: - Dropdowns

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let clicked = items.values.first(where: { $0.owns(sender) }) else { return }
        let change = dropdown.click(clicked.metric)
        store.detailMetric = dropdown.open
        if let close = change.close { items[close]?.hidePanel() }
        if let open = change.open {
            items[open]?.showPanel()
            startDismissMonitors()
        } else {
            stopDismissMonitors()
        }
    }

    private func closeDropdown() {
        if let open = dropdown.dismiss() { items[open]?.hidePanel() }
        store.detailMetric = nil
        stopDismissMonitors()
    }

    /// Close on any click outside the app, or on Escape. Clicks on the other items
    /// are inside the app, so they arrive as item clicks instead and move the
    /// dropdown rather than just closing it.
    private func startDismissMonitors() {
        guard eventMonitors.isEmpty else { return }
        let outsideClick = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeDropdown() }
        }
        let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.closeDropdown() }
            return nil
        }
        eventMonitors = [outsideClick, escape].compactMap { $0 }
    }

    private func stopDismissMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    private var panelActions: PanelActions {
        PanelActions(
            openSettings: { [weak self] in
                self?.closeDropdown()
                self?.showSettings()
            },
            openActivityMonitor: { [weak self] in
                self?.closeDropdown()
                NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath:
                        "/System/Applications/Utilities/Activity Monitor.app"),
                    configuration: NSWorkspace.OpenConfiguration())
            },
            quit: { NSApp.terminate(nil) }
        )
    }

    // MARK: - Settings

    private func showSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(
                rootView: SettingsView(settings: settings, store: store))
            controller.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: controller)
            window.title = "Menu Bar Monitor Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
