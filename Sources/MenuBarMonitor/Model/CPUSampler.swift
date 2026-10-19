import Darwin

/// Reads per-core tick counters and turns the difference between two calls into
/// usage percentages, the same way Activity Monitor does.
final class CPUSampler {
    private struct Ticks {
        var user: UInt32
        var system: UInt32
        var idle: UInt32
        var nice: UInt32
    }

    private let host = mach_host_self()
    private var previous: [Ticks] = []

    /// Returns nil on the first call, since usage needs two snapshots.
    func read() -> CPUReading? {
        guard let current = readTicks() else { return nil }
        defer { previous = current }
        guard previous.count == current.count else { return nil }

        var user: UInt64 = 0, system: UInt64 = 0, idle: UInt64 = 0
        var cores: [Double] = []
        for (old, new) in zip(previous, current) {
            // Counters are 32-bit and wrap; wrapping subtraction keeps the delta right.
            let coreUser = UInt64(new.user &- old.user) + UInt64(new.nice &- old.nice)
            let coreSystem = UInt64(new.system &- old.system)
            let coreIdle = UInt64(new.idle &- old.idle)
            user += coreUser
            system += coreSystem
            idle += coreIdle
            let coreTotal = coreUser + coreSystem + coreIdle
            let busy = Double(coreUser + coreSystem)
            cores.append(coreTotal > 0 ? busy / Double(coreTotal) * 100 : 0)
        }
        let total = Double(user + system + idle)
        guard total > 0 else { return nil }
        let userPct = Double(user) / total * 100
        let systemPct = Double(system) / total * 100
        return CPUReading(total: userPct + systemPct, user: userPct, system: systemPct,
                          coreCount: current.count, cores: cores)
    }

    private func readTicks() -> [Ticks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info,
                                  &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        return (0..<Int(cpuCount)).map { cpu in
            let base = cpu * Int(CPU_STATE_MAX)
            func tick(_ state: Int32) -> UInt32 { UInt32(bitPattern: info[base + Int(state)]) }
            return Ticks(user: tick(CPU_STATE_USER), system: tick(CPU_STATE_SYSTEM),
                         idle: tick(CPU_STATE_IDLE), nice: tick(CPU_STATE_NICE))
        }
    }
}
