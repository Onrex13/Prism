import SwiftUI
import AppKit

/// Deterministic, privacy-respecting UI capture. When launched with `--preview`,
/// HubOS renders a target view inside a normal window over a desktop-like
/// backdrop (so Liquid Glass has something to refract), screenshots ONLY its own
/// window by id, and exits. Never captures the rest of the screen.
enum PreviewConfig {
    static var isPreview: Bool { CommandLine.arguments.contains("--preview") }
    static var target: String { ProcessInfo.processInfo.environment["HUBOS_PREVIEW_TARGET"] ?? "hub" }
    static var outputPath: String {
        ProcessInfo.processInfo.environment["HUBOS_PREVIEW_OUT"] ?? "/tmp/hubos_preview.png"
    }
    /// Makes the brightness UI render in its active (amber) styling for capture
    /// without actually engaging the display boost.
    static var forceActiveBrightness: Bool { isPreview && target == "brightness" }
    /// Lets the Cleaner preview open directly on a specific tab.
    static var forcedCleanerTab: String? {
        switch target {
        case "cleanermem": return "memory"
        case "cleanersec": return "security"
        default: return nil
        }
    }
}

struct PreviewHost: View {
    @State private var hub = HubState.shared

    private var isBar: Bool { PreviewConfig.target == "quickpaste" }
    private var isNotch: Bool {
        ["notch", "notchidle", "notchfocus", "notchfocusbig",
         "notchboth", "notchbothbig", "notchcaffeine",
         "notchtimer", "notchtimerbig", "notchbattery", "notchflash",
         "notchcaffeineinf"].contains(PreviewConfig.target)
    }
    private var isShelf: Bool { PreviewConfig.target == "shelf" }
    @State private var notchModel = NotchModel()
    @State private var shelfModel = ShelfModel()

    /// A near-black wallpaper to stress-test glass on dark desktops (the worst
    /// case for translucent panels). Toggle with `HUBOS_PREVIEW_DARK=1`.
    private var darkWallpaper: Bool {
        ProcessInfo.processInfo.environment["HUBOS_PREVIEW_DARK"] == "1"
    }

    var body: some View {
        ZStack {
            // Simulated desktop wallpaper so glass surfaces read realistically.
            LinearGradient(
                colors: darkWallpaper
                    ? [Color(red: 0.03, green: 0.03, blue: 0.05),
                       Color(red: 0.05, green: 0.05, blue: 0.07),
                       Color(red: 0.02, green: 0.02, blue: 0.03)]
                    : [Color(red: 0.09, green: 0.10, blue: 0.20),
                       Color(red: 0.20, green: 0.13, blue: 0.30),
                       Color(red: 0.32, green: 0.15, blue: 0.34)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            content
        }
        // Dev aid: draw where the physical notch sits so island alignment can be
        // verified (content must never slip under it). Toggle with =1.
        .overlay(alignment: .top) {
            if isNotch, ProcessInfo.processInfo.environment["HUBOS_PREVIEW_NOTCHMARK"] == "1" {
                Rectangle().fill(.red.opacity(0.4))
                    .frame(width: notchModel.metrics.notchWidth, height: notchModel.metrics.notchHeight)
            }
        }
        .frame(width: isBar ? 1000 : (isNotch ? 760 : (isShelf ? 420 : 680)),
               height: isBar ? 332 : (isNotch ? 430 : (isShelf ? 540 : 720)))
        .environment(hub)
        .onAppear(perform: configureTarget)
    }

    @ViewBuilder
    private var content: some View {
        if isNotch {
            VStack(spacing: 0) {
                NotchView(model: notchModel)
                    .frame(width: notchModel.metrics.notchWidth + 380,
                           height: notchModel.metrics.notchHeight + 168)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        } else if isShelf {
            ShelfView(model: shelfModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isBar {
            QuickPasteBar(controller: previewController, onActivate: { _ in })
        } else {
            HubPanel()
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 40, y: 20)
        }
    }

    @State private var previewController = QuickPasteController()

    private func configureTarget() {
        switch PreviewConfig.target {
        case "clipboard":
            ClipboardStore.shared.seedPreviewData()
            hub.openModule = .clipboard
        case "quickpaste":
            ClipboardStore.shared.seedPreviewData()
            previewController.selectedIndex = 1
        case "brightness":
            hub.openModule = .brightness
        case "caffeine":
            CaffeineManager.shared.duration = 30
            hub.setEnabled(.caffeine, true)
            hub.openModule = .caffeine
        case "notch", "notchidle":
            NowPlayingMonitor.shared.seedPreview()
            notchModel.expanded = (PreviewConfig.target == "notch")
            notchModel.metrics = NotchMetrics(hasNotch: true, notchWidth: 200, notchHeight: 34)
        case "notchfocus", "notchfocusbig":
            // Focus live-activity (no media): idle shows the countdown, expanded
            // shows the full Pomodoro panel.
            FocusManager.shared.seedPreview()
            notchModel.expanded = (PreviewConfig.target == "notchfocusbig")
            notchModel.metrics = NotchMetrics(hasNotch: true, notchWidth: 200, notchHeight: 34)
        case "notchboth", "notchbothbig":
            // Media AND a Pomodoro live at once → both lips, tab switch when open.
            NowPlayingMonitor.shared.seedPreview()
            FocusManager.shared.seedPreview()
            notchModel.expanded = (PreviewConfig.target == "notchbothbig")
            notchModel.islandTab = .pomodoro
            notchModel.metrics = NotchMetrics(hasNotch: true, notchWidth: 200, notchHeight: 34)
        case "notchcaffeine":
            // Keep-awake only: a cup indicator in the left lip.
            CaffeineManager.shared.duration = 30
            hub.setEnabled(.caffeine, true)
            notchModel.expanded = false
            notchModel.metrics = NotchMetrics(hasNotch: true, notchWidth: 200, notchHeight: 34)
        case "notchcaffeineinf":
            // Infinite keep-awake: only the cup (no time) — the clipping-repro case.
            CaffeineManager.shared.duration = nil
            hub.setEnabled(.caffeine, true)
            notchModel.expanded = false
            notchModel.metrics = NotchMetrics(hasNotch: true, notchWidth: 200, notchHeight: 34)
        case "notchtimer", "notchtimerbig":
            TimerManager.shared.seedPreview()
            notchModel.expanded = (PreviewConfig.target == "notchtimerbig")
            notchModel.islandTab = .timer
            notchModel.metrics = NotchMetrics(hasNotch: true, notchWidth: 200, notchHeight: 34)
        case "notchbattery":
            BatteryMonitor.shared.seedPreview()   // 72%, charging
            notchModel.expanded = false
            notchModel.metrics = NotchMetrics(hasNotch: true, notchWidth: 200, notchHeight: 34)
        case "notchflash":
            notchModel.flash = IslandFlash(symbol: "checkmark.circle.fill",
                                           text: "Copié · glassEffect(.re…", tint: Theme.green)
            notchModel.expanded = false
            notchModel.metrics = NotchMetrics(hasNotch: true, notchWidth: 200, notchHeight: 34)
        case "shelf":
            ShelfStore.shared.seedPreview()
            shelfModel.revealed = true
        case "battery":
            BatteryMonitor.shared.seedPreview()
            hub.openModule = .battery
        case "audio":
            AudioManager.shared.seedPreview()
            hub.openModule = .audio
        case "focus":
            FocusManager.shared.seedPreview()
            hub.openModule = .focus
        case "focusidle":
            hub.openModule = .focus            // idle → shows the settings card
        case "timer":
            TimerManager.shared.seedPreview()
            hub.openModule = .timer
        case "settings":
            UpdateManager.shared.reset()
            hub.showingSettings = true
        case "colorpicker":
            ColorPickerManager.shared.seedPreview()
            hub.openModule = .colorpicker
        case "cleaner":
            CleanerScanner.shared.seedPreview()
            hub.openModule = .cleaner
        case "cleanermem":
            MemoryMonitor.shared.seedPreview()
            hub.openModule = .cleaner
        case "cleanersec":
            SecurityAuditor.shared.seedPreview()
            hub.openModule = .cleaner
        default:
            break
        }
    }
}

@MainActor
func capturePreview(window: NSWindow) {
    let id = CGWindowID(window.windowNumber)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-o", "-x", "-l", String(id), PreviewConfig.outputPath]
    try? p.run()
    p.waitUntilExit()
    NSApp.terminate(nil)
}
