import AppKit
import Darwin

/// Finds the apps using the most CPU or memory, system processes included.
///
/// An ordinary process may read only its own user's processes, which would leave out
/// `WindowServer`, `kernel_task` and every other daemon. `/bin/ps` and `/usr/bin/top`
/// are installed setuid root to read all of them, so the lists come from running them —
/// only while the matching dropdown is open, since nothing else shows them.
///
/// Helper processes are counted under the app responsible for them (Safari's web
/// content, Chrome's renderers, Xcode's build tools), so the lists read as apps.
@MainActor
final class ProcessSampler {
    enum Measure {
        /// Per core, as Activity Monitor counts it, from `ps`: the kernel's own short
        /// decaying average.
        case cpu
        /// Physical footprint in bytes, from `top` — the figure Activity Monitor's Memory
        /// column shows. `ps` only knows resident size, which counts shared memory in
        /// every process that maps it and ranks the list quite differently.
        case memory
    }

    private let grouper = AppGrouper()
    private var running: Set<Measure> = []
    private var networkRunning = false
    private var previousNetwork: (bytes: [pid_t: NetworkProcessList.Entry], time: Date)?

    /// Runs the tool off the main thread and hands back the top `limit` apps by
    /// `measure`. Grouping happens back on the main thread, where lookups are cached.
    func read(_ measure: Measure, limit: Int,
              completion: @escaping @MainActor ([AppUsage]) -> Void) {
        guard !running.contains(measure) else { return }
        running.insert(measure)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let entries = Self.entries(for: measure)
            Task { @MainActor in
                guard let self else { return }
                self.running.remove(measure)
                completion(ProcessList.top(entries, limit: limit,
                                           group: self.grouper.group(for:)))
            }
        }
    }

    /// The apps moving the most data since the previous call, from `nettop`, which
    /// needs no privileges to count every process's bytes. The first call has nothing
    /// to compare with, so it only takes a baseline and hands back nil.
    func readNetwork(limit: Int, now: Date = Date(),
                     completion: @escaping @MainActor ([NetworkAppUsage]?) -> Void) {
        guard !networkRunning else { return }
        networkRunning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // Per process, cumulative bytes in and out, one sample, as CSV.
            let output = Self.run("/usr/bin/nettop",
                                  ["-P", "-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out"])
            let entries = NetworkProcessList.parse(output ?? "")
            Task { @MainActor in
                guard let self else { return }
                self.networkRunning = false
                let current = Dictionary(entries.map { ($0.pid, $0) },
                                         uniquingKeysWith: { first, _ in first })
                defer { self.previousNetwork = (current, now) }
                guard let previous = self.previousNetwork else { return completion(nil) }
                let rates = NetworkProcessList.rates(
                    from: previous.bytes, to: current,
                    seconds: now.timeIntervalSince(previous.time))
                completion(NetworkProcessList.top(rates, limit: limit) {
                    self.grouper.group(for: ProcessList.Entry(pid: $0.pid, value: 0,
                                                              name: $0.name))
                })
            }
        }
    }

    /// Forgets the previous `nettop` sample, so a dropdown opened again later does not
    /// average over the whole time it was closed.
    func resetNetwork() {
        previousNetwork = nil
    }

    private nonisolated static func entries(for measure: Measure) -> [ProcessList.Entry] {
        switch measure {
        case .cpu:
            // Every process; just the executable's name; no header row.
            return ProcessList.parsePS(run("/bin/ps", ["-Aceo", "pid=,pcpu=,comm="]) ?? "")
        case .memory:
            // One sample of every process, name last because it may contain spaces.
            // About 0.6 s of CPU on a Mac with 700 processes, hence the slower cadence.
            return ProcessList.parseTop(run("/usr/bin/top",
                                            ["-l", "1", "-stats", "pid,mem,command"]) ?? "")
        }
    }

    private nonisolated static func run(_ path: String, _ arguments: [String]) -> String? {
        let tool = Process()
        tool.executableURL = URL(fileURLWithPath: path)
        tool.arguments = arguments
        let output = Pipe()
        tool.standardOutput = output
        tool.standardError = FileHandle.nullDevice
        do { try tool.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        tool.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

enum ProcessList {
    struct Entry: Equatable {
        let pid: pid_t
        /// Per-core CPU percentage, or bytes of memory.
        let value: Double
        let name: String
    }

    /// `ps` lines of "  414  58.2 WindowServer". Names may contain spaces ("Claude
    /// Helper (Renderer)"), so everything after the second column is the name.
    static func parsePS(_ output: String) -> [Entry] {
        rows(output).compactMap { pid, value, name in
            Double(value.replacingOccurrences(of: ",", with: "."))
                .map { Entry(pid: pid, value: $0, name: name) }
        }
    }

    /// `top` lines of "414    2013M WindowServer", among a header block to skip. Sizes
    /// are binary (K, M, G) and may carry a trailing "+" or "-" for the direction they
    /// are moving in.
    static func parseTop(_ output: String) -> [Entry] {
        rows(output).compactMap { pid, value, name in
            bytes(value).map { Entry(pid: pid, value: $0, name: name) }
        }
    }

    static func bytes(_ size: String) -> Double? {
        var text = size.trimmingCharacters(in: CharacterSet(charactersIn: "+-*"))
        let multiplier: Double
        switch text.last {
        case "B": multiplier = 1
        case "K": multiplier = 1024
        case "M": multiplier = 1024 * 1024
        case "G": multiplier = 1024 * 1024 * 1024
        case "T": multiplier = 1024 * 1024 * 1024 * 1024
        default: return Double(text)
        }
        text.removeLast()
        return Double(text).map { $0 * multiplier }
    }

    /// Lines whose first column is a process number, split into three columns.
    private static func rows(_ output: String) -> [(pid_t, String, String)] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 2,
                                    omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = pid_t(fields[0]) else { return nil }
            return (pid, String(fields[1]),
                    fields[2].trimmingCharacters(in: .whitespaces))
        }
    }

    /// Adds up each app's processes and keeps the top `limit`, largest first. Processes
    /// at zero are skipped before grouping, so most are never looked up at all.
    static func top(_ entries: [Entry], limit: Int,
                    group: (Entry) -> AppGroup) -> [AppUsage] {
        var totals: [String: (group: AppGroup, value: Double)] = [:]
        for entry in entries where entry.value > 0 {
            let owner = group(entry)
            totals[owner.key, default: (owner, 0)].value += entry.value
        }
        return totals.values
            .sorted { $0.value != $1.value ? $0.value > $1.value
                                           : $0.group.name < $1.group.name }
            .prefix(limit)
            .map { AppUsage(id: $0.group.key, name: $0.group.name, icon: $0.group.icon,
                            value: $0.value) }
    }
}

enum NetworkProcessList {
    struct Entry: Equatable {
        let pid: pid_t
        let name: String
        let bytesIn: UInt64
        let bytesOut: UInt64
    }

    struct Rate: Equatable {
        let pid: pid_t
        let name: String
        let downloadPerSecond: Double
        let uploadPerSecond: Double
    }

    /// `nettop` lines of "Code Helper (Pl.67467,1285417,780756,": the name, a dot and
    /// the process number, then bytes in and out. Names are cut to fifteen characters
    /// and may contain dots, so the number is whatever follows the last one.
    static func parse(_ output: String) -> [Entry] {
        output.split(separator: "\n").compactMap { line in
            var fields = line.split(separator: ",", omittingEmptySubsequences: false)
            if fields.last?.isEmpty == true { fields.removeLast() }
            guard fields.count >= 3,
                  let bytesOut = UInt64(fields[fields.count - 1]),
                  let bytesIn = UInt64(fields[fields.count - 2])
            else { return nil }
            let label = fields.dropLast(2).joined(separator: ",")
            guard let dot = label.lastIndex(of: "."),
                  let pid = pid_t(label[label.index(after: dot)...])
            else { return nil }
            return Entry(pid: pid, name: String(label[..<dot]), bytesIn: bytesIn,
                         bytesOut: bytesOut)
        }
    }

    /// Bytes per second for each process present in both samples. A process whose
    /// counts went down is a new one with a reused number, and is skipped.
    static func rates(from previous: [pid_t: Entry], to current: [pid_t: Entry],
                      seconds: TimeInterval) -> [Rate] {
        guard seconds > 0 else { return [] }
        return current.values.compactMap { now in
            guard let before = previous[now.pid], before.name == now.name,
                  now.bytesIn >= before.bytesIn, now.bytesOut >= before.bytesOut
            else { return nil }
            return Rate(pid: now.pid, name: now.name,
                        downloadPerSecond: Double(now.bytesIn - before.bytesIn) / seconds,
                        uploadPerSecond: Double(now.bytesOut - before.bytesOut) / seconds)
        }
    }

    /// Adds up each app's processes and keeps the busiest `limit`, by traffic in both
    /// directions. Silent processes are left out, rather than listed at 0 KB/s.
    static func top(_ rates: [Rate], limit: Int,
                    group: (Rate) -> AppGroup) -> [NetworkAppUsage] {
        var totals: [String: (group: AppGroup, down: Double, up: Double)] = [:]
        for rate in rates where rate.downloadPerSecond + rate.uploadPerSecond > 0 {
            let owner = group(rate)
            totals[owner.key, default: (owner, 0, 0)].down += rate.downloadPerSecond
            totals[owner.key, default: (owner, 0, 0)].up += rate.uploadPerSecond
        }
        return totals.values
            .sorted {
                let left = $0.down + $0.up, right = $1.down + $1.up
                return left != right ? left > right : $0.group.name < $1.group.name
            }
            .prefix(limit)
            .map { NetworkAppUsage(id: $0.group.key, name: $0.group.name, icon: $0.group.icon,
                                   downloadPerSecond: $0.down, uploadPerSecond: $0.up) }
    }
}

struct AppGroup {
    let key: String
    let name: String
    let icon: NSImage?
}

/// Which app a process belongs to, remembered per process.
final class AppGrouper {
    private typealias ResponsiblePID = @convention(c) (pid_t) -> pid_t
    private let responsiblePID: ResponsiblePID? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                 "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: ResponsiblePID.self)
    }()

    private var groups: [pid_t: (name: String, group: AppGroup)] = [:]
    private var iconsByPath: [String: NSImage] = [:]

    /// The app macOS holds responsible for the process, then the app bundle its
    /// executable lives in, and failing both the process on its own — named after its
    /// executable, since `top` cuts names to 16 characters.
    func group(for entry: ProcessList.Entry) -> AppGroup {
        // Keyed by number and name together: a number reused by a new process is
        // looked up again.
        if let cached = groups[entry.pid], cached.name == entry.name { return cached.group }
        let owner = entry.pid > 0 ? (responsiblePID?(entry.pid) ?? entry.pid) : entry.pid
        let ownerPID = owner > 0 ? owner : entry.pid
        let group: AppGroup

        if let app = NSRunningApplication(processIdentifier: ownerPID),
           let name = app.localizedName {
            group = AppGroup(key: app.bundleURL?.path ?? name, name: name, icon: app.icon)
        } else if let path = executablePath(of: ownerPID),
                  let range = path.range(of: ".app/") {
            let appPath = String(path[..<range.lowerBound]) + ".app"
            let name = URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
            group = AppGroup(key: appPath, name: name, icon: icon(forAppAt: appPath))
        } else {
            let name = executablePath(of: entry.pid)
                .map { URL(fileURLWithPath: $0).lastPathComponent } ?? entry.name
            group = AppGroup(key: "process:\(name)", name: name, icon: nil)
        }
        groups[entry.pid] = (entry.name, group)
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
}
