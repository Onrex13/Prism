import AppKit
import IOKit.pwr_mgt
import Observation

/// Keeps the Mac (and optionally the display) awake using an IOKit power
/// assertion — the same mechanism `caffeinate(8)` and Amphetamine use. Fully
/// reversible: releasing the assertion instantly restores normal sleep
/// behaviour, and no system energy setting is ever modified. Requires no
/// special permission.
@MainActor
@Observable
final class CaffeineManager {
    static let shared = CaffeineManager()

    /// What to hold awake.
    enum Mode: String, CaseIterable, Identifiable {
        /// Keep the display on (implies the system stays awake too).
        case display
        /// Let the display sleep but keep the Mac running (downloads, renders…).
        case system

        var id: String { rawValue }
        var title: String { self == .display ? "Écran allumé" : "Système seul" }
        var detail: String {
            self == .display ? "L'écran ne s'éteint jamais" : "L'écran peut s'éteindre"
        }
        var symbol: String { self == .display ? "sun.max.fill" : "cpu.fill" }
        var assertionType: String {
            self == .display
                ? kIOPMAssertionTypePreventUserIdleDisplaySleep
                : kIOPMAssertionTypePreventUserIdleSystemSleep
        }
    }

    /// Timed-session presets, in minutes. `nil` = indefinite.
    static let durationOptions: [Int?] = [nil, 15, 30, 60, 120]

    private(set) var isActive = false
    /// Seconds left in the current timed session, or `nil` when indefinite.
    private(set) var remainingSeconds: Int?

    private var assertionID: IOPMAssertionID = 0
    private var countdown: Timer?

    private let modeKey = "hubos.caffeine.mode"
    private let durationKey = "hubos.caffeine.duration"

    // MARK: Persisted preferences (computed over backing to sidestep the
    // `@Observable` + `didSet` self-reassignment recursion trap).

    private var storedMode: Mode
    var mode: Mode {
        get { storedMode }
        set {
            storedMode = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
            if isActive { reassert() }
        }
    }

    private var storedDuration: Int?
    /// Selected session length in minutes; `nil` = indefinite.
    var duration: Int? {
        get { storedDuration }
        set {
            storedDuration = newValue
            UserDefaults.standard.set(newValue ?? 0, forKey: durationKey)
            if isActive { startCountdown() }
        }
    }

    private init() {
        let rawMode = UserDefaults.standard.string(forKey: modeKey)
        storedMode = rawMode.flatMap(Mode.init) ?? .display
        let storedMin = UserDefaults.standard.object(forKey: durationKey) as? Int ?? 0
        storedDuration = storedMin > 0 ? storedMin : nil
    }

    // MARK: Activation

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            assert()
            startCountdown()
        } else {
            release()
            countdown?.invalidate(); countdown = nil
            remainingSeconds = nil
        }
    }

    /// A friendly one-line status for the module tile / detail hero.
    var statusText: String {
        guard isActive else { return "Désactivé" }
        guard let remainingSeconds else { return "Actif · indéfini" }
        let m = remainingSeconds / 60, s = remainingSeconds % 60
        return m > 0 ? "\(m) min \(String(format: "%02d", s)) s" : "\(s) s"
    }

    // MARK: Power assertion

    private func assert() {
        release()
        var id: IOPMAssertionID = 0
        let reason = "Prism — Caféine" as CFString
        let result = IOPMAssertionCreateWithName(
            mode.assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &id
        )
        if result == kIOReturnSuccess { assertionID = id }
    }

    private func release() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }

    /// Swap the live assertion to a new type when the mode changes mid-session.
    private func reassert() { assert() }

    // MARK: Timed session

    private func startCountdown() {
        countdown?.invalidate(); countdown = nil
        guard let minutes = duration, minutes > 0 else {
            remainingSeconds = nil
            return
        }
        remainingSeconds = minutes * 60
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let left = self.remainingSeconds else { return }
                if left <= 1 {
                    // Session elapsed — flip the module off so the tile switch
                    // and persisted state stay in sync (setActive is idempotent).
                    HubState.shared.setEnabled(.caffeine, false)
                } else {
                    self.remainingSeconds = left - 1
                }
            }
        }
    }
}
