import SwiftUI
import AppKit

struct CleanupPage: View {
    @ObservedObject var cleaner = DiskCleaner.shared
    @ObservedObject var monitor = SystemMonitor.shared
    @State private var confirming = false

    private var snap: Snapshot { monitor.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let result = cleaner.lastResult {
                    Label(result, systemImage: "checkmark.seal.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .glassCard(cornerRadius: 14, tint: .green)
                }
                categoriesList
                largeFilesSection
            }
            .padding(24)
        }
        .confirmationDialog(L10n.f("cleanConfirmTitle", Fmt.bytes(cleaner.selectedSize)), isPresented: $confirming) {
            Button(L10n.f("cleanSelected", Fmt.bytes(cleaner.selectedSize)), role: .destructive) { cleaner.clean() }
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(L("cleanConfirmBody"))
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            ZStack {
                RingGauge(value: snap.diskUsedFraction, color: Palette.disk, lineWidth: 12,
                          label: Fmt.bytes(snap.diskFree), caption: L("free"))
            }
            .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: 8) {
                Text(L("cleanup.title")).font(.system(.title, design: .rounded).weight(.bold))
                Text(L("cleanup.subtitle")).foregroundStyle(.secondary)
                Text("\(L("startupDisk")): \(Fmt.bytes(snap.diskTotal - min(snap.diskFree, snap.diskTotal))) \(L("used")) \(L("of")) \(Fmt.bytes(snap.diskTotal, decimals: 0))")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if cleaner.isScanning || cleaner.isCleaning {
                        ProgressView().controlSize(.small)
                        Text(cleaner.isScanning ? L("scanning") : L("cleaning")).foregroundStyle(.secondary)
                    } else {
                        Button {
                            cleaner.scan()
                        } label: {
                            Label(cleaner.hasScanned ? L("rescan") : L("scan"), systemImage: "magnifyingglass")
                        }
                        .glassButton(prominent: !cleaner.hasScanned)
                        .controlSize(.large)

                        if cleaner.hasScanned {
                            Button {
                                confirming = true
                            } label: {
                                Label(cleaner.selectedSize > 0 ? L10n.f("cleanSelected", Fmt.bytes(cleaner.selectedSize)) : L("nothingToClean"),
                                      systemImage: "sparkles")
                            }
                            .glassButton(prominent: true)
                            .controlSize(.large)
                            .disabled(cleaner.selectedSize == 0)
                        }
                    }
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(20)
        .glassCard(cornerRadius: 26, tint: Palette.disk)
    }

    private var categoriesList: some View {
        VStack(spacing: 0) {
            ForEach($cleaner.categories) { $cat in
                CategoryRow(category: $cat, scanned: cleaner.hasScanned, busy: cleaner.isScanning || cleaner.isCleaning)
                if cat.id != cleaner.categories.last?.id {
                    Divider().opacity(0.25).padding(.leading, 60)
                }
            }
        }
        .glassCard(cornerRadius: 20)
    }

    private var largeFilesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("largeFiles")).font(.headline)
                    Text(L("largeFilesHint")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if cleaner.isFindingLarge {
                    ProgressView().controlSize(.small)
                } else {
                    Button { cleaner.findLargeFiles() } label: {
                        Label(L("findLarge"), systemImage: "doc.viewfinder")
                    }
                    .glassButton()
                }
            }
            if cleaner.didSearchLarge && cleaner.largeFiles.isEmpty && !cleaner.isFindingLarge {
                Text(L("noLargeFiles")).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(cleaner.largeFiles) { f in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: f.url.path))
                        .resizable().frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.url.lastPathComponent).lineLimit(1)
                        Text(f.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if let m = f.modified {
                        Text(m, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(Fmt.bytes(f.size)).font(.callout.weight(.semibold)).monospacedDigit().frame(width: 80, alignment: .trailing)
                    Button { cleaner.reveal([f.url]) } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.borderless).help(L("reveal"))
                    Button { cleaner.trash(f) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).help(L("moveToTrash"))
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }
}

private struct CategoryRow: View {
    @Binding var category: CleanCategory
    var scanned: Bool
    var busy: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $category.enabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(busy)
            MetricIcon(symbol: category.symbol, color: category.color, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(category.title).font(.body.weight(.medium))
                    Text(category.regenerable ? L("safe") : L("review"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill((category.regenerable ? Color.green : Color.orange).opacity(0.18)))
                        .foregroundStyle(category.regenerable ? Color.green : Color.orange)
                }
                Text(category.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if category.needsAccess {
                    Button(L("grantAccess")) { DiskCleaner.shared.openFullDiskAccessSettings() }
                        .buttonStyle(.link)
                        .font(.caption)
                        .help(L("needsAccess"))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if scanned && category.scanned {
                    Text(Fmt.bytes(category.size))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(category.size > 0 ? Color.primary : Color.secondary)
                    Text(L10n.f("items", category.items.count)).font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            Button {
                let existing = category.folders.filter { FileManager.default.fileExists(atPath: $0.path) }
                NSWorkspace.shared.activateFileViewerSelecting(existing.isEmpty ? [FileManager.default.homeDirectoryForCurrentUser] : existing)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help(L("reveal"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
