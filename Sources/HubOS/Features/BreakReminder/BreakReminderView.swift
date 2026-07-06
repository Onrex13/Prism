import SwiftUI

/// Detail panel for the Break Reminder active service: a master toggle, the
/// interval selector, and the next-reminder time.
struct BreakReminderView: View {
    @Bindable private var mgr = BreakReminderManager.shared
    @Environment(HubState.self) private var hub

    private var isOn: Bool { hub.isEnabled(.breakreminder) }

    var body: some View {
        VStack(spacing: 16) {
            hero
            masterToggle
            intervalCard
            footnote
        }
        .padding(18)
        .frame(width: Theme.panelWidth)
        .animation(.smooth(duration: 0.25), value: isOn)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            IconBadge(symbol: "figure.walk", tint: Theme.teal, size: 60).padding(.top, 6)
            Text(mgr.statusText).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn ? Theme.teal : .secondary)
        }
    }

    private var masterToggle: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L(fr: "Rappels de pause", en: "Break reminders"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L(fr: "Une pause régulière pour tes yeux et ton dos",
                       en: "A regular break for your eyes and back"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { hub.setEnabled(.breakreminder, $0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Theme.teal)
        }
        .padding(.horizontal, 14).padding(.vertical, 10).glassCard(radius: 14)
    }

    private var intervalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L(fr: "Intervalle", en: "Interval")).padding(.leading, 2)
            HStack(spacing: 6) {
                ForEach(BreakReminderManager.options, id: \.self) { m in
                    Button { mgr.intervalMinutes = m } label: {
                        Text(L(fr: "\(m) min", en: "\(m) min"))
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background {
                                Capsule().fill(mgr.intervalMinutes == m
                                    ? Theme.teal.opacity(0.28) : .white.opacity(0.05))
                            }
                            .overlay {
                                Capsule().strokeBorder(mgr.intervalMinutes == m
                                    ? Theme.teal.opacity(0.6) : .clear, lineWidth: 1)
                            }
                            .foregroundStyle(mgr.intervalMinutes == m ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var footnote: some View {
        if isOn, let next = mgr.nextReminder {
            Label {
                Text(L(fr: "Prochaine pause à \(next.formatted(date: .omitted, time: .shortened))",
                       en: "Next break at \(next.formatted(date: .omitted, time: .shortened))"))
            } icon: {
                Image(systemName: "clock")
            }
            .font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
        } else {
            Text(L(fr: "Active le service pour être rappelé régulièrement.",
                   en: "Turn the service on to be reminded regularly."))
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
        }
    }
}
