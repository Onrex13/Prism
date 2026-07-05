import SwiftUI

// MARK: - Glass card

private struct GlassCardModifier: ViewModifier {
    var radius: CGFloat
    var tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .glassEffect(
                tint.map { .regular.tint($0.opacity(0.18)) } ?? .regular,
                in: shape
            )
    }
}

extension View {
    /// Wraps a view in a Liquid Glass surface with a rounded-rect shape and an
    /// optional accent tint.
    func glassCard(radius: CGFloat = Theme.tileRadius, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(radius: radius, tint: tint))
    }
}

// MARK: - Liquid panel

/// The signature HubOS surface, tuned to match the new Siri "Search or Ask"
/// glass: a deep, neutral translucent panel with a top-lit inner sheen, a fine
/// gradient hairline, and a soft shape-hugging shadow (window shadow must be
/// disabled so it doesn't ghost a rectangle behind the rounded shape).
private struct LiquidPanel: ViewModifier {
    var cornerRadius: CGFloat
    var shadow: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            // Native Liquid Glass refraction.
            .glassEffect(.regular, in: shape)
            // Luminous frosted base so the panel reads as a distinct surface on
            // ANY wallpaper. On dark desktops the old dark wash collapsed the
            // glass into a murky black box; a light top-lift with only a faint
            // bottom grounding keeps it looking like frosted glass everywhere.
            .background {
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.10), .white.opacity(0.03), .black.opacity(0.10)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
            // Top-lit inner sheen.
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.12), .clear],
                            startPoint: .top, endPoint: .center
                        )
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            // Fine gradient hairline border, brighter at the top edge.
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.10), .white.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .compositingGroup()
            .shadow(color: shadow ? .black.opacity(0.35) : .clear, radius: 22, y: 10)
    }
}

extension View {
    /// Applies the HubOS liquid-glass panel treatment.
    func liquidPanel(cornerRadius: CGFloat = 28, shadow: Bool = true) -> some View {
        modifier(LiquidPanel(cornerRadius: cornerRadius, shadow: shadow))
    }
}

// MARK: - Icon badge

/// A tinted, glowing rounded-square badge containing an SF Symbol. Used as the
/// leading icon in module tiles and detail headers.
struct IconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                    }
            }
            .shadow(color: tint.opacity(0.45), radius: 8, y: 3)
    }
}

// MARK: - Section label

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}
