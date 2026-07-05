import SwiftUI
import Observation

/// Shared reveal state for the shelf window.
@MainActor
@Observable
final class ShelfModel {
    var revealed = false
}

/// The right-edge shelf: a slim tab that expands into a Liquid Glass drop panel
/// on hover or when a drag approaches. Items can be dragged back out.
struct ShelfView: View {
    var model: ShelfModel
    private var store: ShelfStore { ShelfStore.shared }

    @State private var dropTargeting = false

    private var open: Bool { model.revealed || dropTargeting }

    var body: some View {
        ZStack(alignment: .trailing) {
            panel
                .frame(width: 264)
                // Content-sized panel, centered vertically, with a right gap.
                // Its soft shadow fades into the surrounding window margin.
                .padding(.trailing, 18)
                .offset(x: open ? 0 : 340)
                .opacity(open ? 1 : 0)

            tab
                .opacity(open ? 0 : 1)
                .offset(x: -4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: open)
        // Accept drops even over the collapsed tab so a drag reveals the shelf.
        .onDrop(of: [.fileURL, .image, .url, .plainText], isTargeted: $dropTargeting) { providers in
            let handled = store.handleDrop(providers)
            // Keep the shelf open ~2s after the drop instead of snapping shut.
            if handled { ShelfController.shared.holdOpen() }
            return handled
        }
    }

    // MARK: Tab

    private var tab: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            if !store.isEmpty {
                Text("\(store.items.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Circle().fill(Theme.teal))
            }
        }
        .frame(width: 30, height: 92)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14,
                                   bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
                .fill(Theme.teal.opacity(0.9))
                .shadow(color: .black.opacity(0.3), radius: 8, x: -2)
        }
    }

    // MARK: Panel

    /// Height of the items area: grows with the item count, then caps and scrolls.
    private var itemsHeight: CGFloat {
        store.isEmpty ? 128 : min(CGFloat(store.items.count) * 62 + 4, 360)
    }

    private var panel: some View {
        VStack(spacing: 10) {
            header
            Group {
                if store.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(store.items) { item in
                                ShelfCard(item: item)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .frame(height: itemsHeight)
        }
        .padding(14)
        .liquidPanel(cornerRadius: 24)
        .overlay {
            if dropTargeting {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.teal, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .padding(1)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconBadge(symbol: "tray.full.fill", tint: Theme.teal, size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text("Shelf").font(.system(size: 14, weight: .bold))
                Text("\(store.items.count) élément\(store.items.count > 1 ? "s" : "")")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if !store.isEmpty {
                Button {
                    withAnimation(.smooth) { store.clearAll() }
                } label: {
                    Image(systemName: "trash").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.teal.opacity(0.8))
            Text("Dépose ici")
                .font(.system(size: 13, weight: .semibold))
            Text("Fichiers, images, texte…")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A single shelf entry that can be dragged back out.
private struct ShelfCard: View {
    let item: ShelfItem
    private var store: ShelfStore { ShelfStore.shared }
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                Text(item.subtitle)
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if hovering {
                Button {
                    withAnimation(.smooth) { store.remove(item) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(hovering ? 0.12 : 0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.15), value: hovering)
        .onDrag { store.provider(for: item) }
    }

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let icon = item.icon {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    item.accent.opacity(0.2)
                    Image(systemName: item.symbol).foregroundStyle(item.accent)
                }
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
