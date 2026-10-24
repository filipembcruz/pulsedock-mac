import AppKit
import SwiftUI
import Combine

@main
@MainActor
enum PulseDockMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private let store = SettingsStore.shared
    private let monitor = SystemMonitor.shared
    private let procs = ProcessMonitor.shared
    private let model = AppModel.shared

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var widget: WidgetController!
    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var lastInterval: Double = 0
    private var lastLanguage = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()
        setupPopover()

        widget = WidgetController()

        model.openMainWindow = { [weak self] section in self?.showMainWindow(section) }
        model.togglePopover = { [weak self] in self?.togglePopover() }
        model.closePopover = { [weak self] in self?.popover.performClose(nil) }
        model.resetWidgetPosition = { [weak self] in self?.widget.resetPosition() }
        procs.isNeeded = { [weak self] in
            guard let self else { return false }
            if self.mainWindow?.isVisible == true && self.mainWindow?.isMiniaturized == false { return true }
            if self.popover.isShown { return true }
            return self.widget.isShown && self.store.s.layout == .expanded && self.store.s.showMemory
        }

        store.$s
            .receive(on: RunLoop.main)
            .sink { [weak self] s in self?.settingsChanged(s) }
            .store(in: &cancellables)

        monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snap in self?.updateStatusTitle(snap) }
            .store(in: &cancellables)

        settingsChanged(store.s)

        // Start with the Mac by default (only from /Applications, where macOS allows login items).
        if !store.s.loginItemConfigured, Bundle.main.bundlePath.hasPrefix("/Applications/") {
            LoginItem.set(true)
            store.s.loginItemConfigured = true
        }

        if !store.s.didOnboard {
            store.s.didOnboard = true
            showMainWindow(.overview)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow(nil)
        return true
    }

    private func settingsChanged(_ s: AppSettings) {
        if s.interval != lastInterval {
            lastInterval = s.interval
            monitor.start(interval: s.interval)
            procs.start(interval: max(2.5, s.interval * 2.5))
        }
        if s.language != lastLanguage {
            lastLanguage = s.language
            setupMainMenu()   // rebuild so the app menu follows the new language
        }
        updateStatusTitle(monitor.snapshot)
    }

    // MARK: Menu bar item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "PulseDock")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: L("open"), action: #selector(openMainFromMenu), keyEquivalent: "").target = self
        let widgetTitle = widget.isShown ? L("set.hideWidget") : L("set.showWidget")
        menu.addItem(withTitle: widgetTitle, action: #selector(toggleWidget), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("set.resetPosition"), action: #selector(resetWidget), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L("settingsEllipsis"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: L("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openMainFromMenu() { showMainWindow(nil) }
    @objc private func openSettings() { showMainWindow(.settings) }
    @objc private func resetWidget() { widget.resetPosition() }
    @objc private func toggleWidget() {
        if widget.isShown {
            store.s.mode = .menuBarOnly
        } else {
            widget.show()
        }
    }

    private func updateStatusTitle(_ snap: Snapshot) {
        guard let button = statusItem?.button else { return }
        let text: String
        switch store.s.menuBarStyle {
        case .iconOnly:
            text = ""
        case .cpu:
            text = Fmt.percent(snap.cpu)
        case .cpuMemory:
            text = "\(Fmt.percent(snap.cpu))  \(Fmt.percent(snap.memFraction))"
        case .full:
            text = "\(Fmt.percent(snap.cpu))  \(Fmt.percent(snap.memFraction))  ↓\(Fmt.shortRate(snap.netDown))"
        }
        let attr = NSAttributedString(string: text.isEmpty ? "" : " " + text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium),
        ])
        if button.attributedTitle != attr { button.attributedTitle = attr }
        button.toolTip = "CPU \(Fmt.percent(snap.cpu)) · RAM \(Fmt.bytes(snap.memUsed)) / \(Fmt.bytes(snap.memTotal, decimals: 0))"
    }

    // MARK: Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: PopoverView())
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            procs.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: Main window

    private func showMainWindow(_ section: NavSection?) {
        if let section { model.section = section }
        if mainWindow == nil {
            let host = NSHostingController(rootView: MainView())
            let window = NSWindow(contentViewController: host)
            window.title = "PulseDock"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 1080, height: 800))
            window.minSize = NSSize(width: 860, height: 600)
            window.setFrameAutosaveName("PulseDockMainWindow")
            window.delegate = self
            if window.frame.origin == .zero { window.center() }
            mainWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
        procs.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === mainWindow else { return }
        // Back to a menu bar app: no Dock icon while only the widget is visible.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: App menu (needed for ⌘Q, ⌘W, copy/paste in search fields)

    private func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("settingsEllipsis"), action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: L("menu.edit"))
        edit.addItem(withTitle: L("menu.undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L("menu.redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: L("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let win = NSMenu(title: L("menu.window"))
        win.addItem(withTitle: L("close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: L("menu.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = win
        NSApp.windowsMenu = win

        NSApp.mainMenu = main
    }
}
