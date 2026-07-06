import SwiftUI

/// In-hub Pomodoro focus timer.
struct FocusView: View {
    @Bindable private var focus = FocusManager.shared

    private var tint: Color { focus.phase.tint }

    var body: some View {
        VStack(spacing: 16) {
            ring
            sessionDots
            controls
            if !focus.isActive { focusSettings }
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
        .animation(.smooth(duration: 0.3), value: focus.phase)
        .animation(.smooth(duration: 0.3), value: focus.state)
    }

    // MARK: Ring

    private var ring: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: 14)
            Circle()
                .trim(from: 0, to: focus.progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.9), value: focus.progress)
            VStack(spacing: 3) {
                Label(focus.phase.short, systemImage: focus.phase.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(focus.timeString)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .monospacedDigit()
                Text(focus.isRunning ? focus.phase.title
                     : focus.state == .paused ? L(fr: "En pause", en: "Paused") : L(fr: "Prêt", en: "Ready"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 168, height: 168)
        .padding(.top, 4)
    }

    // MARK: Session dots

    private var sessionDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<focus.sessionsBeforeLong, id: \.self) { i in
                Circle()
                    .fill(i < focus.dotsFilled ? Theme.red : .white.opacity(0.15))
                    .frame(width: 8, height: 8)
            }
            Text(L(fr: "· \(focus.totalFocus) aujourd'hui", en: "· \(focus.totalFocus) today"))
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button { focus.reset() } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.glass).controlSize(.large).disabled(!focus.isActive)

            Button { focus.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: focus.isRunning ? "pause.fill" : "play.fill")
                    Text(focus.state == .idle ? L(fr: "Démarrer", en: "Start") : focus.isRunning ? L(fr: "Pause", en: "Pause") : L(fr: "Reprendre", en: "Resume"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(tint).controlSize(.large)

            Button { focus.skip() } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(.glass).controlSize(.large).disabled(!focus.isActive)
        }
    }

    // MARK: Duration

    private var focusSettings: some View {
        VStack(spacing: 12) {
            chipRow(L(fr: "Concentration", en: "Focus"), [15, 25, 45, 50], focus.focusMinutes, suffix: "min") { focus.focusMinutes = $0 }
            chipRow(L(fr: "Cycles avant pause longue", en: "Cycles before long break"), [2, 3, 4, 5, 6], focus.sessionsBeforeLong) { focus.sessionsBeforeLong = $0 }
            chipRow(L(fr: "Pause courte", en: "Short break"), [3, 5, 10], focus.shortMinutes, suffix: "min") { focus.shortMinutes = $0 }
            chipRow(L(fr: "Pause longue", en: "Long break"), [10, 15, 20, 30], focus.longMinutes, suffix: "min") { focus.longMinutes = $0 }
        }
        .padding(14).glassCard(radius: 16)
        .animation(.smooth(duration: 0.2), value: focus.sessionsBeforeLong)
    }

    private func chipRow(_ label: String, _ options: [Int], _ selected: Int,
                         suffix: String = "", action: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: label)
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { value in
                    Button { action(value) } label: {
                        Text(suffix.isEmpty ? "\(value)" : "\(value) \(suffix)")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background {
                                Capsule().fill(selected == value ? Theme.red.opacity(0.9) : .white.opacity(0.06))
                            }
                            .foregroundStyle(selected == value ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
