import Foundation
import Testing

@testable import MenuBarMonitor

@Suite("Metrics in the menu bar")
struct MetricTests {

    /// Each new status item goes to the left of the existing ones, so they are made
    /// right to left for CPU to end up first.
    @Test("items are created right to left, so they read CPU, memory, network")
    func creationOrder() {
        #expect(Metric.creationOrder == [.network, .memory, .cpu])
        #expect(Metric.allCases == [.cpu, .memory, .network])
    }

    /// macOS stores each item's position under its autosave name. Renaming one
    /// would quietly forget where everyone had ⌘-dragged it.
    @Test("position names stored on disk do not change")
    func autosaveNames() {
        #expect(Metric.allCases.map(\.autosaveName)
                == ["MenuBarMonitor.cpu", "MenuBarMonitor.memory", "MenuBarMonitor.network"])
    }
}

@Suite("Dropdown state")
struct DropdownStateTests {

    @Test("clicking an item opens its dropdown")
    func opens() {
        var state = DropdownState()
        let change = state.click(.cpu)
        #expect(change.close == nil)
        #expect(change.open == .cpu)
        #expect(state.open == .cpu)
    }

    @Test("clicking the open item closes it")
    func closesOnSecondClick() {
        var state = DropdownState()
        _ = state.click(.memory)
        let change = state.click(.memory)
        #expect(change.close == .memory)
        #expect(change.open == nil)
        #expect(state.open == nil)
    }

    @Test("clicking another item moves the dropdown there")
    func movesToAnotherItem() {
        var state = DropdownState()
        _ = state.click(.cpu)
        let change = state.click(.network)
        #expect(change.close == .cpu)
        #expect(change.open == .network)
        #expect(state.open == .network)
    }

    @Test("dismissing closes whatever is open, and nothing when nothing is")
    func dismiss() {
        var state = DropdownState()
        #expect(state.dismiss() == nil)
        _ = state.click(.memory)
        #expect(state.dismiss() == .memory)
        #expect(state.open == nil)
        #expect(state.dismiss() == nil)
    }
}

@MainActor
@Suite("Which items are shown")
struct MetricVisibilityTests {

    private func makeSettings() -> AppSettings {
        let suite = "MenuBarMonitorTests.\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return AppSettings(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test("every metric is shown on a first launch, in reading order")
    func allVisible() {
        let settings = makeSettings()
        #expect(settings.visibleMetrics == [.cpu, .memory, .network])
        #expect(Metric.allCases.allSatisfy(settings.canHide))
    }

    @Test("hiding one leaves the others in order")
    func hideOne() {
        let settings = makeSettings()
        settings.setVisible(.memory, false)
        #expect(settings.visibleMetrics == [.cpu, .network])
        #expect(settings.showMemory == false)
        settings.setVisible(.memory, true)
        #expect(settings.visibleMetrics == [.cpu, .memory, .network])
    }

    /// With no item left there would be no way to open Settings again.
    @Test("the last visible item cannot be hidden")
    func lastOneStays() {
        let settings = makeSettings()
        settings.setVisible(.cpu, false)
        settings.setVisible(.memory, false)
        #expect(settings.canHide(.network) == false)
        settings.setVisible(.network, false)
        #expect(settings.visibleMetrics == [.network])
        // A hidden one can always come back.
        #expect(settings.canHide(.cpu))
        settings.setVisible(.cpu, true)
        #expect(settings.visibleMetrics == [.cpu, .network])
    }
}
