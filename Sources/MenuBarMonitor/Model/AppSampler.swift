import AppKit
import Darwin

/// Finds the apps using the most CPU. Helper processes are attributed to the app
/// responsible for them (Safari's web content, Chrome renderers, Xcode's
/// build tools), so the list reads like apps rather than process names.
///
/// Only processes owned by the current user are readable without root, which
/// covers the apps you run; system daemons are left out.
final class AppSampler {
    private struct Group {
        let key: String
        let name: String
        let icon: NSImage?
    }

    private typealias ResponsiblePID = @convention(c) (pid_t) -> pid_t
    private let responsiblePID: ResponsiblePID? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                 "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: ResponsiblePID.self)
    }()

    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private var previousCPUTime: [pid_t: UInt64] = [:]
    private var previousTime: UInt64 = 0
    private var groups: [pid_t: Group] = [:]
    private var iconsByPath: [String: NSImage] = [:]

    func read(limit: Int, coreCount: Int) -> [AppUsage] {
        let now = DispatchTime.now().uptimeNanoseconds
        let pids = allPIDs()

        var currentCPUTime: [pid_t: UInt64] = [:]
        var busyByGroup: [String: (group: Group, nanoseconds: UInt64)] = [:]
        for pid in pids {
            guard let cpuTime = cpuTime(of: pid) else { continue }
            currentCPUTime[pid] = cpuTime
            guard let previous = previousCPUTime[pid], cpuTime > previous else { continue }
            let group = group(for: pid)
            busyByGroup[group.key, default: (group, 0)].nanoseconds += cpuTime - previous
        }

        let elapsed = previousTime > 0 ? now - previousTime : 0
        previousCPUTime = currentCPUTime
        previousTime = now
        groups = groups.filter { currentCPUTime[$0.key] != nil }
        guard elapsed > 0 else { return [] }

        let capacity = Double(elapsed) * Double(max(coreCount, 1))
        return busyByGroup.values
            .map { AppUsage(id: $0.group.key, name: $0.group.name, icon: $0.group.icon,
                            cpu: Double($0.nanoseconds) / capacity * 100) }
            .sorted { $0.cpu > $1.cpu }
            .prefix(limit)
            .map { $0 }
    }

    private func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        return pids.prefix(Int(max(count, 0))).filter { $0 > 0 }
    }

    /// Total user + system CPU time in nanoseconds, or nil if the process isn't readable.
    private func cpuTime(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard result == 0 else { return nil }
        // On Apple silicon these are Mach ticks, not nanoseconds.
        let ticks = info.ri_user_time + info.ri_system_time
        return ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    private func group(for pid: pid_t) -> Group {
        if let cached = groups[pid] { return cached }
        let owner = responsiblePID?(pid) ?? pid
        let ownerPID = owner > 0 ? owner : pid
        let group: Group

        if let app = NSRunningApplication(processIdentifier: ownerPID),
           let name = app.localizedName {
            group = Group(key: app.bundleURL?.path ?? name, name: name, icon: app.icon)
        } else if let path = executablePath(of: ownerPID), let range = path.range(of: ".app/") {
            let appPath = String(path[..<range.lowerBound]) + ".app"
            let name = URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
            group = Group(key: appPath, name: name, icon: icon(forAppAt: appPath))
        } else {
            let name = processName(of: pid) ?? "pid \(pid)"
            group = Group(key: "process:\(name)", name: name, icon: nil)
        }
        groups[pid] = group
        return group
    }

    private func icon(forAppAt path: String) -> NSImage {
        if let cached = iconsByPath[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        iconsByPath[path] = icon
        return icon
    }

    private func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private func processName(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
