import SwiftUI
import AppKit

/// "Free up memory": the apps using the most RAM, with one-click quit.
struct MemoryPage: View {
    @ObservedObject var monitor = SystemMonitor.shared
    @ObservedObject var procs = ProcessMonitor.shared
    @ObservedObject var model = AppModel.shared
    @State private var selected = Set<String>()
    @State private var showBackground = true

    private var snap: Snapshot { monitor.snapshot }

    private var rows: [AppGroup] {
        procs.sortedGroups(by: .memory)
            .filter { showBackground || !$0.isBackground }
            .prefix(40)
            .map { $0 }
    }

    private var selectedGroups: [AppGroup] {
        rows.filter { selected.contains($0.id) && !$0.isProtected }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(title: L("freeUpMemory"), subtitle: L("freeUpHint"))
                summary
                list
                Text(L("onlyYours")).font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) { actionBar }
    }

    private var summary: some View {
        HStack(spacing: 20) {
            RingGauge(value: snap.memFraction, color: Palette.memory, lineWidth: 12,
                      label: Fmt.percent(snap.memFraction), caption: "\(Fmt.bytes(snap.memUsed)) / \(Fmt.bytes(snap.memTotal, decimals: 0))")
                .frame(width: 130, height: 130)
            VStack(alignment: .leading, spacing: 10) {
                breakdownBar
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow {
                        legend(L("mem.app"), snap.memApp, Palette.memory)
                        legend(L("mem.wired"), snap.memWired, .orange)
                    }
                    GridRow {
                        legend(L("mem.compressed"), snap.memCompressed, .pink)
                        legend(L("mem.cached"), snap.memCached, .gray)
                    }
                }
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        Circle().fill(Palette.pressure(snap.pressure)).frame(width: 8, height: 8)
                        Text("\(L("pressure")): \(snap.pressure.label)").font(.callout.weight(.medium))
                    }
                    Text("\(L("mem.swap")): \(Fmt.bytes(snap.swapUsed))").font(.callout).foregroundStyle(.secondary)
                }
                Sparkline(values: monitor.memHistory.values, color: Palette.memory, maxValue: 1).frame(height: 32)
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 24, tint: Palette.memory)
    }

    private var breakdownBar: some View {
        GeometryReader { geo in
            let total = max(Double(snap.memTotal), 1)
            let parts: [(Double, Color)] = [
                (Double(snap.memApp), Palette.memory),
                (Double(snap.memWired), .orange),
                (Double(snap.memCompressed), .pink),
                (Double(snap.memCached), .gray.opacity(0.6)),
            ]
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(part.1)
                        .frame(width: max(0, geo.size.width * CGFloat(min(part.0 / total, 1)) - 2))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 12)
        .background(Capsule().fill(.quaternary))
        .clipShape(Capsule())
    }

    private func legend(_ title: String, _ value: UInt64, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(Fmt.bytes(value)).font(.callout.weight(.semibold)).monospacedDigit()
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("topMemory")).font(.headline)
                Spacer()
                Toggle(L("background"), isOn: $showBackground).toggleStyle(.switch).controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.4)

            ForEach(rows) { g in
                row(g)
                if g.id != rows.last?.id { Divider().opacity(0.25).padding(.leading, 52) }
            }
        }
        .glassCard(cornerRadius: 20)
    }

    private func row(_ g: AppGroup) -> some View {
        let maxMem = Double(rows.first?.memory ?? 1)
        let isSelected = selected.contains(g.id)
        return HStack(spacing: 12) {
            Button {
                if isSelected { selected.remove(g.id) } else { selected.insert(g.id) }
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(g.isProtected)
            .opacity(g.isProtected ? 0.3 : 1)

            AppIconView(image: g.icon, size: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(g.name).font(.body.weight(.medium)).lineLimit(1)
                    if g.isProtected {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary).help(L("protected"))
                    }
                }
                HStack(spacing: 8) {
                    LevelBar(value: Double(g.memory) / max(maxMem, 1), color: Palette.memory, height: 4)
                        .frame(maxWidth: 220)
                    Text(L10n.f("processesCount", g.pids.count)).font(.caption2).foregroundStyle(.secondary)
                    Text("CPU \(String(format: "%.0f", g.cpu))%").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer()
            Text(Fmt.bytes(g.memory))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Button(L("quitApp")) { model.confirmQuit(g, force: false) }
                .glassButton()
                .disabled(g.isProtected)
            Menu {
                Button(L("quitApp")) { model.confirmQuit(g, force: false) }
                Button(L("forceQuit")) { model.confirmQuit(g, force: true) }
                if let path = g.app?.bundleURL ?? g.app?.executableURL {
                    Divider()
                    Button(L("reveal")) { NSWorkspace.shared.activateFileViewerSelecting([path]) }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(g.isProtected)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var actionBar: some View {
        let targets = selectedGroups
        if !targets.isEmpty {
            HStack {
                Text(L10n.f("quitManyBody", Fmt.bytes(targets.reduce(UInt64(0)) { $0 + $1.memory })))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button(L("cancel")) { selected.removeAll() }.glassButton()
                Button {
                    model.confirmQuit(groups: targets)
                    selected.removeAll()
                } label: {
                    Label(L10n.f("quitSelected", targets.count), systemImage: "xmark.circle.fill")
                }
                .glassButton(prominent: true)
                .controlSize(.large)
            }
            .padding(12)
            .glassCard(cornerRadius: 20)
            .padding(16)
        }
    }
}
