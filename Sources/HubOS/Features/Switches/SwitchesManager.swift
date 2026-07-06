import AppKit
import Observation

/// A grid of quick system switches/actions — the OnlySwitch idea. Toggles read
/// their real state; actions fire once. All permission-free except Dark Mode,
/// which uses the Automation (System Events) permission the app already declares.
@MainActor
@Observable
final class SwitchesManager {
    static let shared = SwitchesManager()

    private(set) var darkMode = false
    private(set) var hiddenFiles = false

    private init() {}

    /// Re-reads the live state of the toggles (call on appear).
    func refresh() {
        darkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        Task.detached {
            let hidden = Self.readBool("com.apple.finder", "AppleShowAllFiles")
            await MainActor.run { SwitchesManager.shared.hiddenFiles = hidden }
        }
    }

    // MARK: Toggles

    func toggleDarkMode() {
        darkMode.toggle()   // optimistic; refresh() re-syncs on next appear
        Self.runScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
    }

    func toggleHiddenFiles() {
        hiddenFiles.toggle()
        let show = hiddenFiles
        Task.detached {
            Self.run("/usr/bin/defaults", ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", show ? "true" : "false"])
            Self.run("/usr/bin/killall", ["Finder"])
        }
    }

    // MARK: Actions

    func emptyTrash() {
        Task.detached {
            let fm = FileManager.default
            let trash = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            let items = (try? fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? []
            for item in items { try? fm.removeItem(at: item) }
        }
        Notifier.shared.success(L(fr: "Corbeille vidée", en: "Trash emptied"))
    }

    func sleepDisplay() { Self.run("/usr/bin/pmset", ["displaysleepnow"]) }

    func startScreensaver() { Self.run("/usr/bin/open", ["-a", "ScreenSaverEngine"]) }

    func lockScreen() {
        // The system Ctrl+Cmd+Q lock, driven through System Events.
        Self.runScript("tell application \"System Events\" to keystroke \"q\" using {control down, command down}")
    }

    // MARK: Shell helpers (off the main actor)

    nonisolated private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }

    nonisolated private static func runScript(_ source: String) {
        run("/usr/bin/osascript", ["-e", source])
    }

    nonisolated private static func readBool(_ domain: String, _ key: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["read", domain, key]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return out == "1" || out == "true"
    }
}
