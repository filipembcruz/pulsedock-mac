import SwiftUI
import AppKit

/// Activity-Monitor-style table: CPU, memory and disk per app or per process, with end task.
struct ProcessesPage: View {
    @ObservedObject var procs = ProcessMonitor.shared
    @ObservedObject var model = AppModel.shared
    @ObservedObject var store = SettingsStore.shared
    @State private var query = ""
    @State private var selection = Set<String>()

    /// One row type for both modes so the table code is shared.
    struct Row: Identifiable {
        let id: String
        let name: String
        let icon: NSImage?
        let pid: pid_t
        let count: Int
        let cpu: Double
        let memory: UInt64
        let read: Double
        let write: Double
        let isProtected: Bool
        let group: AppGroup?
        let process: ProcInfo?
    }

    private var rows: [Row] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let sort = model.processSort
        if store.s.groupByApp {
            return procs.sortedGroups(by: sort)
                .filter { q.isEmpty || $0.name.lowercased().contains(q) }
                .map { g in
                    Row(id: g.id, name: g.name, icon: g.icon, pid: g.mainPID, count: g.pids.count, cpu: g.cpu,
                        memory: g.memory, read: g.diskRead, write: g.diskWrite, isProtected: g.isProtected,
                        group: g, process: nil)
                }
        } else {
            return procs.sortedProcesses(by: sort)
                .filter { q.isEmpty || $0.name.lowercased().contains(q) || "\($0.pid)" == q }
                .map { p in
                    Row(id: "pid:\(p.pid)", name: p.name, icon: procs.icon(forProcess: p), pid: p.pid, count: 1,
                        cpu: p.cpu, memory: p.memory, read: p.diskRead, write: p.diskWrite,
                        isProtected: p.isProtected, group: nil, process: p)
                }
        }
    }

    var body: some View {
        let data = Array(rows.prefix(200))
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SectionHeader(title: L("processes"))
                Picker(L("sortBy"), selection: $model.processSort) {
                    Text(L("memory")).tag(ProcSort.memory)
                    Text(L("cpu")).tag(ProcSort.cpu)
                    Text(L("disk")).tag(ProcSort.disk)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                Toggle(L("groupByApp"), isOn: $store.s.groupByApp)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Table(data, selection: $selection) {
                TableColumn(L("name")) { r in
                    HStack(spacing: 8) {
                        AppIconView(image: r.icon, size: 18)
                        Text(r.name).lineLimit(1)
                        if r.isProtected {
                            Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                        }
                        if r.count > 1 {
                            Text("\(r.count)").font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(.quaternary))
                        }
                    }
                }
                .width(min: 200, ideal: 280)
                TableColumn("CPU %") { r in
                    Text(String(format: "%.1f", r.cpu)).monospacedDigit()
                        .foregroundStyle(Self.cpuColor(r.cpu))
                }
                .width(70)
                TableColumn(L("memory")) { r in
                    Text(Fmt.bytes(r.memory)).monospacedDigit()
                        .foregroundStyle(Self.memColor(r.memory))
                }
                .width(90)
                TableColumn(L("readPerSec")) { r in Text(Fmt.rate(r.read)).monospacedDigit().foregroundStyle(.secondary) }
                    .width(90)
                TableColumn(L("writePerSec")) { r in Text(Fmt.rate(r.write)).monospacedDigit().foregroundStyle(.secondary) }
                    .width(90)
                TableColumn(L("pid")) { r in Text("\(r.pid)").monospacedDigit().foregroundStyle(.secondary) }
                    .width(60)
                TableColumn("") { r in
                    Button {
                        quit(r, force: false)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(r.isProtected ? Color.secondary.opacity(0.3) : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(r.isProtected)
                    .help(r.isProtected ? L("protected") : L("quitApp"))
                }
                .width(28)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                let selectedRows = data.filter { ids.contains($0.id) }
                if let r = selectedRows.first, selectedRows.count == 1 {
                    Button(L("quitApp")) { quit(r, force: false) }.disabled(r.isProtected)
                    Button(L("forceQuit")) { quit(r, force: true) }.disabled(r.isProtected)
                    if let path = r.process?.path ?? r.group?.app?.bundleURL?.path, !path.isEmpty {
                        Divider()
                        Button(L("reveal")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                    }
                } else if selectedRows.count > 1 {
                    Button(L10n.f("quitSelected", selectedRows.count)) { quitMany(selectedRows) }
                }
            }
            .searchable(text: $query, placement: .toolbar, prompt: L("search"))

            HStack {
                Text(L("onlyYours")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                let chosen = data.filter { selection.contains($0.id) && !$0.isProtected }
                if !chosen.isEmpty {
                    Button(L10n.f("quitSelected", chosen.count)) { quitMany(chosen) }
                        .glassButton(prominent: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
    }

    static func cpuColor(_ v: Double) -> Color {
        if v > 80 { return .red }
        if v > 30 { return .orange }
        return .primary
    }

    static func memColor(_ v: UInt64) -> Color {
        let gb: UInt64 = 1024 * 1024 * 1024
        if v > 2 * gb { return .red }
        if v > gb * 8 / 10 { return .orange }
        return .primary
    }

    private func quit(_ r: Row, force: Bool) {
        if let g = r.group { model.confirmQuit(g, force: force) }
        else if let p = r.process { model.confirmQuit(p, force: force) }
    }

    private func quitMany(_ list: [Row]) {
        let groups: [AppGroup] = list.compactMap { r in
            if let g = r.group { return g }
            guard let p = r.process else { return nil }
            return AppGroup(id: r.id, name: p.name, icon: r.icon, pids: [p.pid], cpu: p.cpu, memory: p.memory,
                            diskRead: p.diskRead, diskWrite: p.diskWrite, app: NSRunningApplication(processIdentifier: p.pid),
                            isProtected: p.isProtected, isBackground: true)
        }
        model.confirmQuit(groups: groups)
        selection.removeAll()
    }
}
