import SwiftUI
import Observation

/// User-customizable behavior for the Dynamic Island, persisted to UserDefaults.
@MainActor
@Observable
final class DynamicIslandSettings {
    static let shared = DynamicIslandSettings()

    var idleArtwork = true { didSet { saveIfNeeded() } }
    var idleWaveform = true { didSet { saveIfNeeded() } }
    var showProgress = true { didSet { saveIfNeeded() } }
    var ambientGlow = true { didSet { saveIfNeeded() } }

    private var loading = false

    private init() {
        loading = true
        let d = UserDefaults.standard
        idleArtwork = d.object(forKey: "di.idleArtwork") as? Bool ?? true
        idleWaveform = d.object(forKey: "di.idleWaveform") as? Bool ?? true
        showProgress = d.object(forKey: "di.showProgress") as? Bool ?? true
        ambientGlow = d.object(forKey: "di.ambientGlow") as? Bool ?? true
        loading = false
    }

    private func saveIfNeeded() {
        guard !loading else { return }
        let d = UserDefaults.standard
        d.set(idleArtwork, forKey: "di.idleArtwork")
        d.set(idleWaveform, forKey: "di.idleWaveform")
        d.set(showProgress, forKey: "di.showProgress")
        d.set(ambientGlow, forKey: "di.ambientGlow")
    }
}
