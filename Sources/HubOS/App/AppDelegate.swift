import AppKit
import SwiftUI

/// App-level lifecycle glue. HubOS is a menu-bar agent, so it must not show a
/// Dock icon or a main window — `.accessory` activation policy enforces that
/// even if the Info.plist `LSUIElement` flag is ever missed.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if PreviewConfig.isPreview {
            startPreviewCapture()
        } else if ProcessInfo.processInfo.environment["HUBOS_SELFTEST"] == "brightness" {
            runBrightnessSelfTest()
        } else if let st = ProcessInfo.processInfo.environment["HUBOS_SELFTEST"], st == "notch" || st == "notchidle" {
            runNotchSelfTest(expand: st == "notch")
        } else if ProcessInfo.processInfo.environment["HUBOS_SELFTEST"] == "cleaner" {
            NSApp.setActivationPolicy(.accessory)
            setbuf(stdout, nil)
            Task { @MainActor in
                await CleanerScanner.shared.scan()
                for c in CleanerScanner.shared.categories {
                    print("CLEANER \(c.name): \(ByteCountFormatter.string(fromByteCount: c.size, countStyle: .file))")
                }
                print("CLEANER TOTAL: \(ByteCountFormatter.string(fromByteCount: CleanerScanner.shared.totalReclaimable, countStyle: .file))")
                NSApp.terminate(nil)
            }
        } else if ProcessInfo.processInfo.environment["HUBOS_SELFTEST"] == "focus" {
            NSApp.setActivationPolicy(.accessory)
            setbuf(stdout, nil)
            let f = FocusManager.shared
            f.reset()
            print("SELFTEST focus start: phase=\(f.phase.title) dots=\(f.dotsFilled)")
            for n in 1...8 {
                f.skip()
                print("SELFTEST focus after skip \(n): phase=\(f.phase.title) completed=\(f.completedFocus) dots=\(f.dotsFilled)")
            }
            f.reset()
            NSApp.terminate(nil)
        } else if ProcessInfo.processInfo.environment["HUBOS_SELFTEST"] == "audio" {
            NSApp.setActivationPolicy(.accessory)
            setbuf(stdout, nil)
            let a = AudioManager.shared
            a.refresh()
            print("SELFTEST audio outputs (\(a.outputs.count)):")
            for d in a.outputs { print("  \(d.id == a.defaultOutputID ? "▶︎" : " ") \(d.name)") }
            print("SELFTEST audio inputs (\(a.inputs.count)):")
            for d in a.inputs { print("  \(d.id == a.defaultInputID ? "▶︎" : " ") \(d.name)") }
            print("SELFTEST audio volume=\(a.volumeAvailable ? String(format: "%.0f%%", a.volume*100) : "n/a")")
            NSApp.terminate(nil)
        } else if ProcessInfo.processInfo.environment["HUBOS_SELFTEST"] == "battery" {
            NSApp.setActivationPolicy(.accessory)
            setbuf(stdout, nil)
            let b = BatteryMonitor.shared
            b.refresh()
            let i = b.info
            print("SELFTEST battery hasBattery=\(i.hasBattery) percent=\(i.percent)% state=\(i.stateText) charging=\(i.charging) plugged=\(i.pluggedIn)")
            print("SELFTEST battery health=\(i.healthPercent.map { "\($0)%" } ?? "—") cycles=\(i.cycleCount.map(String.init) ?? "—") condition=\(i.condition ?? "—") adapter=\(i.adapterWatts.map { "\($0)W" } ?? "—") voltage=\(i.voltage.map { String(format: "%.2fV", $0) } ?? "—")")
            print("SELFTEST battery timeRemaining=\(i.timeRemaining.map { "\($0)min" } ?? "—")")
            NSApp.terminate(nil)
        } else if ProcessInfo.processInfo.environment["HUBOS_SELFTEST"] == "memory" {
            NSApp.setActivationPolicy(.accessory)
            setbuf(stdout, nil)
            let m = MemoryMonitor.shared
            m.refresh()
            func f(_ v: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .memory) }
            print("SELFTEST memory total=\(f(m.sample.total)) used=\(f(m.sample.used)) (\(Int(m.sample.usedFraction*100))%)")
            print("SELFTEST memory app=\(f(m.sample.app)) wired=\(f(m.sample.wired)) compressed=\(f(m.sample.compressed)) free=\(f(m.sample.free))")
            print("SELFTEST memory pressure=\(m.pressure.label) purgeAvailable=\(m.purgeAvailable)")
            NSApp.terminate(nil)
        } else if ProcessInfo.processInfo.environment["HUBOS_SELFTEST"] == "security" {
            NSApp.setActivationPolicy(.accessory)
            setbuf(stdout, nil)
            Task { @MainActor in
                await SecurityAuditor.shared.scan()
                print("SELFTEST security: \(SecurityAuditor.shared.findings.count) items, \(SecurityAuditor.shared.flaggedCount) flagged, \(SecurityAuditor.shared.adwareCount) adware")
                for finding in SecurityAuditor.shared.findings.prefix(12) {
                    print("  [\(finding.severity.label)] \(finding.name) — \(finding.scope) — signer: \(finding.signer ?? "—")")
                }
                NSApp.terminate(nil)
            }
        } else if ProcessInfo.processInfo.environment["HUBOS_SELFTEST"] == "network" {
            NSApp.setActivationPolicy(.accessory)
            setbuf(stdout, nil)
            let (name, ip) = NetworkMonitor.primaryInterface()
            print("SELFTEST network interface=\(name) ip=\(ip)")
            let a = NetworkMonitor.counters()
            print("SELFTEST network counters#1 rx=\(a.rx) tx=\(a.tx)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let b = NetworkMonitor.counters()
                print("SELFTEST network counters#2 rx=\(b.rx) tx=\(b.tx)")
                print("SELFTEST network rate down=\(NetworkMonitor.rate(b.rx - a.rx)) up=\(NetworkMonitor.rate(b.tx - a.tx))")
                NSApp.terminate(nil)
            }
        } else if ProcessInfo.processInfo.environment["HUBOS_SELFTEST"] == "caffeine" {
            NSApp.setActivationPolicy(.accessory)
            setbuf(stdout, nil)
            print("SELFTEST caffeine: asserting (display mode)…")
            CaffeineManager.shared.mode = .display
            CaffeineManager.shared.setActive(true)
            print("SELFTEST caffeine: isActive=\(CaffeineManager.shared.isActive) — check `pmset -g assertions`")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                CaffeineManager.shared.setActive(false)
                print("SELFTEST caffeine: released")
                NSApp.terminate(nil)
            }
        } else if ProcessInfo.processInfo.environment["HUBOS_SELFTEST"] == "shelf" {
            NSApp.setActivationPolicy(.accessory)
            ShelfStore.shared.seedPreview()
            ShelfController.shared.enable()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ShelfController.shared.debugReveal(true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { NSApp.terminate(nil) }
        } else {
            NSApp.setActivationPolicy(.accessory)
            HubState.shared.startEnabledServices()
        }
    }

    /// Dev-only: engages the EDR boost briefly and logs the display's EDR
    /// headroom before/after to prove the technique works, then exits.
    @MainActor
    private func runBrightnessSelfTest() {
        NSApp.setActivationPolicy(.accessory)
        setbuf(stdout, nil)
        func edr() -> CGFloat { NSScreen.main?.maximumExtendedDynamicRangeColorComponentValue ?? -1 }
        func potential() -> CGFloat { NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? -1 }
        print("SELFTEST supportsEDR=\(BrightnessManager.shared.isSupported) potential=\(potential()) maxFactor=\(BrightnessManager.shared.maxFactor)")
        print("SELFTEST EDR before = \(edr())")
        BrightnessManager.shared.intensity = 0.6
        print("SELFTEST activating…")
        BrightnessManager.shared.setActive(true)
        print("SELFTEST activated, windows up; scheduling check")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            print("SELFTEST EDR after  = \(edr())  factor=\(BrightnessManager.shared.currentFactor)")
            BrightnessManager.shared.setActive(false)
            print("SELFTEST done, boost disabled")
            NSApp.terminate(nil)
        }
    }

    /// Dev-only: shows the notch with a demo track, forces it open, then exits.
    @MainActor
    private func runNotchSelfTest(expand: Bool) {
        NSApp.setActivationPolicy(.accessory)
        NowPlayingMonitor.shared.seedPreview()
        NotchController.shared.enable()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NowPlayingMonitor.shared.seedPreview()
            if expand { NotchController.shared.debugExpand() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            NSApp.terminate(nil)
        }
    }

    /// Builds a borderless window hosting the preview target, screenshots just
    /// that window after it renders, then exits.
    @MainActor
    private func startPreviewCapture() {
        NSApp.setActivationPolicy(.regular)
        let host = NSHostingView(rootView: PreviewHost())
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 720),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.contentView = host
        win.isOpaque = false
        win.backgroundColor = .clear
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow = win

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            capturePreview(window: win)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
