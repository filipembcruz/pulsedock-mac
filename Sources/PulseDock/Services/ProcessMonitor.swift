import Foundation
import AppKit
import Darwin
import Combine

struct ProcInfo: Identifiable, Equatable {
    let id: pid_t
    var pid: pid_t { id }
    var name: String
    var path: String
    var bundlePath: String?
    var cpu: Double          // percent of one core (100 = one full core)
    var memory: UInt64       // physical footprint, bytes (same number Activity Monitor shows)
    var diskRead: Double     // bytes/s
    var diskWrite: Double    // bytes/s
    var isProtected: Bool
}

/// Processes grouped under the app that owns them (Chrome + all its helpers = one row).
struct AppGroup: Identifiable {
    let id: String
    var name: String
    var icon: NSImage?
    var pids: [pid_t]
    var cpu: Double
    var memory: UInt64
    var diskRead: Double
    var diskWrite: Double
    var app: NSRunningApplication?
    var isProtected: Bool
    var isBackground: Bool
    var mainPID: pid_t { app?.processIdentifier ?? pids.first ?? 0 }
}

enum ProcSort: String, CaseIterable, Identifiable {
    case memory, cpu, disk
    var id: String { rawValue }
}

/// Raw per-process sampler. Runs on a background queue.
final class ProcessSampler {
    private struct Prev { var cpuNs: Double; var read: UInt64; var written: UInt64 }
    private var prev: [pid_t: Prev] = [:]
    private var lastWall: TimeInterval = 0
    private var nameCache: [pid_t: (name: String, path: String)] = [:]
    private let timebase: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb.denom == 0 ? 1 : Double(tb.numer) / Double(tb.denom)
    }()
    private let myUID = getuid()
    private let myPID = getpid()

    static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "Dock", "Finder", "SystemUIServer",
        "ControlCenter", "NotificationCenter", "coreaudiod", "cfprefsd", "distnoted", "UserEventAgent",
        "mds", "mds_stores", "mdworker", "mdworker_shared", "trustd", "secd", "securityd", "tccd",
        "WallpaperAgent", "Spotlight", "TextInputMenuAgent", "universalaccessd", "talagent", "sharingd",
        "PulseDock", "useractivityd", "pboard", "lsd", "corespotlightd", "nsurlsessiond", "CommCenter",
    ]

    func sample() -> [ProcInfo] {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = lastWall == 0 ? 0 : now - lastWall
        lastWall = now

        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimated) + 64)
        let n = pids.withUnsafeMutableBufferPointer { buf in
            proc_listallpids(buf.baseAddress, Int32(buf.count * MemoryLayout<pid_t>.size))
        }
        guard n > 0 else { return [] }

        var result: [ProcInfo] = []
        var nextPrev: [pid_t: Prev] = [:]
        var seen = Set<pid_t>()

        for pid in pids.prefix(Int(n)) where pid > 0 {
            seen.insert(pid)
            // Only the user's own processes: those are the ones we can read and close.
            var bsd = proc_bsdinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize else { continue }
            guard bsd.pbi_uid == myUID else { continue }

            var usage = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &usage) { ptr -> Bool in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) == 0
                }
            }
            guard ok else { continue }

            let ident = identity(of: pid)
            let cpuNs = Double(usage.ri_user_time + usage.ri_system_time) * timebase
            var cpu = 0.0
            var rd = 0.0
            var wr = 0.0
            if let p = prev[pid], dt > 0 {
                cpu = max(0, (cpuNs - p.cpuNs) / (dt * 1_000_000_000) * 100)
                rd = Double(usage.ri_diskio_bytesread &- p.read) / dt
                wr = Double(usage.ri_diskio_byteswritten &- p.written) / dt
                if usage.ri_diskio_bytesread < p.read { rd = 0 }
                if usage.ri_diskio_byteswritten < p.written { wr = 0 }
            }
            nextPrev[pid] = Prev(cpuNs: cpuNs, read: usage.ri_diskio_bytesread, written: usage.ri_diskio_byteswritten)

            let isProtected = pid == myPID || pid <= 1 || Self.protectedNames.contains(ident.name)
            result.append(ProcInfo(id: pid, name: ident.name, path: ident.path,
                                   bundlePath: Self.outermostApp(in: ident.path),
                                   cpu: cpu, memory: usage.ri_phys_footprint,
                                   diskRead: rd, diskWrite: wr, isProtected: isProtected))
        }
        prev = nextPrev
        nameCache = nameCache.filter { seen.contains($0.key) }
        return result
    }

    private func identity(of pid: pid_t) -> (name: String, path: String) {
        if let cached = nameCache[pid] { return cached }
        var pathBuf = [CChar](repeating: 0, count: 4096)
        let pathLen = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
        let path = pathLen > 0 ? String(cString: pathBuf) : ""
        var nameBuf = [CChar](repeating: 0, count: 256)
        proc_name(pid, &nameBuf, UInt32(nameBuf.count))
        var name = String(cString: nameBuf)
        if !path.isEmpty {
            let last = (path as NSString).lastPathComponent
            if last.count > name.count { name = last }   // proc_name truncates long names
        }
        if name.isEmpty { name = "pid \(pid)" }
        let value = (name, path)
        nameCache[pid] = value
        return value
    }

    /// "/Applications/Google Chrome.app/Contents/Frameworks/…/Helper.app/…" → "/Applications/Google Chrome.app"
    static func outermostApp(in path: String) -> String? {
        guard let range = path.range(of: ".app/") else {
            return path.hasSuffix(".app") ? path : nil
        }
        return String(path[path.startIndex..<range.lowerBound]) + ".app"
    }
}

@MainActor
final class ProcessMonitor: ObservableObject {
    static let shared = ProcessMonitor()

    @Published private(set) var processes: [ProcInfo] = []
    @Published private(set) var groups: [AppGroup] = []
    @Published private(set) var lastUpdate = Date.distantPast

    private let sampler = ProcessSampler()
    private let queue = DispatchQueue(label: "PulseDock.processes", qos: .utility)
    private var timer: Timer?
    private var busy = false
    private var iconCache: [String: NSImage] = [:]

    private init() {}

    func start(interval: TimeInterval) {
        timer?.invalidate()
        refresh()
        let t = Timer(timeInterval: max(interval, 1.5), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        guard !busy else { return }
        busy = true
        let sampler = self.sampler
        queue.async {
            let list = sampler.sample()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    ProcessMonitor.shared.apply(list)
                }
            }
        }
    }

    private func apply(_ list: [ProcInfo]) {
        busy = false
        processes = list
        groups = buildGroups(list)
        lastUpdate = Date()
    }

    private func buildGroups(_ list: [ProcInfo]) -> [AppGroup] {
        var appsByBundle: [String: NSRunningApplication] = [:]
        var appsByPID: [pid_t: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            appsByPID[app.processIdentifier] = app
            if let path = app.bundleURL?.path { appsByBundle[path] = app }
        }

        var dict: [String: AppGroup] = [:]
        for p in list {
            let key = p.bundlePath ?? "proc:\(p.name)"
            if var g = dict[key] {
                g.pids.append(p.pid)
                g.cpu += p.cpu
                g.memory += p.memory
                g.diskRead += p.diskRead
                g.diskWrite += p.diskWrite
                g.isProtected = g.isProtected || p.isProtected
                dict[key] = g
            } else {
                let app = p.bundlePath.flatMap { appsByBundle[$0] } ?? appsByPID[p.pid]
                var name = app?.localizedName ?? p.name
                if app == nil, let bundle = p.bundlePath {
                    name = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
                }
                let icon = iconFor(key: key, app: app, bundlePath: p.bundlePath)
                let isProtected = p.isProtected || (app?.bundleIdentifier == Bundle.main.bundleIdentifier && app != nil)
                dict[key] = AppGroup(id: key, name: name, icon: icon, pids: [p.pid], cpu: p.cpu,
                                     memory: p.memory, diskRead: p.diskRead, diskWrite: p.diskWrite,
                                     app: app, isProtected: isProtected,
                                     isBackground: app.map { $0.activationPolicy != .regular } ?? true)
            }
        }
        return Array(dict.values)
    }

    private func iconFor(key: String, app: NSRunningApplication?, bundlePath: String?) -> NSImage? {
        if let cached = iconCache[key] { return cached }
        var icon: NSImage?
        if let i = app?.icon {
            icon = i
        } else if let b = bundlePath {
            icon = NSWorkspace.shared.icon(forFile: b)
        }
        if let icon { iconCache[key] = icon }
        return icon
    }

    // MARK: Sorting helpers

    func sortedGroups(by sort: ProcSort) -> [AppGroup] {
        switch sort {
        case .memory: return groups.sorted { $0.memory > $1.memory }
        case .cpu: return groups.sorted { $0.cpu > $1.cpu }
        case .disk: return groups.sorted { ($0.diskRead + $0.diskWrite) > ($1.diskRead + $1.diskWrite) }
        }
    }

    func sortedProcesses(by sort: ProcSort) -> [ProcInfo] {
        switch sort {
        case .memory: return processes.sorted { $0.memory > $1.memory }
        case .cpu: return processes.sorted { $0.cpu > $1.cpu }
        case .disk: return processes.sorted { ($0.diskRead + $0.diskWrite) > ($1.diskRead + $1.diskWrite) }
        }
    }

    func icon(forProcess p: ProcInfo) -> NSImage? {
        let key = p.bundlePath ?? "proc:\(p.name)"
        if let cached = iconCache[key] { return cached }
        return p.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
    }

    // MARK: Ending processes

    @discardableResult
    func quit(_ group: AppGroup, force: Bool) -> Bool {
        guard !group.isProtected else { return false }
        var ok = false
        if let app = group.app {
            ok = force ? app.forceTerminate() : app.terminate()
            if force {
                for pid in group.pids where pid != app.processIdentifier { kill(pid, SIGKILL) }
            }
        } else {
            for pid in group.pids {
                if kill(pid, force ? SIGKILL : SIGTERM) == 0 { ok = true }
            }
        }
        scheduleRefresh()
        return ok
    }

    @discardableResult
    func quit(_ p: ProcInfo, force: Bool) -> Bool {
        guard !p.isProtected else { return false }
        let ok: Bool
        if let app = NSRunningApplication(processIdentifier: p.pid) {
            ok = force ? app.forceTerminate() : app.terminate()
        } else {
            ok = kill(p.pid, force ? SIGKILL : SIGTERM) == 0
        }
        scheduleRefresh()
        return ok
    }

    private func scheduleRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
}
