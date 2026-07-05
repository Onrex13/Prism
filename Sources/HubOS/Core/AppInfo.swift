import Foundation

/// Central identity + release metadata for the app. Update `githubOwner` once,
/// then GitHub-release-based auto-update and the About/links all follow.
enum AppInfo {
    static let name = "Prism"

    /// ⚠️ Set this to your GitHub username before publishing (repo must be public).
    static let githubOwner = "CHANGE_ME"
    static let githubRepo = "Prism"

    /// Marketing version from the bundle (falls back for dev/`swift run`).
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    static var isRepoConfigured: Bool { githubOwner != "CHANGE_ME" && !githubOwner.isEmpty }

    static var repoURL: URL {
        URL(string: "https://github.com/\(githubOwner)/\(githubRepo)")!
    }
    static var latestReleaseAPI: URL {
        URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest")!
    }
    static var latestReleasePage: URL {
        URL(string: "https://github.com/\(githubOwner)/\(githubRepo)/releases/latest")!
    }
}
