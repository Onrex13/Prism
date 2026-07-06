import SwiftUI
import Observation

/// Central observable store for HubOS. Holds which modules are enabled and
/// which detail view (if any) is currently open in the hub panel.
@MainActor
@Observable
final class HubState {
    static let shared = HubState()

    /// Enabled state per module, persisted to `UserDefaults`.
    private(set) var enabled: [ModuleID: Bool]

    /// The module whose detail panel is currently displayed, or `nil` for the
    /// grid overview.
    var openModule: ModuleID?

    /// Whether the app settings panel (permissions, updates) is showing.
    var showingSettings = false

    private let defaultsKey = "hubos.enabledModules"

    private init() {
        let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Bool] ?? [:]
        var map: [ModuleID: Bool] = [:]
        for module in ModuleID.allCases {
            // Only the clipboard ships enabled by default in this build.
            let fallback = module == .clipboard
            map[module] = stored[module.rawValue] ?? fallback
        }
        enabled = map
    }

    func isEnabled(_ id: ModuleID) -> Bool { enabled[id] ?? false }

    func setEnabled(_ id: ModuleID, _ value: Bool) {
        enabled[id] = value
        persist()
        applySideEffects(for: id, enabled: value)
    }

    /// Starts or stops the background service backing a module when toggled.
    func applySideEffects(for id: ModuleID, enabled: Bool) {
        switch id {
        case .clipboard:
            if enabled {
                ClipboardStore.shared.start()
                QuickPasteManager.shared.enable()
            } else {
                ClipboardStore.shared.stop()
                QuickPasteManager.shared.disable()
            }
        case .brightness:
            BrightnessManager.shared.setActive(enabled)
        case .notch:
            enabled ? NotchController.shared.enable() : NotchController.shared.disable()
        case .shelf:
            enabled ? ShelfController.shared.enable() : ShelfController.shared.disable()
        case .caffeine:
            CaffeineManager.shared.setActive(enabled)
        case .breakreminder:
            BreakReminderManager.shared.setActive(enabled)
        case .desktop:
            DesktopManager.shared.setHidden(enabled)
        default:
            break
        }
    }

    /// Boots every enabled module's background service at launch.
    func startEnabledServices() {
        for id in ModuleID.allCases where isEnabled(id) {
            applySideEffects(for: id, enabled: true)
        }
    }

    func toggle(_ id: ModuleID) {
        setEnabled(id, !isEnabled(id))
    }

    private func persist() {
        let raw = Dictionary(uniqueKeysWithValues: enabled.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(raw, forKey: defaultsKey)
    }
}
