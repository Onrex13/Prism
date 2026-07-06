import SwiftUI

/// Live system load: CPU and RAM gauges, load average and uptime. Polls only
/// while visible.
struct SensorsView: View {
    @Bindable private var s = SensorsMonitor.shared

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                gauge(L(fr: "Processeur", en: "CPU"), s.cpu, Theme.pink)
                gauge(L(fr: "Mémoire", en: "Memory"), s.ramFraction, Theme.teal)
            }
            infoCard
            Label(L(fr: "Lecture noyau en direct · aucune connexion",
                    en: "Live kernel read · no network calls"),
                  systemImage: "info.circle")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
        .onAppear { if !PreviewConfig.isPreview { s.start() } }
        .onDisappear { s.stop() }
    }

    private func gauge(_ label: String, _ value: Double, _ tint: Color) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: max(0, min(1, value)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: value)
                Text("\(Int(value * 100))%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
            .frame(width: 92, height: 92)
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).glassCard(radius: 18)
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            row(L(fr: "RAM utilisée", en: "RAM used"),
                "\(CleanerView.bytes(s.ramUsed)) / \(CleanerView.bytes(s.ramTotal))", "memorychip")
            Divider().opacity(0.12).padding(.horizontal, 12)
            row(L(fr: "Charge (1 · 5 · 15 min)", en: "Load (1 · 5 · 15 min)"),
                String(format: "%.2f · %.2f · %.2f", s.load.0, s.load.1, s.load.2), "gauge.medium")
            Divider().opacity(0.12).padding(.horizontal, 12)
            row(L(fr: "Démarré depuis", en: "Uptime"),
                SensorsMonitor.uptimeString(s.uptime), "clock")
        }
        .padding(.vertical, 4).glassCard(radius: 16)
    }

    private func row(_ name: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
            Text(name).font(.system(size: 12.5, weight: .medium))
            Spacer()
            Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
}
