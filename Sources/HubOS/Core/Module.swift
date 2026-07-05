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

/// Static metadata describing a module for the hub grid.
struct ModuleInfo: Identifiable {
    let id: ModuleID
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    /// Whether the feature is wired up yet. Un-implemented modules still show
    /// in the grid (as a teaser) but are marked "coming soon".
    let available: Bool
    /// Toggleable background services show a switch; on-demand actions (Cleaner)
    /// just open on tap.
    var hasToggle: Bool = true

    static let all: [ModuleInfo] = [
        ModuleInfo(
            id: .clipboard,
            title: "Clipboard",
            subtitle: "Historique du presse-papiers",
            symbol: "doc.on.clipboard.fill",
            tint: Theme.indigo,
            available: true
        ),
        ModuleInfo(
            id: .notch,
            title: "Dynamic Island",
            subtitle: "Île dynamique sur l'encoche",
            symbol: "rectangle.topthird.inset.filled",
            tint: Theme.pink,
            available: true
        ),
        ModuleInfo(
            id: .shelf,
            title: "Shelf",
            subtitle: "Étagère glisser-déposer",
            symbol: "tray.full.fill",
            tint: Theme.teal,
            available: true
        ),
        ModuleInfo(
            id: .brightness,
            title: "Brightness",
            subtitle: "Luminosité au-delà du max",
            symbol: "sun.max.fill",
            tint: Theme.amber,
            available: true
        ),
        ModuleInfo(
            id: .caffeine,
            title: "Caféine",
            subtitle: "Empêche la mise en veille",
            symbol: "cup.and.saucer.fill",
            tint: Theme.violet,
            available: true
        ),
        ModuleInfo(
            id: .focus,
            title: "Pomodoro",
            subtitle: "Minuteur de concentration",
            symbol: "brain.head.profile",
            tint: Theme.red,
            available: true,
            hasToggle: false
        ),
        ModuleInfo(
            id: .timer,
            title: "Minuteur",
            subtitle: "Compte à rebours & chrono",
            symbol: "timer",
            tint: Theme.amber,
            available: true,
            hasToggle: false
        ),
        ModuleInfo(
            id: .audio,
            title: "Audio",
            subtitle: "Sortie, entrée & volume",
            symbol: "hifispeaker.and.homepod.fill",
            tint: Theme.teal,
            available: true,
            hasToggle: false
        ),
        ModuleInfo(
            id: .battery,
            title: "Batterie",
            subtitle: "Santé, cycles & énergie",
            symbol: "battery.100.bolt",
            tint: Theme.blue,
            available: true,
            hasToggle: false
        ),
        ModuleInfo(
            id: .cleaner,
            title: "Cleaner",
            subtitle: "Nettoyage · mémoire · sécurité",
            symbol: "sparkles",
            tint: Theme.green,
            available: true,
            hasToggle: false
        )
    ]

    static func info(for id: ModuleID) -> ModuleInfo {
        all.first { $0.id == id }!
    }
}
