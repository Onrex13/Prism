import SwiftUI

/// A compact, tappable module tile in the hub grid. Two rows: an icon + control
/// (toggle for services, chevron for on-demand tools) on top, the title beneath
/// on the full tile width so nothing truncates. Tapping the tile opens the
/// module's detail; the toggle flips the service without navigating.
struct ModuleTile: View {
    let info: ModuleInfo
    @Environment(HubState.self) private var hub
    @State private var hovering = false

    private var enabled: Bool { hub.isEnabled(info.id) }

    var body: some View {
        Button {
            guard info.available else { return }
            withAnimation(.smooth(duration: 0.35)) {
                hub.openModule = info.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    IconBadge(symbol: info.symbol, tint: info.tint, size: 30)
                    Spacer(minLength: 2)
                    trailingControl
                }
                Text(info.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(info.tint.glow(hovering ? 0.45 : 0.28))
            }
            .glassCard(radius: 15, tint: enabled ? info.tint : nil)
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(.white.opacity(hovering ? 0.22 : 0.10), lineWidth: 0.75)
            }
            .scaleEffect(hovering && info.available ? 1.03 : 1.0)
            .opacity(info.available ? 1 : 0.7)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.2), value: hovering)
    }

    @ViewBuilder
    private var trailingControl: some View {
        if info.available && !info.hasToggle {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        } else if info.available {
            Toggle("", isOn: Binding(
                get: { enabled },
                set: { hub.setEnabled(info.id, $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .tint(info.tint)
        } else {
            Text("Bientôt")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(0.12)))
        }
    }
}
