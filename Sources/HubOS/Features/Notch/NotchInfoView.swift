import SwiftUI

/// In-hub panel for the Dynamic Island: enable, live now-playing, and settings.
struct NotchInfoView: View {
    @Environment(HubState.self) private var hub
    private var np: NowPlayingMonitor { NowPlayingMonitor.shared }
    @Bindable private var settings = DynamicIslandSettings.shared

    private var enabled: Bool { hub.isEnabled(.notch) }

    var body: some View {
        VStack(spacing: 14) {
            header

            HStack {
                Text(L(fr: "Activer l'île dynamique", en: "Enable Dynamic Island"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("", isOn: Binding(get: { enabled },
                                         set: { hub.setEnabled(.notch, $0) }))
                    .toggleStyle(.switch).labelsHidden().tint(Theme.pink)
            }
            .padding(14)
            .glassCard(radius: 16)

            if np.hasMedia { nowPlaying }

            customization

            Label(L(fr: "Spotify & Apple Music pris en charge", en: "Spotify & Apple Music supported"),
                  systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
    }

    private var header: some View {
        VStack(spacing: 5) {
            IconBadge(symbol: "rectangle.topthird.inset.filled", tint: Theme.pink, size: 54)
            Text("Dynamic Island")
                .font(.system(size: 16, weight: .bold))
            Text(L(fr: "Survole l'encoche pour dérouler le lecteur.", en: "Hover the notch to expand the player."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var nowPlaying: some View {
        HStack(spacing: 11) {
            ZStack {
                if let art = np.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: [Theme.pink, Theme.violet],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(np.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(np.artist).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: np.isPlaying ? "waveform" : "pause.fill")
                .foregroundStyle(np.accentColor ?? Theme.pink)
        }
        .padding(12)
        .glassCard(radius: 16)
    }

    private var customization: some View {
        VStack(spacing: 0) {
            settingRow(L(fr: "Pochette en veille", en: "Idle artwork"), "photo", $settings.idleArtwork)
            divider
            settingRow(L(fr: "Waveform en veille", en: "Idle waveform"), "waveform", $settings.idleWaveform)
            divider
            settingRow(L(fr: "Barre de progression", en: "Progress bar"), "timeline.selection", $settings.showProgress)
            divider
            settingRow(L(fr: "Halo ambiant", en: "Ambient glow"), "sparkles", $settings.ambientGlow)
        }
        .padding(.vertical, 4)
        .glassCard(radius: 16)
    }

    private var divider: some View {
        Divider().opacity(0.15).padding(.horizontal, 12)
    }

    private func settingRow(_ title: String, _ symbol: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Theme.pink)
                .frame(width: 18)
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            Toggle("", isOn: binding)
                .toggleStyle(.switch).labelsHidden().controlSize(.mini).tint(Theme.pink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
