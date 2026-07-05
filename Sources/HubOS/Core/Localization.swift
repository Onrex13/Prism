import Foundation
import Observation

/// In-app localization that avoids SwiftPM resource bundles. The `.app` packaging
/// script (`Scripts/build_app.sh`) copies only the binary, so `Bundle.module` /
/// `.strings` files wouldn't ship. Instead translations live at the call site via
/// `L(fr:en:)`, the language is switchable in Settings independently of the system
/// locale, and changes apply live: because views read `resolved` through this
/// `@Observable` singleton, switching language re-renders every string on screen.
@MainActor
@Observable
final class Localization {
    static let shared = Localization()

    /// User's language choice. `.system` follows the macOS preferred language.
    enum Language: String, CaseIterable, Identifiable {
        case system, francais, english
        var id: String { rawValue }
        @MainActor var label: String {
            switch self {
            case .system: return L(fr: "Automatique", en: "Automatic")
            case .francais: return "Français"
            case .english: return "English"
            }
        }
    }

    /// The concrete language after resolving `.system`.
    enum Resolved { case fr, en }

    private let key = "hubos.language"
    private(set) var language: Language

    private init() {
        language = UserDefaults.standard.string(forKey: key).flatMap(Language.init) ?? .system
    }

    func set(_ language: Language) {
        self.language = language
        UserDefaults.standard.set(language.rawValue, forKey: key)
    }

    var resolved: Resolved {
        switch language {
        case .francais: return .fr
        case .english: return .en
        case .system:
            let pref = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return pref.hasPrefix("fr") ? .fr : .en
        }
    }
}

/// The string for the currently active language. Call from the main actor (all
/// UI and feature managers here are `@MainActor`). Reading it inside a SwiftUI
/// `body` makes that view update automatically when the language changes.
@MainActor
func L(fr: String, en: String) -> String {
    Localization.shared.resolved == .fr ? fr : en
}
