import SwiftUI

/// The clipboard history UI shown inside the hub popover.
struct ClipboardView: View {
    @Bindable private var store = ClipboardStore.shared

    var body: some View {
        VStack(spacing: 10) {
            searchBar

            if store.filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.filtered) { item in
                            ClipboardRow(item: item)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(height: 360)
                .scrollIndicators(.hidden)
            }

            footer
        }
        .padding(14)
        .onAppear { store.start() }
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Rechercher…", text: $store.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassCard(radius: 12)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.indigo.opacity(0.8))
            Text(store.searchText.isEmpty ? "Ton historique apparaîtra ici" : "Aucun résultat")
                .font(.system(size: 13, weight: .semibold))
            if store.searchText.isEmpty {
                Text("Copie du texte, une image ou un fichier (⌘C)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("\(store.items.count) élément\(store.items.count > 1 ? "s" : "")")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
            if store.items.contains(where: { !$0.pinned }) {
                Button {
                    withAnimation(.smooth) { store.clearUnpinned() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Tout effacer")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.glass)
            }
        }
    }
}

/// A single history entry row with thumbnail, text, and hover actions.
private struct ClipboardRow: View {
    let item: ClipboardItem
    private var store: ClipboardStore { ClipboardStore.shared }

    @State private var hovering = false
    @State private var justCopied = false

    var body: some View {
        Button {
            store.copy(item)
            withAnimation(.smooth(duration: 0.2)) { justCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.smooth(duration: 0.3)) { justCopied = false }
            }
        } label: {
            HStack(spacing: 11) {
                thumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.subtitle())
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                trailing
            }
            .padding(9)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.white.opacity(hovering ? 0.10 : 0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        justCopied ? Theme.green.opacity(0.9) : .white.opacity(hovering ? 0.14 : 0.06),
                        lineWidth: justCopied ? 1.5 : 0.75
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.15), value: hovering)
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.kind {
        case .image:
            if let image = store.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                    }
            } else {
                IconBadge(symbol: item.symbol, tint: item.accent)
            }
        case .color:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(item.swatchColor ?? Theme.violet)
                .frame(width: 40, height: 40)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 0.75)
                }
        default:
            IconBadge(symbol: item.symbol, tint: item.accent)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 6) {
            if justCopied {
                Label("Copié", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.green)
                    .transition(.scale.combined(with: .opacity))
            }
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.amber)
                    .rotationEffect(.degrees(35))
            }
            if hovering {
                Button {
                    store.togglePin(item)
                } label: {
                    Image(systemName: item.pinned ? "pin.slash" : "pin")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(item.pinned ? "Détacher" : "Épingler")

                Button {
                    withAnimation(.smooth) { store.delete(item) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Supprimer")
            }
        }
    }
}
