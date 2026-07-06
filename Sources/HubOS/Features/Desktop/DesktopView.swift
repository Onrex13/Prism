import SwiftUI

/// Detail panel for the Clean Desktop active service: a master toggle that hides
/// or shows the Finder desktop icons.
struct DesktopView: View {
    @Environment(HubState.self) private var hub

    private var isOn: Bool { hub.isEnabled(.desktop) }

    var body: some View {
        VStack(spacing: 16) {
            hero
            masterToggle
            Label(L(fr: "Rien n'est supprimé · masque seulement les icônes, réversible à tout moment",
                    en: "Nothing is deleted · only hides the icons, reversible anytime"),
                  systemImage: "info.circle")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
        .animation(.smooth(duration: 0.25), value: isOn)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            IconBadge(symbol: isOn ? "menubar.dock.rectangle" : "macwindow.on.rectangle",
                      tint: Theme.indigo, size: 60).padding(.top, 6)
            Text(isOn ? L(fr: "Bureau épuré", en: "Desktop hidden")
                 : L(fr: "Icônes visibles", en: "Icons visible"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn ? Theme.indigo : .secondary)
        }
    }

    private var masterToggle: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L(fr: "Masquer les icônes du bureau", en: "Hide desktop icons"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L(fr: "Un bureau net pour les captures et la concentration",
                       en: "A clean desktop for screenshots and focus"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { hub.setEnabled(.desktop, $0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Theme.indigo)
        }
        .padding(.horizontal, 14).padding(.vertical, 10).glassCard(radius: 14)
    }
}
