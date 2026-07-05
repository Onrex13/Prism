import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - Controller

/// Observable state for the floating quick-paste bar: the live filter query and
/// the current selection. Results are derived from the shared clipboard store.
@MainActor
@Observable
final class QuickPasteController {
    var query: String = ""
    var selectedIndex: Int = 0

    var results: [ClipboardItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty
            ? ClipboardStore.shared.items
            : ClipboardStore.shared.items.filter {
                $0.title.lowercased().contains(q) || $0.text.lowercased().contains(q)
            }
        return Array(base.prefix(60))
    }

    var selected: ClipboardItem? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    func reset() { query = ""; selectedIndex = 0 }
    func moveLeft() { selectedIndex = max(0, selectedIndex - 1) }
    func moveRight() { selectedIndex = min(max(0, results.count - 1), selectedIndex + 1) }
    func append(_ s: String) { query += s; selectedIndex = 0 }
    func backspace() { if !query.isEmpty { query.removeLast(); selectedIndex = 0 } }
}

// MARK: - Window

/// Borderless, non-activating panel that can still become key to receive key
/// events. Swallows handled keys (no system beep) by not forwarding to super.
final class QuickPasteWindow: NSPanel {
    var onKey: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        onKey?(event)
    }
}

// MARK: - Manager

/// Owns the global hot key, the floating panel, and the paste flow.
@MainActor
final class QuickPasteManager {
    static let shared = QuickPasteManager()

    private var hotKey: GlobalHotKey?
    private var window: QuickPasteWindow?
    private let controller = QuickPasteController()
    private var targetApp: NSRunningApplication?
    private(set) var isVisible = false

    private init() {}

    func enable() {
        guard hotKey == nil else { return }
        hotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_V),
                              modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.toggle()
        }
    }

    func disable() {
        hotKey?.unregister()
        hotKey = nil
        hide()
    }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        targetApp = NSWorkspace.shared.frontmostApplication
        controller.reset()
        let panel = window ?? makeWindow()
        window = panel
        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
    }

    func hide() {
        window?.orderOut(nil)
        isVisible = false
    }

    private func makeWindow() -> QuickPasteWindow {
        let panel = QuickPasteWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 332),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The rounded panel provides its own shape-hugging SwiftUI shadow; a
        // window shadow would ghost a rectangle behind it.
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.onKey = { [weak self] event in self?.handleKey(event) }

        let root = QuickPasteBar(
            controller: controller,
            onActivate: { [weak self] index in
                self?.controller.selectedIndex = index
                self?.commit()
            }
        )
        panel.contentView = NSHostingView(rootView: root)
        return panel
    }

    private func position(_ panel: QuickPasteWindow) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let width = min(CGFloat(1000), visible.width - 60)
        let height: CGFloat = 332
        panel.setFrame(
            NSRect(x: visible.midX - width / 2,
                   y: visible.minY + 96,
                   width: width, height: height),
            display: true
        )
    }

    private func handleKey(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_LeftArrow:                     controller.moveLeft()
        case kVK_RightArrow:                    controller.moveRight()
        case kVK_Return, kVK_ANSI_KeypadEnter:  commit()
        case kVK_Escape:                        hide()
        case kVK_Delete:                        controller.backspace()
        default:
            guard !event.modifierFlags.contains(.command),
                  let chars = event.charactersIgnoringModifiers, chars.count == 1,
                  let scalar = chars.unicodeScalars.first, scalar.value >= 32 else { return }
            controller.append(chars)
        }
    }

    private func commit() {
        guard let item = controller.selected else { hide(); return }
        hide()
        ClipboardStore.shared.copy(item)
        targetApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            PasteService.paste()
        }
    }
}

// MARK: - Paste service

/// Synthesises ⌘V into the front app. Requires Accessibility permission; if it
/// isn't granted, the item is already on the pasteboard so the user can paste
/// manually, and we prompt for permission once.
enum PasteService {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        // Literal of `kAXTrustedCheckOptionPrompt` — avoids referencing the
        // non-concurrency-safe global constant under Swift 6.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func paste() {
        guard isTrusted else {
            requestAccessibility()
            return
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
