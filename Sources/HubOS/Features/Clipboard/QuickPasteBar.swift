import SwiftUI

/// The floating quick-paste strip: a horizontal, keyboard-navigable row of
/// clipboard cards shown at the bottom of the screen on ⌘⇧V.
struct QuickPasteBar: View {
    let controller: QuickPasteController
    let onActivate: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if controller.results.isEmpty {
                emptyRow
            } else {
                cards
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidPanel(cornerRadius: 30)
        // Transparent margin ≥ the shadow's blur radius so the soft shadow fades
        // fully inside the window instead of being clipped into a hard rectangle.
        .padding(44)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.brandGradient)
            Text(L(fr: "Presse-papiers", en: "Clipboard"))
                .font(.system(size: 14, weight: .bold))

            if !controller.query.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .bold))
                    Text(controller.query)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(0.14)))
            }

            Spacer()
            hint("←→", L(fr: "naviguer", en: "navigate"))
            hint("⏎", L(fr: "coller", en: "paste"))
            hint("esc", L(fr: "fermer", en: "close"))
        }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.12)))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyRow: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.secondary)
                Text(controller.query.isEmpty
                     ? L(fr: "Historique vide", en: "History empty")
                     : L(fr: "Aucun résultat", en: "No results"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(height: 150)
    }

    // MARK: Cards

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(controller.results.enumerated()), id: \.element.id) { index, item in
                        QuickCard(item: item, selected: index == controller.selectedIndex)
                            .id(index)
                            .onTapGesture { onActivate(index) }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .frame(height: 158)
            .onChange(of: controller.selectedIndex) { _, new in
                withAnimation(.snappy(duration: 0.25)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }
}

/// A single card in the quick-paste strip.
private struct QuickCard: View {
    let item: ClipboardItem
    let selected: Bool

    private let width: CGFloat = 158
    private let height: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
                .frame(width: width, height: height - 34)
                .clipped()
            footer
        }
        .frame(width: width, height: height)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(selected ? 0.14 : 0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    selected ? item.accent : .white.opacity(0.10),
                    lineWidth: selected ? 2.5 : 0.75
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: selected ? item.accent.opacity(0.5) : .clear, radius: 12, y: 4)
        .scaleEffect(selected ? 1.04 : 1.0)
        .animation(.snappy(duration: 0.2), value: selected)
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .image:
            if let image = ClipboardStore.shared.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                iconPreview
            }
        case .color:
            ZStack {
                (item.swatchColor ?? Theme.violet)
                Text(item.text.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        case .emoji:
            ZStack {
                Theme.amber.opacity(0.18)
                Text(item.text).font(.system(size: 42))
            }
        case .text, .link, .file:
            textPreview
        }
    }

    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: item.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(item.accent)
            Text(item.kind == .file ? item.title : item.text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var iconPreview: some View {
        ZStack {
            item.accent.opacity(0.18)
            Image(systemName: item.symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(item.accent)
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: item.symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(item.accent)
            Text(footerText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.amber)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.18))
    }

    private var footerText: String {
        switch item.kind {
        case .image: return L(fr: "Image", en: "Image")
        case .color: return L(fr: "Couleur", en: "Color")
        case .link:  return item.source ?? L(fr: "Lien", en: "Link")
        case .file:  return item.source ?? L(fr: "Fichier", en: "File")
        case .text:  return item.source ?? L(fr: "Texte", en: "Text")
        case .emoji: return L(fr: "Emoji", en: "Emoji")
        }
    }
}
