import SwiftUI

/// In-hub battery & power monitor. Read-only telemetry; no system state changed.
struct BatteryView: View {
    @Bindable private var battery = BatteryMonitor.shared

    private var info: BatteryMonitor.Info { battery.info }

    /// Fill colour reflects charge/level like the system indicator.
    private var levelColor: Color {
        if info.charging || info.pluggedIn { return Theme.green }
        if info.percent <= 10 { return Theme.red }
        if info.percent <= 20 { return Theme.amber }
        return Theme.green
    }

    var body: some View {
        Group {
            if info.hasBattery {
                content
            } else {
                noBattery
            }
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
        .onAppear { if !PreviewConfig.isPreview { battery.start() } }
        .onDisappear { battery.stop() }
    }

    private var content: some View {
        VStack(spacing: 16) {
            hero
            statsGrid
            if let condition = info.condition {
                Label("État de la batterie : \(localizedCondition(condition))",
                      systemImage: "cross.case.fill")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Hero — big battery glyph

    private var hero: some View {
        VStack(spacing: 12) {
            batteryGlyph
            HStack(spacing: 6) {
                if info.charging {
                    Image(systemName: "bolt.fill").font(.system(size: 12)).foregroundStyle(Theme.green)
                }
                Text(info.stateText).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let mins = info.timeRemaining {
                    Text("· \(timeString(mins))").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var batteryGlyph: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.04)))
                    .frame(width: 132, height: 60)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(levelColor)
                    .frame(width: max(10, 124 * CGFloat(info.percent) / 100), height: 52)
                    .padding(.leading, 4)
                    .animation(.smooth, value: info.percent)
                HStack {
                    Spacer()
                    Text("\(info.percent)%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Spacer()
                }
                .frame(width: 132)
            }
            Capsule().fill(.white.opacity(0.25)).frame(width: 5, height: 22)
        }
    }

    // MARK: Stats

    private var statsGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            statCard("Santé", info.healthPercent.map { "\($0)%" } ?? "—", "heart.fill", Theme.green)
            statCard("Cycles", info.cycleCount.map(String.init) ?? "—", "arrow.triangle.2.circlepath", Theme.blue)
            statCard("Adaptateur", info.adapterWatts.map { "\($0) W" } ?? (info.pluggedIn ? "—" : "Débranché"),
                     "powerplug.fill", Theme.amber)
            statCard("Tension", info.voltage.map { String(format: "%.2f V", $0) } ?? "—",
                     "bolt.circle.fill", Theme.pink)
        }
    }

    private func statCard(_ title: String, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            IconBadge(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 15, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .glassCard(radius: 14)
    }

    // MARK: No battery (desktop)

    private var noBattery: some View {
        VStack(spacing: 12) {
            Image(systemName: "powerplug.fill")
                .font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text("Aucune batterie").font(.system(size: 15, weight: .semibold))
            Text("Ce Mac est alimenté en permanence sur secteur.")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 30).padding(.horizontal, 20)
    }

    // MARK: Helpers

    private func timeString(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h) h \(String(format: "%02d", m))" : "\(m) min"
    }

    private func localizedCondition(_ c: String) -> String {
        switch c { case "Good": return "Bon"; case "Fair": return "Correct"
        case "Poor": return "Faible"; default: return c }
    }
}
