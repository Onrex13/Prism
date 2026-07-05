import SwiftUI

/// In-hub panel for the Shelf module.
struct ShelfInfoView: View {
    @Environment(HubState.self) private var hub
    private var store: ShelfStore { ShelfStore.shared }

    private var enabled: Bool { hub.isEnabled(.shelf) }

    var body: some View {
        VStack(spacing: 14) {
            IconBadge(symbol: "tray.full.fill", tint: Theme.teal, size: 58)
                .padding(.top, 4)

            VStack(spacing: 4) {
                Text("Shelf").font(.system(size: 16, weight: .bold))
                Text("Une étagère au bord droit de l'écran. Dépose-y fichiers, images ou texte, puis re-glisse-les où tu veux.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Text("Activer le Shelf").font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("", isOn: Binding(get: { enabled },
                                         set: { hub.setEnabled(.shelf, $0) }))
                    .toggleStyle(.switch).labelsHidden().tint(Theme.teal)
            }
            .padding(14)
            .glassCard(radius: 16)

            HStack(spacing: 8) {
                Image(systemName: "arrow.right.to.line").foregroundStyle(Theme.teal)
                Text("Approche le bord droit ou glisse un fichier vers la droite pour l'ouvrir.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
            .glassCard(radius: 14)

            if !store.isEmpty {
                Text("\(store.items.count) élément\(store.items.count > 1 ? "s" : "") en attente")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
    }
}
