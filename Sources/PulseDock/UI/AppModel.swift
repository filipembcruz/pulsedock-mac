import SwiftUI
import AppKit

enum NavSection: String, CaseIterable, Identifiable, Hashable {
    case overview, memory, processes, cleanup, settings
    var id: String { rawValue }

    var title: String { L(rawValue) }

    var symbol: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .memory: return "memorychip.fill"
        case .processes: return "list.bullet.rectangle.fill"
        case .cleanup: return "sparkles"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Navigation + window actions shared by the widget, the popover and the main window.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var section: NavSection = .overview
    @Published var processSort: ProcSort = .memory
    /// Bumped to force views to re-read localized strings after a language change.
    @Published var languageTick = 0

    var openMainWindow: (NavSection?) -> Void = { _ in }
    var togglePopover: () -> Void = {}
    var closePopover: () -> Void = {}
    var resetWidgetPosition: () -> Void = {}

    private init() {}

    func open(_ section: NavSection, sort: ProcSort? = nil) {
        if let sort { processSort = sort }
        self.section = section
        closePopover()
        openMainWindow(section)
    }

    // MARK: Quitting with confirmation

    func confirmQuit(_ group: AppGroup, force: Bool) {
        let alert = NSAlert()
        alert.messageText = L10n.f("quitConfirmTitle", group.name)
        alert.informativeText = L10n.f(force ? "forceConfirmBody" : "quitConfirmBody", Fmt.bytes(group.memory))
        alert.alertStyle = force ? .critical : .warning
        if let icon = group.icon { alert.icon = icon }
        alert.addButton(withTitle: force ? L("forceQuit") : L("quitApp"))
        alert.addButton(withTitle: L("cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if !ProcessMonitor.shared.quit(group, force: force) && !force {
                // Graceful quit refused (e.g. hung app): offer force quit.
                confirmQuit(group, force: true)
            }
        }
    }

    func confirmQuit(_ process: ProcInfo, force: Bool) {
        let alert = NSAlert()
        alert.messageText = L10n.f("quitConfirmTitle", process.name)
        alert.informativeText = L10n.f(force ? "forceConfirmBody" : "quitConfirmBody", Fmt.bytes(process.memory))
        alert.alertStyle = force ? .critical : .warning
        alert.addButton(withTitle: force ? L("forceQuit") : L("quitApp"))
        alert.addButton(withTitle: L("cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            ProcessMonitor.shared.quit(process, force: force)
        }
    }

    func confirmQuit(groups: [AppGroup]) {
        let targets = groups.filter { !$0.isProtected }
        guard !targets.isEmpty else { return }
        if targets.count == 1 { confirmQuit(targets[0], force: false); return }
        let total = targets.reduce(UInt64(0)) { $0 + $1.memory }
        let alert = NSAlert()
        alert.messageText = L10n.f("quitManyTitle", targets.count)
        alert.informativeText = L10n.f("quitManyBody", Fmt.bytes(total)) + "\n\n" + targets.map { "• \($0.name) — \(Fmt.bytes($0.memory))" }.joined(separator: "\n")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("quitApp"))
        alert.addButton(withTitle: L("cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            for g in targets { ProcessMonitor.shared.quit(g, force: false) }
        }
    }
}
