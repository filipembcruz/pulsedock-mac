import Foundation
import Combine

/// Fixed-size history for sparklines.
struct History: Equatable {
    private(set) var values: [Double] = []
    let capacity: Int

    init(capacity: Int = 60) { self.capacity = capacity }

    mutating func push(_ v: Double) {
        values.append(v)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    var max: Double { values.max() ?? 0 }
}

@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var cpuHistory = History()
    @Published private(set) var memHistory = History()
    @Published private(set) var gpuHistory = History()
    @Published private(set) var netDownHistory = History()
    @Published private(set) var netUpHistory = History()
    @Published private(set) var diskReadHistory = History()
    @Published private(set) var diskWriteHistory = History()

    let machine = MachineInfo.current
    private let sampler = SystemSampler()
    private var timer: Timer?
    private(set) var interval: TimeInterval = 1

    private init() {}

    func start(interval: TimeInterval) {
        self.interval = interval
        timer?.invalidate()
        tick()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refreshDiskSpace() {
        sampler.invalidateDiskSpace()
    }

    private func tick() {
        let s = sampler.sample()
        snapshot = s
        cpuHistory.push(s.cpu)
        memHistory.push(s.memFraction)
        gpuHistory.push(s.gpus.map(\.utilization).max() ?? 0)
        netDownHistory.push(s.netDown)
        netUpHistory.push(s.netUp)
        diskReadHistory.push(s.diskRead)
        diskWriteHistory.push(s.diskWrite)
    }
}
