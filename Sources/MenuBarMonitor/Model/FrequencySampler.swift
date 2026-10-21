import Darwin
import Foundation
import IOKit

/// Works out how fast each cluster of cores has been running.
///
/// Apple silicon reports, per core, how long it spent in each of its clock steps
/// (IOReport's "CPU Core Performance States"), and the power manager's registry entry
/// holds the frequency of each step. The average clock is the time-weighted mean of
/// those frequencies. `powermetrics` reports the same thing but needs root; these two
/// sources do not. Both are undocumented, so IOReport is looked up at run time and a
/// failure means the frequency is simply not shown.
final class FrequencySampler {
    private let api = IOReportAPI()
    private var subscription: OpaquePointer?
    private var subscribed: CFMutableDictionary?
    private var previous: CFDictionary?
    private lazy var tables = DVFSTable.cpuTables()

    /// Nil on the first call, since the times are differences between two readings.
    func read() -> FrequencyReading? {
        guard let api, let sample = takeSample(api) else { return nil }
        defer { previous = sample }
        guard let previous,
              let delta = api.samplesDelta(previous, sample, nil)?.takeRetainedValue(),
              let channels = (delta as NSDictionary)["IOReportChannels"] as? [CFDictionary]
        else { return nil }

        var clusters: [Character: ClusterTotals] = [:]
        for channel in channels {
            guard api.subGroup(channel)?.takeUnretainedValue() as String?
                    == "CPU Core Performance States",
                  let name = api.channelName(channel)?.takeUnretainedValue() as String?,
                  let letter = name.first
            else { continue }
            let count = api.stateCount(channel)
            let states = (0..<max(count, 0)).map { index in
                (name: api.stateName(channel, index)?.takeUnretainedValue() as String? ?? "",
                 residency: api.stateResidency(channel, index))
            }
            clusters[letter, default: ClusterTotals()].add(states: states, tables: tables)
        }
        return FrequencyMath.reading(from: Array(clusters.values))
    }

    private func takeSample(_ api: IOReportAPI) -> CFDictionary? {
        if subscription == nil {
            guard let channels = api.copyChannels("CPU Stats" as CFString, nil, 0, 0, 0)?
                    .takeRetainedValue(),
                  let mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, channels)
            else { return nil }
            var subscribedChannels: Unmanaged<CFMutableDictionary>?
            subscription = api.createSubscription(nil, mutable, &subscribedChannels, 0, nil)
            subscribed = subscribedChannels?.takeRetainedValue()
        }
        guard let subscription, let subscribed else { return nil }
        return api.createSamples(subscription, subscribed, nil)?.takeRetainedValue()
    }
}

/// One cluster's clock steps, summed over its cores.
struct ClusterTotals {
    var weightedMHz: Double = 0
    var activeResidency: Double = 0
    var coreCount = 0
    var maxMHz: Double = 0

    mutating func add(states: [(name: String, residency: Int64)], tables: [String: [Double]]) {
        let active = states.compactMap { state in
            FrequencyMath.stepIndex(state.name).map { (index: $0, residency: state.residency) }
        }
        guard let table = DVFSTable.match(stepCount: active.count, in: tables) else { return }
        coreCount += 1
        maxMHz = max(maxMHz, table.max() ?? 0)
        for step in active where step.index < table.count {
            weightedMHz += Double(step.residency) * table[step.index]
            activeResidency += Double(step.residency)
        }
    }
}

enum FrequencyMath {
    /// Clock steps are named "V0P14", "V1P13" … — the number after V is the step's
    /// place in the frequency table. "IDLE" and "DOWN" are not steps.
    static func stepIndex(_ name: String) -> Int? {
        guard name.first == "V", let p = name.firstIndex(of: "P") else { return nil }
        return Int(name[name.index(after: name.startIndex)..<p])
    }

    static func reading(from clusters: [ClusterTotals]) -> FrequencyReading? {
        let usable = clusters.filter { $0.coreCount > 0 }.sorted { $0.maxMHz < $1.maxMHz }
        guard !usable.isEmpty else { return nil }
        let weighted = usable.map(\.weightedMHz).reduce(0, +)
        let residency = usable.map(\.activeResidency).reduce(0, +)
        return FrequencyReading(
            allCores: residency > 0 ? weighted / residency : nil,
            clusters: usable.map {
                FrequencyReading.Cluster(
                    mhz: $0.activeResidency > 0 ? $0.weightedMHz / $0.activeResidency : nil,
                    maxMHz: $0.maxMHz, coreCount: $0.coreCount)
            })
    }
}

/// The power manager's frequency tables ("voltage-states…" in the `pmgr` registry
/// entry): pairs of 32-bit frequency and voltage, one pair per clock step.
enum DVFSTable {
    /// Frequencies in MHz. Some tables count in Hz and others in kHz — on an M5 Pro the
    /// CPU tables are in kHz and the GPU's in Hz — so the unit is read off the size of
    /// the numbers: no clock is below 100 MHz or above 100 GHz.
    static func decode(_ data: Data) -> [Double] {
        let raw = stride(from: 0, to: data.count - data.count % 8, by: 8).map { offset in
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        }
        guard let largest = raw.max(), largest > 0 else { return [] }
        let divisor: Double = largest >= 100_000_000 ? 1_000_000 : 1_000
        return raw.map { Double(UInt32(littleEndian: $0)) / divisor }
    }

    /// The table for a cluster whose cores have `stepCount` clock steps. CPU tables
    /// start above zero and top out between half a gigahertz and ten; the GPU's start
    /// at zero. Tables that tie (two identical clusters) are interchangeable.
    static func match(stepCount: Int, in tables: [String: [Double]]) -> [Double]? {
        tables.keys.sorted()
            .compactMap { tables[$0] }
            .first { table in
                table.count == stepCount && (table.first ?? 0) > 0
                    && (500...10_000).contains(table.max() ?? 0)
            }
    }

    static func cpuTables() -> [String: [Double]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceNameMatching("pmgr"),
                                           &iterator) == KERN_SUCCESS
        else { return [:] }
        defer { IOObjectRelease(iterator) }

        var tables: [String: [Double]] = [:]
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0)
                == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as? [String: Any] {
                for (key, value) in dictionary
                where key.hasPrefix("voltage-states") && key.hasSuffix("-sram") {
                    if let data = value as? Data { tables[key] = decode(data) }
                }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return tables
    }
}

/// IOReport's functions, looked up in libIOReport at run time. Nil when any is missing.
private struct IOReportAPI {
    typealias CopyChannels = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64)
        -> Unmanaged<CFDictionary>?
    typealias CreateSubscription = @convention(c) (
        UnsafeRawPointer?, CFMutableDictionary,
        UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?
    ) -> OpaquePointer?
    typealias CreateSamples = @convention(c) (OpaquePointer, CFMutableDictionary, CFTypeRef?)
        -> Unmanaged<CFDictionary>?
    typealias SamplesDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?)
        -> Unmanaged<CFDictionary>?
    typealias ChannelString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    typealias StateCount = @convention(c) (CFDictionary) -> Int32
    typealias StateName = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    typealias StateResidency = @convention(c) (CFDictionary, Int32) -> Int64

    let copyChannels: CopyChannels
    let createSubscription: CreateSubscription
    let createSamples: CreateSamples
    let samplesDelta: SamplesDelta
    let subGroup: ChannelString
    let channelName: ChannelString
    let stateCount: StateCount
    let stateName: StateName
    let stateResidency: StateResidency

    init?() {
        guard let library = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return nil }
        func lookUp<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(library, name).map { unsafeBitCast($0, to: type) }
        }
        guard let copyChannels = lookUp("IOReportCopyChannelsInGroup", as: CopyChannels.self),
              let createSubscription = lookUp("IOReportCreateSubscription",
                                              as: CreateSubscription.self),
              let createSamples = lookUp("IOReportCreateSamples", as: CreateSamples.self),
              let samplesDelta = lookUp("IOReportCreateSamplesDelta", as: SamplesDelta.self),
              let subGroup = lookUp("IOReportChannelGetSubGroup", as: ChannelString.self),
              let channelName = lookUp("IOReportChannelGetChannelName", as: ChannelString.self),
              let stateCount = lookUp("IOReportStateGetCount", as: StateCount.self),
              let stateName = lookUp("IOReportStateGetNameForIndex", as: StateName.self),
              let stateResidency = lookUp("IOReportStateGetResidency", as: StateResidency.self)
        else { return nil }
        self.copyChannels = copyChannels
        self.createSubscription = createSubscription
        self.createSamples = createSamples
        self.samplesDelta = samplesDelta
        self.subGroup = subGroup
        self.channelName = channelName
        self.stateCount = stateCount
        self.stateName = stateName
        self.stateResidency = stateResidency
    }
}
