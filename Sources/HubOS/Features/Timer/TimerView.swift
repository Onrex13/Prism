import SwiftUI

/// In-hub countdown timer + stopwatch.
struct TimerView: View {
    @Bindable private var timer = TimerManager.shared

    private let presets = [60, 300, 600, 900, 1500] // 1, 5, 10, 15, 25 min

    var body: some View {
        VStack(spacing: 16) {
            modeSwitch
            ring
            controls
            if timer.isCountdown {
                if timer.isActive { quickAdd } else { presetPicker }
            }
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
        .animation(.smooth(duration: 0.3), value: timer.state)
        .animation(.smooth(duration: 0.25), value: timer.mode)
    }

    // MARK: Mode

    private var modeSwitch: some View {
        HStack(spacing: 8) {
            ForEach(TimerManager.Mode.allCases) { m in
                Button { timer.mode = m } label: {
                    Label(m.title, systemImage: m.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background {
                            Capsule().fill(timer.mode == m ? Theme.amber.opacity(0.25) : .white.opacity(0.05))
                        }
                        .overlay {
                            Capsule().strokeBorder(timer.mode == m ? Theme.amber.opacity(0.6) : .clear, lineWidth: 1)
                        }
                        .foregroundStyle(timer.mode == m ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .disabled(timer.isActive)
                .opacity(timer.isActive && timer.mode != m ? 0.4 : 1)
            }
        }
    }

    // MARK: Ring

    private var ring: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: 14)
            if timer.isCountdown {
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(Theme.amber, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.9), value: timer.progress)
            }
            VStack(spacing: 2) {
                Text(timer.timeString)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white).monospacedDigit()
                    .contentTransition(.numericText())
                Text(timer.isRunning ? timer.mode.title
                     : timer.state == .paused ? L(fr: "En pause", en: "Paused") : L(fr: "Prêt", en: "Ready"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 168, height: 168)
        .padding(.top, 2)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button { timer.reset() } label: { Image(systemName: "stop.fill") }
                .buttonStyle(.glass).controlSize(.large).disabled(!timer.isActive)
            Button { timer.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    Text(timer.state == .idle ? L(fr: "Démarrer", en: "Start") : timer.isRunning ? L(fr: "Pause", en: "Pause") : L(fr: "Reprendre", en: "Resume"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(Theme.amber).controlSize(.large)
        }
    }

    // MARK: Presets / quick add

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L(fr: "Durée", en: "Duration"))
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { p in
                    Button { timer.presetSeconds = p } label: {
                        Text(p >= 60 ? L(fr: "\(p / 60) min", en: "\(p / 60) min") : L(fr: "\(p) s", en: "\(p) s"))
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background {
                                Capsule().fill(timer.presetSeconds == p ? Theme.amber.opacity(0.9) : .white.opacity(0.06))
                            }
                            .foregroundStyle(timer.presetSeconds == p ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14).glassCard(radius: 16)
    }

    private var quickAdd: some View {
        HStack(spacing: 10) {
            ForEach([1, 5], id: \.self) { m in
                Button { timer.addMinutes(m) } label: {
                    Text(L(fr: "+\(m) min", en: "+\(m) min")).font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                }
                .buttonStyle(.glass)
            }
        }
    }
}
