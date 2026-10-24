import SwiftUI
import AppKit

struct MainView: View {
    @ObservedObject var model = AppModel.shared
    @ObservedObject var monitor = SystemMonitor.shared

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<NavSection?>(get: { model.section }, set: { if let v = $0 { model.section = v } })) {
                ForEach(NavSection.allCases) { s in
                    Label(s.title, systemImage: s.symbol).tag(s)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.machine.chip).font(.caption.weight(.semibold))
                    Text("\(monitor.machine.osVersion) · \(Fmt.bytes(monitor.snapshot.memTotal, decimals: 0)) RAM")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        } detail: {
            Group {
                switch model.section {
                case .overview: OverviewPage()
                case .memory: MemoryPage()
                case .processes: ProcessesPage()
                case .cleanup: CleanupPage()
                case .settings: SettingsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 600)
        .id(model.languageTick)
    }
}

// MARK: - Overview

struct OverviewPage: View {
    @ObservedObject var monitor = SystemMonitor.shared
    @ObservedObject var model = AppModel.shared
    private var snap: Snapshot { monitor.snapshot }

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(title: L("overview"), subtitle: "\(monitor.machine.chip) · \(monitor.machine.model) · \(L("uptime")) \(Fmt.duration(snap.uptime))")
                GlassGroup(spacing: 16) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        cpuCard
                        memoryCard
                        diskCard
                        gpuCard
                        networkCard
                        systemCard
                    }
                }
            }
            .padding(24)
        }
    }

    private func tile<C: View>(_ title: String, _ symbol: String, _ color: Color, action: (() -> Void)? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                MetricIcon(symbol: symbol, color: color, size: 24)
                Text(title).font(.headline)
                Spacer()
                if action != nil {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .contentShape(Rectangle())
        .glassCard(cornerRadius: 22, tint: color, interactive: action != nil)
        .onTapGesture { action?() }
    }

    private var cpuCard: some View {
        tile(L("cpu"), "cpu", Palette.cpu, action: { model.open(.processes, sort: .cpu) }) {
            HStack(spacing: 14) {
                RingGauge(value: snap.cpu, color: Palette.cpu, lineWidth: 9, label: Fmt.percent(snap.cpu))
                    .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 6) {
                    let m = monitor.machine
                    if m.performanceCores > 0 {
                        Text("\(m.performanceCores)P + \(m.efficiencyCores)E \(L("cores"))").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("\(m.logicalCores) \(L("cores"))").font(.caption).foregroundStyle(.secondary)
                    }
                    CoreBars(values: snap.perCore, color: Palette.cpu).frame(height: 34)
                    Text("\(L("load")): " + snap.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " · "))
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Sparkline(values: monitor.cpuHistory.values, color: Palette.cpu, maxValue: 1).frame(height: 30)
        }
    }

    private var memoryCard: some View {
        tile(L("memory"), "memorychip.fill", Palette.memory, action: { model.open(.memory) }) {
            HStack(spacing: 14) {
                RingGauge(value: snap.memFraction, color: Palette.memory, lineWidth: 9, label: Fmt.percent(snap.memFraction), caption: Fmt.bytes(snap.memUsed))
                    .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 4) {
                    kv(L("mem.app"), Fmt.bytes(snap.memApp))
                    kv(L("mem.wired"), Fmt.bytes(snap.memWired))
                    kv(L("mem.compressed"), Fmt.bytes(snap.memCompressed))
                    kv(L("mem.swap"), Fmt.bytes(snap.swapUsed))
                    HStack(spacing: 4) {
                        Circle().fill(Palette.pressure(snap.pressure)).frame(width: 7, height: 7)
                        Text("\(L("pressure")): \(snap.pressure.label)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Sparkline(values: monitor.memHistory.values, color: Palette.memory, maxValue: 1).frame(height: 30)
        }
    }

    private var diskCard: some View {
        tile(L("disk"), "internaldrive.fill", Palette.disk, action: { model.open(.cleanup) }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.bytes(snap.diskFree)).font(.system(.title2, design: .rounded).weight(.semibold))
                    Text("\(L("free")) \(L("of")) \(Fmt.bytes(snap.diskTotal, decimals: 0))").font(.caption).foregroundStyle(.secondary)
                }
                LevelBar(value: snap.diskUsedFraction, color: Palette.disk, height: 8)
                HStack {
                    kv(L("read"), Fmt.rate(snap.diskRead))
                    Spacer()
                    kv(L("write"), Fmt.rate(snap.diskWrite))
                }
            }
            ZStack {
                Sparkline(values: monitor.diskReadHistory.values, color: Palette.disk,
                          maxValue: max(monitor.diskReadHistory.max, monitor.diskWriteHistory.max))
                Sparkline(values: monitor.diskWriteHistory.values, color: .red,
                          maxValue: max(monitor.diskReadHistory.max, monitor.diskWriteHistory.max), fill: false)
            }
            .frame(height: 30)
        }
    }

    private var gpuCard: some View {
        tile(L("gpu"), "cube.transparent.fill", Palette.gpu) {
            if snap.gpus.isEmpty {
                Text("—").foregroundStyle(.secondary)
            }
            ForEach(snap.gpus) { g in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(g.name).font(.callout.weight(.medium)).lineLimit(1)
                        Spacer()
                        Text(Fmt.percent(g.utilization)).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                    }
                    LevelBar(value: g.utilization, color: Palette.gpu, height: 8)
                    if g.memoryUsed > 0 {
                        Text("\(L("memory")): \(Fmt.bytes(g.memoryUsed))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Sparkline(values: monitor.gpuHistory.values, color: Palette.gpu, maxValue: 1).frame(height: 30)
        }
    }

    private var networkCard: some View {
        tile(L("network"), "network", Palette.netDown) {
            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text(L("down")).font(.caption).foregroundStyle(.secondary)
                    Text(Fmt.rate(snap.netDown)).font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(Palette.netDown).monospacedDigit()
                }
                VStack(alignment: .leading) {
                    Text(L("up")).font(.caption).foregroundStyle(.secondary)
                    Text(Fmt.rate(snap.netUp)).font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(Palette.netUp).monospacedDigit()
                }
            }
            ZStack {
                Sparkline(values: monitor.netDownHistory.values, color: Palette.netDown,
                          maxValue: max(monitor.netDownHistory.max, monitor.netUpHistory.max))
                Sparkline(values: monitor.netUpHistory.values, color: Palette.netUp,
                          maxValue: max(monitor.netDownHistory.max, monitor.netUpHistory.max), fill: false)
            }
            .frame(height: 54)
        }
    }

    private var systemCard: some View {
        tile(snap.battery != nil ? L("battery") : L("thermal"), snap.battery != nil ? "battery.75" : "thermometer.medium", Palette.battery) {
            VStack(alignment: .leading, spacing: 8) {
                if let b = snap.battery {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.percent(b.level)).font(.system(.title2, design: .rounded).weight(.semibold))
                        Text(b.isCharging ? L("charging") : (b.onAC ? L("pluggedIn") : L("onBattery")))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LevelBar(value: b.level, color: b.level < 0.2 ? .red : Palette.battery, height: 8)
                    if let mins = b.minutesRemaining, !b.onAC {
                        Text(L10n.f("remaining", Fmt.duration(Double(mins) * 60))).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Circle().fill(snap.thermal.color).frame(width: 8, height: 8)
                    Text("\(L("thermal")): \(snap.thermal.label)").font(.callout)
                }
                kv(L("uptime"), Fmt.duration(snap.uptime))
            }
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(spacing: 6) {
            Text(k).foregroundStyle(.secondary)
            Text(v).fontWeight(.medium).monospacedDigit()
        }
        .font(.caption)
    }
}
