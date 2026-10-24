import Foundation
import AppKit
import SwiftUI

struct CleanCategory: Identifiable {
    enum Rule {
        /// Everything inside the folders.
        case contents
        /// Files directly inside the folders with these extensions, older than N days.
        case files(extensions: Set<String>, olderThanDays: Int)
        /// Everything inside the folders that hasn't been modified in N days.
        case olderThan(days: Int)
    }

    let id: String
    let symbol: String
    let color: Color
    let folders: [URL]
    let rule: Rule
    /// Regenerable data is deleted; anything else goes to the Trash.
    let regenerable: Bool
    let excluded: Set<String>

    var enabled: Bool
    var size: UInt64 = 0
    var items: [URL] = []
    var itemSizes: [URL: UInt64] = [:]
    var needsAccess = false
    var scanned = false

    var title: String { L("cat.\(id)") }
    var detail: String { L("cat.\(id).d") }
}

struct LargeFile: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: UInt64
    let modified: Date?
}

@MainActor
final class DiskCleaner: ObservableObject {
    static let shared = DiskCleaner()

    @Published var categories: [CleanCategory]
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published private(set) var hasScanned = false
    @Published private(set) var lastResult: String?
    @Published private(set) var largeFiles: [LargeFile] = []
    @Published private(set) var isFindingLarge = false
    @Published private(set) var didSearchLarge = false

    private init() {
        categories = Self.makeCategories()
    }

    var selectedSize: UInt64 {
        categories.filter { $0.enabled }.reduce(0) { $0 + $1.size }
    }

    var totalFound: UInt64 {
        categories.reduce(0) { $0 + $1.size }
    }

    static func makeCategories() -> [CleanCategory] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        func h(_ p: String) -> URL { home.appendingPathComponent(p, isDirectory: true) }
        let bundleID = Bundle.main.bundleIdentifier ?? "io.github.filipembcruz.PulseDock"

        return [
            CleanCategory(id: "caches", symbol: "shippingbox.fill", color: .orange,
                          folders: [h("Library/Caches")], rule: .contents, regenerable: true,
                          excluded: [bundleID, "com.apple.HomeKit", "com.apple.containermanagerd", "CloudKit", "com.apple.Safari.SafeBrowsing", "FamilyCircle"],
                          enabled: true),
            CleanCategory(id: "logs", symbol: "doc.text.fill", color: .blue,
                          folders: [h("Library/Logs")], rule: .contents, regenerable: true,
                          excluded: [], enabled: true),
            CleanCategory(id: "tmp", symbol: "clock.arrow.circlepath", color: .teal,
                          folders: [URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)],
                          rule: .olderThan(days: 3), regenerable: true, excluded: [], enabled: true),
            CleanCategory(id: "derived", symbol: "hammer.fill", color: .indigo,
                          folders: [h("Library/Developer/Xcode/DerivedData")], rule: .contents,
                          regenerable: true, excluded: [], enabled: true),
            CleanCategory(id: "simcaches", symbol: "iphone.gen3", color: .purple,
                          folders: [h("Library/Developer/CoreSimulator/Caches")], rule: .contents,
                          regenerable: true, excluded: [], enabled: true),
            CleanCategory(id: "devicesupport", symbol: "applewatch", color: .pink,
                          folders: [h("Library/Developer/Xcode/iOS DeviceSupport"),
                                    h("Library/Developer/Xcode/watchOS DeviceSupport"),
                                    h("Library/Developer/Xcode/tvOS DeviceSupport"),
                                    h("Library/Developer/Xcode/visionOS DeviceSupport")],
                          rule: .olderThan(days: 30), regenerable: true, excluded: [], enabled: false),
            CleanCategory(id: "devcaches", symbol: "cube.box.fill", color: .mint,
                          folders: [h(".npm/_cacache"), h(".gradle/caches"), h(".yarn/cache"),
                                    h(".cache/pip"), h(".cache/yarn"), h(".pnpm-store")],
                          rule: .contents, regenerable: true, excluded: [], enabled: false),
            CleanCategory(id: "mail", symbol: "paperclip", color: .cyan,
                          folders: [h("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")],
                          rule: .contents, regenerable: true, excluded: [], enabled: true),
            CleanCategory(id: "installers", symbol: "arrow.down.app.fill", color: .green,
                          folders: [h("Downloads")],
                          rule: .files(extensions: ["dmg", "pkg", "zip", "xip", "iso", "mpkg"], olderThanDays: 14),
                          regenerable: false, excluded: [], enabled: false),
            CleanCategory(id: "trash", symbol: "trash.fill", color: .red,
                          folders: [h(".Trash")], rule: .contents, regenerable: true,
                          excluded: [], enabled: false),
        ]
    }

    // MARK: Scan

    func scan() {
        guard !isScanning, !isCleaning else { return }
        isScanning = true
        lastResult = nil
        let snapshot = categories
        Task.detached(priority: .userInitiated) {
            var scanned: [CleanCategory] = []
            for var c in snapshot {
                Self.scan(&c)
                scanned.append(c)
            }
            let result = scanned
            await MainActor.run {
                // Keep the user's toggles from before the scan.
                let enabledByID = Dictionary(uniqueKeysWithValues: self.categories.map { ($0.id, $0.enabled) })
                self.categories = result.map { c in
                    var c = c
                    c.enabled = enabledByID[c.id] ?? c.enabled
                    return c
                }
                self.isScanning = false
                self.hasScanned = true
            }
        }
    }

    nonisolated static func scan(_ c: inout CleanCategory) {
        let fm = FileManager.default
        var items: [URL] = []
        var sizes: [URL: UInt64] = [:]
        var total: UInt64 = 0
        var needsAccess = false
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]

        for folder in c.folders {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let children: [URL]
            do {
                children = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])
            } catch {
                needsAccess = true
                continue
            }
            for child in children {
                let name = child.lastPathComponent
                if c.excluded.contains(name) || name == ".DS_Store" || name == ".localized" { continue }
                let values = try? child.resourceValues(forKeys: Set(keys))
                switch c.rule {
                case .contents:
                    break
                case let .files(exts, days):
                    if values?.isDirectory == true { continue }
                    guard exts.contains(child.pathExtension.lowercased()) else { continue }
                    if let m = values?.contentModificationDate, m > Date().addingTimeInterval(-Double(days) * 86400) { continue }
                case let .olderThan(days):
                    if let m = values?.contentModificationDate, m > Date().addingTimeInterval(-Double(days) * 86400) { continue }
                }
                let size = allocatedSize(of: child)
                guard size > 0 || values?.isDirectory == true else { continue }
                items.append(child)
                sizes[child] = size
                total += size
            }
        }
        c.items = items
        c.itemSizes = sizes
        c.size = total
        c.needsAccess = needsAccess
        c.scanned = true
    }

    nonisolated static func allocatedSize(of url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isSymbolicLinkKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return 0 }
        if v.isDirectory != true || v.isSymbolicLink == true {
            return UInt64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: UInt64 = 0
        for case let f as URL in e {
            guard let fv = try? f.resourceValues(forKeys: keys), fv.isRegularFile == true else { continue }
            total += UInt64(fv.totalFileAllocatedSize ?? fv.fileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: Clean

    func clean() {
        guard !isCleaning, !isScanning else { return }
        let selected = categories.filter { $0.enabled && !$0.items.isEmpty }
        guard !selected.isEmpty else { return }
        isCleaning = true
        Task.detached(priority: .userInitiated) {
            var freed: UInt64 = 0
            var skipped = 0
            let fm = FileManager.default
            for c in selected {
                for item in c.items {
                    let size = c.itemSizes[item] ?? 0
                    do {
                        if c.regenerable {
                            try fm.removeItem(at: item)
                        } else {
                            try fm.trashItem(at: item, resultingItemURL: nil)
                        }
                        freed += size
                    } catch {
                        // Partially removed folders still free some space; count what's gone.
                        let remaining = fm.fileExists(atPath: item.path) ? Self.allocatedSize(of: item) : 0
                        if remaining < size { freed += size - remaining }
                        skipped += 1
                    }
                }
            }
            let freedTotal = freed
            let skippedTotal = skipped
            await MainActor.run {
                self.isCleaning = false
                self.lastResult = skippedTotal == 0
                    ? L10n.f("cleanDone", Fmt.bytes(freedTotal))
                    : L10n.f("cleanPartial", Fmt.bytes(freedTotal), skippedTotal)
                SystemMonitor.shared.refreshDiskSpace()
                self.scan()
            }
        }
    }

    // MARK: Large files

    func findLargeFiles(minimum: UInt64 = 500 * 1024 * 1024) {
        guard !isFindingLarge else { return }
        isFindingLarge = true
        Task.detached(priority: .utility) {
            let found = Self.searchLarge(minimum: minimum)
            await MainActor.run {
                self.largeFiles = found
                self.isFindingLarge = false
                self.didSearchLarge = true
            }
        }
    }

    nonisolated static func searchLarge(minimum: UInt64) -> [LargeFile] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey]
        let skipTop: Set<String> = ["Library", "Applications", ".Trash"]
        var results: [LargeFile] = []
        guard let e = fm.enumerator(at: home, includingPropertiesForKeys: keys,
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                    errorHandler: { _, _ in true }) else { return [] }
        for case let url as URL in e {
            if e.level == 1, skipTop.contains(url.lastPathComponent) {
                e.skipDescendants()
                continue
            }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            let size = UInt64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            if size >= minimum {
                results.append(LargeFile(url: url, size: size, modified: v.contentModificationDate))
            }
        }
        return Array(results.sorted { $0.size > $1.size }.prefix(50))
    }

    func trash(_ file: LargeFile) {
        do {
            try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
            largeFiles.removeAll { $0.url == file.url }
            lastResult = L10n.f("freed", Fmt.bytes(file.size))
            SystemMonitor.shared.refreshDiskSpace()
        } catch {
            NSSound.beep()
        }
    }

    func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
