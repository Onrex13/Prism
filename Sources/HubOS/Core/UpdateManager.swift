import AppKit
import Observation

/// GitHub-release auto-updater. Checks the repo's latest release, and — on the
/// user's go-ahead — downloads the `.zip` asset and installs it IN PLACE over the
/// running app, preserving the code signature (and therefore the granted TCC
/// permissions, since all releases share one stable signing identity).
@MainActor
@Observable
final class UpdateManager {
    static let shared = UpdateManager()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case downloading(Double)
        case installing
        case failed(String)
    }

    private(set) var state: State = .idle

    private init() {}

    func reset() { state = .idle }

    private struct Release: Decodable {
        let tag_name: String
        let assets: [Asset]
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
    }

    // MARK: Check

    func check() async {
        guard AppInfo.isRepoConfigured else {
            state = .failed("Dépôt non configuré (AppInfo.githubOwner)")
            return
        }
        state = .checking
        do {
            var req = URLRequest(url: AppInfo.latestReleaseAPI)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                state = .failed("Aucune release trouvée"); return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            guard Self.isNewer(latest, than: AppInfo.version) else { state = .upToDate; return }
            guard let zip = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
                state = .failed("Release sans .zip"); return
            }
            state = .available(version: latest, url: zip.browser_download_url)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Semantic-ish comparison: 1.2.10 > 1.2.9 > 1.2.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }
        let (x, y) = (parts(a), parts(b))
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: Download + install

    func downloadAndInstall() async {
        guard case let .available(version, url) = state else { return }
        do {
            state = .downloading(0)
            let (tempZip, _) = try await URLSession.shared.download(from: url)
            state = .installing

            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("PrismUpdate-\(version)", isDirectory: true)
            try? fm.removeItem(at: work)
            try fm.createDirectory(at: work, withIntermediateDirectories: true)

            // Unzip with ditto so the code signature / xattrs survive.
            try run("/usr/bin/ditto", ["-x", "-k", tempZip.path, work.path])

            guard let newApp = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else {
                state = .failed("Archive invalide (pas de .app)"); return
            }

            let installedPath = Bundle.main.bundlePath
            try Self.spawnSwap(newApp: newApp.path, installedPath: installedPath)
            // Quit so the helper can replace us, then relaunch the new version.
            NSApp.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Helpers

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "Prism.update", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(tool) a échoué"])
        }
    }

    /// Writes and launches a detached script that waits for this process to exit,
    /// swaps the app bundle (preserving signature via `ditto`), and relaunches.
    private static func spawnSwap(newApp: String, installedPath: String) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/bash
        while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done
        sleep 0.4
        /bin/rm -rf "\(installedPath)"
        /usr/bin/ditto "\(newApp)" "\(installedPath)"
        /usr/bin/open "\(installedPath)"
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prism-update.sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [url.path]
        try p.run()   // detached; keeps running after we terminate
    }
}
