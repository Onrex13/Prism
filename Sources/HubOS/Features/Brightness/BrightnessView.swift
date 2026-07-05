import SwiftUI

/// In-hub control for the EDR brightness boost.
struct BrightnessView: View {
    @Environment(HubState.self) private var hub
    @Bindable private var brightness = BrightnessManager.shared

    private var active: Bool { PreviewConfig.forceActiveBrightness || hub.isEnabled(.brightness) }

    var body: some View {
        VStack(spacing: 16) {
            if brightness.isSupported {
                hero
                masterToggle
                slider
                footnote
            } else {
                unsupported
            }
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Theme.amber.opacity(active ? 0.35 : 0.12))
                    .frame(width: 120, height: 120)
                    .blur(radius: 24)
                    .scaleEffect(1 + brightness.intensity * (active ? 0.5 : 0))
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(
                        active
                            ? AnyShapeStyle(LinearGradient(colors: [.white, Theme.amber],
                                                           startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(Color.secondary)
                    )
                    .shadow(color: Theme.amber.opacity(active ? 0.8 : 0),
                            radius: 10 + brightness.intensity * 22)
            }
            .frame(height: 120)
            .animation(.smooth(duration: 0.35), value: active)
            .animation(.smooth(duration: 0.2), value: brightness.intensity)

            Text(active ? "+\(brightness.boostPercent)%" : "Désactivé")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(active ? AnyShapeStyle(Theme.amber) : AnyShapeStyle(.secondary))
                .contentTransition(.numericText())
                .animation(.smooth, value: brightness.boostPercent)
        }
    }

    // MARK: Master toggle

    private var masterToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Boost de luminosité")
                    .font(.system(size: 13, weight: .semibold))
                Text("Au-delà du maximum, via EDR")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { active },
                set: { hub.setEnabled(.brightness, $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(Theme.amber)
        }
        .padding(14)
        .glassCard(radius: 16)
    }

    // MARK: Slider

    private var slider: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.min.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Slider(value: $brightness.intensity, in: 0...1)
                .tint(Theme.amber)
                .disabled(!active)
            Image(systemName: "sun.max.fill")
                .font(.system(size: 17))
                .foregroundStyle(active ? Theme.amber : .secondary)
        }
        .padding(14)
        .glassCard(radius: 16)
        .opacity(active ? 1 : 0.5)
    }

    // MARK: Footnote

    private var footnote: some View {
        Label("Réversible instantanément · aucun réglage système modifié",
              systemImage: "checkmark.shield.fill")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

    // MARK: Unsupported

    private var unsupported: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max.trianglebadge.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("Écran non compatible")
                .font(.system(size: 15, weight: .semibold))
            Text("Le boost nécessite un écran EDR/HDR (MacBook Liquid Retina XDR, Pro Display XDR…).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 20)
    }
}
