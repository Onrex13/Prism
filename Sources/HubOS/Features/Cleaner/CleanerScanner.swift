import SwiftUI
import Observation

/// A group of removable files (e.g. user caches). Only ever contents of the
/// listed directories are removed — never the directories themselves or
/// anything outside this allow-list.
struct CleanerCategory: Identifiable {
    let id: String
    var name: String
    var detail: String
    var symbol: String
    var tint: Color
    var paths: [URL]
    var size: Int64 = 0
    var selected: Bool = true
}

/// Scans safe, user-owned locations for reclaimable space and clears them on
/// request. Conservative by design: caches/logs/trash/DerivedData only.
@MainActor
@Observable
final class CleanerScanner {
    static let shared = CleanerScanner()

    enum Phase { case idle, scanning, ready, cleaning, done }

    var phase: Phase = .idle
    var categories: [CleanerCategory] = []
    var lastFreed: Int64 = 0

    private init() {}

    var totalReclaimable: Int64 { categories.reduce(0) { $0 + $1.size } }
    var totalSelected: Int64 {
        categories.filter { $0.selected }.reduce(0) { $0 + $1.size }
    }
    var hasSelection: Bool { categories.contains { $0.selected && $0.size > 0 } }

    func toggle(_ id: String) {
        guard let idx = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[idx].selected.toggle()
    }

    // MARK: Scan

    func scan() async {
        phase = .scanning
        lastFreed = 0
        var result: [CleanerCategory] = []
        for var cat in Self.makeCategories() {
            let paths = cat.paths
            cat.size = await Task.detached { Self.totalSize(of: paths) }.value
            cat.selected = cat.size > 0
            result.append(cat)
        }
        categories = result
        phase = .ready
    }

    // MARK: Clean

    func clean() async {
        phase = .cleaning
        let targets = categories.filter { $0.selected && $0.size > 0 }.flatMap { $0.paths }
        let freed = await Task.detached { Self.removeContents(of: targets) }.value
        lastFreed = freed
        // Re-measure so the UI reflects what remains.
        var result = categories
        for i in result.indices {
            let paths = result[i].paths
            result[i].size = await Task.detached { Self.totalSize(of: paths) }.value
            result[i].selected = result[i].size > 0
        }
        categories = result
        phase = .done
    }

    func reset() { phase = .idle; categories = []; lastFreed = 0 }

    /// Preview-only sample results (empty paths → nothing can be deleted).
    func seedPreview() {
        categories = [
            CleanerCategory(id: "caches", name: "Caches d'applications", detail: "~/Library/Caches",
                            symbol: "shippingbox.fill", tint: Theme.indigo, paths: [], size: 3_240_000_000),
            CleanerCategory(id: "logs", name: "Journaux", detail: "~/Library/Logs",
                            symbol: "doc.text.fill", tint: Theme.teal, paths: [], size: 128_000_000),
            CleanerCategory(id: "trash", name: "Corbeille", detail: "~/.Trash",
                            symbol: "trash.fill", tint: Theme.pink, paths: [], size: 1_900_000_000),
            CleanerCategory(id: "derived", name: "Xcode DerivedData", detail: "Données de build",
                            symbol: "hammer.fill", tint: Theme.amber, paths: [], size: 5_600_000_000)
        ]
        phase = .ready
    }

    // MARK: Categories

    private static func makeCategories() -> [CleanerCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var cats: [CleanerCategory] = [
            CleanerCategory(id: "caches", name: "Caches d'applications",
                            detail: "~/Library/Caches", symbol: "shippingbox.fill", tint: Theme.indigo,
                            paths: [home.appendingPathComponent("Library/Caches")]),
            CleanerCategory(id: "logs", name: "Journaux", detail: "~/Library/Logs",
                            symbol: "doc.text.fill", tint: Theme.teal,
                            paths: [home.appendingPathComponent("Library/Logs")]),
            CleanerCategory(id: "trash", name: "Corbeille", detail: "~/.Trash",
                            symbol: "trash.fill", tint: Theme.pink,
                            paths: [home.appendingPathComponent(".Trash")])
        ]
        let derived = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        if FileManager.default.fileExists(atPath: derived.path) {
            cats.append(CleanerCategory(id: "derived", name: "Xcode DerivedData",
                                        detail: "Données de build", symbol: "hammer.fill", tint: Theme.amber,
                                        paths: [derived]))
        }
        return cats
    }

    // MARK: File ops (off the main actor)

    nonisolated private static func totalSize(of paths: [URL]) -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        for dir in paths {
            guard let en = fm.enumerator(at: dir,
                                         includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
                                         options: [], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in en {
                let vals = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
                if vals?.isRegularFile == true {
                    total += Int64(vals?.totalFileAllocatedSize ?? 0)
                }
            }
        }
        return total
    }

    nonisolated private static func removeContents(of paths: [URL]) -> Int64 {
        var freed: Int64 = 0
        let fm = FileManager.default
        for dir in paths {
            guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles]) else { continue }
            for child in children {
                let size = totalSize(of: [child]) + fileSize(child)
                if (try? fm.removeItem(at: child)) != nil {
                    freed += size
                }
            }
        }
        return freed
    }

    nonisolated private static func fileSize(_ url: URL) -> Int64 {
        let vals = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
        return vals?.isRegularFile == true ? Int64(vals?.totalFileAllocatedSize ?? 0) : 0
    }
}
