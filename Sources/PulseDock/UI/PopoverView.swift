import SwiftUI
import AppKit

/// The panel that opens from the menu bar icon.
struct PopoverView: View {
    @ObservedObject var monitor = SystemMonitor.shared
    @ObservedObject var procs = ProcessMonitor.shared
    @ObservedObject var store = SettingsStore.shared
    @ObservedObject var model = AppModel.shared

    private var snap: Snapshot { monitor.snapshot }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg").font(.headline).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text("PulseDock").font(.system(.headline, design: .rounded))
                    Text("\(monitor.machine.chip) · \(L("uptime")) \(Fmt.duration(snap.uptime))")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { model.open(.settings) } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help(L("settings"))
            }

            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    gaugeTile(L("cpu"), snap.cpu, Palette.cpu) { model.open(.processes, sort: .cpu) }
                    gaugeTile(L("ram"), snap.memFraction, Palette.memory) { model.open(.memory) }
                    gaugeTile(L("disk"), snap.diskUsedFraction, Palette.disk) { model.open(.cleanup) }
                    if let g = snap.gpus.first {
                        gaugeTile(L("gpu"), g.utilization, Palette.gpu) { model.open(.overview) }
                    }
                }
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("↓ \(Fmt.rate(snap.netDown))").foregroundStyle(Palette.netDown)
                    Text("↑ \(Fmt.rate(snap.netUp))").foregroundStyle(Palette.netUp)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .frame(width: 96, alignment: .leading)
                ZStack {
                    Sparkline(values: monitor.netDownHistory.values, color: Palette.netDown,
                              maxValue: max(monitor.netDownHistory.max, monitor.netUpHistory.max))
                    Sparkline(values: monitor.netUpHistory.values, color: Palette.netUp,
                              maxValue: max(monitor.netDownHistory.max, monitor.netUpHistory.max), fill: false)
                }
                .frame(height: 28)
            }
            .padding(10)
            .glassCard(cornerRadius: 16)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("topMemory")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(Palette.pressure(snap.pressure)).frame(width: 6, height: 6)
                        Text(snap.pressure.label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ForEach(procs.sortedGroups(by: .memory).prefix(5)) { g in
                    HStack(spacing: 8) {
                        AppIconView(image: g.icon, size: 18)
                        Text(g.name).font(.callout).lineLimit(1)
                        Spacer()
                        Text(Fmt.bytes(g.memory)).font(.callout.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
                        Button {
                            model.closePopover()
                            model.confirmQuit(g, force: false)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(g.isProtected ? Color.secondary.opacity(0.3) : Color.secondary)
                        .disabled(g.isProtected)
                        .help(g.isProtected ? L("protected") : L("quitApp"))
                    }
                }
            }
            .padding(10)
            .glassCard(cornerRadius: 16)

            HStack(spacing: 8) {
                Button { model.open(.memory) } label: {
                    Label(L("freeUpMemory"), systemImage: "memorychip").frame(maxWidth: .infinity)
                }
                .glassButton(prominent: true)
                Button { model.open(.cleanup) } label: {
                    Label(L("cleanup"), systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .glassButton()
            }
            .controlSize(.large)

            HStack {
                Button(L("open")) { model.open(.overview) }
                Spacer()
                Menu {
                    WidgetMenu()
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                Button(L("quit")) { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 340)
        .focusEffectDisabled()
        .id(model.languageTick)
    }

    private func gaugeTile(_ title: String, _ value: Double, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RingGauge(value: value, color: color, lineWidth: 6, label: Fmt.percent(value))
                    .frame(width: 58, height: 58)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: 16, tint: color, interactive: true)
        }
        .buttonStyle(.plain)
    }
}
