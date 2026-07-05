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
        }
    }

    var accent: Color {
        switch kind {
        case .text:  return Theme.indigo
        case .link:  return Theme.teal
        case .color: return swatchColor ?? Theme.violet
        case .image: return Theme.pink
        case .file:  return Theme.amber
        }
    }

    /// Short one-line title for the row.
    var title: String {
        switch kind {
        case .link:
            return URL(string: text)?.host ?? text
        case .color:
            return text.uppercased()
        case .image:
            return "Image"
        case .file:
            let names = (filePaths ?? []).map { ($0 as NSString).lastPathComponent }
            return names.first ?? "Fichier"
        case .text:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
        }
    }

    /// Secondary line: source app + kind + relative age.
    func subtitle(now: Date = Date()) -> String {
        var parts: [String] = []
        switch kind {
        case .text:  parts.append("\(text.count) caractères")
        case .link:  parts.append("Lien")
        case .color: parts.append("Couleur")
        case .image: parts.append("Image")
        case .file:
            let n = filePaths?.count ?? 1
            parts.append(n > 1 ? "\(n) fichiers" : "Fichier")
        }
        if let source, !source.isEmpty { parts.append(source) }
        parts.append(Self.relativeAge(from: date, to: now))
        return parts.joined(separator: " · ")
    }

    /// Parses a `#RGB`/`#RRGGBB` hex string into a Color for `.color` items.
    var swatchColor: Color? {
        guard kind == .color else { return nil }
        var hex = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard let value = UInt64(hex, radix: 16) else { return nil }
        let r, g, b: Double
        if hex.count == 6 {
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
        } else if hex.count == 3 {
            r = Double((value & 0xF00) >> 8) / 15
            g = Double((value & 0x0F0) >> 4) / 15
            b = Double(value & 0x00F) / 15
        } else { return nil }
        return Color(red: r, green: g, blue: b)
    }

    private static func relativeAge(from: Date, to: Date) -> String {
        let s = max(0, to.timeIntervalSince(from))
        if s < 60 { return "à l'instant" }
        if s < 3600 { return "il y a \(Int(s / 60)) min" }
        if s < 86400 { return "il y a \(Int(s / 3600)) h" }
        return "il y a \(Int(s / 86400)) j"
    }
}
