import AppKit
import SwiftUI
import CoreImage
import Observation

/// Tracks the currently playing track from Spotify and Apple Music via their
/// broadcast distributed notifications (no permission needed to read), and
/// drives transport controls via AppleScript (prompts for Automation once).
@MainActor
@Observable
final class NowPlayingMonitor {
    static let shared = NowPlayingMonitor()

    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var isPlaying: Bool = false
    var artwork: NSImage? { didSet { accentColor = artwork?.averageColor } }
    /// Dominant color of the current artwork, used for the ambient glow.
    var accentColor: Color?
    /// Human-readable source app ("Spotify" / "Musique").
    var sourceName: String = ""

    // Playback position (interpolated locally between AppleScript syncs).
    var duration: Double = 0
    private var positionSync: Double = 0
    private var syncTime = Date()

    /// Player volume 0…1 (backing avoids the `@Observable` didSet recursion trap).
    private var storedVolume: Double = 0.7
    var volume: Double {
        get { storedVolume }
        set {
            let v = min(1, max(0, newValue))
            storedVolume = v
            control("set sound volume to \(Int((v * 100).rounded()))")
        }
    }

    /// Current elapsed seconds, interpolated while playing.
    var elapsed: Double {
        guard duration > 0 else { return 0 }
        let raw = isPlaying ? positionSync + Date().timeIntervalSince(syncTime) : positionSync
        return min(max(0, raw), duration)
    }
    var progress: Double { duration > 0 ? elapsed / duration : 0 }

    private var sourceBundleID: String = ""
    private var observers: [NSObjectProtocol] = []
    private var artworkToken = 0

    var hasMedia: Bool { !title.isEmpty }

    private struct Player: Sendable {
        let bundleID: String
        let notification: String
        let displayName: String
    }
    private let players = [
        Player(bundleID: "com.spotify.client", notification: "com.spotify.client.PlaybackStateChanged", displayName: "Spotify"),
        Player(bundleID: "com.apple.Music", notification: "com.apple.Music.playerInfo", displayName: "Musique")
    ]

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for player in players {
            let obs = center.addObserver(forName: NSNotification.Name(player.notification),
                                         object: nil, queue: .main) { [weak self] note in
                // Extract Sendable values off the non-Sendable Notification before
                // hopping onto the main actor.
                let info = note.userInfo as? [String: Any]
                let state = (info?["Player State"] as? String) ?? ""
                let name = (info?["Name"] as? String) ?? ""
                let artist = (info?["Artist"] as? String) ?? ""
                let album = (info?["Album"] as? String) ?? ""
                let artURL = info?["Artwork URL"] as? String
                MainActor.assumeIsolated {
                    self?.handle(state: state, name: name, artist: artist,
                                 album: album, artURL: artURL, player: player)
                }
            }
            observers.append(obs)
        }
        fetchInitial()
    }

    func stop() {
        let center = DistributedNotificationCenter.default()
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    // MARK: Incoming updates

    private func handle(state: String, name: String, artist: String, album: String,
                        artURL: String?, player: Player) {
        // Spotify sends "Stopped" with no track when nothing is playing.
        if state == "Stopped" || name.isEmpty {
            if player.bundleID == sourceBundleID { clear() }
            return
        }
        sourceBundleID = player.bundleID
        sourceName = player.displayName
        title = name
        self.artist = artist
        self.album = album
        isPlaying = (state == "Playing")
        loadArtwork(for: player, spotifyURL: artURL)
        syncProgress()
    }

    private func clear() {
        title = ""; artist = ""; album = ""; isPlaying = false
        artwork = nil; accentColor = nil; sourceName = ""; sourceBundleID = ""
        duration = 0; positionSync = 0
    }

    // MARK: Playback position

    /// Fetches the authoritative play state + duration + position via AppleScript;
    /// the view interpolates between syncs so the bar moves smoothly. Reading the
    /// real `player state` here is what keeps the island in sync when a play/pause
    /// notification is missed or races (otherwise the bar kept advancing paused).
    private func syncProgress() {
        guard !sourceBundleID.isEmpty else { return }
        let isMusic = sourceBundleID == "com.apple.Music"
        let app = isMusic ? "Music" : "Spotify"
        let durExpr = isMusic ? "(duration of current track as text)"
                              : "(((duration of current track) / 1000) as text)"
        let script = "tell application \"\(app)\" to return (player state as text) & \"\\n\" & \(durExpr) & \"\\n\" & (player position as text) & \"\\n\" & (sound volume as text)"
        Task.detached { [weak self] in
            guard let out = Self.runAppleScript(script) else { return }
            let parts = out.components(separatedBy: "\n")
            guard parts.count >= 3,
                  let dur = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
                  let pos = Double(parts[2].replacingOccurrences(of: ",", with: ".")) else { return }
            let playing = parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "playing"
            let vol = parts.count >= 4 ? Double(parts[3].replacingOccurrences(of: ",", with: ".")) : nil
            await MainActor.run {
                guard let self else { return }
                self.isPlaying = playing
                self.duration = dur
                self.positionSync = pos
                self.syncTime = Date()
                if let vol { self.storedVolume = min(1, max(0, vol / 100)) }
            }
        }
    }

    // MARK: Artwork

    private func loadArtwork(for player: Player, spotifyURL: String?) {
        artworkToken += 1
        let token = artworkToken
        if let urlString = spotifyURL, let url = URL(string: urlString) {
            Task { [weak self] in
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = NSImage(data: data) {
                    await MainActor.run {
                        guard let self, token == self.artworkToken else { return }
                        self.artwork = image
                    }
                }
            }
            return
        }
        // Music.app: pull artwork bytes via AppleScript, best effort.
        if player.bundleID == "com.apple.Music" {
            Task.detached { [weak self] in
                let image = Self.fetchMusicArtwork()
                await MainActor.run {
                    guard let self, token == self.artworkToken else { return }
                    self.artwork = image
                }
            }
        } else {
            artwork = nil
        }
    }

    private nonisolated static func fetchMusicArtwork() -> NSImage? {
        let script = """
        tell application "Music"
            if player state is stopped then return ""
            try
                set d to raw data of artwork 1 of current track
                set p to (POSIX path of (path to temporary items)) & "hubos_music_art.tiff"
                set f to open for access p with write permission
                set eof f to 0
                write d to f
                close access f
                return p
            on error
                return ""
            end try
        end tell
        """
        guard let path = runAppleScript(script), !path.isEmpty else { return nil }
        return NSImage(contentsOfFile: path)
    }

    // MARK: Transport controls

    func togglePlayPause() {
        let current = elapsed          // capture BEFORE toggling isPlaying
        control("playpause")
        isPlaying.toggle()             // optimistic; re-sync confirms state + position
        positionSync = current
        syncTime = Date()
        resyncSoon()
    }
    func next() { control("next track"); resyncSoon() }
    func previous() { control("previous track"); resyncSoon() }

    /// Seeks to a fraction (0…1) of the track — drag the island's progress bar.
    func seek(toFraction f: Double) {
        guard duration > 0 else { return }
        let seconds = min(1, max(0, f)) * duration
        control("set player position to \(Int(seconds.rounded()))")
        positionSync = seconds
        syncTime = Date()
    }

    /// Re-reads the authoritative player state/position shortly after a transport
    /// command (once the app has actually applied it).
    private func resyncSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.syncProgress()
        }
    }

    private func control(_ command: String) {
        guard !sourceName.isEmpty else { return }
        let app = sourceBundleID == "com.apple.Music" ? "Music" : "Spotify"
        _ = Self.runAppleScript("tell application \"\(app)\" to \(command)")
    }

    // MARK: Initial state

    private func fetchInitial() {
        Task.detached { [weak self] in
            for app in ["Spotify", "Music"] {
                guard let result = Self.runAppleScript("""
                if application "\(app)" is running then
                    tell application "\(app)"
                        if player state is playing or player state is paused then
                            return (player state as text) & "\\n" & (name of current track) & "\\n" & (artist of current track) & "\\n" & (album of current track)
                        end if
                    end tell
                end if
                return ""
                """), !result.isEmpty else { continue }
                let parts = result.components(separatedBy: "\n")
                guard parts.count >= 4 else { continue }
                let bundleID = app == "Music" ? "com.apple.Music" : "com.spotify.client"
                await MainActor.run {
                    guard let self else { return }
                    self.sourceBundleID = bundleID
                    self.sourceName = app == "Music" ? "Musique" : "Spotify"
                    self.isPlaying = parts[0] == "playing"
                    self.title = parts[1]
                    self.artist = parts[2]
                    self.album = parts[3]
                    self.loadArtwork(for: self.players.first { $0.bundleID == bundleID }!, spotifyURL: nil)
                    self.syncProgress()
                }
                break
            }
        }
    }

    // MARK: Preview

    func seedPreview() {
        title = "Midnight City"
        artist = "M83"
        album = "Hurry Up, We're Dreaming"
        sourceName = "Spotify"
        isPlaying = true
        artwork = Self.gradientArtwork()
        duration = 245
        positionSync = 78
        syncTime = Date()
    }

    private static func gradientArtwork() -> NSImage {
        let size = NSSize(width: 120, height: 120)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colors: [
            NSColor(red: 0.98, green: 0.36, blue: 0.68, alpha: 1),
            NSColor(red: 0.42, green: 0.36, blue: 0.98, alpha: 1)
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 45)
        image.unlockFocus()
        return image
    }

    // MARK: AppleScript helper

    @discardableResult
    private nonisolated static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let output = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return output.stringValue
    }
}

extension NSImage {
    /// Average color of the image, used for the Dynamic Island ambient glow.
    var averageColor: Color? {
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cg = bitmap.cgImage else { return nil }
        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: ci.extent)
        ]), let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(output, toBitmap: &pixel, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return Color(.sRGB,
                     red: Double(pixel[0]) / 255,
                     green: Double(pixel[1]) / 255,
                     blue: Double(pixel[2]) / 255)
    }
}
