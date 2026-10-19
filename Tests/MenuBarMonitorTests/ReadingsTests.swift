import Testing

@testable import MenuBarMonitor

@Suite("Readings")
struct ReadingsTests {

    @Test("memory used is a fraction of what is installed, never above one")
    func usedFraction() {
        #expect(MemoryReading(total: 0, used: 10).usedFraction == 0)
        #expect(MemoryReading(total: 100, used: 25).usedFraction == 0.25)
        #expect(MemoryReading(total: 100, used: 150).usedFraction == 1)
    }

    @Test("memory pressure has a word for each level")
    func pressureTitles() {
        #expect(MemoryPressure.normal.title == "Normal")
        #expect(MemoryPressure.warning.title == "Elevated")
        #expect(MemoryPressure.critical.title == "Critical")
    }
}
