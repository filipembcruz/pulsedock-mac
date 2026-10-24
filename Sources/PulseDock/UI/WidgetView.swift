import SwiftUI
import AppKit

struct WidgetView: View {
    @ObservedObject var monitor = SystemMonitor.shared
    @ObservedObject var store = SettingsStore.shared
    @ObservedObject var model = AppModel.shared
    @ObservedObject var procs = ProcessMonitor.shared

    var onDrag: (CGPoint) -> Void = { _ in }
    var onDragEnd: () -> Void = {}
    var onSize: (CGSize) -> Void = { _ in }

    private var s: AppSettings { store.s }
    private var snap: Snapshot { monitor.snapshot }

    var body: some View {
        content
            .fixedSize()
            .background(GeometryReader { g in
                Color.clear.preference(key: WidgetSizeKey.self, value: g.size)
            })
            .onPreferenceChange(WidgetSizeKey.self) { size in onSize(size) }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { _ in if !s.lockPosition { onDrag(NSEvent.mouseLocation) } }
                    .onEnded { _ in if !s.lockPosition { onDragEnd() } }
            )
            .contextMenu { WidgetMenu() }
            .id(model.languageTick)
    }

    @ViewBuilder
    private var content: some View {
        switch s.layout {
        case .compact: compact
        case .expanded: expanded
        case .strip: strip
        }
    }

    // MARK: Compact (vertical)

    private var compact: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if s.showCPU {
                row(symbol: "cpu", color: Palette.cpu, title: L("cpu"), value: Fmt.percent(snap.cpu), level: snap.cpu)
                    .onTapGesture { model.open(.processes, sort: .cpu) }
            }
            if s.showMemory {
                row(symbol: "memorychip", color: Palette.memory, title: L("ram"),
                    value: "\(Fmt.bytes(snap.memUsed)) / \(Fmt.bytes(snap.memTotal, decimals: 0))", level: snap.memFraction)
                    .onTapGesture { model.open(.memory) }
            }
            if s.showDisk {
                row(symbol: "internaldrive", color: Palette.disk, title: L("disk"),
                    value: "↓\(Fmt.shortRate(snap.diskRead)) ↑\(Fmt.shortRate(snap.diskWrite))", level: snap.diskBusy)
                    .onTapGesture { model.open(.processes, sort: .disk) }
            }
            if s.showGPU, let gpu = snap.gpus.first {
                row(symbol: "cube.transparent", color: Palette.gpu, title: L("gpu"), value: Fmt.percent(gpu.utilization), level: gpu.utilization)
                    .onTapGesture { model.open(.overview) }
            }
            if s.showNetwork {
                HStack(spacing: 8) {
                    MetricIcon(symbol: "network", color: Palette.netDown, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("↓ \(Fmt.rate(snap.netDown))").foregroundStyle(Palette.netDown)
                        Text("↑ \(Fmt.rate(snap.netUp))").foregroundStyle(Palette.netUp)
                    }
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    Spacer(minLength: 4)
                    Sparkline(values: monitor.netDownHistory.values, color: Palette.netDown)
                        .frame(width: 54, height: 22)
                }
            }
            if s.showBattery, let b = snap.battery {
                row(symbol: b.isCharging ? "battery.100.bolt" : "battery.75", color: Palette.battery,
                    title: L("battery"), value: Fmt.percent(b.level), level: b.level)
            }
        }
        .padding(12)
        .frame(width: 214)
        .glassCard(cornerRadius: 22)
    }

    // MARK: Expanded

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if s.showCPU {
                card(color: Palette.cpu) {
                    HStack(spacing: 10) {
                        RingGauge(value: snap.cpu, color: Palette.cpu, lineWidth: 5, label: Fmt.percent(snap.cpu))
                            .frame(width: 54, height: 54)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(L("cpu")) · \(monitor.machine.logicalCores) \(L("cores"))").font(.caption.weight(.semibold))
                            CoreBars(values: snap.perCore, color: Palette.cpu).frame(height: 22)
                            Text("\(L("load")): " + snap.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: "  "))
                                .font(.system(size: 9.5)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                .onTapGesture { model.open(.processes, sort: .cpu) }
            }
            if s.showMemory {
                card(color: Palette.memory) {
                    HStack(spacing: 10) {
                        RingGauge(value: snap.memFraction, color: Palette.memory, lineWidth: 5, label: Fmt.percent(snap.memFraction))
                            .frame(width: 54, height: 54)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(L("ram")) · \(Fmt.bytes(snap.memUsed)) / \(Fmt.bytes(snap.memTotal, decimals: 0))").font(.caption.weight(.semibold))
                            HStack(spacing: 4) {
                                Circle().fill(Palette.pressure(snap.pressure)).frame(width: 6, height: 6)
                                Text("\(L("pressure")): \(snap.pressure.label)").font(.system(size: 9.5)).foregroundStyle(.secondary)
                            }
                            if let top = procs.sortedGroups(by: .memory).first {
                                Text(L10n.f("memoryHog", top.name, Fmt.bytes(top.memory)))
                                    .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                .onTapGesture { model.open(.memory) }
            }
            if s.showDisk {
                card(color: Palette.disk) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Label(L("disk"), systemImage: "internaldrive").font(.caption.weight(.semibold))
                            Spacer()
                            Text("\(Fmt.bytes(snap.diskFree)) \(L("free"))").font(.caption2).foregroundStyle(.secondary)
                        }
                        LevelBar(value: snap.diskUsedFraction, color: Palette.disk, height: 5)
                        HStack {
                            Text("↓ \(Fmt.rate(snap.diskRead))")
                            Spacer()
                            Text("↑ \(Fmt.rate(snap.diskWrite))")
                        }
                        .font(.system(size: 9.5, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .onTapGesture { model.open(.processes, sort: .disk) }
            }
            if s.showGPU, !snap.gpus.isEmpty {
                card(color: Palette.gpu) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(snap.gpus) { gpu in
                            HStack {
                                Text(gpu.name).font(.caption.weight(.semibold)).lineLimit(1)
                                Spacer()
                                Text(Fmt.percent(gpu.utilization)).font(.caption.weight(.semibold)).monospacedDigit()
                            }
                            LevelBar(value: gpu.utilization, color: Palette.gpu, height: 5)
                        }
                        Sparkline(values: monitor.gpuHistory.values, color: Palette.gpu, maxValue: 1).frame(height: 18)
                    }
                }
            }
            if s.showNetwork {
                card(color: Palette.netDown) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(L("network"), systemImage: "network").font(.caption.weight(.semibold))
                            Spacer()
                        }
                        HStack {
                            Text("↓ \(Fmt.rate(snap.netDown))").foregroundStyle(Palette.netDown)
                            Spacer()
                            Text("↑ \(Fmt.rate(snap.netUp))").foregroundStyle(Palette.netUp)
                        }
                        .font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                        ZStack {
                            Sparkline(values: monitor.netDownHistory.values, color: Palette.netDown,
                                      maxValue: max(monitor.netDownHistory.max, monitor.netUpHistory.max))
                            Sparkline(values: monitor.netUpHistory.values, color: Palette.netUp,
                                      maxValue: max(monitor.netDownHistory.max, monitor.netUpHistory.max), fill: false)
                        }
                        .frame(height: 22)
                    }
                }
            }
            if s.showBattery, let b = snap.battery {
                card(color: Palette.battery) {
                    HStack {
                        Label(L("battery"), systemImage: b.isCharging ? "battery.100.bolt" : "battery.75").font(.caption.weight(.semibold))
                        Spacer()
                        Text(Fmt.percent(b.level)).font(.caption.weight(.semibold)).monospacedDigit()
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 260)
        .glassCard(cornerRadius: 26)
    }

    // MARK: Strip (horizontal)

    private var strip: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg").font(.system(size: 12, weight: .bold)).foregroundStyle(.tint)
            if s.showCPU {
                stripItem(symbol: "cpu", color: Palette.cpu, text: Fmt.percent(snap.cpu))
                    .onTapGesture { model.open(.processes, sort: .cpu) }
            }
            if s.showMemory {
                stripItem(symbol: "memorychip", color: Palette.memory, text: Fmt.percent(snap.memFraction))
                    .onTapGesture { model.open(.memory) }
            }
            if s.showDisk {
                stripItem(symbol: "internaldrive", color: Palette.disk, text: "\(Fmt.shortRate(snap.diskRead + snap.diskWrite))/s")
                    .onTapGesture { model.open(.processes, sort: .disk) }
            }
            if s.showGPU, let g = snap.gpus.first {
                stripItem(symbol: "cube.transparent", color: Palette.gpu, text: Fmt.percent(g.utilization))
            }
            if s.showNetwork {
                stripItem(symbol: "arrow.down", color: Palette.netDown, text: Fmt.shortRate(snap.netDown))
                stripItem(symbol: "arrow.up", color: Palette.netUp, text: Fmt.shortRate(snap.netUp))
            }
            if s.showBattery, let b = snap.battery {
                stripItem(symbol: b.isCharging ? "bolt.fill" : "battery.75", color: Palette.battery, text: Fmt.percent(b.level))
            }
            menuButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .fixedSize()
        .glassCard(cornerRadius: 18)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.tint)
            Text("PulseDock")
                .font(.system(size: 11, weight: .bold, design: .rounded))
            Spacer()
            Button {
                var copy = store.s
                copy.layout = copy.layout == .expanded ? .compact : .expanded
                store.s = copy
            } label: {
                Image(systemName: s.layout == .expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(s.layout == .expanded ? L("layout.compact") : L("layout.expanded"))
            menuButton
        }
        .foregroundStyle(.secondary)
    }

    private var menuButton: some View {
        Menu {
            WidgetMenu()
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func row(symbol: String, color: Color, title: String, value: String, level: Double) -> some View {
        HStack(spacing: 8) {
            MetricIcon(symbol: symbol, color: color, size: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 10.5, weight: .semibold))
                    Spacer(minLength: 4)
                    Text(value)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                LevelBar(value: level, color: color, height: 4)
            }
        }
        .contentShape(Rectangle())
    }

    private func stripItem(symbol: String, color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            Text(text).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }

    private func card<C: View>(color: Color, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(color.opacity(0.18), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// The "⋯" quick menu: also used as the widget's right-click menu.
struct WidgetMenu: View {
    @ObservedObject var store = SettingsStore.shared
    @ObservedObject var model = AppModel.shared

    var body: some View {
        Button(L("open")) { model.open(.overview) }
        Button(L("freeUpMemory")) { model.open(.memory) }
        Button(L("cleanup.title")) { model.open(.cleanup) }
        Divider()
        Picker(L("set.layout"), selection: binding(\.layout)) {
            ForEach(WidgetLayout.allCases) { Text(L("layout.\($0.rawValue)")).tag($0) }
        }
        Picker(L("set.mode"), selection: binding(\.mode)) {
            ForEach(DisplayMode.allCases) { Text(L("mode.\($0.rawValue)")).tag($0) }
        }
        Picker(L("set.corner"), selection: cornerBinding) {
            ForEach(Corner.allCases) { Text(L("corner.\($0.rawValue)")).tag($0) }
        }
        Toggle(L("set.lock"), isOn: binding(\.lockPosition))
        Toggle(L("set.launchAtLogin"), isOn: Binding(get: { LoginItem.isEnabled }, set: { LoginItem.set($0) }))
        Picker(L("set.language"), selection: languageBinding) {
            Text("English").tag("en")
            Text("Português").tag("pt")
            Text(L("set.lang.auto")).tag("auto")
        }
        Divider()
        Button(L("settingsEllipsis")) { model.open(.settings) }
        Button(L("quit")) { NSApp.terminate(nil) }
    }

    private func binding<T>(_ kp: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { store.s[keyPath: kp] }, set: { store.s[keyPath: kp] = $0 })
    }

    private var cornerBinding: Binding<Corner> {
        Binding(get: { store.s.corner }, set: {
            store.s.corner = $0
            store.s.freePosition = false
        })
    }

    private var languageBinding: Binding<String> {
        Binding(get: { store.s.language }, set: {
            store.s.language = $0
            model.languageTick += 1
        })
    }
}

private struct WidgetSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
