import SwiftUI

/// A grid of quick system switches and actions.
struct SwitchesView: View {
    @Bindable private var mgr = SwitchesManager.shared

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 10) {
                tile(L(fr: "Mode sombre", en: "Dark Mode"), "moon.fill", tint: Theme.indigo,
                     on: mgr.darkMode) { mgr.toggleDarkMode() }
                tile(L(fr: "Fichiers cachés", en: "Hidden Files"), "eye.fill", tint: Theme.teal,
                     on: mgr.hiddenFiles) { mgr.toggleHiddenFiles() }
                tile(L(fr: "Vider la corbeille", en: "Empty Trash"), "trash.fill", tint: Theme.pink,
                     on: nil) { mgr.emptyTrash() }
                tile(L(fr: "Économiseur", en: "Screensaver"), "display", tint: Theme.violet,
                     on: nil) { mgr.startScreensaver() }
                tile(L(fr: "Veille écran", en: "Sleep Display"), "moon.zzz.fill", tint: Theme.blue,
                     on: nil) { mgr.sleepDisplay() }
                tile(L(fr: "Verrouiller", en: "Lock Screen"), "lock.fill", tint: Theme.amber,
                     on: nil) { mgr.lockScreen() }
            }
            Label(L(fr: "Toggles = état réel · les actions se déclenchent au clic",
                    en: "Toggles show the real state · actions fire on tap"),
                  systemImage: "info.circle")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
        .animation(.smooth(duration: 0.2), value: mgr.darkMode)
        .animation(.smooth(duration: 0.2), value: mgr.hiddenFiles)
        .onAppear { mgr.refresh() }
    }

    private func tile(_ label: String, _ symbol: String, tint: Color, on: Bool?, _ action: @escaping () -> Void) -> some View {
        let active = on == true
        return Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 21))
                    .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).frame(height: 76)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(active ? tint.opacity(0.85) : .white.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(active ? tint.opacity(0.9) : .white.opacity(0.10), lineWidth: active ? 1 : 0.75)
            }
        }
        .buttonStyle(.plain)
    }
}
