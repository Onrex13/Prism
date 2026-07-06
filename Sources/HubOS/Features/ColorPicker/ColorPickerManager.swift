import AppKit
import SwiftUI
import Observation

/// Screen colour picker: opens the native macOS eyedropper (`NSColorSampler`),
/// keeps a persistent history of picked colours, and copies them as HEX or RGB.
/// No permission required.
@MainActor
@Observable
final class ColorPickerManager {
    static let shared = ColorPickerManager()

    /// A picked colour, stored as an uppercase `#RRGGBB` string.
    struct Swatch: Identifiable, Codable, Equatable {
        var id = UUID()
        var hex: String

        var rgb: String {
            let (r, g, b) = ColorPickerManager.rgb(hex)
            return "rgb(\(r), \(g), \(b))"
        }
        var color: Color {
            let (r, g, b) = ColorPickerManager.rgb(hex)
            return Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }
    }

    private(set) var history: [Swatch] = []
    private let key = "hubos.colorpicker.history"
    private let maxHistory = 30

    private init() { load() }

    var latest: Swatch? { history.first }

    // MARK: Picking

    /// Opens the system eyedropper. The picked colour is added to the history and
    /// its HEX copied to the clipboard automatically.
    func pick() {
        NSColorSampler().show { color in
            guard let color else { return }
            let hex = ColorPickerManager.hex(from: color)
            MainActor.assumeIsolated {
                ColorPickerManager.shared.ingest(hex)
            }
        }
    }

    private func ingest(_ hex: String) {
        history.removeAll { $0.hex == hex }          // dedupe, float to front
        history.insert(Swatch(hex: hex), at: 0)
        if history.count > maxHistory { history.removeLast(history.count - maxHistory) }
        save()
        if let latest { copy(latest) }               // auto-copy the fresh pick
    }

    /// Saves a colour composed in the built-in colour selector (wheel/sliders)
    /// to the history, exactly like a screen pick.
    func addComposed(_ color: Color) {
        ingest(Self.hex(from: NSColor(color)))
    }

    // MARK: Actions

    /// Copies a swatch to the clipboard as HEX (default) or `rgb(…)`.
    func copy(_ swatch: Swatch, asRGB: Bool = false) {
        let value = asRGB ? swatch.rgb : swatch.hex
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
        Notifier.shared.success(L(fr: "Copié · \(value)", en: "Copied · \(value)"))
    }

    func remove(_ swatch: Swatch) {
        history.removeAll { $0.id == swatch.id }
        save()
    }

    func clear() { history.removeAll(); save() }

    // MARK: Colour maths

    /// sRGB hex string for an `NSColor`, e.g. `#1E90FF`.
    nonisolated static func hex(from color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Parses `#RRGGBB` (or `RRGGBB`) into 0–255 components.
    nonisolated static func rgb(_ hex: String) -> (Int, Int, Int) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        return (Int((v >> 16) & 0xFF), Int((v >> 8) & 0xFF), Int(v & 0xFF))
    }

    // MARK: Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Swatch].self, from: data) else { return }
        history = decoded
    }

    // MARK: Preview

    func seedPreview() {
        history = ["#6B5CFA", "#1E90FF", "#22C55E", "#F59E0B", "#EC4899",
                   "#14B8A6", "#EF4444", "#8B5CF6", "#0EA5E9", "#84CC16"]
            .map { Swatch(hex: $0) }
    }
}
