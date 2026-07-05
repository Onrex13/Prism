import SwiftUI

/// Design tokens for HubOS. Everything visual pulls from here so the whole app
/// stays coherent with a single accent language.
enum Theme {
    // MARK: Brand palette
    static let indigo = Color(red: 0.42, green: 0.36, blue: 0.98)   // #6B5CFA
    static let violet = Color(red: 0.63, green: 0.35, blue: 0.98)   // #A15AFA
    static let pink   = Color(red: 0.98, green: 0.36, blue: 0.68)   // #FA5CAD
    static let teal   = Color(red: 0.22, green: 0.82, blue: 0.80)   // #38D1CC
    static let amber  = Color(red: 0.99, green: 0.70, blue: 0.28)   // #FDB347
    static let green  = Color(red: 0.30, green: 0.83, blue: 0.53)   // #4CD388
    static let blue   = Color(red: 0.28, green: 0.60, blue: 0.99)   // #479AFC
    static let red    = Color(red: 0.98, green: 0.38, blue: 0.35)   // #FA615A

    /// Signature brand gradient — indigo → violet → pink, used for the wordmark
    /// and hero accents.
    static let brandGradient = LinearGradient(
        colors: [indigo, violet, pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Metrics
    static let panelWidth: CGFloat = 380
    static let cornerRadius: CGFloat = 22
    static let tileRadius: CGFloat = 20
    static let tileSpacing: CGFloat = 12
}

extension Color {
    /// Builds a soft radial glow gradient from an accent color, used behind
    /// glass tiles to give them a lit-from-within quality.
    func glow(_ strength: Double = 0.55) -> RadialGradient {
        RadialGradient(
            colors: [self.opacity(strength), .clear],
            center: .topLeading,
            startRadius: 0,
            endRadius: 140
        )
    }
}
