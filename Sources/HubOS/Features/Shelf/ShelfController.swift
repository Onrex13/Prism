import AppKit
import SwiftUI

/// A non-activating panel hosting the right-edge shelf.
final class ShelfWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the shelf window docked to the right edge and reveals it on hover.
/// The window stays a fixed size; transparent areas are click-through via the
/// hosting view's hit-testing, and only the tab/panel receive events.
@MainActor
final class ShelfController {
    static let shared = ShelfController()

    private var window: ShelfWindow?
    private let model = ShelfModel()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var holdUntil: Date?
    private var holdTimer: Timer?
    private(set) var isEnabled = false

    private let width: CGFloat = 320
    private let height: CGFloat = 480

    private init() {}

    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
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
    }

    func debugReveal(_ value: Bool) { model.revealed = value }

    /// Keeps the shelf open for a moment after a drop, then collapses if the
    /// pointer has left. Called by `ShelfView` when an item is dropped.
    func holdOpen() {
        model.revealed = true
        holdUntil = Date().addingTimeInterval(2.0)
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.holdUntil = nil
                self.collapseIfPointerOutside()
            }
        }
    }

    private func collapseIfPointerOutside() {
        guard let screen = shelfScreen else { return }
        if !frame(screen).insetBy(dx: -12, dy: -12).contains(NSEvent.mouseLocation) {
            model.revealed = false
        }
    }

    private var shelfScreen: NSScreen? { NSScreen.main }

    private func frame(_ screen: NSScreen) -> CGRect {
        CGRect(x: screen.frame.maxX - width,
               y: screen.frame.midY - height / 2,
               width: width, height: height)
    }

    private func build() {
        guard let screen = shelfScreen else { return }
        let panel = ShelfWindow(
            contentRect: frame(screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: ShelfView(model: model))
        panel.setFrame(frame(screen), display: true)
        panel.orderFrontRegardless()
        window = panel
    }

    // MARK: Hover reveal

    private func startMouseMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluateHover() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { e in handler(e); return e }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler)
    }

    private func stopMouseMonitor() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil; globalMonitor = nil
    }

    private func evaluateHover() {
        guard let screen = shelfScreen else { return }
        let mouse = NSEvent.mouseLocation
        if model.revealed {
            // Respect the post-drop hold window.
            if let holdUntil, Date() < holdUntil { return }
            if !frame(screen).insetBy(dx: -12, dy: -12).contains(mouse) {
                model.revealed = false
            }
        } else {
            let tab = CGRect(x: screen.frame.maxX - 32,
                             y: screen.frame.midY - 64,
                             width: 32, height: 128)
            if tab.contains(mouse) { model.revealed = true }
        }
    }

    private func observeScreens() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let screen = self.shelfScreen else { return }
                self.window?.setFrame(self.frame(screen), display: true)
            }
        }
    }
}
