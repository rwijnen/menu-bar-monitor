import AppKit

let app = NSApplication.shared

MainActor.assumeIsolated {
    if DevTools.runIfRequested() { exit(0) }
}

let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
