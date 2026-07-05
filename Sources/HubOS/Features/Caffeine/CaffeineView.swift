import SwiftUI

/// In-hub control for the Caffeine (keep-awake) module.
struct CaffeineView: View {
    @Environment(HubState.self) private var hub
    @Bindable private var caffeine = CaffeineManager.shared

    private var active: Bool { hub.isEnabled(.caffeine) }

    var body: some View {
        VStack(spacing: 16) {
            hero
            masterToggle
            modePicker
            durationPicker
            footnote
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
        .animation(.smooth(duration: 0.3), value: active)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Theme.violet.opacity(active ? 0.35 : 0.12))
                    .frame(width: 120, height: 120)
                    .blur(radius: 24)
                Image(systemName: active ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 50, weight: .regular))
                    .foregroundStyle(
                        active
                            ? AnyShapeStyle(LinearGradient(colors: [.white, Theme.violet],
                                                           startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(Color.secondary)
                    )
                    .shadow(color: Theme.violet.opacity(active ? 0.8 : 0), radius: 16)
                    .symbolEffect(.pulse, options: .repeating, isActive: active)
            }
            .frame(height: 120)

            Text(caffeine.statusText)
                .font(.system(size: active && caffeine.remainingSeconds != nil ? 30 : 24,
                              weight: .bold, design: .rounded))
                .foregroundStyle(active ? AnyShapeStyle(Theme.violet) : AnyShapeStyle(.secondary))
                .contentTransition(.numericText())
                .animation(.smooth, value: caffeine.remainingSeconds)
        }
    }

    // MARK: Master toggle

    private var masterToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Garder mon Mac éveillé")
                    .font(.system(size: 13, weight: .semibold))
                Text("Empêche l'écran et la mise en veille")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { active },
                set: { hub.setEnabled(.caffeine, $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(Theme.violet)
        }
        .padding(14)
        .glassCard(radius: 16)
    }

    // MARK: Mode

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(CaffeineManager.Mode.allCases) { m in
                Button {
                    caffeine.mode = m
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: m.symbol).font(.system(size: 15, weight: .medium))
                        Text(m.title).font(.system(size: 11, weight: .semibold))
                        Text(m.detail).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(caffeine.mode == m ? Theme.violet.opacity(0.22) : .white.opacity(0.05))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(caffeine.mode == m ? Theme.violet.opacity(0.6) : .white.opacity(0.08),
                                          lineWidth: 1)
                    }
                    .foregroundStyle(caffeine.mode == m ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.smooth(duration: 0.2), value: caffeine.mode)
    }

    // MARK: Duration

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Durée")
            HStack(spacing: 6) {
                ForEach(CaffeineManager.durationOptions.indices, id: \.self) { i in
                    let option = CaffeineManager.durationOptions[i]
                    Button {
                        caffeine.duration = option
                    } label: {
                        Text(Self.label(option))
                            .font(.system(size: 11.5, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background {
                                Capsule().fill(caffeine.duration == option
                                    ? Theme.violet.opacity(0.9) : .white.opacity(0.06))
                            }
                            .foregroundStyle(caffeine.duration == option ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .glassCard(radius: 16)
        .animation(.smooth(duration: 0.2), value: caffeine.duration)
    }

    private static func label(_ minutes: Int?) -> String {
        guard let minutes else { return "∞" }
        return minutes >= 60 ? "\(minutes / 60) h" : "\(minutes) min"
    }

    // MARK: Footnote

    private var footnote: some View {
        Label("Réversible instantanément · aucun réglage système modifié",
              systemImage: "checkmark.shield.fill")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }
}
