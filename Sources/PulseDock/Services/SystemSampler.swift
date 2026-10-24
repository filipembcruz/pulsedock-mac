import Foundation
import Darwin
import IOKit
import IOKit.ps

enum MemoryPressure: Int {
    case normal = 1, warning = 2, critical = 4

    var label: String {
        switch self {
        case .normal: return L("pressure.normal")
        case .warning: return L("pressure.warning")
        case .critical: return L("pressure.critical")
        }
    }
}

struct GPUInfo: Identifiable, Equatable {
    var id: Int
    var name: String
    var utilization: Double   // 0...1
    var memoryUsed: UInt64    // bytes
}

struct BatteryInfo: Equatable {
    var level: Double          // 0...1
    var isCharging: Bool
    var onAC: Bool
    var minutesRemaining: Int? // to empty
}

struct Snapshot: Equatable {
    var cpu: Double = 0
    var perCore: [Double] = []
    var loadAverage: [Double] = [0, 0, 0]

    var memTotal: UInt64 = 0
    var memUsed: UInt64 = 0
    var memApp: UInt64 = 0
    var memWired: UInt64 = 0
    var memCompressed: UInt64 = 0
    var memCached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressure: MemoryPressure = .normal

    var diskRead: Double = 0
    var diskWrite: Double = 0
    var diskBusy: Double = 0
    var diskFree: UInt64 = 0
    var diskTotal: UInt64 = 0

    var netDown: Double = 0
    var netUp: Double = 0

    var gpus: [GPUInfo] = []
    var battery: BatteryInfo?
    var thermal: ProcessInfo.ThermalState = .nominal
    var uptime: TimeInterval = 0

    var memFraction: Double { memTotal == 0 ? 0 : Double(memUsed) / Double(memTotal) }
    var diskUsedFraction: Double { diskTotal == 0 ? 0 : Double(diskTotal - min(diskFree, diskTotal)) / Double(diskTotal) }
}

/// Static facts about this Mac.
struct MachineInfo {
    var chip: String
    var model: String
    var physicalCores: Int
    var logicalCores: Int
    var performanceCores: Int
    var efficiencyCores: Int
    var osVersion: String

    static let current: MachineInfo = {
        let brand = Sysctl.string("machdep.cpu.brand_string") ?? "Apple silicon"
        let model = Sysctl.string("hw.model") ?? "Mac"
        let phys = Int(Sysctl.int("hw.physicalcpu") ?? 0)
        let logical = Int(Sysctl.int("hw.logicalcpu") ?? Int64(ProcessInfo.processInfo.activeProcessorCount))
        let p = Int(Sysctl.int("hw.perflevel0.logicalcpu") ?? 0)
        let e = Int(Sysctl.int("hw.perflevel1.logicalcpu") ?? 0)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        return MachineInfo(chip: brand, model: model, physicalCores: phys, logicalCores: logical,
                           performanceCores: p, efficiencyCores: e, osVersion: os)
    }()
}

enum Sysctl {
    static func int(_ name: String) -> Int64? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }
        if size == MemoryLayout<Int32>.size {
            var v: Int32 = 0
            guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
            return Int64(v)
        }
        var v: Int64 = 0
        size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
        return v
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}

/// Collects system-wide metrics. Not thread-safe: call `sample()` from one queue.
final class SystemSampler {
    private var lastCoreTicks: [[UInt64]] = []
    private var lastNet: [String: (UInt32, UInt32)] = [:]
    private var lastDisk: (read: UInt64, write: UInt64, time: UInt64)?
    private var lastTime: TimeInterval = 0
    private var diskSpaceCounter = 0
    private var cachedDiskSpace: (free: UInt64, total: UInt64) = (0, 0)

    func sample() -> Snapshot {
        var s = Snapshot()
        let now = ProcessInfo.processInfo.systemUptime
        let dt = lastTime == 0 ? 0 : now - lastTime
        lastTime = now

        sampleCPU(into: &s)
        sampleMemory(into: &s)
        sampleNetwork(into: &s, dt: dt)
        sampleDiskIO(into: &s, dt: dt)
        sampleDiskSpace(into: &s)
        s.gpus = Self.sampleGPUs()
        s.battery = Self.sampleBattery()
        s.thermal = ProcessInfo.processInfo.thermalState
        s.uptime = now

        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 { s.loadAverage = loads }
        return s
    }

    // MARK: CPU

    private func sampleCPU(into s: inout Snapshot) {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS, let info else { return }
        defer {
            let size = vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), size)
        }

        let stateMax = Int(CPU_STATE_MAX)
        var current: [[UInt64]] = []
        for i in 0..<Int(cpuCount) {
            let base = i * stateMax
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            current.append([user, system, idle, nice])
        }

        var perCore: [Double] = []
        var busyTotal: UInt64 = 0
        var allTotal: UInt64 = 0
        if lastCoreTicks.count == current.count {
            for (cur, prev) in zip(current, lastCoreTicks) {
                let user = cur[0] &- prev[0]
                let sys = cur[1] &- prev[1]
                let idle = cur[2] &- prev[2]
                let nice = cur[3] &- prev[3]
                let busy = user + sys + nice
                let total = busy + idle
                busyTotal += busy
                allTotal += total
                perCore.append(total == 0 ? 0 : Double(busy) / Double(total))
            }
        } else {
            perCore = Array(repeating: 0, count: current.count)
        }
        lastCoreTicks = current
        s.perCore = perCore
        s.cpu = allTotal == 0 ? 0 : Double(busyTotal) / Double(allTotal)
    }

    // MARK: Memory

    private func sampleMemory(into s: inout Snapshot) {
        s.memTotal = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let internalPages = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            let app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
            let wired = UInt64(stats.wire_count) * page
            let compressed = UInt64(stats.compressor_page_count) * page
            let cached = (UInt64(stats.external_page_count) + purgeable) * page
            s.memApp = app
            s.memWired = wired
            s.memCompressed = compressed
            s.memCached = cached
            s.memUsed = min(app + wired + compressed, s.memTotal)
        }

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            s.swapUsed = swap.xsu_used
            s.swapTotal = swap.xsu_total
        }
        if let level = Sysctl.int("kern.memorystatus_vm_pressure_level"),
           let p = MemoryPressure(rawValue: Int(level)) {
            s.pressure = p
        }
    }

    // MARK: Network

    private func sampleNetwork(into s: inout Snapshot, dt: TimeInterval) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return }
        defer { freeifaddrs(addrs) }

        var current: [String: (UInt32, UInt32)] = [:]
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = ptr {
            defer { ptr = ifa.pointee.ifa_next }
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let dataPtr = ifa.pointee.ifa_data else { continue }
            let flags = Int32(ifa.pointee.ifa_flags)
            if flags & IFF_LOOPBACK != 0 || flags & IFF_UP == 0 { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            // Skip virtual / tunnel interfaces that double-count traffic.
            if name.hasPrefix("utun") || name.hasPrefix("awdl") || name.hasPrefix("llw") || name.hasPrefix("bridge") || name.hasPrefix("ap") { continue }
            let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
            current[name] = (data.ifi_ibytes, data.ifi_obytes)
        }

        if dt > 0 {
            var down: UInt64 = 0
            var up: UInt64 = 0
            for (name, cur) in current {
                guard let prev = lastNet[name] else { continue }
                down += UInt64(cur.0 &- prev.0)   // 32-bit counters: wrapping subtraction handles rollover
                up += UInt64(cur.1 &- prev.1)
            }
            s.netDown = Double(down) / dt
            s.netUp = Double(up) / dt
        }
        lastNet = current
    }

    // MARK: Disk I/O

    private func sampleDiskIO(into s: inout Snapshot, dt: TimeInterval) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var write: UInt64 = 0
        var time: UInt64 = 0
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["Statistics"] as? [String: Any] else { continue }
            read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            time += (stats["Total Time (Read)"] as? NSNumber)?.uint64Value ?? 0
            time += (stats["Total Time (Write)"] as? NSNumber)?.uint64Value ?? 0
        }

        if let last = lastDisk, dt > 0 {
            s.diskRead = Double(read &- last.read) / dt
            s.diskWrite = Double(write &- last.write) / dt
            let busyNs = Double(time &- last.time)
            s.diskBusy = min(max(busyNs / (dt * 1_000_000_000), 0), 1)
        }
        lastDisk = (read, write, time)
    }

    private func sampleDiskSpace(into s: inout Snapshot) {
        // Free space changes slowly; refresh it every 10 samples.
        if diskSpaceCounter % 10 == 0 {
            let url = URL(fileURLWithPath: "/")
            if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]) {
                let total = UInt64(max(v.volumeTotalCapacity ?? 0, 0))
                let important = v.volumeAvailableCapacityForImportantUsage.map { UInt64(max($0, 0)) }
                let plain = UInt64(max(v.volumeAvailableCapacity ?? 0, 0))
                cachedDiskSpace = (important ?? plain, total)
            }
        }
        diskSpaceCounter += 1
        s.diskFree = cachedDiskSpace.free
        s.diskTotal = cachedDiskSpace.total
    }

    func invalidateDiskSpace() { diskSpaceCounter = 0 }

    // MARK: GPU

    static func sampleGPUs() -> [GPUInfo] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var result: [GPUInfo] = []
        var index = 0
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else { continue }
            let perf = dict["PerformanceStatistics"] as? [String: Any] ?? [:]
            let util = (perf["Device Utilization %"] as? NSNumber)?.doubleValue
                ?? (perf["GPU Activity(%)"] as? NSNumber)?.doubleValue
                ?? 0
            let mem = (perf["In use system memory"] as? NSNumber)?.uint64Value
                ?? (perf["vramUsedBytes"] as? NSNumber)?.uint64Value
                ?? 0
            var name = (dict["model"] as? String) ?? ""
            if name.isEmpty, let data = dict["model"] as? Data { name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .controlCharacters) }
            if name.isEmpty { name = (dict["IOClass"] as? String) ?? "GPU" }
            if name.hasPrefix("AGX") { name = MachineInfo.current.chip + " GPU" }
            if let cores = dict["gpu-core-count"] as? NSNumber { name += " · \(cores.intValue) \(L("cores"))" }
            result.append(GPUInfo(id: index, name: name, utilization: min(max(util / 100, 0), 1), memoryUsed: mem))
            index += 1
        }
        return result
    }

    // MARK: Battery

    static func sampleBattery() -> BatteryInfo? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            guard (desc["Type"] as? String) == "InternalBattery" else { continue }
            let cur = (desc["Current Capacity"] as? NSNumber)?.doubleValue ?? 0
            let max = (desc["Max Capacity"] as? NSNumber)?.doubleValue ?? 100
            let charging = (desc["Is Charging"] as? NSNumber)?.boolValue ?? false
            let onAC = (desc["Power Source State"] as? String) == "AC Power"
            let tte = (desc["Time to Empty"] as? NSNumber)?.intValue
            return BatteryInfo(level: max > 0 ? cur / max : 0, isCharging: charging, onAC: onAC,
                               minutesRemaining: (tte ?? -1) > 0 ? tte : nil)
        }
        return nil
    }
}
