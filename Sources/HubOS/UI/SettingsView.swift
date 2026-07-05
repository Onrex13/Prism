import SwiftUI

/// App-level settings: required permissions (with live status), launch-at-login,
/// and GitHub-release updates.
struct SettingsView: View {
    @Bindable private var perms = PermissionsManager.shared
    @Bindable private var updates = UpdateManager.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            permissionsSection
            generalSection
            updatesSection
            aboutFooter
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
        .onAppear { perms.refresh() }
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Permissions").padding(.leading, 2)
            VStack(spacing: 0) {
                ForEach(perms.permissions) { p in
                    permissionRow(p)
                    if p.id != perms.permissions.last?.id {
                        Divider().opacity(0.1).padding(.leading, 46)
                    }
                }
            }
            .padding(.vertical, 4).glassCard(radius: 16)
        }
    }

    private func permissionRow(_ p: PermissionsManager.Permission) -> some View {
        let granted = perms.status(for: p.id)
        return HStack(spacing: 11) {
            IconBadge(symbol: p.symbol, tint: granted == true ? Theme.green : Theme.indigo, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).font(.system(size: 12.5, weight: .semibold))
                Text(p.detail).font(.system(size: 9.5)).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            statusControl(p, granted: granted)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    private func statusControl(_ p: PermissionsManager.Permission, granted: Bool?) -> some View {
        if granted == true {
            pill("Accordée", Theme.green, "checkmark")
        } else if p.checkable {
            Button {
                perms.requestAccessibility()
                perms.openSettings(for: p.id)
            } label: { pill("Accorder", Theme.amber, "exclamationmark") }
                .buttonStyle(.plain)
        } else {
            // Automation: can't be pre-granted — just open the pane to review it.
            Button { perms.openSettings(for: p.id) } label: {
                pill("Réglages", Theme.indigo, "arrow.up.forward")
            }
            .buttonStyle(.plain)
        }
    }

    private func pill(_ text: String, _ tint: Color, _ symbol: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold))
            Text(text).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.18)))
    }

    // MARK: General

    private var generalSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "power.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.indigo)
            Text("Lancer au démarrage").font(.system(size: 12.5, weight: .medium))
            Spacer()
            Toggle("", isOn: Binding(get: { launchAtLogin },
                                     set: { launchAtLogin = $0; LaunchAtLogin.set($0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Theme.indigo)
        }
        .padding(.horizontal, 14).padding(.vertical, 10).glassCard(radius: 14)
    }

    // MARK: Updates

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Mises à jour").padding(.leading, 2)
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    IconBadge(symbol: "arrow.down.circle.fill", tint: Theme.teal, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Version \(AppInfo.version)").font(.system(size: 12.5, weight: .semibold))
                        Text(updateStatusText).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    updateControl
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10).glassCard(radius: 16)
        }
    }

    private var updateStatusText: String {
        switch updates.state {
        case .idle: return "Vérifie la dernière release GitHub"
        case .checking: return "Recherche…"
        case .upToDate: return "Tu as la dernière version ✓"
        case .available(let v, _): return "Nouvelle version \(v) disponible"
        case .downloading(let p): return "Téléchargement… \(Int(p * 100))%"
        case .installing: return "Installation…"
        case .failed(let m): return m
        }
    }

    @ViewBuilder
    private var updateControl: some View {
        switch updates.state {
        case .checking, .downloading, .installing:
            ProgressView().controlSize(.small)
        case .available:
            Button { Task { await updates.downloadAndInstall() } } label: {
                Text("Installer").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.glassProminent).tint(Theme.teal).controlSize(.small)
        default:
            Button { Task { await updates.check() } } label: {
                Text("Vérifier").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.glass).controlSize(.small)
        }
    }

    // MARK: About

    private var aboutFooter: some View {
        HStack(spacing: 6) {
            Text(AppInfo.name).font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.brandGradient)
            Text("· ton Mac, en mieux").font(.system(size: 10)).foregroundStyle(.tertiary)
            Spacer()
            Button {
                NSWorkspace.shared.open(AppInfo.isRepoConfigured ? AppInfo.repoURL
                                        : URL(string: "https://github.com")!)
            } label: {
                Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.glass).controlSize(.small)
        }
        .padding(.top, 2)
    }
}
