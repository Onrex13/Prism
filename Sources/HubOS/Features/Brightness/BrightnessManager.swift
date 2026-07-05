import AppKit
import Observation

/// Drives the EDR brightness boost across all capable displays. Fully reversible:
/// disabling closes the overlay windows and the display returns to normal
/// instantly — no global gamma or ColorSync state is ever touched.
@MainActor
@Observable
final class BrightnessManager {
    static let shared = BrightnessManager()

    private(set) var isActive = false

    private var storedIntensity: Double = 0.6

    /// Boost amount, 0…1. 0 = no boost, 1 = the display's full EDR headroom.
    /// Computed over a private backing so clamping in the setter can't re-enter
    /// itself (an `@Observable` `didSet` that reassigns would recurse forever).
    var intensity: Double {
        get { storedIntensity }
        set {
            let clamped = newValue.clamped(to: 0...1)
            storedIntensity = clamped
            UserDefaults.standard.set(clamped, forKey: intensityKey)
            if isActive { applyValue() }
        }
    }

    private var windows: [CGDirectDisplayID: BrightnessOverlayWindow] = [:]
    private var observer: NSObjectProtocol?
    private let intensityKey = "hubos.brightness.intensity"

    private init() {
        let stored = UserDefaults.standard.object(forKey: intensityKey) as? Double
        intensity = stored.map { $0.clamped(to: 0...1) } ?? 0.6
    }

    // MARK: Capability

    /// True if at least one attached display supports EDR.
    var isSupported: Bool {
        NSScreen.screens.contains { $0.supportsEDR }
    }

    /// The largest multiply factor the hardware allows, capped for safety.
    var maxFactor: Double {
        let potential = NSScreen.screens
            .map { Double($0.maximumPotentialExtendedDynamicRangeColorComponentValue) }
            .max() ?? 1.0
        return min(max(potential, 1.0), 1.6)
    }

    /// Current multiply value applied to the screen (1.0 = untouched).
    var currentFactor: Double {
        1.0 + intensity * (maxFactor - 1.0)
    }

    /// Approximate brightness gain as a percentage, for display in the UI.
    var boostPercent: Int {
        Int(((currentFactor) - 1.0) * 100)
    }

    // MARK: Activation

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            showOverlays()
            startObservingScreens()
        } else {
            hideOverlays()
            stopObservingScreens()
        }
    }

    private func showOverlays() {
        for screen in NSScreen.screens where screen.supportsEDR {
            guard let id = screen.displayId, windows[id] == nil else { continue }
            let window = BrightnessOverlayWindow(screen: screen, value: currentFactor)
            window.orderFrontRegardless()
            windows[id] = window
        }
    }

    private func hideOverlays() {
        windows.values.forEach { $0.close() }
        windows.removeAll()
    }

    private func applyValue() {
        for window in windows.values {
            window.overlayView?.setValue(currentFactor)
        }
    }

    // MARK: Screen changes

    private func startObservingScreens() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildOverlays() }
        }
    }

    private func stopObservingScreens() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    /// Rebuilds overlays after displays are added/removed or rearranged.
    private func rebuildOverlays() {
        guard isActive else { return }
        let activeIds = Set(NSScreen.screens.compactMap { $0.displayId })
        for (id, window) in windows where !activeIds.contains(id) {
            window.close()
            windows.removeValue(forKey: id)
        }
        for screen in NSScreen.screens where screen.supportsEDR {
            guard let id = screen.displayId else { continue }
            if let window = windows[id] {
                window.setFrame(screen.frame, display: true)
                window.overlayView?.setValue(currentFactor)
            } else {
                let window = BrightnessOverlayWindow(screen: screen, value: currentFactor)
                window.orderFrontRegardless()
                windows[id] = window
            }
        }
    }
}
