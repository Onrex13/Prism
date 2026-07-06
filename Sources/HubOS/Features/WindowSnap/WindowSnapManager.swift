import AppKit
import Carbon.HIToolbox
import ApplicationServices
import Observation

/// Window snapping à la Rectangle: moves/resizes the focused window into halves,
/// quarters, thirds, maximize or center — via the Accessibility API (already
/// requested by the app) and global ⌃⌥ hot keys registered while the service is
/// on. Global hot keys avoid the "the panel is focused" problem entirely.
@MainActor
@Observable
final class WindowSnapManager {
    static let shared = WindowSnapManager()

    enum Position: String, CaseIterable, Identifiable {
        case leftHalf, rightHalf, topHalf, bottomHalf
        case topLeft, topRight, bottomLeft, bottomRight
        case leftThird, centerThird, rightThird
        case maximize, center
        var id: String { rawValue }

        /// Target rect within a screen's visible frame (AppKit coords, y-up).
        func frame(in vf: CGRect) -> CGRect {
            let x = vf.minX, y = vf.minY, w = vf.width, h = vf.height
            switch self {
            case .leftHalf:    return CGRect(x: x, y: y, width: w / 2, height: h)
            case .rightHalf:   return CGRect(x: x + w / 2, y: y, width: w / 2, height: h)
            case .topHalf:     return CGRect(x: x, y: y + h / 2, width: w, height: h / 2)
            case .bottomHalf:  return CGRect(x: x, y: y, width: w, height: h / 2)
            case .topLeft:     return CGRect(x: x, y: y + h / 2, width: w / 2, height: h / 2)
            case .topRight:    return CGRect(x: x + w / 2, y: y + h / 2, width: w / 2, height: h / 2)
            case .bottomLeft:  return CGRect(x: x, y: y, width: w / 2, height: h / 2)
            case .bottomRight: return CGRect(x: x + w / 2, y: y, width: w / 2, height: h / 2)
            case .leftThird:   return CGRect(x: x, y: y, width: w / 3, height: h)
            case .centerThird: return CGRect(x: x + w / 3, y: y, width: w / 3, height: h)
            case .rightThird:  return CGRect(x: x + 2 * w / 3, y: y, width: w / 3, height: h)
            case .maximize:    return vf
            case .center:      return CGRect(x: x + w * 0.15, y: y + h * 0.12, width: w * 0.7, height: h * 0.76)
            }
        }
    }

    /// The ⌃⌥ hot keys bound while the service is active.
    private static let bindings: [(key: UInt32, pos: Position, label: String)] = [
        (UInt32(kVK_LeftArrow), .leftHalf, "⌃⌥←"),
        (UInt32(kVK_RightArrow), .rightHalf, "⌃⌥→"),
        (UInt32(kVK_UpArrow), .topHalf, "⌃⌥↑"),
        (UInt32(kVK_DownArrow), .bottomHalf, "⌃⌥↓"),
        (UInt32(kVK_Return), .maximize, "⌃⌥↩"),
        (UInt32(kVK_ANSI_C), .center, "⌃⌥C")
    ]
    static var shortcutHints: [(pos: Position, label: String)] { bindings.map { ($0.pos, $0.label) } }

    private var hotKeys: [GlobalHotKey] = []
    private(set) var isActive = false

    private init() {}

    var accessibilityGranted: Bool { AXIsProcessTrusted() }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active { registerHotKeys() } else { hotKeys.forEach { $0.unregister() }; hotKeys.removeAll() }
    }

    private func registerHotKeys() {
        let mod = UInt32(controlKey | optionKey)
        for b in Self.bindings {
            if let hk = GlobalHotKey(keyCode: b.key, modifiers: mod, action: { [weak self] in self?.snap(b.pos) }) {
                hotKeys.append(hk)
            }
        }
    }

    // MARK: Snapping

    func snap(_ pos: Position) {
        guard AXIsProcessTrusted() else {
            Notifier.shared.error(L(fr: "Accessibilité requise pour déplacer les fenêtres",
                                    en: "Accessibility required to move windows"))
            return
        }
        guard let window = targetWindow(), let screen = NSScreen.main ?? NSScreen.screens.first else {
            Notifier.shared.error(L(fr: "Aucune fenêtre au premier plan", en: "No frontmost window"))
            return
        }
        let target = pos.frame(in: screen.visibleFrame)
        // AppKit (bottom-left) → Accessibility/Quartz (top-left of primary display).
        let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let axRect = CGRect(x: target.minX, y: primaryH - target.maxY, width: target.width, height: target.height)
        setFrame(window, axRect)
    }

    /// The focused window of the frontmost app (never Prism's own panel).
    private func targetWindow() -> AXUIElement? {
        let pid: pid_t
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            pid = front.processIdentifier
        } else {
            // Fallback: whichever app the system reports as AX-focused.
            let system = AXUIElementCreateSystemWide()
            var app: CFTypeRef?
            guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &app) == .success,
                  let appEl = app else { return nil }
            var win: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appEl as! AXUIElement, kAXFocusedWindowAttribute as CFString, &win) == .success else { return nil }
            return (win as! AXUIElement)
        }
        let appEl = AXUIElementCreateApplication(pid)
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &win) == .success else { return nil }
        return (win as! AXUIElement)
    }

    private func setFrame(_ window: AXUIElement, _ rect: CGRect) {
        var origin = rect.origin
        var size = rect.size
        if let posValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        // Re-apply position: some apps clamp origin until they know their new size.
        if let posValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
    }
}
