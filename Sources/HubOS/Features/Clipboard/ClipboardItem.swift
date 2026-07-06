import SwiftUI
import AppKit

/// The kind of content captured from the pasteboard. Drives the icon, preview
/// style, and how the item is written back when re-copied.
enum ClipKind: String, Codable {
    case text
    case link
    case color
    case image
    case file
    case emoji
}

/// A single entry in the clipboard history. Codable metadata only — image
/// pixels live on disk and are loaded on demand by `ClipboardStore`.
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: ClipKind
    /// Primary string payload: the text, URL, hex color, or newline-joined file paths.
    var text: String
    /// Relative filename inside the images directory (for `.image`).
    var imageFileName: String?
    /// Absolute file paths (for `.file`).
    var filePaths: [String]?
    var date: Date
    var pinned: Bool
    /// Best-effort source application name at capture time.
    var source: String?

    init(kind: ClipKind,
         text: String,
         imageFileName: String? = nil,
         filePaths: [String]? = nil,
         date: Date = Date(),
         pinned: Bool = false,
         source: String? = nil) {
        self.id = UUID()
        self.kind = kind
        self.text = text
        self.imageFileName = imageFileName
        self.filePaths = filePaths
        self.date = date
        self.pinned = pinned
        self.source = source
    }

    /// Two items are "the same content" (for dedup) when kind + payload key
    /// match. For images, `text` holds a content hash so this stays cheap.
    func sameContent(as other: ClipboardItem) -> Bool {
        kind == other.kind && text == other.text
    }

    // MARK: Display helpers

    var symbol: String {
        switch kind {
        case .text:  return "text.alignleft"
        case .link:  return "link"
        case .color: return "paintpalette.fill"
        case .image: return "photo.fill"
        case .file:  return "doc.fill"
        case .emoji: return "face.smiling"
        }
    }

    var accent: Color {
        switch kind {
        case .text:  return Theme.indigo
        case .link:  return Theme.teal
        case .color: return swatchColor ?? Theme.violet
        case .image: return Theme.pink
        case .file:  return Theme.amber
        case .emoji: return Theme.amber
        }
    }

    /// Short one-line title for the row.
    @MainActor var title: String {
        switch kind {
        case .link:
            return URL(string: text)?.host ?? text
        case .color:
            return text.uppercased()
        case .image:
            return L(fr: "Image", en: "Image")
        case .file:
            let names = (filePaths ?? []).map { ($0 as NSString).lastPathComponent }
            return names.first ?? L(fr: "Fichier", en: "File")
        case .emoji:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .text:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
        }
    }

    /// Secondary line: source app + kind + relative age.
    @MainActor func subtitle(now: Date = Date()) -> String {
        var parts: [String] = []
        switch kind {
        case .text:  parts.append(L(fr: "\(text.count) caractères", en: "\(text.count) characters"))
        case .link:  parts.append(L(fr: "Lien", en: "Link"))
        case .color: parts.append(L(fr: "Couleur", en: "Color"))
        case .image: parts.append(L(fr: "Image", en: "Image"))
        case .emoji: parts.append(L(fr: "Emoji", en: "Emoji"))
        case .file:
            let n = filePaths?.count ?? 1
            parts.append(n > 1 ? L(fr: "\(n) fichiers", en: "\(n) files") : L(fr: "Fichier", en: "File"))
        }
        if let source, !source.isEmpty { parts.append(source) }
        parts.append(Self.relativeAge(from: date, to: now))
        return parts.joined(separator: " · ")
    }

    /// The swatch colour for a `.color` item.
    var swatchColor: Color? {
        guard kind == .color else { return nil }
        return Self.parseColor(text)
    }

    /// Parses a `#hex`, `rgb()/rgba()` or `hsl()/hsla()` string into a Color, or
    /// `nil` if unrecognised. Used both to render swatches and to classify copies.
    static func parseColor(_ raw: String) -> Color? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("#") {
            var hex = s; hex.removeFirst()
            guard let v = UInt64(hex, radix: 16) else { return nil }
            if hex.count == 6 {
                return Color(red: Double((v >> 16) & 0xFF) / 255,
                             green: Double((v >> 8) & 0xFF) / 255,
                             blue: Double(v & 0xFF) / 255)
            } else if hex.count == 3 {
                return Color(red: Double((v >> 8) & 0xF) / 15,
                             green: Double((v >> 4) & 0xF) / 15,
                             blue: Double(v & 0xF) / 15)
            }
            return nil
        }
        let nums = s.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .compactMap(Double.init)
        if s.hasPrefix("rgb"), nums.count >= 3 {
            return Color(red: (nums[0] / 255).clamped(to: 0...1),
                         green: (nums[1] / 255).clamped(to: 0...1),
                         blue: (nums[2] / 255).clamped(to: 0...1))
        }
        if s.hasPrefix("hsl"), nums.count >= 3 {
            return hslColor(h: nums[0] / 360, s: (nums[1] / 100).clamped(to: 0...1), l: (nums[2] / 100).clamped(to: 0...1))
        }
        return nil
    }

    private static func hslColor(h: Double, s: Double, l: Double) -> Color {
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch h * 6 {
        case 0..<1:  (r, g, b) = (c, x, 0)
        case 1..<2:  (r, g, b) = (x, c, 0)
        case 2..<3:  (r, g, b) = (0, c, x)
        case 3..<4:  (r, g, b) = (0, x, c)
        case 4..<5:  (r, g, b) = (x, 0, c)
        default:     (r, g, b) = (c, 0, x)
        }
        return Color(red: r + m, green: g + m, blue: b + m)
    }

    /// A stable colour derived from a link's host, for the favicon-less avatar.
    static func domainColor(_ host: String) -> Color {
        let sum = host.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(hue: Double(sum % 360) / 360, saturation: 0.5, brightness: 0.82)
    }

    /// True when a string is just a short run of emoji (so it can be shown as-is).
    static func isEmojiOnly(_ string: String) -> Bool {
        let chars = string.filter { !$0.isWhitespace }
        guard !chars.isEmpty, chars.count <= 8 else { return false }
        return chars.allSatisfy { c in
            c.unicodeScalars.contains { $0.properties.isEmojiPresentation }
                || (c.unicodeScalars.count > 1 && (c.unicodeScalars.first?.properties.isEmoji ?? false))
        }
    }

    @MainActor private static func relativeAge(from: Date, to: Date) -> String {
        let s = max(0, to.timeIntervalSince(from))
        if s < 60 { return L(fr: "à l'instant", en: "just now") }
        if s < 3600 { return L(fr: "il y a \(Int(s / 60)) min", en: "\(Int(s / 60)) min ago") }
        if s < 86400 { return L(fr: "il y a \(Int(s / 3600)) h", en: "\(Int(s / 3600)) h ago") }
        return L(fr: "il y a \(Int(s / 86400)) j", en: "\(Int(s / 86400)) d ago")
    }
}
