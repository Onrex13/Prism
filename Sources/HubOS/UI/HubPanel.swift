import SwiftUI

/// The root content shown in the menu-bar popover: a Control-Center-style hub
/// of Liquid Glass module tiles, or a module's detail view when one is open.
struct HubPanel: View {
    @Environment(HubState.self) private var hub

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)

            Group {
                if hub.showingSettings {
                    SettingsView()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if let open = hub.openModule {
                    ModuleDetailView(id: open)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                } else {
                    grid
                        .transition(.opacity)
                }
            }

            if hub.openModule == nil && !hub.showingSettings {
                Divider().opacity(0.4)
                footer
            }
        }
        .frame(width: Theme.panelWidth)
        .background(PanelBackground())
        .overlay(alignment: .bottom) {
            if let toast = Notifier.shared.toast {
                ToastBanner(toast: toast)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.32), value: Notifier.shared.toast)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            if showingDetail {
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        hub.openModule = nil
                        hub.showingSettings = false
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.glass)
                .transition(.scale.combined(with: .opacity))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(AppInfo.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.brandGradient)
                Text(headerSubtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Settings gear (hidden while a detail panel is open).
            if !showingDetail {
                Button {
                    withAnimation(.smooth(duration: 0.3)) { hub.showingSettings = true }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.glass)
            }

            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.brandGradient)
                .opacity(0.9)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var showingDetail: Bool { hub.openModule != nil || hub.showingSettings }

    private var headerSubtitle: String {
        if hub.showingSettings {
            return L(fr: "Réglages · permissions · mises à jour", en: "Settings · permissions · updates")
        }
        if let open = hub.openModule {
            return ModuleInfo.info(for: open).subtitle
        }
        return L(fr: "Ton Mac, en mieux.", en: "Your Mac, but better.")
    }

    // MARK: Grid

    private var grid: some View {
        // Self-sizing (NOT a ScrollView): a ScrollView collapses to zero height
        // inside MenuBarExtra(.window)'s content-sizing pass, blanking the grid.
        VStack(alignment: .leading, spacing: 14) {
            // Services run in the background (toggleable); tools open on demand.
            // (Launch-at-login lives in Settings now.)
            moduleSection(L(fr: "Services actifs", en: "Active services"), ModuleInfo.all.filter { $0.hasToggle })
            moduleSection(L(fr: "Outils", en: "Tools"), ModuleInfo.all.filter { !$0.hasToggle })
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
    }

    private func moduleSection(_ title: String, _ items: [ModuleInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title).padding(.leading, 2)
            GlassEffectContainer(spacing: 10) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items) { ModuleTile(info: $0) }
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text("v\(AppInfo.version)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                    Text(L(fr: "Quitter", en: "Quit"))
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// Transient outcome banner shown at the bottom of the panel (see `Notifier`).
private struct ToastBanner: View {
    let toast: Notifier.Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(toast.isError ? Theme.red : Theme.green)
            Text(toast.message)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button { Notifier.shared.dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .glassCard(radius: 12)
    }
}

/// Ambient background: a subtle brand-tinted radial wash beneath the glass.
private struct PanelBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.001)) // hosts the visual effect below
            RadialGradient(
                colors: [Theme.indigo.opacity(0.22), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 340
            )
            RadialGradient(
                colors: [Theme.pink.opacity(0.14), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 300
            )
        }
        .ignoresSafeArea()
    }
}
