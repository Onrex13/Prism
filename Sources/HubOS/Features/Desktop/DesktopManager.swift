import AppKit

/// Hides or shows the Finder desktop icons — the classic `CreateDesktop` toggle
/// (`defaults write com.apple.finder CreateDesktop` + relaunch Finder). Fully
/// reversible, no permission. Nothing is deleted; only icon visibility changes.
@MainActor
final class DesktopManager {
    static let shared = DesktopManager()

    private init() {}

    /// `true` hides the desktop icons, `false` shows them again.
    func setHidden(_ hidden: Bool) {
        Task.detached { Self.apply(hidden: hidden) }
    }

    nonisolated private static func apply(hidden: Bool) {
        run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", hidden ? "false" : "true"])
        run("/usr/bin/killall", ["Finder"])   // Finder must relaunch to apply
    }

    nonisolated private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }
}
