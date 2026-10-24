import SwiftUI
import AppKit

/// Liquid Glass on macOS 26+, translucent material on older systems.
extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 20, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Self.makeGlass(tint: tint, interactive: interactive),
                             in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.regularMaterial)
                        if let tint {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tint.opacity(0.08))
                        }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                }
        }
    }

    @available(macOS 26.0, *)
    private static func makeGlass(tint: Color?, interactive: Bool) -> Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint.opacity(0.22)) }
        if interactive { g = g.interactive() }
        return g
    }

    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}

/// Groups glass shapes so they blend and morph together (macOS 26+).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

enum Palette {
    static let cpu = Color(red: 0.24, green: 0.56, blue: 1.0)
    static let memory = Color(red: 0.69, green: 0.38, blue: 1.0)
    static let disk = Color(red: 1.0, green: 0.62, blue: 0.18)
    static let gpu = Color(red: 0.16, green: 0.82, blue: 0.62)
    static let netDown = Color(red: 0.20, green: 0.78, blue: 0.95)
    static let netUp = Color(red: 1.0, green: 0.36, blue: 0.52)
    static let battery = Color(red: 0.35, green: 0.85, blue: 0.35)

    static func level(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: return .green
        case ..<0.85: return .orange
        default: return .red
        }
    }

    static func pressure(_ p: MemoryPressure) -> Color {
        switch p {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
