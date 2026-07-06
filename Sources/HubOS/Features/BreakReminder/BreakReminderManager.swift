import AppKit
import SwiftUI
import Observation

/// A gentle "take a break" nudge on a fixed interval. When active it flashes the
/// Dynamic Island (and chimes) every N minutes to remind you to look away / move.
/// No permission required.
@MainActor
@Observable
final class BreakReminderManager {
    static let shared = BreakReminderManager()

    private let ticker = PeriodicTask()
    private let intervalKey = "hubos.break.interval"

    private(set) var isActive = false
    /// When the next reminder is due (for the detail view).
    private(set) var nextReminder: Date?

    /// Preset intervals in minutes.
    static let options = [20, 30, 45, 60, 90]

    private var storedInterval: Int
    /// Minutes between reminders.
    var intervalMinutes: Int {
        get { storedInterval }
        set {
            storedInterval = newValue.clamped(to: 10...240)
            UserDefaults.standard.set(storedInterval, forKey: intervalKey)
            if isActive { schedule() }      // apply the new cadence immediately
        }
    }

    private init() {
        storedInterval = (UserDefaults.standard.object(forKey: intervalKey) as? Int)
            .map { $0.clamped(to: 10...240) } ?? 30
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active { schedule() } else { ticker.stop(); nextReminder = nil }
    }

    private func schedule() {
        let seconds = Double(intervalMinutes * 60)
        nextReminder = Date().addingTimeInterval(seconds)
        ticker.start(every: seconds) { [weak self] in self?.fire() }
    }

    private func fire() {
        nextReminder = Date().addingTimeInterval(Double(intervalMinutes * 60))
        NSSound(named: "Ping")?.play()
        NotchController.shared.showFlash(
            symbol: "figure.walk",
            text: L(fr: "Pause · repose tes yeux 👀", en: "Break · rest your eyes 👀"),
            tint: Theme.teal, duration: 4)
    }

    var statusText: String {
        guard isActive else { return L(fr: "Désactivé", en: "Off") }
        return L(fr: "Toutes les \(intervalMinutes) min", en: "Every \(intervalMinutes) min")
    }
}
