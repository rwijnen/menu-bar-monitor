import Darwin
import Foundation

final class MemorySampler {
    private let host = mach_host_self()
    private let pageSize = UInt64(vm_kernel_page_size)

    func read() -> MemoryReading {
        var reading = MemoryReading()

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let anonymous = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            reading.app = (anonymous > purgeable ? anonymous - purgeable : 0) * pageSize
            reading.wired = UInt64(stats.wire_count) * pageSize
            reading.compressed = UInt64(stats.compressor_page_count) * pageSize
            reading.used = reading.app + reading.wired + reading.compressed
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            reading.swapUsed = swap.xsu_used
        }

        var level: Int32 = 0
        var levelSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize,
                        nil, 0) == 0 {
            // 1 = normal, 2 = warning, 4 = critical
            reading.pressure = level >= 4 ? .critical : level == 2 ? .warning : .normal
        }

        return reading
    }
}
