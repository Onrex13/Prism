import SwiftUI
import AppKit

/// Screen colour picker: a big eyedropper button, a built-in colour selector for
/// composing any colour, the last pick with its HEX/RGB (tap to copy), and a
/// persistent swatch history.
struct ColorPickerView: View {
    @Bindable private var picker = ColorPickerManager.shared

    // Inline HSB selector state (a web-style square + hue slider).
    @State private var hue = 0.72
    @State private var sat = 0.62
    @State private var bri = 0.98

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    private var composedColor: Color { Color(hue: hue, saturation: sat, brightness: bri) }
    private var composedHex: String { ColorPickerManager.hex(from: NSColor(composedColor)) }

    var body: some View {
        VStack(spacing: 14) {
            hero
            composeCard
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
                Text(L(fr: "Pipette écran", en: "Screen eyedropper"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent).tint(Theme.pink).controlSize(.large)
    }

    /// An inline web-style colour selector: a saturation/brightness square, a hue
    /// slider, a live HEX/RGB readout, and a button to save the composed colour.
    private var composeCard: some View {
        VStack(spacing: 10) {
            svSquare
            hueSlider
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(composedColor)
                    .frame(width: 34, height: 34)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(composedHex)
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    let (r, g, b) = ColorPickerManager.rgb(composedHex)
                    Text("rgb(\(r), \(g), \(b))")
                        .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { picker.addComposed(composedColor) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text(L(fr: "Ajouter", en: "Add"))
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.glassProminent).controlSize(.small).tint(Theme.pink)
            }
        }
        .padding(12).glassCard(radius: 16)
    }

    /// Saturation (x) × brightness (y) field for the current hue.
    private var svSquare: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                Color(hue: hue, saturation: 1, brightness: 1)
                LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                Circle()
                    .strokeBorder(.white, lineWidth: 2)
                    .background(Circle().fill(composedColor))
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(x: CGFloat(sat) * w - 8, y: (1 - CGFloat(bri)) * h - 8)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                sat = Double(v.location.x / w).clamped(to: 0...1)
                bri = Double(1 - v.location.y / h).clamped(to: 0...1)
            })
        }
        .frame(height: 130)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Full-spectrum hue slider.
    private var hueSlider: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6)
                        .map { Color(hue: $0, saturation: 1, brightness: 1) },
                    startPoint: .leading, endPoint: .trailing)
                Capsule()
                    .strokeBorder(.white, lineWidth: 2)
                    .background(Capsule().fill(Color(hue: hue, saturation: 1, brightness: 1)))
                    .frame(width: 14, height: 22)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(x: (CGFloat(hue) * w - 7).clamped(to: 0...(w - 14)))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                hue = Double(v.location.x / w).clamped(to: 0...1)
            })
        }
        .frame(height: 18)
        .clipShape(Capsule())
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
