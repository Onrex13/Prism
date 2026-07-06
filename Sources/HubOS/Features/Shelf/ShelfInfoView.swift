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
                Text(L(fr: "Une étagère au bord droit de l'écran. Dépose-y fichiers, images ou texte, puis re-glisse-les où tu veux.",
                       en: "A shelf on the right edge of your screen. Drop files, images or text onto it, then drag them back out wherever you like."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Text(L(fr: "Activer le Shelf", en: "Enable Shelf")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("", isOn: Binding(get: { enabled },
                                         set: { hub.setEnabled(.shelf, $0) }))
                    .toggleStyle(.switch).labelsHidden().tint(Theme.teal)
            }
            .padding(14)
            .glassCard(radius: 16)

            HStack(spacing: 8) {
                Image(systemName: "arrow.right.to.line").foregroundStyle(Theme.teal)
                Text(L(fr: "Approche le bord droit ou glisse un fichier vers la droite pour l'ouvrir.",
                       en: "Move toward the right edge or drag a file rightward to open it."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
            .glassCard(radius: 14)

            if !store.isEmpty {
                Text(L(fr: "\(store.items.count) élément\(store.items.count > 1 ? "s" : "") en attente",
                       en: "\(store.items.count) item\(store.items.count > 1 ? "s" : "") waiting"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
    }
}
