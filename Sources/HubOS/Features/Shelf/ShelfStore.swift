import AppKit
import SwiftUI
import Observation
import UniformTypeIdentifiers

/// The kind of content held on the shelf.
enum ShelfKind {
    case file
    case image
    case text
}

/// A single item parked on the shelf.
struct ShelfItem: Identifiable {
    let id = UUID()
    var kind: ShelfKind
    var name: String
    var url: URL?
    var image: NSImage?
    var text: String?
    /// Display thumbnail.
    var icon: NSImage?

    var subtitle: String {
        switch kind {
        case .file:
            if let url { return (url.pathExtension.isEmpty ? "Fichier" : url.pathExtension.uppercased()) }
            return "Fichier"
        case .image: return "Image"
        case .text:  return "\(text?.count ?? 0) caractères"
        }
    }

    var symbol: String {
        switch kind {
        case .file: return "doc.fill"
        case .image: return "photo.fill"
        case .text: return "text.alignleft"
        }
    }

    var accent: Color {
        switch kind {
        case .file: return Theme.amber
        case .image: return Theme.pink
        case .text: return Theme.indigo
        }
    }
}

/// Holds items dropped onto the shelf and vends drag providers to move them out.
@MainActor
@Observable
final class ShelfStore {
    static let shared = ShelfStore()

    private(set) var items: [ShelfItem] = []
    var isEmpty: Bool { items.isEmpty }

    private init() {}

    // MARK: Add

    func addFile(_ url: URL) {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        items.insert(ShelfItem(kind: .file, name: url.lastPathComponent, url: url, icon: icon), at: 0)
    }

    func addImageData(_ data: Data) {
        guard let image = NSImage(data: data) else { return }
        items.insert(ShelfItem(kind: .image, name: "Image", image: image, icon: image), at: 0)
    }

    func addText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let name = String(trimmed.replacingOccurrences(of: "\n", with: " ").prefix(48))
        items.insert(ShelfItem(kind: .text, name: name, text: text), at: 0)
    }

    // MARK: Remove

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
    }

    func clearAll() {
        items.removeAll()
    }

    // MARK: Drop handling

    /// Ingests dropped item providers. Values are marshalled as Sendable types
    /// (URL/Data/String) before hopping to the main actor.
    @discardableResult
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            // File or web URL first, so files keep their real name and extension.
            if provider.canLoadObject(ofClass: URL.self) {
                handled = true
                provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    if url.isFileURL {
                        Task { @MainActor in ShelfStore.shared.addFile(url) }
                    } else {
                        let link = url.absoluteString
                        Task { @MainActor in ShelfStore.shared.addText(link) }
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                handled = true
                provider.loadObject(ofClass: NSImage.self) { obj, _ in
                    guard let data = (obj as? NSImage)?.tiffRepresentation else { return }
                    Task { @MainActor in ShelfStore.shared.addImageData(data) }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                provider.loadObject(ofClass: NSString.self) { obj, _ in
                    guard let s = obj as? NSString else { return }
                    let str = s as String
                    Task { @MainActor in ShelfStore.shared.addText(str) }
                }
            }
        }
        return handled
    }

    // MARK: Drag out

    /// An item provider to drag the item out to another app or Finder.
    func provider(for item: ShelfItem) -> NSItemProvider {
        switch item.kind {
        case .file:
            if let url = item.url, let p = NSItemProvider(contentsOf: url) { return p }
        case .image:
            if let image = item.image { return NSItemProvider(object: image) }
        case .text:
            if let text = item.text { return NSItemProvider(object: text as NSString) }
        }
        return NSItemProvider()
    }

    // MARK: Preview

    func seedPreview() {
        items = [
            ShelfItem(kind: .image, name: "capture.png", image: Self.swatch([Theme.teal, Theme.indigo]),
                      icon: Self.swatch([Theme.teal, Theme.indigo])),
            ShelfItem(kind: .file, name: "HubOS.dmg", url: URL(fileURLWithPath: "/tmp/HubOS.dmg"),
                      icon: NSWorkspace.shared.icon(forFileType: "dmg")),
            ShelfItem(kind: .text, name: "npm run build && make dmg", text: "npm run build && make dmg")
        ]
    }

    private static func swatch(_ colors: [Color]) -> NSImage {
        let size = NSSize(width: 80, height: 80)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: colors.map { NSColor($0) })?.draw(in: NSRect(origin: .zero, size: size), angle: 45)
        image.unlockFocus()
        return image
    }
}
