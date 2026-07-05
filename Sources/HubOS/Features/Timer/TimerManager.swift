import AppKit
import SwiftUI
import Observation

/// A countdown timer + stopwatch. Like `FocusManager`, state and ticking live on
/// the singleton so it keeps running while the popover is closed, and it exposes
/// a live value the Dynamic Island can surface.
@MainActor
@Observable
final class TimerManager {
    static let shared = TimerManager()

    enum Mode: String, CaseIterable, Identifiable {
        case countdown, stopwatch
        var id: String { rawValue }
        var title: String { self == .countdown ? "Minuteur" : "Chrono" }
        var symbol: String { self == .countdown ? "timer" : "stopwatch" }
    }
    enum State { case idle, running, paused }

    private(set) var state: State = .idle
    private(set) var remaining = 0     // countdown, seconds
    private(set) var elapsed = 0       // stopwatch, seconds

    private var storedMode: Mode = .countdown
    var mode: Mode {
        get { storedMode }
        set { if state == .idle { storedMode = newValue } }
    }

    /// Selected countdown length in seconds (persisted).
    private var storedPreset: Int
    var presetSeconds: Int {
        get { storedPreset }
        set {
            storedPreset = max(10, newValue)
            UserDefaults.standard.set(storedPreset, forKey: presetKey)
            if state == .idle && mode == .countdown { remaining = storedPreset }
        }
    }

    private let ticker = PeriodicTask()
    private let presetKey = "hubos.timer.preset"

    private init() {
        storedPreset = UserDefaults.standard.object(forKey: presetKey) as? Int ?? 300
        remaining = storedPreset
    }

    // MARK: Derived

    var isActive: Bool { state != .idle }
    var isRunning: Bool { state == .running }
    var isCountdown: Bool { mode == .countdown }

    var value: Int { isCountdown ? remaining : elapsed }
    var progress: Double {
        guard isCountdown, presetSeconds > 0 else { return 0 }
        return Double(presetSeconds - remaining) / Double(presetSeconds)
    }
    var timeString: String { Self.format(value) }

    static func format(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    // MARK: Controls

    func toggle() {
        switch state {
        case .idle, .paused: run()
        case .running: pause()
        }
    }

    func run() {
        if state == .idle && isCountdown && remaining == 0 { remaining = presetSeconds }
        state = .running
        ticker.start(every: 1) { [weak self] in self?.tick() }
    }

    func pause() { state = .paused; ticker.stop() }

    func reset() {
        ticker.stop()
        state = .idle
        elapsed = 0
        remaining = presetSeconds
    }

    /// Adds minutes to a running/idle countdown (e.g. +1, +5).
    func addMinutes(_ m: Int) {
        guard isCountdown else { return }
        remaining = max(0, remaining + m * 60)
        if state == .idle { presetSeconds = remaining }
    }

    private func tick() {
        if isCountdown {
            guard remaining > 0 else { finish(); return }
            remaining -= 1
            if remaining == 0 { finish() }
        } else {
            elapsed += 1
        }
    }

    private func finish() {
        ticker.stop()
        state = .idle
        NSSound(named: "Submarine")?.play()
        remaining = presetSeconds
    }

    func seedPreview() {
        storedMode = .countdown
        state = .running
        storedPreset = 600
        remaining = 372
    }
}
