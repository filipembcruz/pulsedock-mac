import SwiftUI
import AppKit

struct RingGauge: View {
    var value: Double
    var color: Color
    var lineWidth: CGFloat = 8
    var label: String? = nil
    var caption: String? = nil

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(value, 1)))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.65), color], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360 * max(0.001, min(value, 1)))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                if let label {
                    Text(label)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                }
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct Sparkline: View {
    var values: [Double]
    var color: Color
    /// Fixed maximum (e.g. 1 for percentages). nil = auto-scale.
    var maxValue: Double? = nil
    var fill = true
    var lineWidth: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            let maxV = max(maxValue ?? (values.max() ?? 0), 0.0001)
            let pts = points(in: geo.size, maxV: maxV)
            ZStack {
                if fill, pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                }
                if pts.count > 1 {
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize, maxV: Double) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let capacity = max(values.count, 60)
        let step = size.width / CGFloat(capacity - 1)
        let offset = CGFloat(capacity - values.count) * step
        return values.enumerated().map { i, v in
            let y = size.height - CGFloat(min(v / maxV, 1)) * (size.height - 2) - 1
            return CGPoint(x: offset + CGFloat(i) * step, y: y)
        }
    }
}

struct LevelBar: View {
    var value: Double
    var color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.16))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * CGFloat(max(0, min(value, 1)))))
            }
        }
        .frame(height: height)
    }
}

/// Mini vertical bars, one per CPU core.
struct CoreBars: View {
    var values: [Double]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(color.opacity(0.25 + 0.75 * min(v, 1)))
                        .frame(height: max(2, geo.size.height * CGFloat(min(v, 1))))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
    }
}

struct MetricIcon: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom))
            )
    }
}

struct AppIconView: View {
    var image: NSImage?
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "gearshape.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Section title used in the main window.
struct SectionHeader: View {
    var title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(.title2, design: .rounded).weight(.bold))
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: return L("thermal.nominal")
        case .fair: return L("thermal.fair")
        case .serious: return L("thermal.serious")
        case .critical: return L("thermal.critical")
        @unknown default: return "—"
        }
    }

    var color: Color {
        switch self {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }
}
