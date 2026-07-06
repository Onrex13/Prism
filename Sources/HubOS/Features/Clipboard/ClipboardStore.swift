import SwiftUI
import AppKit
import Observation
import CryptoKit

/// Watches the system pasteboard, keeps a searchable, persistent history, and
/// writes entries back when re-copied. Single shared instance for the app.
@MainActor
@Observable
final class ClipboardStore {
    static let shared = ClipboardStore()

    private(set) var items: [ClipboardItem] = []
    var searchText: String = ""

    /// Max non-pinned entries retained. Pinned items are never auto-evicted.
    private let maxItems = 250

    private var timer: DispatchSourceTimer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var imageCache: [UUID: NSImage] = [:]
    private var isMonitoring = false

    // MARK: Storage locations

    private let baseDir: URL
    private let imagesDir: URL
    private var indexURL: URL { baseDir.appendingPathComponent("index.json") }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDir = appSupport.appendingPathComponent("HubOS/Clipboard", isDirectory: true)
        imagesDir = baseDir.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: Monitoring

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.5, repeating: 0.4)
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        isMonitoring = false
    }

    private func tick() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let item = readCurrent(pb) else { return }
        ingest(item)
        // Flash a confirmation in the Dynamic Island (no-op if that module is off).
        NotchController.shared.showFlash(symbol: "checkmark.circle.fill",
                                         text: Self.flashText(for: item), tint: Theme.green)
    }

    private static func flashText(for item: ClipboardItem) -> String {
        switch item.kind {
        case .image: return L(fr: "Image copiée", en: "Image copied")
        case .file:
            let name = item.filePaths?.first.map { ($0 as NSString).lastPathComponent } ?? L(fr: "Fichier", en: "File")
            return L(fr: "Copié · \(name)", en: "Copied · \(name)")
        case .color: return L(fr: "Copié · \(item.text)", en: "Copied · \(item.text)")
        case .link, .text:
            let s = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            let clipped = s.count > 18 ? String(s.prefix(18)) + "…" : s
            return L(fr: "Copié · \(clipped)", en: "Copied · \(clipped)")
        }
    }

    // MARK: Reading the pasteboard

    private func readCurrent(_ pb: NSPasteboard) -> ClipboardItem? {
        let source = NSWorkspace.shared.frontmostApplication?.localizedName
        let types = pb.types ?? []

        // Image (screenshots, copied pictures).
        if types.contains(.png) || types.contains(.tiff) {
            if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff),
               let image = NSImage(data: data) {
                return makeImageItem(image, data: data, source: source)
            }
        }

        // Files copied from Finder.
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let paths = urls.map(\.path)
            return ClipboardItem(kind: .file,
                                 text: paths.joined(separator: "\n"),
                                 filePaths: paths,
                                 source: source)
        }

        // Plain text — classified into link / color / text.
        if let string = pb.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ClipboardItem(kind: classify(string), text: string, source: source)
        }
        return nil
    }

    private func makeImageItem(_ image: NSImage, data: Data, source: String?) -> ClipboardItem {
        let hash = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        var item = ClipboardItem(kind: .image, text: "img:\(hash)", source: source)
        let filename = "\(item.id.uuidString).png"
        let png = image.pngData() ?? data
        try? png.write(to: imagesDir.appendingPathComponent(filename))
        item.imageFileName = filename
        imageCache[item.id] = image
        return item
    }

    private func classify(_ string: String) -> ClipKind {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: "^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$", options: .regularExpression) != nil {
            return .color
        }
        if !trimmed.contains(" "), !trimmed.contains("\n"),
           let url = URL(string: trimmed), let scheme = url.scheme,
           ["http", "https"].contains(scheme.lowercased()) {
            return .link
        }
        return .text
    }

    // MARK: Ingest / dedup

    private func ingest(_ item: ClipboardItem) {
        if let idx = items.firstIndex(where: { $0.sameContent(as: item) }) {
            // Refresh timestamp and float to the top, preserving pin state.
            var existing = items.remove(at: idx)
            existing.date = item.date
            if existing.kind == .image, imageCache[existing.id] == nil,
               let newImg = imageCache[item.id] {
                imageCache[existing.id] = newImg
            }
            insertRespectingPins(existing)
        } else {
            insertRespectingPins(item)
            trim()
        }
        save()
    }

    /// Inserts at the top of the appropriate section (pinned items stay grouped
    /// above the rest).
    private func insertRespectingPins(_ item: ClipboardItem) {
        if item.pinned {
            items.insert(item, at: 0)
        } else {
            let firstUnpinned = items.firstIndex { !$0.pinned } ?? items.count
            items.insert(item, at: firstUnpinned)
        }
    }

    private func trim() {
        var unpinnedCount = 0
        var removable: [Int] = []
        for (i, item) in items.enumerated() where !item.pinned {
            unpinnedCount += 1
            if unpinnedCount > maxItems { removable.append(i) }
        }
        for i in removable.reversed() {
            deleteImageFile(items[i])
            imageCache[items[i].id] = nil
            items.remove(at: i)
        }
    }

    // MARK: Actions

    /// Writes an item back to the pasteboard and floats it to the top.
    func copy(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .image:
            if let image = image(for: item), let png = image.pngData() {
                pb.setData(png, forType: .png)
            }
        case .file:
            let urls = (item.filePaths ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            if !urls.isEmpty { pb.writeObjects(urls) }
        case .text, .link, .color:
            pb.setString(item.text, forType: .string)
        }
        lastChangeCount = pb.changeCount
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            var moved = items.remove(at: idx)
            moved.date = Date()
            insertRespectingPins(moved)
            save()
        }
    }

    func togglePin(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items.remove(at: idx)
        updated.pinned.toggle()
        insertRespectingPins(updated)
        save()
    }

    func delete(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        deleteImageFile(items[idx])
        imageCache[item.id] = nil
        items.remove(at: idx)
        save()
    }

    /// Clears everything except pinned items.
    func clearUnpinned() {
        for item in items where !item.pinned {
            deleteImageFile(item)
            imageCache[item.id] = nil
        }
        items.removeAll { !$0.pinned }
        save()
    }

    // MARK: Query

    var filtered: [ClipboardItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.title.lowercased().contains(q)
                || $0.text.lowercased().contains(q)
                || ($0.source?.lowercased().contains(q) ?? false)
        }
    }

    // MARK: Images

    func image(for item: ClipboardItem) -> NSImage? {
        if let cached = imageCache[item.id] { return cached }
        guard let name = item.imageFileName else { return nil }
        let url = imagesDir.appendingPathComponent(name)
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache[item.id] = image
        return image
    }

    private func deleteImageFile(_ item: ClipboardItem) {
        guard let name = item.imageFileName else { return }
        try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(name))
    }

    // MARK: Persistence

    private func save() {
        let snapshot = items
        let url = indexURL
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        items = decoded
    }

    // MARK: Preview

    /// Replaces the in-memory history with representative sample entries so the
    /// UI can be captured populated. Preview-only; does not persist.
    func seedPreviewData() {
        items = [
            ClipboardItem(kind: .text, text: "./Scripts/make_dmg.sh  # build the perfect DMG",
                          date: Date(timeIntervalSinceNow: -30), pinned: true, source: "Terminal"),
            ClipboardItem(kind: .link, text: "https://developer.apple.com/documentation/swiftui/glasseffect",
                          date: Date(timeIntervalSinceNow: -120), source: "Safari"),
            ClipboardItem(kind: .text, text: "Le Liquid Glass change tout sur macOS 27 ✨ — HubOS arrive.",
                          date: Date(timeIntervalSinceNow: -600), source: "Notes"),
            ClipboardItem(kind: .color, text: "#6B5CFA",
                          date: Date(timeIntervalSinceNow: -1800), source: "Figma"),
            ClipboardItem(kind: .file, text: "/Users/onrex/Desktop/HubOS/dist/HubOS.dmg",
                          filePaths: ["/Users/onrex/Desktop/HubOS/dist/HubOS.dmg"],
                          date: Date(timeIntervalSinceNow: -7200), source: "Finder")
        ]
    }
}

extension NSImage {
    /// Encodes to PNG data.
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
