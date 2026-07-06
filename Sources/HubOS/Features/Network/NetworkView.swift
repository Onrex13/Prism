import SwiftUI

/// Live network throughput: download/upload rate plus the active interface and
/// local IP. Polls only while visible.
struct NetworkView: View {
    @Bindable private var net = NetworkMonitor.shared

    var body: some View {
        VStack(spacing: 16) {
            rates
            infoCard
            Label(L(fr: "Débit temps réel · lecture noyau, aucune connexion",
                    en: "Live throughput · kernel read, no network calls"),
                  systemImage: "info.circle")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
        .onAppear { if !PreviewConfig.isPreview { net.start() } }
        .onDisappear { net.stop() }
    }

    private var rates: some View {
        HStack(spacing: 12) {
            rateBlock(symbol: "arrow.down", tint: Theme.blue,
                      label: L(fr: "Réception", en: "Download"), value: net.downBytesPerSec)
            rateBlock(symbol: "arrow.up", tint: Theme.green,
                      label: L(fr: "Envoi", en: "Upload"), value: net.upBytesPerSec)
        }
    }

    private func rateBlock(symbol: String, tint: Color, label: String, value: UInt64) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(tint)
            Text(NetworkMonitor.rate(value))
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16).glassCard(radius: 18)
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            row(L(fr: "Interface", en: "Interface"), net.interfaceName, "wifi")
            Divider().opacity(0.12).padding(.horizontal, 12)
            row(L(fr: "IP locale", en: "Local IP"), net.localIP, "network")
        }
        .padding(.vertical, 4).glassCard(radius: 16)
    }

    private func row(_ name: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
            Text(name).font(.system(size: 12.5, weight: .medium))
            Spacer()
            Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
}
