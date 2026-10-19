import AppKit
import Darwin

/// Finds the apps using the most CPU, system processes included.
///
/// An ordinary process may read only its own user's processes, which would leave out
/// `WindowServer`, `kernel_task` and every other daemon. `/bin/ps` is installed setuid
/// root to read all of them, so the list comes from running it — only while the CPU
/// dropdown is open, since nothing else shows it. Its percentages are per core, as in
/// Activity Monitor, and are averaged by the kernel over the last few seconds.
///
/// Helper processes are counted under the app responsible for them (Safari's web
/// content, Chrome's renderers, Xcode's build tools), so the list reads as apps.
@MainActor
final class ProcessSampler {
    private let grouper = AppGrouper()
    private var isRunning = false

    /// Runs `ps` off the main thread and hands back the busiest `limit` apps on it.
    /// Grouping happens back on the main thread, where the app lookups are cached.
    func read(limit: Int, completion: @escaping @MainActor ([AppUsage]) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let entries = ProcessList.parse(Self.runPS() ?? "")
            Task { @MainActor in
                guard let self else { return }
                self.isRunning = false
                self.grouper.forget(allBut: Set(entries.map(\.pid)))
                completion(ProcessList.top(entries, limit: limit,
                                           group: self.grouper.group(for:)))
            }
        }
    }

    private nonisolated static func runPS() -> String? {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        // Every process; just the executable's name; no header row.
        ps.arguments = ["-Aceo", "pid=,pcpu=,comm="]
        let output = Pipe()
        ps.standardOutput = output
        ps.standardError = FileHandle.nullDevice
        do { try ps.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

enum ProcessList {
    struct Entry: Equatable {
        let pid: pid_t
        let cpu: Double
        let name: String
    }

    /// Lines of "  414  58.2 WindowServer". Names may contain spaces ("Claude Helper
    /// (Renderer)"), so everything after the second column is the name.
    static func parse(_ output: String) -> [Entry] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 2,
                                    omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = pid_t(fields[0]),
                  let cpu = Double(fields[1].replacingOccurrences(of: ",", with: "."))
            else { return nil }
            return Entry(pid: pid, cpu: cpu, name: String(fields[2]))
        }
    }

    /// Adds up each app's processes and keeps the busiest `limit`, busiest first. Idle
    /// processes are skipped before grouping, so most are never looked up at all.
    static func top(_ entries: [Entry], limit: Int,
                    group: (Entry) -> AppGroup) -> [AppUsage] {
        var totals: [String: (group: AppGroup, cpu: Double)] = [:]
        for entry in entries where entry.cpu > 0 {
            let owner = group(entry)
            totals[owner.key, default: (owner, 0)].cpu += entry.cpu
        }
        return totals.values
            .sorted { $0.cpu != $1.cpu ? $0.cpu > $1.cpu : $0.group.name < $1.group.name }
            .prefix(limit)
            .map { AppUsage(id: $0.group.key, name: $0.group.name, icon: $0.group.icon,
                            cpu: $0.cpu) }
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

    private var groups: [pid_t: AppGroup] = [:]
    private var iconsByPath: [String: NSImage] = [:]

    /// The app macOS holds responsible for the process, then the app bundle its
    /// executable lives in, and failing both the process on its own.
    func group(for entry: ProcessList.Entry) -> AppGroup {
        if let cached = groups[entry.pid] { return cached }
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
            group = AppGroup(key: "process:\(entry.name)", name: entry.name, icon: nil)
        }
        groups[entry.pid] = group
        return group
    }

    /// Drops processes that have exited, so a reused process number is looked up again.
    func forget(allBut running: Set<pid_t>) {
        groups = groups.filter { running.contains($0.key) }
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
