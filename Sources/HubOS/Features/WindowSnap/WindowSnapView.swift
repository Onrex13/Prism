import SwiftUI

/// Detail panel for the Window Snapping active service: master toggle,
/// Accessibility status, and a grid of snap positions (click, or use the ⌃⌥
/// shortcuts once the service is on).
struct WindowSnapView: View {
    @Bindable private var mgr = WindowSnapManager.shared
    @Environment(HubState.self) private var hub

    private var isOn: Bool { hub.isEnabled(.windowsnap) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    private var hints: [WindowSnapManager.Position: String] {
        Dictionary(uniqueKeysWithValues: WindowSnapManager.shortcutHints.map { ($0.pos, $0.label) })
    }

    var body: some View {
        VStack(spacing: 14) {
            masterToggle
            if !mgr.accessibilityGranted { accessibilityRow }
            grid
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
        .animation(.smooth(duration: 0.2), value: isOn)
    }

    private var masterToggle: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L(fr: "Snapping de fenêtres", en: "Window snapping"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L(fr: "Raccourcis ⌃⌥ + flèches quand activé",
                       en: "⌃⌥ + arrows shortcuts when on"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { hub.setEnabled(.windowsnap, $0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Theme.indigo)
        }
        .padding(.horizontal, 14).padding(.vertical, 10).glassCard(radius: 14)
    }

    private var accessibilityRow: some View {
        Button {
            PermissionsManager.shared.requestAccessibility()
            PermissionsManager.shared.openSettings(for: "accessibility")
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
                Text(L(fr: "Autoriser l'Accessibilité pour déplacer les fenêtres",
                       en: "Grant Accessibility to move windows"))
                    .font(.system(size: 11, weight: .medium)).multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.forward").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.amber.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(WindowSnapManager.Position.allCases) { pos in
                Button { mgr.snap(pos) } label: {
                    VStack(spacing: 5) {
                        miniLayout(pos)
                        Text(hints[pos] ?? " ")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(hints[pos] != nil ? AnyShapeStyle(Theme.indigo) : AnyShapeStyle(.clear))
                    }
                    .padding(.vertical, 8).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func miniLayout(_ pos: WindowSnapManager.Position) -> some View {
        let W = 48.0, H = 30.0
        let r = Self.unitRect(pos)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.white.opacity(0.06))
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Theme.indigo.opacity(0.9))
                .frame(width: r.width * W - 3, height: r.height * H - 3)
                .offset(x: r.minX * W + 1.5, y: r.minY * H + 1.5)
        }
        .frame(width: W, height: H)
    }

    /// Position as a fraction rect in SwiftUI (top-left) orientation.
    private static func unitRect(_ pos: WindowSnapManager.Position) -> CGRect {
        let t = 1.0 / 3
        switch pos {
        case .leftHalf:    return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf:   return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf:     return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf:  return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft:     return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight:    return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft:  return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .leftThird:   return CGRect(x: 0, y: 0, width: t, height: 1)
        case .centerThird: return CGRect(x: t, y: 0, width: t, height: 1)
        case .rightThird:  return CGRect(x: 2 * t, y: 0, width: t, height: 1)
        case .maximize:    return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .center:      return CGRect(x: 0.15, y: 0.12, width: 0.7, height: 0.76)
        }
    }
}
