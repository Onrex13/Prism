import AppKit
import ApplicationServices
import CoreServices
import Observation

/// Surfaces the macOS privacy permissions HubOS relies on, with live status
/// where the system lets us read it, plus deep-links to the right Settings pane.
@MainActor
@Observable
final class PermissionsManager {
    static let shared = PermissionsManager()

    struct Permission: Identifiable {
        let id: String
        let name: String
        let detail: String       // what it unlocks
        let symbol: String
        let checkable: Bool      // false = status can't be read, only opened
    }

    /// True once the user has granted Accessibility (auto-paste, quick-paste).
    private(set) var accessibilityGranted = false

    /// Computed (not stored) so the labels follow the live language.
    var permissions: [Permission] {
        [
            Permission(id: "accessibility",
                       name: L(fr: "Accessibilité", en: "Accessibility"),
                       detail: L(fr: "Collage automatique du presse-papiers (⌘V) et barre de collage rapide",
                                 en: "Clipboard auto-paste (⌘V) and the quick-paste bar"),
                       symbol: "accessibility", checkable: true),
            Permission(id: "automation",
                       name: L(fr: "Événements Apple (Automation)", en: "Apple Events (Automation)"),
                       detail: L(fr: "Contrôler Spotify / Musique. S'accorde à la 1ʳᵉ commande média depuis l'île (macOS le demande alors) — impossible à activer à l'avance.",
                                 en: "Control Spotify / Music. Granted on the first media command from the island (macOS asks then) — can't be pre-enabled."),
                       symbol: "apple.terminal", checkable: false)
        ]
    }

    private init() { refresh() }

    func refresh() {
        // Only Accessibility is safely readable. Automation can't be polled
        // (AEDeterminePermissionToAutomateTarget can block), so we don't.
        accessibilityGranted = AXIsProcessTrusted()
    }

    func status(for id: String) -> Bool? {
        id == "accessibility" ? accessibilityGranted : nil   // nil = informational row
    }

    /// Triggers the system Accessibility prompt (adds the app to the list).
    func requestAccessibility() {
        // Literal key avoids the non-Sendable global `kAXTrustedCheckOptionPrompt`.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openSettings(for id: String) {
        let anchor: String
        switch id {
        case "accessibility": anchor = "Privacy_Accessibility"
        case "automation":    anchor = "Privacy_Automation"
        default:              anchor = "Privacy"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
