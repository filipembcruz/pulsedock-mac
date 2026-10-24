import Foundation
import Combine

enum DisplayMode: String, Codable, CaseIterable, Identifiable {
    case overlay      // floating above windows
    case desktop      // pinned to the desktop, behind windows
    case menuBarOnly  // only the menu bar item
    var id: String { rawValue }
}

enum WidgetLayout: String, Codable, CaseIterable, Identifiable {
    case compact, expanded, strip
    var id: String { rawValue }
}

enum Corner: String, Codable, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
}

enum MenuBarStyle: String, Codable, CaseIterable, Identifiable {
    case iconOnly, cpu, cpuMemory, full
    var id: String { rawValue }
}

struct AppSettings: Codable, Equatable {
    var mode: DisplayMode = .overlay
    var layout: WidgetLayout = .compact
    var corner: Corner = .topRight
    var edgeMargin: Double = 12
    var freePosition: Bool = false
    /// Top-left of the widget, in screen coordinates (y = top edge).
    var freeX: Double = 0
    var freeY: Double = 0
    var lockPosition: Bool = false
    /// CGDirectDisplayID of the chosen screen. 0 = main screen.
    var screenID: UInt32 = 0
    var opacity: Double = 1.0
    var interval: Double = 1.0

    var showCPU = true
    var showMemory = true
    var showDisk = true
    var showGPU = true
    var showNetwork = true
    var showBattery = true

    var clickThrough = false
    var hideInFullscreen = true
    var menuBarStyle: MenuBarStyle = .cpuMemory
    /// "en" (default), "pt" or "auto" (follows macOS)
    var language: String = "en"
    var groupByApp = true
    var didOnboard = false

    init() {}

    // Tolerant decoding: missing keys keep their defaults, so new versions can add settings safely.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        mode = (try? c.decodeIfPresent(DisplayMode.self, forKey: .mode)) ?? d.mode
        layout = (try? c.decodeIfPresent(WidgetLayout.self, forKey: .layout)) ?? d.layout
        corner = (try? c.decodeIfPresent(Corner.self, forKey: .corner)) ?? d.corner
        edgeMargin = (try? c.decodeIfPresent(Double.self, forKey: .edgeMargin)) ?? d.edgeMargin
        freePosition = (try? c.decodeIfPresent(Bool.self, forKey: .freePosition)) ?? d.freePosition
        freeX = (try? c.decodeIfPresent(Double.self, forKey: .freeX)) ?? d.freeX
        freeY = (try? c.decodeIfPresent(Double.self, forKey: .freeY)) ?? d.freeY
        lockPosition = (try? c.decodeIfPresent(Bool.self, forKey: .lockPosition)) ?? d.lockPosition
        screenID = (try? c.decodeIfPresent(UInt32.self, forKey: .screenID)) ?? d.screenID
        opacity = (try? c.decodeIfPresent(Double.self, forKey: .opacity)) ?? d.opacity
        interval = (try? c.decodeIfPresent(Double.self, forKey: .interval)) ?? d.interval
        showCPU = (try? c.decodeIfPresent(Bool.self, forKey: .showCPU)) ?? d.showCPU
        showMemory = (try? c.decodeIfPresent(Bool.self, forKey: .showMemory)) ?? d.showMemory
        showDisk = (try? c.decodeIfPresent(Bool.self, forKey: .showDisk)) ?? d.showDisk
        showGPU = (try? c.decodeIfPresent(Bool.self, forKey: .showGPU)) ?? d.showGPU
        showNetwork = (try? c.decodeIfPresent(Bool.self, forKey: .showNetwork)) ?? d.showNetwork
        showBattery = (try? c.decodeIfPresent(Bool.self, forKey: .showBattery)) ?? d.showBattery
        clickThrough = (try? c.decodeIfPresent(Bool.self, forKey: .clickThrough)) ?? d.clickThrough
        hideInFullscreen = (try? c.decodeIfPresent(Bool.self, forKey: .hideInFullscreen)) ?? d.hideInFullscreen
        menuBarStyle = (try? c.decodeIfPresent(MenuBarStyle.self, forKey: .menuBarStyle)) ?? d.menuBarStyle
        language = (try? c.decodeIfPresent(String.self, forKey: .language)) ?? d.language
        groupByApp = (try? c.decodeIfPresent(Bool.self, forKey: .groupByApp)) ?? d.groupByApp
        didOnboard = (try? c.decodeIfPresent(Bool.self, forKey: .didOnboard)) ?? d.didOnboard
        sanitize()
    }

    mutating func sanitize() {
        opacity = min(max(opacity, 0.4), 1.0)
        interval = min(max(interval, 0.5), 10)
        edgeMargin = min(max(edgeMargin, 0), 400)
        if !["auto", "en", "pt"].contains(language) { language = "en" }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var s: AppSettings {
        didSet {
            guard s != oldValue else { return }
            L10n.language = s.language
            save()
        }
    }

    private let key = "PulseDock.settings.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            s = decoded
        } else {
            s = AppSettings()
        }
        L10n.language = s.language
    }

    private func save() {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func reset() {
        let onboarded = s.didOnboard
        s = AppSettings()
        s.didOnboard = onboarded
    }
}
