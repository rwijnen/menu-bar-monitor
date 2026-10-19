import Darwin
import Foundation

/// Reads the CPU's temperature from the sensors Apple silicon exposes through IOHID.
///
/// There is no public interface for this. The functions used here are exported by
/// IOKit but undocumented, so they are looked up at run time: if a future macOS drops
/// or changes them, the lookup fails and the temperature is simply not shown. Intel
/// Macs keep theirs in the SMC instead, which this does not read.
final class TemperatureSampler {
    private typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64)
        -> Unmanaged<AnyObject>?
    private typealias GetFloat = @convention(c) (AnyObject, Int32) -> Double

    private static let temperatureEvent: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16

    private var copyEvent: CopyEvent?
    private var getFloat: GetFloat?
    /// The client has to stay alive for its services to keep answering.
    private var client: AnyObject?
    private var sensors: [AnyObject] = []

    init() {
        let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        func lookUp<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(iokit, name).map { unsafeBitCast($0, to: type) }
        }
        guard let create = lookUp("IOHIDEventSystemClientCreate", as: CreateClient.self),
              let setMatching = lookUp("IOHIDEventSystemClientSetMatching", as: SetMatching.self),
              let copyServices = lookUp("IOHIDEventSystemClientCopyServices",
                                        as: CopyServices.self),
              let copyProperty = lookUp("IOHIDServiceClientCopyProperty", as: CopyProperty.self),
              let copyEvent = lookUp("IOHIDServiceClientCopyEvent", as: CopyEvent.self),
              let getFloat = lookUp("IOHIDEventGetFloatValue", as: GetFloat.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue()
        else { return }

        // Apple's vendor usage page and its temperature usage.
        _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        let services = copyServices(client)?.takeRetainedValue() as? [AnyObject] ?? []
        let names = services.map {
            copyProperty($0, "Product" as CFString)?.takeRetainedValue() as? String ?? ""
        }
        // Chosen once: the sensors do not change while the app runs, and asking all
        // seventy-odd of them every reading would be wasted work.
        sensors = TemperatureMath.cpuSensorIndices(names: names).map { services[$0] }
        self.client = client
        self.copyEvent = copyEvent
        self.getFloat = getFloat
    }

    func read() -> Double? {
        guard let copyEvent, let getFloat, !sensors.isEmpty else { return nil }
        let values = sensors.compactMap { sensor -> Double? in
            guard let event = copyEvent(sensor, Self.temperatureEvent, 0, 0)?.takeRetainedValue()
            else { return nil }
            return getFloat(event, Self.temperatureField)
        }
        return TemperatureMath.average(values)
    }
}

enum TemperatureMath {
    /// The CPU's sensors among everything the system reports. Apple silicon names its
    /// die sensors "PMU tdie1", "PMU tdie2" and so on; older chips name the CPU
    /// clusters' sensors "pACC" and "eACC". Battery, SSD and calibration sensors
    /// ("PMU tcal") are left out, and so are the "PMU tdev" ones, which read nonsense.
    static func cpuSensorIndices(names: [String]) -> [Int] {
        let dies = names.indices.filter { names[$0].contains("tdie") }
        if !dies.isEmpty { return dies }
        return names.indices.filter { name in
            ["pACC", "eACC", "CPU"].contains { names[name].contains($0) }
        }
    }

    /// The mean of the plausible readings. A sensor that is off or broken reports
    /// zero or thousands of degrees below it.
    static func average(_ values: [Double]) -> Double? {
        let plausible = values.filter { $0 > 0 && $0 < 150 }
        return plausible.isEmpty ? nil : plausible.reduce(0, +) / Double(plausible.count)
    }
}
