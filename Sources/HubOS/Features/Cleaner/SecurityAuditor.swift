import AppKit
import Observation

// Well-known macOS adware / PUP persistence family names (matched on the launch
// item label or its target path, case-insensitive). File-scoped so the
// off-main-actor audit can read it.
private let adwareSignatures = [
    "genieo", "vsearch", "installmac", "conduit", "spigot", "trovi",
    "searchmine", "pirrit", "bundlore", "adload", "shlayer", "mughthesec",
    "mackeeper", "advancedmaccleaner", "omnikey", "vidsqu",
    "chumsearch", "alongy", "smartsearch"
]

/// Honest, offline "security check" — NOT a signature antivirus. It audits the
/// things macbook malware/adware actually abuse to persist: LaunchAgents,
/// LaunchDaemons and their target binaries. Each is checked for a valid code
/// signature and matched against well-known adware family names. This mirrors
/// what tools like KnockKnock surface; nothing is deleted without the user.
@MainActor
@Observable
final class SecurityAuditor {
    static let shared = SecurityAuditor()

    enum Severity: Int, Comparable {
        case adware = 0, unsigned = 1, ok = 2
        static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }
        @MainActor var label: String {
            self == .adware ? L(fr: "Adware connu", en: "Known adware")
                : self == .unsigned ? L(fr: "Non signé", en: "Unsigned")
                : L(fr: "Signé", en: "Signed")
        }
        var symbol: String { self == .adware ? "exclamationmark.octagon.fill"
            : self == .unsigned ? "questionmark.diamond.fill" : "checkmark.seal.fill" }
    }

    struct Finding: Identifiable {
        let id: String          // plist path (unique)
        var name: String        // Label / file name
        var plistPath: String
        var program: String?    // resolved target binary
        var scope: String       // human-readable location
        var severity: Severity
        var signer: String?
        var userWritable: Bool   // can we quarantine it without admin?
    }

    enum Phase { case idle, scanning, done }
    var phase: Phase = .idle
    var findings: [Finding] = []

    private init() {}

    var flaggedCount: Int { findings.filter { $0.severity != .ok }.count }
    var adwareCount: Int { findings.filter { $0.severity == .adware }.count }

    // MARK: Scan

    func scan() async {
        phase = .scanning
        findings = []
        let dirs = Self.scanDirs()
        let result = await Task.detached { Self.audit(dirs) + Self.scanExtensions() }.value
        findings = result.sorted { ($0.severity, $0.name) < ($1.severity, $1.name) }
        phase = .done
    }

    func reset() { phase = .idle; findings = [] }

    /// Preview-only sample results.
    func seedPreview() {
        findings = [
            Finding(id: "1", name: "com.genieo.completer", plistPath: "/Library/LaunchAgents/com.genieo.completer.plist",
                    program: "/usr/local/bin/completer", scope: "Agent système", severity: .adware,
                    signer: nil, userWritable: false),
            Finding(id: "2", name: "com.random.helper", plistPath: "~/Library/LaunchAgents/com.random.helper.plist",
                    program: "/tmp/helper", scope: "Agent utilisateur", severity: .unsigned,
                    signer: nil, userWritable: true),
            Finding(id: "3", name: "com.google.keystone.agent", plistPath: "~/Library/LaunchAgents/com.google.keystone.agent.plist",
                    program: "/Users/x/Library/Google/GoogleSoftwareUpdate", scope: "Agent utilisateur",
                    severity: .ok, signer: "Developer ID Application: Google LLC", userWritable: true),
            Finding(id: "4", name: "com.docker.helper", plistPath: "~/Library/LaunchAgents/com.docker.helper.plist",
                    program: "/Applications/Docker.app/Contents/MacOS/Docker", scope: "Agent utilisateur",
                    severity: .ok, signer: "Developer ID Application: Docker Inc", userWritable: true)
        ]
        phase = .done
    }

    func reveal(_ f: Finding) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f.plistPath)])
    }

    /// Quarantines a flagged, user-writable launch item: unloads it now and
    /// moves its plist into `~/.hubos-quarantine` so it won't relaunch. Fully
    /// reversible (the file is preserved), and only offered for user agents so
    /// no admin rights or system files are involved.
    func quarantine(_ f: Finding) async {
        guard f.userWritable, f.severity != .ok else { return }
        let failure = await Task.detached { Self.performQuarantine(f.plistPath) }.value
        if let failure {
            Notifier.shared.error(L(fr: "Quarantaine impossible : \(f.name)",
                                    en: "Couldn't quarantine \(f.name)"), detail: failure)
        } else {
            Notifier.shared.success(L(fr: "\(f.name) mis en quarantaine",
                                      en: "\(f.name) quarantined"))
        }
        await scan()
    }

    // MARK: Implementation (off the main actor)

    private struct ScanDir { let url: URL; let scope: String; let userWritable: Bool }

    nonisolated private static func scanDirs() -> [ScanDir] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ScanDir(url: home.appendingPathComponent("Library/LaunchAgents"),
                    scope: "Agent utilisateur", userWritable: true),
            ScanDir(url: URL(fileURLWithPath: "/Library/LaunchAgents"),
                    scope: "Agent système", userWritable: false),
            ScanDir(url: URL(fileURLWithPath: "/Library/LaunchDaemons"),
                    scope: "Démon système", userWritable: false)
        ]
    }

    nonisolated private static func audit(_ dirs: [ScanDir]) -> [Finding] {
        let fm = FileManager.default
        var out: [Finding] = []
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(at: dir.url,
                                                          includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else { continue }
            for plist in items where plist.pathExtension == "plist" {
                let dict = NSDictionary(contentsOf: plist)
                let label = (dict?["Label"] as? String) ?? plist.deletingPathExtension().lastPathComponent
                let program = resolveProgram(dict)

                let haystack = (label + " " + (program ?? "")).lowercased()
                let isAdware = adwareSignatures.contains { haystack.contains($0) }

                var severity: Severity = .ok
                var signer: String?
                if isAdware {
                    severity = .adware
                } else if let program {
                    let sign = signingStatus(program)
                    signer = sign.signer
                    severity = sign.signed ? .ok : .unsigned
                } else {
                    severity = .ok // no resolvable program (e.g. RunAtLoad script)
                }

                out.append(Finding(
                    id: plist.path, name: label, plistPath: plist.path,
                    program: program, scope: dir.scope, severity: severity,
                    signer: signer, userWritable: dir.userWritable
                ))
            }
        }
        return out
    }

    // MARK: Browser extensions (a common adware vector)

    nonisolated private static func scanExtensions() -> [Finding] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let browsers: [(name: String, path: String)] = [
            ("Chrome", "Library/Application Support/Google/Chrome"),
            ("Brave", "Library/Application Support/BraveSoftware/Brave-Browser"),
            ("Edge", "Library/Application Support/Microsoft Edge"),
            ("Chromium", "Library/Application Support/Chromium")
        ]
        var out: [Finding] = []
        for browser in browsers {
            let root = home.appendingPathComponent(browser.path)
            guard let profiles = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles]) else { continue }
            for profile in profiles where profile.hasDirectoryPath {
                let extRoot = profile.appendingPathComponent("Extensions")
                guard let extIDs = try? fm.contentsOfDirectory(at: extRoot, includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles]) else { continue }
                for extDir in extIDs where extDir.hasDirectoryPath {
                    let id = extDir.lastPathComponent
                    guard let versions = try? fm.contentsOfDirectory(at: extDir, includingPropertiesForKeys: nil,
                                                                     options: [.skipsHiddenFiles]),
                          let versionDir = versions.first(where: { $0.hasDirectoryPath }) else { continue }
                    let manifest = versionDir.appendingPathComponent("manifest.json")
                    let name = extensionName(manifest: manifest, versionDir: versionDir) ?? id
                    let haystack = (name + " " + id).lowercased()
                    let isAdware = adwareSignatures.contains { haystack.contains($0) }
                    out.append(Finding(
                        id: manifest.path, name: name, plistPath: versionDir.path,
                        program: nil, scope: "Extension \(browser.name)",
                        severity: isAdware ? .adware : .ok, signer: nil, userWritable: false))
                }
            }
        }
        return out
    }

    nonisolated private static func extensionName(manifest: URL, versionDir: URL) -> String? {
        guard let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var name = json["name"] as? String, !name.isEmpty else { return nil }
        if name.hasPrefix("__MSG_") {
            let key = name.replacingOccurrences(of: "__MSG_", with: "").replacingOccurrences(of: "__", with: "")
            let locale = (json["default_locale"] as? String) ?? "en"
            let messages = versionDir.appendingPathComponent("_locales/\(locale)/messages.json")
            guard let mdata = try? Data(contentsOf: messages),
                  let mjson = try? JSONSerialization.jsonObject(with: mdata) as? [String: Any],
                  let entry = mjson[key] as? [String: Any],
                  let msg = entry["message"] as? String else { return nil }
            name = msg
        }
        return name
    }

    nonisolated private static func resolveProgram(_ dict: NSDictionary?) -> String? {
        if let program = dict?["Program"] as? String { return program }
        if let args = dict?["ProgramArguments"] as? [String], let first = args.first { return first }
        return nil
    }

    nonisolated private static func signingStatus(_ binary: String) -> (signed: Bool, signer: String?) {
        guard FileManager.default.fileExists(atPath: binary) else { return (false, nil) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["-dv", "--verbose=2", binary]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        try? p.run()
        p.waitUntilExit()
        let text = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else { return (false, nil) }
        let signer = text.split(separator: "\n")
            .first { $0.hasPrefix("Authority=") }
            .map { String($0.dropFirst("Authority=".count)) }
            ?? (text.contains("Signature=adhoc") ? "Signature ad-hoc" : nil)
        return (true, signer)
    }

    /// Returns `nil` on success, or a human-readable reason on failure — the
    /// move out of the launch directory is what actually matters, so its error
    /// is surfaced instead of being swallowed.
    nonisolated private static func performQuarantine(_ plistPath: String) -> String? {
        let fm = FileManager.default
        let quarantine = fm.homeDirectoryForCurrentUser.appendingPathComponent(".hubos-quarantine")
        try? fm.createDirectory(at: quarantine, withIntermediateDirectories: true)
        // Best-effort unload so it stops immediately.
        let unload = Process()
        unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        unload.arguments = ["unload", plistPath]
        try? unload.run(); unload.waitUntilExit()
        // Move the plist out of the launch directory.
        let dest = quarantine.appendingPathComponent(URL(fileURLWithPath: plistPath).lastPathComponent)
        try? fm.removeItem(at: dest)
        do {
            try fm.moveItem(at: URL(fileURLWithPath: plistPath), to: dest)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
