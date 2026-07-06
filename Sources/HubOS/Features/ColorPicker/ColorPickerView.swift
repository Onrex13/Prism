import SwiftUI

/// Screen colour picker: a big eyedropper button, the last pick with its HEX/RGB
/// (tap to copy), and a persistent swatch history.
struct ColorPickerView: View {
    @Bindable private var picker = ColorPickerManager.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        VStack(spacing: 16) {
            hero
            if let latest = picker.latest {
                latestCard(latest)
                historySection
            } else {
                emptyHint
            }
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
        .animation(.smooth(duration: 0.25), value: picker.history)
    }

    private var hero: some View {
        Button { picker.pick() } label: {
            HStack(spacing: 8) {
                Image(systemName: "eyedropper.halffull")
                Text(L(fr: "Choisir une couleur", en: "Pick a color"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent).tint(Theme.pink).controlSize(.large)
    }

    private func latestCard(_ s: ColorPickerManager.Swatch) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(s.color)
                .frame(width: 62, height: 62)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                }
            VStack(alignment: .leading, spacing: 7) {
                copyRow(s.hex) { picker.copy(s) }
                copyRow(s.rgb) { picker.copy(s, asRGB: true) }
            }
            Spacer(minLength: 0)
        }
        .padding(12).glassCard(radius: 18)
    }

    private func copyRow(_ text: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(text).font(.system(size: 13, weight: .semibold, design: .monospaced))
                Image(systemName: "doc.on.doc").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: L(fr: "Historique", en: "History"))
                Spacer()
                Button { picker.clear() } label: {
                    Text(L(fr: "Effacer", en: "Clear")).font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(picker.history) { swatch($0) }
            }
        }
    }

    private func swatch(_ s: ColorPickerManager.Swatch) -> some View {
        Button { picker.copy(s) } label: {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(s.color)
                .frame(height: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(s.hex)
        .contextMenu {
            Button(L(fr: "Copier HEX", en: "Copy HEX")) { picker.copy(s) }
            Button(L(fr: "Copier RGB", en: "Copy RGB")) { picker.copy(s, asRGB: true) }
            Button(L(fr: "Supprimer", en: "Remove"), role: .destructive) { picker.remove(s) }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            IconBadge(symbol: "eyedropper.halffull", tint: Theme.pink, size: 56).padding(.top, 8)
            Text(L(fr: "Aucune couleur", en: "No colors yet")).font(.system(size: 14, weight: .semibold))
            Text(L(fr: "Pointe n'importe quel pixel de l'écran pour capturer sa couleur.",
                   en: "Point at any pixel on screen to capture its color."))
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(height: 160)
    }
}
