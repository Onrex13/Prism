import CoreAudio
import Foundation
import Observation

/// FourCharCode 'vmvc' — the device's virtual master volume selector (from the
/// legacy AudioHardwareService API, but the property is readable/settable
/// straight on the AudioObject on modern macOS). Defined inline so we don't
/// depend on the deprecated AudioToolbox constant.
private let kVirtualMainVolume: AudioObjectPropertySelector = 0x766D_7663

/// Enumerates CoreAudio devices and switches the system default output/input —
/// the same thing the Sound menu-bar item does, but one click away. Also exposes
/// the default output's master volume. All standard, public CoreAudio APIs.
@MainActor
@Observable
final class AudioManager {
    static let shared = AudioManager()

    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let uid: String
        let name: String
        let symbol: String
    }

    private(set) var outputs: [Device] = []
    private(set) var inputs: [Device] = []
    private(set) var defaultOutputID: AudioDeviceID = 0
    private(set) var defaultInputID: AudioDeviceID = 0

    /// Master output volume 0…1 over a private backing (clamp in the setter
    /// without an `@Observable` didSet re-entrancy loop).
    private var storedVolume: Float = 0
    var volume: Float {
        get { storedVolume }
        set {
            let v = newValue.clamped(to: 0...1)
            storedVolume = v
            Self.setOutputVolume(defaultOutputID, v)
        }
    }
    private(set) var volumeAvailable = false

    private init() {}

    // MARK: Refresh

    func refresh() {
        let all = Self.deviceIDs()
        outputs = all.compactMap { Self.device($0, scope: kAudioObjectPropertyScopeOutput) }
        inputs = all.compactMap { Self.device($0, scope: kAudioObjectPropertyScopeInput) }
        defaultOutputID = Self.defaultDevice(output: true)
        defaultInputID = Self.defaultDevice(output: false)
        let vol = Self.outputVolume(defaultOutputID)
        volumeAvailable = vol != nil
        storedVolume = vol ?? 0
    }

    func selectOutput(_ d: Device) {
        let status = Self.setDefault(d.id, output: true)
        refresh()
        if status != noErr || defaultOutputID != d.id {
            Notifier.shared.error(L(fr: "Impossible de basculer sur \(d.name)",
                                    en: "Couldn't switch to \(d.name)"))
        }
    }

    func selectInput(_ d: Device) {
        let status = Self.setDefault(d.id, output: false)
        refresh()
        if status != noErr || defaultInputID != d.id {
            Notifier.shared.error(L(fr: "Impossible de basculer sur \(d.name)",
                                    en: "Couldn't switch to \(d.name)"))
        }
    }

    /// Preview-only device list.
    func seedPreview() {
        outputs = [
            Device(id: 1, uid: "a", name: "Haut-parleurs MacBook Pro", symbol: "laptopcomputer"),
            Device(id: 2, uid: "b", name: "AirPods Pro", symbol: "airpods.pro"),
            Device(id: 3, uid: "c", name: "Studio Display", symbol: "display")
        ]
        inputs = [
            Device(id: 4, uid: "d", name: "Micro MacBook Pro", symbol: "laptopcomputer"),
            Device(id: 5, uid: "b", name: "AirPods Pro", symbol: "airpods.pro")
        ]
        defaultOutputID = 2; defaultInputID = 4
        volumeAvailable = true; storedVolume = 0.65
    }

    // MARK: CoreAudio (nonisolated helpers)

    nonisolated private static let system = AudioObjectID(kAudioObjectSystemObject)

    nonisolated private static func address(_ selector: AudioObjectPropertySelector,
                                            _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    nonisolated private static func deviceIDs() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// Builds a `Device` only if the device has streams in the given scope.
    nonisolated private static func device(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Device? {
        var streamsAddr = address(kAudioDevicePropertyStreams, scope)
        var streamSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &streamsAddr, 0, nil, &streamSize) == noErr,
              streamSize > 0 else { return nil }

        // CFString properties return a +1 reference — read into an Unmanaged and
        // take ownership so we neither leak nor mis-cast a raw pointer.
        var nameAddr = address(kAudioObjectPropertyName)
        var nameRef: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, &nameRef) == noErr,
              let name = nameRef?.takeRetainedValue() as String? else { return nil }

        var uidAddr = address(kAudioDevicePropertyDeviceUID)
        var uidRef: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        AudioObjectGetPropertyData(id, &uidAddr, 0, nil, &uidSize, &uidRef)
        let uid = (uidRef?.takeRetainedValue() as String?) ?? ""

        return Device(id: id, uid: uid, name: name, symbol: symbol(for: name))
    }

    nonisolated private static func symbol(for name: String) -> String {
        let l = name.lowercased()
        if l.contains("airpods") { return "airpods.pro" }
        if l.contains("headphone") || l.contains("casque") || l.contains("écouteur") { return "headphones" }
        if l.contains("display") || l.contains("écran") || l.contains("monitor") { return "display" }
        if l.contains("macbook") || l.contains("built-in") || l.contains("intégré") || l.contains("interne") { return "laptopcomputer" }
        if l.contains("micro") || l.contains("mic") { return "mic.fill" }
        if l.contains("bluetooth") { return "wave.3.right" }
        return "hifispeaker.fill"
    }

    nonisolated private static func defaultDevice(output: Bool) -> AudioDeviceID {
        var addr = address(output ? kAudioHardwarePropertyDefaultOutputDevice
                                  : kAudioHardwarePropertyDefaultInputDevice)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &id)
        return id
    }

    @discardableResult
    nonisolated private static func setDefault(_ id: AudioDeviceID, output: Bool) -> OSStatus {
        var addr = address(output ? kAudioHardwarePropertyDefaultOutputDevice
                                  : kAudioHardwarePropertyDefaultInputDevice)
        var dev = id
        return AudioObjectSetPropertyData(system, &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &dev)
    }

    nonisolated private static func outputVolume(_ id: AudioDeviceID) -> Float? {
        guard id != 0 else { return nil }
        var addr = address(kVirtualMainVolume, kAudioObjectPropertyScopeOutput)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &vol) == noErr else { return nil }
        return vol
    }

    nonisolated private static func setOutputVolume(_ id: AudioDeviceID, _ value: Float) {
        guard id != 0 else { return }
        var addr = address(kVirtualMainVolume, kAudioObjectPropertyScopeOutput)
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(id, &addr, &settable) == noErr, settable.boolValue else { return }
        var vol = Float32(value)
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
    }
}
