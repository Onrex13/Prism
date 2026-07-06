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
        let outcome = await Task.detached { Self.removeContents(of: targets) }.value
        lastFreed = outcome.freed
        // Re-measure so the UI reflects what remains.
        var result = categories
        for i in result.indices {
            let paths = result[i].paths
            result[i].size = await Task.detached { Self.totalSize(of: paths) }.value
            result[i].selected = result[i].size > 0
        }
        categories = result
        phase = .done
        let freedText = ByteCountFormatter.string(fromByteCount: outcome.freed, countStyle: .file)
        if outcome.failed > 0 {
            Notifier.shared.error(L(fr: "Nettoyage · \(freedText) libérés, \(outcome.failed) éléments ignorés",
                                    en: "Cleanup · \(freedText) freed, \(outcome.failed) items skipped"),
                                  detail: "\(outcome.failed) items could not be removed (locked / in use / permission)")
        } else {
            Notifier.shared.success(L(fr: "Nettoyage terminé · \(freedText) libérés",
                                      en: "Cleanup complete · \(freedText) freed"))
        }
    }

    func reset() { phase = .idle; categories = []; lastFreed = 0 }

    /// Preview-only sample results (empty paths → nothing can be deleted).
    func seedPreview() {
        categories = [
            CleanerCategory(id: "caches", name: L(fr: "Caches d'applications", en: "App caches"), detail: "~/Library/Caches",
                            symbol: "shippingbox.fill", tint: Theme.indigo, paths: [], size: 3_240_000_000),
            CleanerCategory(id: "logs", name: L(fr: "Journaux", en: "Logs"), detail: "~/Library/Logs",
                            symbol: "doc.text.fill", tint: Theme.teal, paths: [], size: 128_000_000),
            CleanerCategory(id: "trash", name: L(fr: "Corbeille", en: "Trash"), detail: "~/.Trash",
                            symbol: "trash.fill", tint: Theme.pink, paths: [], size: 1_900_000_000),
            CleanerCategory(id: "derived", name: "Xcode DerivedData", detail: L(fr: "Données de build", en: "Build data"),
                            symbol: "hammer.fill", tint: Theme.amber, paths: [], size: 5_600_000_000)
        ]
        phase = .ready
    }

    // MARK: Categories

    @MainActor
    private static func makeCategories() -> [CleanerCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var cats: [CleanerCategory] = [
            CleanerCategory(id: "caches", name: L(fr: "Caches d'applications", en: "App caches"),
                            detail: "~/Library/Caches", symbol: "shippingbox.fill", tint: Theme.indigo,
                            paths: [home.appendingPathComponent("Library/Caches")]),
            CleanerCategory(id: "logs", name: L(fr: "Journaux", en: "Logs"), detail: "~/Library/Logs",
                            symbol: "doc.text.fill", tint: Theme.teal,
                            paths: [home.appendingPathComponent("Library/Logs")]),
            CleanerCategory(id: "trash", name: L(fr: "Corbeille", en: "Trash"), detail: "~/.Trash",
                            symbol: "trash.fill", tint: Theme.pink,
                            paths: [home.appendingPathComponent(".Trash")])
        ]
        // Dev caches — added only if present, and OUTSIDE ~/Library/Caches so they
        // never double-count the broad "App caches" category above.
        let fm = FileManager.default
        func addIfExists(_ id: String, _ name: String, _ detail: String, _ symbol: String, _ tint: Color, _ rel: String) {
            let url = home.appendingPathComponent(rel)
            if fm.fileExists(atPath: url.path) {
                cats.append(CleanerCategory(id: id, name: name, detail: detail, symbol: symbol, tint: tint, paths: [url]))
            }
        }
        addIfExists("derived", "Xcode DerivedData", L(fr: "Données de build", en: "Build data"),
                    "hammer.fill", Theme.amber, "Library/Developer/Xcode/DerivedData")
        addIfExists("devicesupport", "Xcode DeviceSupport", L(fr: "Symboles d'appareils", en: "Device symbols"),
                    "iphone", Theme.blue, "Library/Developer/Xcode/iOS DeviceSupport")
        addIfExists("simulator", L(fr: "Caches Simulateur", en: "Simulator caches"), "CoreSimulator",
                    "apps.iphone", Theme.violet, "Library/Developer/CoreSimulator/Caches")
        addIfExists("npm", "npm", "~/.npm", "shippingbox", Theme.pink, ".npm")
        addIfExists("yarn", "Yarn", "~/.yarn/berry/cache", "shippingbox", Theme.teal, ".yarn/berry/cache")
        addIfExists("pnpm", "pnpm", "~/Library/pnpm/store", "shippingbox", Theme.amber, "Library/pnpm/store")
        addIfExists("gradle", "Gradle", "~/.gradle/caches", "hammer", Theme.green, ".gradle/caches")
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

    nonisolated private static func removeContents(of paths: [URL]) -> (freed: Int64, failed: Int) {
        var freed: Int64 = 0
        var failed = 0
        let fm = FileManager.default
        for dir in paths {
            guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles]) else { continue }
            for child in children {
                let size = totalSize(of: [child]) + fileSize(child)
                do { try fm.removeItem(at: child); freed += size }
                catch { failed += 1 }   // locked / permission / in-use — reported, not swallowed
            }
        }
        return (freed, failed)
    }

    nonisolated private static func fileSize(_ url: URL) -> Int64 {
        let vals = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
        return vals?.isRegularFile == true ? Int64(vals?.totalFileAllocatedSize ?? 0) : 0
    }
}
