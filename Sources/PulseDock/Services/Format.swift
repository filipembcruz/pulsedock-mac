import Foundation

enum Fmt {
    static func bytes(_ value: UInt64, decimals: Int = 1) -> String {
        bytes(Double(value), decimals: decimals)
    }

    static func bytes(_ value: Double, decimals: Int = 1) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = max(value, 0)
        var i = 0
        while v >= 1024 && i < units.count - 1 {
            v /= 1024
            i += 1
        }
        if i == 0 { return "\(Int(v)) B" }
        let d = v >= 100 ? 0 : decimals
        return String(format: "%.\(d)f %@", v, units[i])
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1024 { return "\(Int(max(bytesPerSecond, 0))) B/s" }
        return bytes(bytesPerSecond) + "/s"
    }

    /// Short form for tight spaces: "1.2M", "340K".
    static func shortRate(_ bytesPerSecond: Double) -> String {
        let v = max(bytesPerSecond, 0)
        if v < 1024 { return "\(Int(v))B" }
        if v < 1024 * 1024 { return String(format: "%.0fK", v / 1024) }
        if v < 1024 * 1024 * 1024 {
            let m = v / 1024 / 1024
            return m >= 100 ? String(format: "%.0fM", m) : String(format: "%.1fM", m)
        }
        return String(format: "%.1fG", v / 1024 / 1024 / 1024)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((max(0, min(fraction, 1)) * 100).rounded()))%"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let days = s / 86400
        let hours = (s % 86400) / 3600
        let minutes = (s % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
