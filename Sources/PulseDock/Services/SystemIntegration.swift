import Foundation
import AppKit
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
            return true
        } catch {
            NSLog("PulseDock: login item change failed: \(error.localizedDescription)")
            return false
        }
    }
}

enum FullscreenDetector {
    /// True when the frontmost app (not us) has a window covering an entire screen.
    static func frontmostAppIsFullscreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != getpid() else { return false }
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let screens = NSScreen.screens.map { $0.frame.size }
        for w in info {
            guard (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == front.processIdentifier,
                  (w[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let b = w[kCGWindowBounds as String] as? [String: Any],
                  let width = (b["Width"] as? NSNumber)?.doubleValue,
                  let height = (b["Height"] as? NSNumber)?.doubleValue else { continue }
            if screens.contains(where: { abs($0.width - width) < 1 && abs($0.height - height) < 1 }) {
                return true
            }
        }
        return false
    }
}

extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

enum AppInfo {
    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }
}
