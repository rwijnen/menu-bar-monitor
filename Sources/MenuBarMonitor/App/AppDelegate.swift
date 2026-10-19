import AppKit
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    private(set) lazy var store = MetricsStore(settings: settings)

    private var statusItem: NSStatusItem!
    private var label: NSView?
    private var panel: DropdownPanel?
    private var settingsWindow: NSWindow?
    private var eventMonitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "MenuBarMonitor"

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.setAccessibilityLabel("Menu Bar Monitor")

            let label = StatusLabelHostingView(
                rootView: MenuBarLabel(store: store, settings: settings))
            label.translatesAutoresizingMaskIntoConstraints = false
            label.onSizeChange = { [weak self] in self?.updateStatusItemLength() }
            button.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
            self.label = label
        }

        store.onUpdate = { [weak self] in self?.updateStatusItemLength() }
        store.start()
        updateStatusItemLength()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveTraffic()
    }

    private func updateStatusItemLength() {
        guard let label else { return }
        let width = ceil(label.fittingSize.width)
        if statusItem.length != width { statusItem.length = width }
    }

    // MARK: Dropdown

    @objc private func statusItemClicked() {
        if panel?.isVisible == true { closePanel() } else { openPanel() }
    }

    private func openPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        panel.show(below: anchor)
        button.highlight(true)

        // Close on any click outside the app, or on Escape.
        let outsideClick = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }
        let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.closePanel() }
            return nil
        }
        eventMonitors = [outsideClick, escape].compactMap { $0 }
    }

    private func closePanel() {
        panel?.orderOut(nil)
        statusItem.button?.highlight(false)
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    private func makePanel() -> DropdownPanel {
        let actions = PanelActions(
            openSettings: { [weak self] in
                self?.closePanel()
                self?.showSettings()
            },
            openActivityMonitor: { [weak self] in
                self?.closePanel()
                NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath:
                        "/System/Applications/Utilities/Activity Monitor.app"),
                    configuration: NSWorkspace.OpenConfiguration())
            },
            quit: { NSApp.terminate(nil) }
        )
        return DropdownPanel(
            rootView: PanelView(store: store, settings: settings, actions: actions))
    }

    // MARK: Settings

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
