import Foundation
import Testing

@testable import MenuBarMonitor

/// These read the real counters of whatever machine runs them, so they check
/// shape and consistency rather than exact values.
@Suite("Samplers, on this machine")
struct SamplerTests {

    @Test("CPU usage needs two readings, then stays between 0 and 100")
    func cpu() throws {
        let sampler = CPUSampler()
        #expect(sampler.read() == nil)
        burnCPU(for: 0.2)
        let reading = try #require(sampler.read())
        #expect((0...100).contains(reading.total))
        #expect(abs(reading.user + reading.system - reading.total) < 0.001)
        #expect(reading.coreCount == ProcessInfo.processInfo.processorCount)
    }

    @Test("memory used is app + wired + compressed, within what is installed")
    func memory() {
        let reading = MemorySampler().read()
        #expect(reading.total == ProcessInfo.processInfo.physicalMemory)
        #expect(reading.used == reading.app + reading.wired + reading.compressed)
        #expect(reading.wired > 0)
        #expect(reading.used <= reading.total)
        #expect((0...1).contains(reading.usedFraction))
    }

    @Test("network rates start at zero, then name the interface they measure")
    func network() {
        let sampler = NetworkSampler()
        let first = sampler.read()
        #expect(first.downloadPerSecond == 0)
        #expect(first.uploadPerSecond == 0)

        Thread.sleep(forTimeInterval: 0.2)
        let second = sampler.read()
        #expect(second.downloadPerSecond.isFinite && second.uploadPerSecond.isFinite)
        // A runner may have no network at all; when it does, the name must be usable.
        if let name = second.interfaceName {
            #expect(!name.isEmpty)
            #expect(second.interfaceDisplayName?.isEmpty == false)
        }
    }

    private func burnCPU(for seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        var value = 0.5
        while Date() < end { value = sin(value) + 1 }
        #expect(value.isFinite)
    }
}
