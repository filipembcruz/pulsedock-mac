import AppKit
import SwiftUI
import Combine

final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating widget window: level, position, snapping, click-through and auto-hide.
@MainActor
final class WidgetController {
    private let panel: WidgetPanel
    private let host: NSHostingView<WidgetView>
    private var sizeTimer: Timer?
    private let store = SettingsStore.shared
    private var cancellables = Set<AnyCancellable>()
    private var dragOffset: CGPoint?
    private var modifierTimer: Timer?
    private var fullscreenTimer: Timer?
    private var hiddenForFullscreen = false

    init() {
        panel = WidgetPanel(contentRect: NSRect(x: 0, y: 0, width: 214, height: 200),
                            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        var view = WidgetView()
        host = NSHostingView(rootView: view)
        host.sizingOptions = [.intrinsicContentSize]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host

        // Callbacks need `self`, so install them after init.
        view.onDrag = { [weak self] p in self?.drag(to: p) }
        view.onDragEnd = { [weak self] in self?.endDrag() }
        view.onSize = { [weak self] size in self?.resize(to: size) }
        host.rootView = view
        // Never start at 0×0: SwiftUI doesn't lay out (or report its size from) an empty view.
        panel.setContentSize(NSSize(width: 214, height: 240))
        fitToContent()

        // Safety net: content size changes with data (e.g. a GPU or battery row appearing).
        // Comparing two sizes twice a second costs nothing and guarantees the panel never clips.
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitToContent() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        sizeTimer = t

        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }

        store.$s
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] s in self?.apply(s) }
            .store(in: &cancellables)
    }

    // MARK: Settings → window

    func apply(_ s: AppSettings) {
        switch s.mode {
        case .overlay:
            panel.level = .floating
        case .desktop:
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .menuBarOnly:
            break
        }
        panel.alphaValue = s.opacity
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.fitToContent() } }
        updateClickThrough(s)
        updateFullscreenWatcher(s)
        reposition()
        updateVisibility()
    }

    private func updateVisibility() {
        let s = store.s
        if s.mode == .menuBarOnly || hiddenForFullscreen {
            panel.orderOut(nil)
        } else if !panel.isVisible {
            reposition()
            panel.orderFrontRegardless()
        }
    }

    var isShown: Bool { panel.isVisible }

    func show() {
        if store.s.mode == .menuBarOnly { store.s.mode = .overlay }
        hiddenForFullscreen = false
        updateVisibility()
    }

    // MARK: Size

    /// Sizes the panel to the SwiftUI content's ideal size (the root view is `.fixedSize()`).
    private func fitToContent() {
        let fit = host.fittingSize
        if fit.width > 1, fit.height > 1 { resize(to: fit) }
    }

    private func resize(to size: CGSize) {
        let target = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard target.width > 1, target.height > 1,
              abs(panel.frame.width - target.width) > 0.5 || abs(panel.frame.height - target.height) > 0.5 else { return }
        panel.setContentSize(target)
        reposition()
    }

    // MARK: Position

    private var targetScreen: NSScreen {
        let id = store.s.screenID
        if id != 0, let s = NSScreen.screens.first(where: { $0.displayID == id }) { return s }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    func reposition() {
        let s = store.s
        let size = panel.frame.size
        if s.freePosition {
            var origin = CGPoint(x: s.freeX, y: s.freeY - size.height)
            // Keep it reachable if the screen setup changed.
            let union = NSScreen.screens.reduce(NSRect.null) { $0.union($1.visibleFrame) }
            if !union.intersects(NSRect(origin: origin, size: size)) {
                origin = cornerOrigin(.topRight, size: size, screen: targetScreen, margin: s.edgeMargin)
            }
            panel.setFrameOrigin(origin)
        } else {
            panel.setFrameOrigin(cornerOrigin(s.corner, size: size, screen: targetScreen, margin: s.edgeMargin))
        }
    }

    private func cornerOrigin(_ corner: Corner, size: CGSize, screen: NSScreen, margin: Double) -> CGPoint {
        let vf = screen.visibleFrame
        let m = CGFloat(margin)
        switch corner {
        case .topLeft: return CGPoint(x: vf.minX + m, y: vf.maxY - size.height - m)
        case .topRight: return CGPoint(x: vf.maxX - size.width - m, y: vf.maxY - size.height - m)
        case .bottomLeft: return CGPoint(x: vf.minX + m, y: vf.minY + m)
        case .bottomRight: return CGPoint(x: vf.maxX - size.width - m, y: vf.minY + m)
        }
    }

    func resetPosition() {
        var s = store.s
        s.freePosition = false
        s.screenID = 0
        store.s = s
        show()
        reposition()
    }

    // MARK: Drag & snap

    private func drag(to mouse: CGPoint) {
        if dragOffset == nil {
            dragOffset = CGPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        }
        guard let off = dragOffset else { return }
        panel.setFrameOrigin(CGPoint(x: mouse.x - off.x, y: mouse.y - off.y))
    }

    private func endDrag() {
        dragOffset = nil
        let frame = panel.frame
        let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }) ?? targetScreen
        let snapDistance: CGFloat = 70
        var best: (Corner, CGFloat)?
        for c in Corner.allCases {
            let o = cornerOrigin(c, size: frame.size, screen: screen, margin: store.s.edgeMargin)
            let d = hypot(o.x - frame.minX, o.y - frame.minY)
            if d < snapDistance, d < (best?.1 ?? .greatestFiniteMagnitude) { best = (c, d) }
        }
        var s = store.s
        s.screenID = screen.displayID
        if let b = best {
            s.corner = b.0
            s.freePosition = false
        } else {
            s.freePosition = true
            s.freeX = Double(frame.minX)
            s.freeY = Double(frame.maxY)
        }
        store.s = s   // the settings sink repositions (snaps) the panel
        reposition()
    }

    // MARK: Click-through (hold ⌥ to interact)

    private func updateClickThrough(_ s: AppSettings) {
        modifierTimer?.invalidate()
        modifierTimer = nil
        guard s.clickThrough else {
            panel.ignoresMouseEvents = false
            return
        }
        panel.ignoresMouseEvents = true
        let t = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let option = NSEvent.modifierFlags.contains(.option)
                if self.panel.ignoresMouseEvents == option { self.panel.ignoresMouseEvents = !option }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        modifierTimer = t
    }

    // MARK: Hide in full screen

    private func updateFullscreenWatcher(_ s: AppSettings) {
        fullscreenTimer?.invalidate()
        fullscreenTimer = nil
        guard s.hideInFullscreen, s.mode != .menuBarOnly else {
            if hiddenForFullscreen { hiddenForFullscreen = false; updateVisibility() }
            return
        }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let fs = FullscreenDetector.frontmostAppIsFullscreen()
                if fs != self.hiddenForFullscreen {
                    self.hiddenForFullscreen = fs
                    self.updateVisibility()
                }
            }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        fullscreenTimer = t
    }
}
