import SwiftUI
import Observation

/// Notch geometry for a given screen.
struct NotchMetrics {
    var hasNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat

    static let fallback = NotchMetrics(hasNotch: false, notchWidth: 210, notchHeight: 32)
}

extension NSScreen {
    var notchMetrics: NotchMetrics {
        let top = safeAreaInsets.top
        guard top > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else {
            return NotchMetrics(hasNotch: top > 0, notchWidth: 210, notchHeight: max(top, 32))
        }
        let width = max(150, right.minX - left.maxX)
        return NotchMetrics(hasNotch: true, notchWidth: width, notchHeight: top)
    }
}

/// A brief transient message that pops out of the notch (e.g. "Copié").
struct IslandFlash: Equatable {
    var symbol: String
    var text: String
    var tint: Color
}

/// Shared expansion state for the Dynamic Island window.
@MainActor
@Observable
final class NotchModel {
    /// Which activity the expanded island shows when several are live at once.
    enum IslandTab { case pomodoro, timer, media }

    var expanded = false
    var metrics: NotchMetrics = .fallback
    var islandTab: IslandTab = .pomodoro
    /// A transient toast shown briefly around the notch, overriding the lips.
    var flash: IslandFlash?
}

/// The Dynamic Island: a black surface that fuses with the physical notch. While
/// idle it shows a compact live-activity (artwork + waveform flanking the notch)
/// and on hover it fluidly grows *out of* the notch into a full media player.
struct NotchView: View {
    var model: NotchModel
    private var np: NowPlayingMonitor { NowPlayingMonitor.shared }
    private var settings: DynamicIslandSettings { DynamicIslandSettings.shared }
    private var focus: FocusManager { FocusManager.shared }
    private var caffeine: CaffeineManager { CaffeineManager.shared }
    private var countdown: TimerManager { TimerManager.shared }
    private var battery: BatteryMonitor { BatteryMonitor.shared }

    private var expanded: Bool { model.expanded }
    private var m: NotchMetrics { model.metrics }

    private var flashActive: Bool { model.flash != nil }
    private var focusActive: Bool { focus.isActive }
    private var timerActive: Bool { countdown.isActive }
    private var caffeineActive: Bool { caffeine.isActive }
    /// Battery earns a lip while charging or running low.
    private var batteryActive: Bool {
        let b = battery.info
        return b.hasBattery && (b.charging || (!b.pluggedIn && b.percent <= 20))
    }

    /// Expandable activities (each gets a full panel), in display priority.
    private var expandablePanels: [NotchModel.IslandTab] {
        var p: [NotchModel.IslandTab] = []
        if focusActive { p.append(.pomodoro) }
        if timerActive { p.append(.timer) }
        if np.hasMedia { p.append(.media) }
        return p
    }
    private var currentTab: NotchModel.IslandTab {
        expandablePanels.contains(model.islandTab) ? model.islandTab : (expandablePanels.first ?? .media)
    }

    /// Whether anything is filling the idle live-activity.
    private var hasActivity: Bool {
        flashActive || np.hasMedia || focusActive || timerActive || caffeineActive || batteryActive
    }

    // Idle lips flank the physical notch with content.
    private var leftLip: CGFloat {
        if flashActive { return 30 }
        if np.hasMedia && settings.idleArtwork { return 42 }
        if batteryActive { return 50 }
        if caffeineActive { return caffeine.remainingSeconds != nil ? 52 : 26 }
        return 5
    }
    private var rightLip: CGFloat {
        if let flash = model.flash { return min(150, CGFloat(flash.text.count) * 7 + 24) }
        if focusActive || timerActive { return 58 }
        return np.hasMedia && settings.idleWaveform ? 42 : 5
    }

    /// Expanded width adapts to the content: media needs room for long titles +
    /// a progress bar; a Pomodoro/timer panel is tighter.
    private var expandedWidth: CGFloat { m.notchWidth + (np.hasMedia ? 380 : 260) }
    private var expandedHeight: CGFloat {
        let base: CGFloat
        switch currentTab {
        case .media: base = (settings.showProgress ? 132 : 106) + 22   // + volume row
        case .pomodoro, .timer: base = 88
        }
        return m.notchHeight + base + (expandablePanels.count > 1 ? 24 : 0)
    }

    /// The idle lips are asymmetric (a Pomodoro fills the right, caffeine the
    /// left…), which would slide the notch cut-out off the physical notch and
    /// clip the content. Shift the whole collapsed panel to keep the cut-out
    /// centred on the real notch. (Expanded content is symmetric → no shift.)
    private var notchAlignOffset: CGFloat { expanded ? 0 : (rightLip - leftLip) / 2 }

    private var collapsedWidth: CGFloat { hasActivity ? m.notchWidth + leftLip + rightLip : m.notchWidth }
    private var collapsedHeight: CGFloat { m.notchHeight + (hasActivity ? 3 : 0) }

    private var panelWidth: CGFloat { expanded ? expandedWidth : collapsedWidth }
    private var panelHeight: CGFloat { expanded ? expandedHeight : collapsedHeight }
    private var radius: CGFloat { expanded ? 26 : (hasActivity ? m.notchHeight * 0.42 : 9) }

    var body: some View {
        VStack(spacing: 0) {
            panel
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // When the last expandable activity ends (e.g. you stop the Pomodoro from
        // the island), collapse instead of falling back to an empty media panel.
        .onChange(of: expandablePanels.isEmpty) { _, isEmpty in
            if isEmpty && model.expanded { NotchController.shared.forceCollapse() }
        }
    }

    private var panel: some View {
        ZStack(alignment: .top) {
            shape.fill(.black)

            // Ambient glow tinted by the artwork.
            if settings.ambientGlow, let accent = np.accentColor {
                shape
                    .fill(
                        RadialGradient(colors: [accent.opacity(expanded ? 0.40 : 0.20), .clear],
                                       center: .init(x: 0.22, y: 0.0),
                                       startRadius: 0, endRadius: expanded ? 320 : 90)
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }

            // Only lift/outline when EXPANDED. Collapsed stays pure black so it
            // fuses seamlessly with the physical (pure-black) notch — any white
            // sheen or hairline would make the island read as a separate shape.
            if expanded {
                shape
                    .fill(LinearGradient(colors: [.white.opacity(0.06), .clear],
                                         startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
                shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }

            idleContent
                .opacity(expanded ? 0 : 1)
                .allowsHitTesting(false)

            expandedContent
                .opacity(expanded ? 1 : 0)
                .blur(radius: expanded ? 0 : 8)
                .scaleEffect(expanded ? 1 : 0.92, anchor: .top)
                .allowsHitTesting(expanded)
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .top)
        .clipShape(shape)
        .offset(x: notchAlignOffset)
        .shadow(color: .black.opacity(expanded ? 0.55 : 0), radius: 22, y: 13)
        .animation(.spring(response: 0.5, dampingFraction: 0.68), value: expanded)
        .animation(.easeInOut(duration: 0.3), value: np.hasMedia)
        .animation(.easeInOut(duration: 0.3), value: focusActive)
        .animation(.easeInOut(duration: 0.3), value: timerActive)
        .animation(.easeInOut(duration: 0.3), value: caffeineActive)
        .animation(.easeInOut(duration: 0.3), value: batteryActive)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: flashActive)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: radius,
            bottomTrailingRadius: radius, topTrailingRadius: 0, style: .continuous
        )
    }

    // MARK: Idle live-activity

    private var idleContent: some View {
        HStack(spacing: 0) {
            Group {
                if let flash = model.flash {
                    Image(systemName: flash.symbol)
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(flash.tint)
                } else if np.hasMedia, settings.idleArtwork {
                    idleArtwork
                } else if batteryActive {
                    batteryLip
                } else if caffeineActive {
                    caffeineLip
                }
            }
            .frame(width: leftLip)

            Color.clear.frame(width: m.notchWidth)

            Group {
                if let flash = model.flash {
                    Text(flash.text)
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(1).truncationMode(.tail)
                        .padding(.trailing, 6)
                } else if focusActive {
                    focusLip
                } else if timerActive {
                    timerLip
                } else if np.hasMedia, settings.idleWaveform {
                    Waveform(tint: np.accentColor ?? Theme.pink, active: np.isPlaying)
                        .frame(width: 22, height: 13)
                }
            }
            .frame(width: rightLip)
        }
        .frame(height: collapsedHeight)
    }

    /// Compact countdown/stopwatch indicator.
    private var timerLip: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().stroke(.white.opacity(0.20), lineWidth: 2)
                if countdown.isCountdown {
                    Circle().trim(from: 0, to: countdown.progress)
                        .stroke(Theme.amber, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.9), value: countdown.progress)
                } else {
                    Image(systemName: "stopwatch").font(.system(size: 8)).foregroundStyle(Theme.amber)
                }
            }
            .frame(width: max(12, m.notchHeight - 16), height: max(12, m.notchHeight - 16))
            Text(countdown.timeString)
                .font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    /// Compact battery indicator: charging bolt (green) or low-battery (red).
    private var batteryLip: some View {
        let b = battery.info
        let charging = b.charging
        return HStack(spacing: 4) {
            Image(systemName: charging ? "bolt.fill" : "battery.25")
                .font(.system(size: 11)).foregroundStyle(charging ? Theme.green : Theme.red)
            Text("\(b.percent)%")
                .font(.system(size: 9, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    /// Compact keep-awake indicator: a cup, plus the remaining time if the
    /// caffeine session is timed.
    private var caffeineLip: some View {
        HStack(spacing: 4) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 11)).foregroundStyle(Theme.violet)
            if let s = caffeine.remainingSeconds {
                Text(s >= 60 ? "\(s / 60)m" : "\(s)s")
                    .font(.system(size: 9, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    /// Compact Pomodoro live-activity: a progress ring + remaining time.
    private var focusLip: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().stroke(.white.opacity(0.20), lineWidth: 2)
                Circle().trim(from: 0, to: focus.progress)
                    .stroke(focus.phase.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.9), value: focus.progress)
            }
            .frame(width: max(12, m.notchHeight - 16), height: max(12, m.notchHeight - 16))
            Text(focus.timeString)
                .font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white.opacity(focus.isRunning ? 1 : 0.55))
        }
    }

    private var idleArtwork: some View {
        Group {
            if let art = np.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Theme.pink, Theme.violet], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .frame(width: m.notchHeight - 10, height: m.notchHeight - 10)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: Expanded content — whichever activity is current

    @ViewBuilder
    private var expandedContent: some View {
        ZStack(alignment: .bottom) {
            currentPanel
            if expandablePanels.count > 1 { islandTabDots }
        }
    }

    /// The panel for the currently-selected activity. Empty when nothing is live
    /// (the island is collapsing) — never falls back to an empty media player.
    @ViewBuilder
    private var currentPanel: some View {
        if !expandablePanels.isEmpty {
            switch currentTab {
            case .pomodoro: focusExpanded
            case .timer:    timerExpanded
            case .media:    mediaExpanded
            }
        }
    }

    /// One pill per live expandable activity, to flip the expanded island.
    private var islandTabDots: some View {
        HStack(spacing: 7) {
            ForEach(expandablePanels, id: \.self) { tab in
                tabPill(tab, symbol(for: tab))
            }
        }
        .padding(.bottom, 8)
    }

    private func symbol(for tab: NotchModel.IslandTab) -> String {
        switch tab {
        case .pomodoro: return "brain.head.profile"
        case .timer:    return "timer"
        case .media:    return "music.note"
        }
    }

    private func tabPill(_ tab: NotchModel.IslandTab, _ symbol: String) -> some View {
        let selected = currentTab == tab
        return Button {
            withAnimation(.smooth(duration: 0.25)) { model.islandTab = tab }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(selected ? .white : .white.opacity(0.4))
                .frame(width: 26, height: 15)
                .background(Capsule().fill(.white.opacity(selected ? 0.24 : 0.08)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Expanded countdown/stopwatch

    private var timerExpanded: some View {
        VStack(spacing: 10) {
            Color.clear.frame(height: m.notchHeight - 6)
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 4)
                    if countdown.isCountdown {
                        Circle().trim(from: 0, to: countdown.progress)
                            .stroke(Theme.amber, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.9), value: countdown.progress)
                    }
                    Image(systemName: countdown.mode.symbol)
                        .font(.system(size: 16)).foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(countdown.timeString)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white).monospacedDigit()
                    Text(countdown.mode.title)
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    Text(countdown.isRunning ? L(fr: "En cours", en: "Running") : L(fr: "En pause", en: "Paused"))
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.amber)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    NotchControlButton(symbol: "stop.fill", size: 13) { countdown.reset() }
                    NotchControlButton(symbol: countdown.isRunning ? "pause.fill" : "play.fill", size: 17) { countdown.toggle() }
                    if countdown.isCountdown {
                        NotchControlButton(symbol: "plus", size: 13) { countdown.addMinutes(1) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Expanded Pomodoro

    private var focusExpanded: some View {
        VStack(spacing: 10) {
            Color.clear.frame(height: m.notchHeight - 6)
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 4)
                    Circle().trim(from: 0, to: focus.progress)
                        .stroke(focus.phase.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.9), value: focus.progress)
                    Image(systemName: focus.phase.symbol)
                        .font(.system(size: 17)).foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(focus.timeString)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white).monospacedDigit()
                    Text(focus.phase.title)
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    Text("Pomodoro · \(focus.dotsFilled)/\(focus.sessionsBeforeLong)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(focus.phase.tint.opacity(0.95))
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    NotchControlButton(symbol: "stop.fill", size: 13) { focus.reset() }
                    NotchControlButton(symbol: focus.isRunning ? "pause.fill" : "play.fill", size: 17) { focus.toggle() }
                    NotchControlButton(symbol: "forward.end.fill", size: 13) { focus.skip() }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Expanded player

    private var mediaExpanded: some View {
        VStack(spacing: 10) {
            Color.clear.frame(height: m.notchHeight - 6)
            HStack(spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Text(np.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white).lineLimit(1)
                    Text(np.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    Text(np.sourceName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle((np.accentColor ?? Theme.pink).opacity(0.95))
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    NotchControlButton(symbol: "backward.fill", size: 14) { np.previous() }
                    NotchControlButton(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 18) { np.togglePlayPause() }
                    NotchControlButton(symbol: "forward.fill", size: 14) { np.next() }
                }
            }
            if settings.showProgress { progressBar }
            volumeRow
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Seekable position bar + time labels — drag anywhere to scrub the track.
    private var progressBar: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(spacing: 3) {
                NotchScrubBar(value: np.progress, tint: .white.opacity(0.9)) { np.seek(toFraction: $0) }
                HStack {
                    Text(Self.time(np.elapsed))
                    Spacer()
                    Text(Self.time(np.duration))
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    /// Player volume — drag to set.
    private var volumeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
            NotchScrubBar(value: np.volume, tint: .white.opacity(0.55)) { np.volume = $0 }
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
        }
    }

    private var artwork: some View {
        Group {
            if let image = np.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Theme.pink, Theme.violet], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        }
        .shadow(color: (np.accentColor ?? .black).opacity(0.5), radius: 10, y: 3)
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Waveform

/// A lightweight animated audio waveform driven by a timeline.
struct Waveform: View {
    var tint: Color
    var active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(tint)
                        .frame(width: 3, height: height(i, t))
                }
            }
        }
    }

    private func height(_ i: Int, _ t: Double) -> CGFloat {
        guard active else { return 3 }
        let phase = t * 6.0 + Double(i) * 1.15
        return 4 + CGFloat(sin(phase) * 0.5 + 0.5) * 11
    }
}

// MARK: - Scrub bar

/// A thin, draggable bar (0…1) used for seeking and volume in the island. The
/// visual is slim but the hit area is taller so it's easy to grab.
private struct NotchScrubBar: View {
    var value: Double
    var tint: Color
    var onScrub: (Double) -> Void
    @State private var drag: Double?

    var body: some View {
        GeometryReader { geo in
            let shown = drag ?? value
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(tint)
                    .frame(width: max(2, geo.size.width * CGFloat(min(1, max(0, shown)))))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)              // centre the slim bar in the row
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in drag = frac(g.location.x, geo.size.width) }
                    .onEnded { g in onScrub(frac(g.location.x, geo.size.width)); drag = nil }
            )
        }
        .frame(height: 14)
    }

    private func frac(_ x: CGFloat, _ w: CGFloat) -> Double {
        w > 0 ? Double(min(1, max(0, x / w))) : 0
    }
}

// MARK: - Control button

/// A transport control with a soft hover highlight.
private struct NotchControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white.opacity(hover ? 1 : 0.85))
                .frame(width: 38, height: 38)
                .background(Circle().fill(.white.opacity(hover ? 0.15 : 0)))
                .contentShape(Circle())
                .scaleEffect(hover ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.smooth(duration: 0.15), value: hover)
    }
}
