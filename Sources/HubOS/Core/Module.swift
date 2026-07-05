import SwiftUI

/// Identifies each HubOS feature module.
enum ModuleID: String, CaseIterable, Identifiable, Codable {
    case clipboard
    case notch
    case shelf
    case brightness
    case caffeine
    case focus
    case timer
    case audio
    case battery
    case cleaner

    var id: String { rawValue }
}

/// Static metadata describing a module for the hub grid. `title`/`subtitle` are
/// computed (not stored) so they follow the live language — see `Localization`.
struct ModuleInfo: Identifiable {
    let id: ModuleID
    let symbol: String
    let tint: Color
    /// Whether the feature is wired up yet. Un-implemented modules still show
    /// in the grid (as a teaser) but are marked "coming soon".
    let available: Bool
    /// Toggleable background services show a switch; on-demand actions (Cleaner)
    /// just open on tap.
    var hasToggle: Bool = true

    @MainActor var title: String {
        switch id {
        case .clipboard: return "Clipboard"
        case .notch: return "Dynamic Island"
        case .shelf: return "Shelf"
        case .brightness: return "Brightness"
        case .caffeine: return L(fr: "Caféine", en: "Caffeine")
        case .focus: return "Pomodoro"
        case .timer: return L(fr: "Minuteur", en: "Timer")
        case .audio: return "Audio"
        case .battery: return L(fr: "Batterie", en: "Battery")
        case .cleaner: return "Cleaner"
        }
    }

    @MainActor var subtitle: String {
        switch id {
        case .clipboard: return L(fr: "Historique du presse-papiers", en: "Clipboard history")
        case .notch: return L(fr: "Île dynamique sur l'encoche", en: "Dynamic Island on the notch")
        case .shelf: return L(fr: "Étagère glisser-déposer", en: "Drag-and-drop shelf")
        case .brightness: return L(fr: "Luminosité au-delà du max", en: "Brightness beyond max")
        case .caffeine: return L(fr: "Empêche la mise en veille", en: "Keeps the Mac awake")
        case .focus: return L(fr: "Minuteur de concentration", en: "Focus timer")
        case .timer: return L(fr: "Compte à rebours & chrono", en: "Countdown & stopwatch")
        case .audio: return L(fr: "Sortie, entrée & volume", en: "Output, input & volume")
        case .battery: return L(fr: "Santé, cycles & énergie", en: "Health, cycles & power")
        case .cleaner: return L(fr: "Nettoyage · mémoire · sécurité", en: "Cleanup · memory · security")
        }
    }

    static let all: [ModuleInfo] = [
        ModuleInfo(id: .clipboard, symbol: "doc.on.clipboard.fill", tint: Theme.indigo, available: true),
        ModuleInfo(id: .notch, symbol: "rectangle.topthird.inset.filled", tint: Theme.pink, available: true),
        ModuleInfo(id: .shelf, symbol: "tray.full.fill", tint: Theme.teal, available: true),
        ModuleInfo(id: .brightness, symbol: "sun.max.fill", tint: Theme.amber, available: true),
        ModuleInfo(id: .caffeine, symbol: "cup.and.saucer.fill", tint: Theme.violet, available: true),
        ModuleInfo(id: .focus, symbol: "brain.head.profile", tint: Theme.red, available: true, hasToggle: false),
        ModuleInfo(id: .timer, symbol: "timer", tint: Theme.amber, available: true, hasToggle: false),
        ModuleInfo(id: .audio, symbol: "hifispeaker.and.homepod.fill", tint: Theme.teal, available: true, hasToggle: false),
        ModuleInfo(id: .battery, symbol: "battery.100.bolt", tint: Theme.blue, available: true, hasToggle: false),
        ModuleInfo(id: .cleaner, symbol: "sparkles", tint: Theme.green, available: true, hasToggle: false)
    ]

    static func info(for id: ModuleID) -> ModuleInfo {
        all.first { $0.id == id }!
    }
}
