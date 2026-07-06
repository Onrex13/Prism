import SwiftUI

/// In-hub Cleaner hub with three tabs: reclaim disk space, monitor memory, and
/// audit startup items for adware / unsigned persistence.
struct CleanerView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case clean, memory, security
        var id: String { rawValue }
        @MainActor var title: String {
            self == .clean ? L(fr: "Nettoyage", en: "Cleanup")
                : self == .memory ? L(fr: "Mémoire", en: "Memory")
                : L(fr: "Sécurité", en: "Security")
        }
        var symbol: String { self == .clean ? "sparkles" : self == .memory ? "memorychip.fill" : "checkmark.shield.fill" }
        var tint: Color { self == .clean ? Theme.green : self == .memory ? Theme.teal : Theme.indigo }
    }

    @State private var tab: Tab

    init() {
        _tab = State(initialValue: Tab(rawValue: PreviewConfig.forcedCleanerTab ?? "") ?? .clean)
    }

    var body: some View {
        VStack(spacing: 14) {
            tabBar
            Group {
                switch tab {
                case .clean:    CleanTab()
                case .memory:   MemoryTab()
                case .security: SecurityTab()
                }
            }
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
        .animation(.smooth(duration: 0.25), value: tab)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { t in
                Button { tab = t } label: {
                    HStack(spacing: 5) {
                        Image(systemName: t.symbol).font(.system(size: 11, weight: .semibold))
                        Text(t.title).font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        Capsule().fill(tab == t ? t.tint.opacity(0.25) : .white.opacity(0.05))
                    }
                    .overlay {
                        Capsule().strokeBorder(tab == t ? t.tint.opacity(0.6) : .clear, lineWidth: 1)
                    }
                    .foregroundStyle(tab == t ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
            }
        }
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
    static func bytes(_ value: UInt64) -> String { bytes(Int64(value)) }
}

// MARK: - Nettoyage (disk reclaim)

private struct CleanTab: View {
    @Bindable private var scanner = CleanerScanner.shared
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 14) {
            switch scanner.phase {
            case .idle:     idle
            case .scanning: busy(L(fr: "Analyse en cours…", en: "Scanning…"))
            case .ready:    results
            case .cleaning: busy(L(fr: "Nettoyage…", en: "Cleaning…"))
            case .done:     done
            }
        }
        .animation(.smooth(duration: 0.3), value: scanner.phase)
    }

    private var idle: some View {
        VStack(spacing: 14) {
            IconBadge(symbol: "sparkles", tint: Theme.green, size: 64).padding(.top, 8)
            Text(L(fr: "Nettoyer mon Mac", en: "Clean my Mac")).font(.system(size: 17, weight: .bold))
            Text(L(fr: "Analyse les caches, journaux, la corbeille et les données de build récupérables.",
                   en: "Scans reclaimable caches, logs, trash and build data."))
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { Task { await scanner.scan() } } label: {
                Text(L(fr: "Analyser", en: "Scan")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(Theme.green).controlSize(.large).padding(.top, 4)
        }
        .padding(.bottom, 6)
    }

    private func busy(_ label: String) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(height: 200)
    }

    private var results: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(CleanerView.bytes(scanner.totalSelected))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.green).contentTransition(.numericText())
                Text(L(fr: "récupérables", en: "reclaimable")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(scanner.categories) { cat in
                    categoryRow(cat)
                    if cat.id != scanner.categories.last?.id {
                        Divider().opacity(0.12).padding(.horizontal, 12)
                    }
                }
            }
            .padding(.vertical, 4).glassCard(radius: 16)

            HStack(spacing: 10) {
                Button { scanner.reset() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.glass)
                Button {
                    if confirming { confirming = false; Task { await scanner.clean() } }
                    else { withAnimation(.smooth) { confirming = true } }
                } label: {
                    Text(confirming ? L(fr: "Confirmer la suppression", en: "Confirm deletion")
                         : L(fr: "Nettoyer \(CleanerView.bytes(scanner.totalSelected))",
                             en: "Clean \(CleanerView.bytes(scanner.totalSelected))"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).tint(confirming ? Theme.pink : Theme.green)
                .disabled(!scanner.hasSelection)
            }
        }
    }

    private func categoryRow(_ cat: CleanerCategory) -> some View {
        HStack(spacing: 11) {
            IconBadge(symbol: cat.symbol, tint: cat.tint, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(cat.name).font(.system(size: 12.5, weight: .semibold))
                Text(cat.detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(CleanerView.bytes(cat.size))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(cat.size > 0 ? .primary : .tertiary)
            Toggle("", isOn: Binding(get: { cat.selected }, set: { _ in scanner.toggle(cat.id) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.mini).tint(cat.tint)
                .disabled(cat.size == 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var done: some View {
        VStack(spacing: 12) {
            IconBadge(symbol: "checkmark", tint: Theme.green, size: 60).padding(.top, 8)
            Text(scanner.lastFreed > 0 ? L(fr: "\(CleanerView.bytes(scanner.lastFreed)) libérés",
                                           en: "\(CleanerView.bytes(scanner.lastFreed)) freed")
                 : L(fr: "Déjà propre", en: "Already clean"))
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(L(fr: "Ton Mac respire mieux ✨", en: "Your Mac breathes easier ✨")).font(.system(size: 11)).foregroundStyle(.secondary)
            Button { scanner.reset() } label: { Text(L(fr: "Terminé", en: "Done")).frame(maxWidth: .infinity) }
                .buttonStyle(.glassProminent).tint(Theme.green).controlSize(.large).padding(.top, 4)
        }
        .padding(.bottom, 6)
    }
}

// MARK: - Mémoire (live monitor)

private struct MemoryTab: View {
    @Bindable private var mem = MemoryMonitor.shared

    private var pressureColor: Color {
        switch mem.pressure {
        case .normal: return Theme.green
        case .warning: return Theme.amber
        case .critical: return Theme.pink
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            gauge
            breakdown
            if mem.purgeAvailable { purgeButton }
            Label(L(fr: "Chiffres réels du noyau · la purge est temporaire",
                    en: "Real kernel figures · purge is temporary"),
                  systemImage: "info.circle")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
        }
        .onAppear { if !PreviewConfig.isPreview { mem.start() } }
        .onDisappear { mem.stop() }
    }

    private var gauge: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: mem.sample.usedFraction)
                    .stroke(pressureColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: mem.sample.usedFraction)
                VStack(spacing: 1) {
                    Text("\(Int(mem.sample.usedFraction * 100))%")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(L(fr: "utilisée", en: "used")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 128, height: 128)

            Text(L(fr: "Pression \(mem.pressure.label.lowercased())",
                   en: "\(mem.pressure.label) pressure"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(pressureColor)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(pressureColor.opacity(0.18)))
        }
        .padding(.top, 6)
    }

    private var breakdown: some View {
        VStack(spacing: 0) {
            row(L(fr: "App", en: "App"), mem.sample.app, Theme.indigo)
            Divider().opacity(0.12).padding(.horizontal, 12)
            row(L(fr: "Câblée", en: "Wired"), mem.sample.wired, Theme.violet)
            Divider().opacity(0.12).padding(.horizontal, 12)
            row(L(fr: "Compressée", en: "Compressed"), mem.sample.compressed, Theme.amber)
            Divider().opacity(0.12).padding(.horizontal, 12)
            row(L(fr: "Libre", en: "Free"), mem.sample.free, Theme.green)
        }
        .padding(.vertical, 4).glassCard(radius: 16)
    }

    private func row(_ name: String, _ value: UInt64, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(name).font(.system(size: 12.5, weight: .medium))
            Spacer()
            Text(CleanerView.bytes(value))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private var purgeButton: some View {
        Button { Task { await mem.purge() } } label: {
            HStack {
                if mem.isPurging { ProgressView().controlSize(.small) }
                Text(mem.isPurging ? L(fr: "Libération…", en: "Freeing…")
                     : mem.lastFreed > 0 ? L(fr: "\(CleanerView.bytes(mem.lastFreed)) libérés — relancer",
                                             en: "\(CleanerView.bytes(mem.lastFreed)) freed — run again")
                     : L(fr: "Libérer la mémoire inactive", en: "Free inactive memory"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent).tint(Theme.teal).controlSize(.large).disabled(mem.isPurging)
    }
}

// MARK: - Sécurité (startup / adware audit)

private struct SecurityTab: View {
    @Bindable private var auditor = SecurityAuditor.shared

    var body: some View {
        VStack(spacing: 14) {
            switch auditor.phase {
            case .idle:     idle
            case .scanning: busy
            case .done:     results
            }
        }
        .animation(.smooth(duration: 0.3), value: auditor.phase)
    }

    private var idle: some View {
        VStack(spacing: 14) {
            IconBadge(symbol: "checkmark.shield.fill", tint: Theme.indigo, size: 64).padding(.top, 8)
            Text(L(fr: "Audit de sécurité", en: "Security audit")).font(.system(size: 17, weight: .bold))
            Text(L(fr: "Inspecte les agents de démarrage et démons : signature du code et adwares connus. Aucune modification sans ton accord.",
                   en: "Inspects launch agents and daemons: code signature and known adware. Nothing is changed without your consent."))
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { Task { await auditor.scan() } } label: {
                Text(L(fr: "Analyser", en: "Scan")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(Theme.indigo).controlSize(.large).padding(.top, 4)
        }
        .padding(.bottom, 6)
    }

    private var busy: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(L(fr: "Inspection des éléments de démarrage…", en: "Inspecting startup items…"))
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(height: 200)
    }

    private var results: some View {
        VStack(spacing: 12) {
            summary
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(auditor.findings) { f in FindingRow(finding: f) }
                }
            }
            .frame(maxHeight: 300).scrollIndicators(.hidden)
            Button { auditor.reset() } label: {
                Label(L(fr: "Nouvelle analyse", en: "New scan"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass).controlSize(.large)
        }
    }

    private var summary: some View {
        let flagged = auditor.flaggedCount
        return VStack(spacing: 2) {
            Text(L(fr: "\(auditor.findings.count) éléments", en: "\(auditor.findings.count) items"))
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(flagged == 0 ? L(fr: "Aucun élément suspect ✓", en: "Nothing suspicious ✓")
                 : L(fr: "\(flagged) à examiner\(auditor.adwareCount > 0 ? " · \(auditor.adwareCount) adware" : "")",
                     en: "\(flagged) to review\(auditor.adwareCount > 0 ? " · \(auditor.adwareCount) adware" : "")"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(flagged == 0 ? Theme.green : (auditor.adwareCount > 0 ? Theme.pink : Theme.amber))
        }
    }
}

private struct FindingRow: View {
    let finding: SecurityAuditor.Finding
    @State private var confirming = false

    /// The `scope` is a stored French string set off the main actor during the
    /// scan, so it's localized here at display time rather than at its source.
    private func localizedScope(_ scope: String) -> String {
        switch scope {
        case "Agent utilisateur": return L(fr: "Agent utilisateur", en: "User agent")
        case "Agent système":     return L(fr: "Agent système", en: "System agent")
        case "Démon système":     return L(fr: "Démon système", en: "System daemon")
        default:                  return scope
        }
    }

    private var color: Color {
        switch finding.severity {
        case .ok: return Theme.green
        case .unsigned: return Theme.amber
        case .adware: return Theme.pink
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: finding.severity.symbol)
                .font(.system(size: 15)).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(finding.name).font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Text("\(localizedScope(finding.scope)) · \(finding.severity.label)")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                Button(L(fr: "Révéler dans le Finder", en: "Reveal in Finder")) { SecurityAuditor.shared.reveal(finding) }
                if finding.userWritable && finding.severity != .ok {
                    Button(L(fr: "Désactiver (quarantaine)", en: "Disable (quarantine)"), role: .destructive) {
                        Task { await SecurityAuditor.shared.quarantine(finding) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 15)).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(finding.severity == .ok ? .white.opacity(0.04) : color.opacity(0.1))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(finding.severity == .ok ? .white.opacity(0.06) : color.opacity(0.3), lineWidth: 0.5)
        }
    }
}
