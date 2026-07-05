import Carbon.HIToolbox
import AppKit

/// A registered system-wide hot key backed by Carbon's `RegisterEventHotKey`.
/// Detection works without Accessibility permission. Callbacks fire on the main
/// thread (Carbon delivers hot-key events on the main event dispatcher).
@MainActor
final class GlobalHotKey {
    // Handlers are keyed by hot-key id. Accessed only on the main thread.
    nonisolated(unsafe) private static var handlers: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) private static var nextID: UInt32 = 1
    nonisolated(unsafe) private static var handlerInstalled = false

    private let id: UInt32
    private var ref: EventHotKeyRef?

    /// `keyCode` is a virtual key code (e.g. `kVK_ANSI_V`); `modifiers` is a
    /// Carbon modifier mask (e.g. `cmdKey | shiftKey`).
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        Self.installHandlerIfNeeded()
        id = Self.nextID
        Self.nextID += 1
        Self.handlers[id] = action

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x4855_4253 /* 'HUBS' */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetEventDispatcherTarget(), 0, &hotKeyRef)
        guard status == noErr, let hotKeyRef else {
            Self.handlers[id] = nil
            return nil
        }
        ref = hotKeyRef
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            MainActor.assumeIsolated {
                GlobalHotKey.handlers[hkID.id]?()
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
