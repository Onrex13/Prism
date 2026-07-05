import AppKit
import SwiftUI
import Observation

/// A Pomodoro focus timer. Runs independently of the hub popover (state + timer
/// live on this singleton), cycles focus → short break → … → long break, and
/// exposes its progress so the Dynamic Island can surface a live countdown.
@MainActor
@Observable
final class FocusManager {
    static let shared = FocusManager()

    enum Phase: String {
        case focus, shortBreak, longBreak
        var title: String {
            switch self { case .focus: "Concentration"; case .shortBreak: "Pause courte"; case .longBreak: "Pause longue" }
        }
        var short: String { self == .focus ? "Focus" : "Pause" }
        var symbol: String { self == .focus ? "brain.head.profile" : "cup.and.saucer.fill" }
        var tint: Color { self == .focus ? Theme.red : Theme.teal }
    }

    enum State { case idle, running, paused }

    private(set) var state: State = .idle
    private(set) var phase: Phase = .focus
    private(set) var remaining: Int = 25 * 60
    /// Completed focus sessions in the current set (resets after a long break).
    private(set) var completedFocus = 0
    /// Focus sessions finished all-time this launch (for the header count).
    private(set) var totalFocus = 0

    private let ticker = PeriodicTask()
    private let focusKey = "hubos.focus.minutes"
    private let shortKey = "hubos.focus.short"
    private let longKey = "hubos.focus.long"
    private let cyclesKey = "hubos.focus.cycles"

    // Persisted, editable settings (computed over backing to avoid the
    // `@Observable` + `didSet` self-reassignment recursion trap).

    private var storedFocusMinutes: Int
    /// Focus length in minutes. Editing while idle resets the clock.
    var focusMinutes: Int {
        get { storedFocusMinutes }
        set {
            let v = max(5, min(120, newValue))
            storedFocusMinutes = v
            UserDefaults.standard.set(v, forKey: focusKey)
            if state == .idle && phase == .focus { remaining = v * 60 }
        }
    }

    private var storedShort: Int
    var shortMinutes: Int {
        get { storedShort }
        set { storedShort = max(1, min(30, newValue)); UserDefaults.standard.set(storedShort, forKey: shortKey) }
    }

    private var storedLong: Int
    var longMinutes: Int {
        get { storedLong }
        set { storedLong = max(5, min(60, newValue)); UserDefaults.standard.set(storedLong, forKey: longKey) }
    }

    private var storedCycles: Int
    /// Focus sessions before a long break.
    var sessionsBeforeLong: Int {
        get { storedCycles }
        set { storedCycles = max(2, min(8, newValue)); UserDefaults.standard.set(storedCycles, forKey: cyclesKey) }
    }

    private init() {
        let d = UserDefaults.standard
        storedFocusMinutes = (d.object(forKey: focusKey) as? Int).map { max(5, min(120, $0)) } ?? 25
        storedShort = (d.object(forKey: shortKey) as? Int).map { max(1, min(30, $0)) } ?? 5
        storedLong = (d.object(forKey: longKey) as? Int).map { max(5, min(60, $0)) } ?? 15
        storedCycles = (d.object(forKey: cyclesKey) as? Int).map { max(2, min(8, $0)) } ?? 4
        remaining = storedFocusMinutes * 60
    }

    // MARK: Derived

    var isActive: Bool { state != .idle }
    var isRunning: Bool { state == .running }

    func phaseLength(_ p: Phase) -> Int {
        switch p {
        case .focus: return focusMinutes * 60
        case .shortBreak: return shortMinutes * 60
        case .longBreak: return longMinutes * 60
        }
    }

    var totalForPhase: Int { phaseLength(phase) }
    var progress: Double {
        let total = totalForPhase
        return total > 0 ? Double(total - remaining) / Double(total) : 0
    }
    var timeString: String { String(format: "%d:%02d", remaining / 60, remaining % 60) }
    /// Filled session dots toward the next long break.
    var dotsFilled: Int {
        let mod = completedFocus % sessionsBeforeLong
        return (mod == 0 && completedFocus > 0) ? sessionsBeforeLong : mod
    }

    // MARK: Controls

    /// Primary button: start when idle, pause when running, resume when paused.
    func toggle() {
        switch state {
        case .idle, .paused: run()
        case .running: pause()
        }
    }

    func run() {
        state = .running
        ticker.start(every: 1) { [weak self] in self?.tick() }
    }

    func pause() {
        state = .paused
        ticker.stop()
    }

    /// Full stop back to a fresh focus phase.
    func reset() {
        ticker.stop()
        state = .idle
        phase = .focus
        completedFocus = 0
        remaining = phaseLength(.focus)
    }

    /// Jump to the next phase immediately (counts an in-progress focus as done).
    func skip() { advance(userSkipped: true) }

    // MARK: Ticking

    private func tick() {
        guard remaining > 0 else { advance(userSkipped: false); return }
        remaining -= 1
        if remaining == 0 { advance(userSkipped: false) }
    }

    private func advance(userSkipped: Bool) {
        let wasFocus = (phase == .focus)
        if wasFocus {
            completedFocus += 1
            totalFocus += 1
        }
        // Decide the next phase.
        if wasFocus {
            phase = (completedFocus % sessionsBeforeLong == 0) ? .longBreak : .shortBreak
        } else {
            if phase == .longBreak { completedFocus = 0 }
            phase = .focus
        }
        remaining = phaseLength(phase)
        if !userSkipped { chime() }
        // Auto-continue the cycle unless it was a manual skip from idle.
        if state != .idle { run() }
    }

    private func chime() {
        NSSound(named: phase == .focus ? "Ping" : "Glass")?.play()
    }

    // MARK: Preview

    func seedPreview() {
        state = .running
        phase = .focus
        remaining = 18 * 60 + 24
        completedFocus = 2
        totalFocus = 2
    }
}
