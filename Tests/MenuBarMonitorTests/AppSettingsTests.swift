import Foundation
import Testing

@testable import MenuBarMonitor

@MainActor
@Suite("Settings")
struct AppSettingsTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "MenuBarMonitorTests.\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    @Test("a first launch shows everything as sparklines, every two seconds")
    func defaults() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.style == .sparklines)
        #expect(settings.showCPU && settings.showMemory && settings.showNetwork)
        #expect(settings.refreshInterval == 2)
        #expect(settings.colorWarnings)
        #expect(settings.visibleMetricCount == 3)
    }

    @Test("changes are kept across launches")
    func persistence() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.style = .miniBars
        settings.showNetwork = false
        settings.refreshInterval = 5
        settings.colorWarnings = false

        let relaunched = AppSettings(defaults: defaults)
        #expect(relaunched.style == .miniBars)
        #expect(relaunched.showNetwork == false)
        #expect(relaunched.refreshInterval == 5)
        #expect(relaunched.colorWarnings == false)
        #expect(relaunched.visibleMetricCount == 2)
    }

    /// The raw values are what is stored in the user's defaults. Renaming a case
    /// would quietly reset everyone's chosen style on the next update.
    @Test("style names stored on disk do not change")
    func storedStyleNames() {
        #expect(MenuBarStyle.allCases.map(\.rawValue)
                == ["sparklines", "miniBars", "iconsAndNumbers"])
    }

    @Test("an unknown stored style falls back to sparklines")
    func unknownStyle() {
        let defaults = makeDefaults()
        defaults.set("hologram", forKey: "menuBarStyle")
        #expect(AppSettings(defaults: defaults).style == .sparklines)
    }
}
