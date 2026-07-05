import AppKit
import SwiftUI

/// A non-activating panel that hosts the notch. Never becomes key so it doesn't
/// steal focus; controls still receive clicks when expanded.
final class NotchWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the notch window: pins it under the physical notch and expands/collapses
/// its content on hover.
///
/// The window is kept at a fixed (expanded) size and only its SwiftUI *content*
/// animates — animating an NSWindow frame that hosts an `NSHostingView` throws an
/// "Update Constraints" exception. Click-through is toggled via
/// `ignoresMouseEvents` so the collapsed strip never blocks the desktop.
@MainActor
final class NotchController {
    static let shared = NotchController()

    private var window: NotchWindow?
    private let model = NotchModel()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var flashTimer: Timer?
    private(set) var isEnabled = false

    private init() {}

    // MARK: Lifecycle

    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        NowPlayingMonitor.shared.start()
        BatteryMonitor.shared.start()   // powers the island's charging/low lip
        build()
        startMouseMonitor()
        observeScreens()
    }

    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        stopMouseMonitor()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        window?.orderOut(nil)
        window = nil
        flashTimer?.invalidate(); flashTimer = nil
        model.flash = nil
        NowPlayingMonitor.shared.stop()
        BatteryMonitor.shared.stop()
    }

    /// Pops a brief toast out of the notch (e.g. "Copié"), then clears it. No-op
    /// if the Dynamic Island module is off.
    func showFlash(symbol: String, text: String, tint: Color, duration: TimeInterval = 2.2) {
        guard isEnabled else { return }
        model.flash = IslandFlash(symbol: symbol, text: text, tint: tint)
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.flash = nil }
        }
    }

    // MARK: Window

    private var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.notchMetrics.hasNotch } ?? NSScreen.main
    }

    private func build() {
        guard let screen = notchScreen else { return }
        model.metrics = screen.notchMetrics

        let panel = NotchWindow(
            contentRect: expandedFrame(screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true // collapsed: fully click-through
        panel.contentView = NSHostingView(rootView: NotchView(model: model))
        panel.setFrame(expandedFrame(screen), display: true)
        panel.orderFrontRegardless()
        window = panel
    }

    /// The window is always this size (expanded panel + margin for the shadow
    /// and the grow animation); only the drawn content changes.
    private func expandedFrame(_ screen: NSScreen) -> CGRect {
        let m = screen.notchMetrics
        let w = m.notchWidth + 380 + 80
        let h = m.notchHeight + 132 + 44
        return CGRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
    }

    private func setExpanded(_ expanded: Bool) {
        guard model.expanded != expanded else { return }
        withAnimation(.smooth(duration: 0.3)) { model.expanded = expanded }
        window?.ignoresMouseEvents = !expanded
    }

    // MARK: Dev hooks

    /// Collapses the island when its last expandable activity ends (called by the
    /// view when `expandablePanels` empties), so stopping a task doesn't fall back
    /// to an empty media player.
    func forceCollapse() {
        guard model.expanded else { return }
        setExpanded(false)
    }

    func debugExpand() { setExpanded(true) }
    func debugState() {
        if let w = window {
            print("NOTCH state isVisible=\(w.isVisible) frame=\(w.frame) ignoresMouse=\(w.ignoresMouseEvents)")
        } else { print("NOTCH state: window nil") }
    }

    // MARK: Mouse tracking

    private func startMouseMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluateHover() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            handler(event); return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler)
    }

    private func stopMouseMonitor() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil; globalMonitor = nil
    }

    /// Only media, a Pomodoro or a running timer have an expanded panel; without
    /// one, hovering the notch does nothing (it stays a plain notch).
    private var canExpand: Bool {
        NowPlayingMonitor.shared.hasMedia
            || FocusManager.shared.isActive
            || TimerManager.shared.isActive
    }

    private func evaluateHover() {
        guard let screen = notchScreen else { return }
        let mouse = NSEvent.mouseLocation
        if model.expanded {
            if !expandedFrame(screen).insetBy(dx: -8, dy: -8).contains(mouse) {
                setExpanded(false)
            }
        } else {
            guard canExpand else { return }
            let m = screen.notchMetrics
            let triggerWidth = m.notchWidth + 80
            let trigger = CGRect(x: screen.frame.midX - triggerWidth / 2,
                                 y: screen.frame.maxY - (m.notchHeight + 6),
                                 width: triggerWidth, height: m.notchHeight + 6)
            if trigger.contains(mouse) { setExpanded(true) }
        }
    }

    // MARK: Screens

    private func observeScreens() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let screen = self.notchScreen else { return }
                self.model.metrics = screen.notchMetrics
                self.window?.setFrame(self.expandedFrame(screen), display: true)
            }
        }
    }
}
