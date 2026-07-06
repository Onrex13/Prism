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
            if !s.bluetooth.isEmpty { bluetoothCard }
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

    private var bluetoothCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(s.bluetooth.enumerated()), id: \.element.id) { idx, dev in
                HStack(spacing: 10) {
                    Image(systemName: dev.symbol).font(.system(size: 13)).foregroundStyle(Theme.blue).frame(width: 20)
                    Text(dev.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    Spacer()
                    Image(systemName: batterySymbol(dev.percent))
                        .font(.system(size: 12)).foregroundStyle(dev.percent <= 20 ? Theme.pink : Theme.green)
                    Text("\(dev.percent)%").font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                if idx != s.bluetooth.count - 1 { Divider().opacity(0.12).padding(.horizontal, 12) }
            }
        }
        .padding(.vertical, 4).glassCard(radius: 16)
    }

    private func batterySymbol(_ pct: Int) -> String {
        switch pct {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
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
