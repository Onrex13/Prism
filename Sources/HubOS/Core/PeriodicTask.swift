import Foundation

/// A single-owner repeating timer for the main actor. Centralises the
/// `invalidate` → `scheduledTimer` → `MainActor.assumeIsolated` sequence that the
/// ticking managers (Focus, Timer, Caffeine) each re-implemented by hand, so a
/// task can never be double-scheduled and is always torn down on `stop()`.
@MainActor
final class PeriodicTask {
    private var timer: Timer?

    /// True while a tick is scheduled.
    var isRunning: Bool { timer != nil }

    /// (Re)starts ticking every `interval` seconds. Any timer already running is
    /// invalidated first, so this is safe to call repeatedly. Capture the owner
    /// weakly in `onTick` to avoid a retain cycle.
    func start(every interval: TimeInterval, onTick: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { onTick() }
        }
    }

    /// Stops ticking. No-op if nothing is scheduled.
    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
