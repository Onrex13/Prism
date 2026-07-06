import Foundation
import IOKit
import IOKit.ps
import Observation

/// Reads real battery + power-adapter telemetry from IOKit (Power Sources API
/// and the `AppleSmartBattery` service). Read-only: HubOS never writes SMC/PM
/// state, so nothing here can harm the battery. Gracefully reports "no battery"
/// on desktops.
@MainActor
@Observable
final class BatteryMonitor {
    static let shared = BatteryMonitor()

    struct Info {
        var hasBattery = false
        var percent = 0
        var charging = false
        var pluggedIn = false
        var fullyCharged = false
        var timeRemaining: Int?     // minutes; nil = calculating / unknown
        var cycleCount: Int?
        var healthPercent: Int?     // fullChargeCapacity / designCapacity
        var condition: String?      // "Good" / "Fair" / "Poor"
        var adapterWatts: Int?
        var voltage: Double?        // Volts

        @MainActor var stateText: String {
            if !hasBattery { return L(fr: "Aucune batterie", en: "No battery") }
            if fullyCharged || (pluggedIn && percent >= 100) { return L(fr: "Chargée", en: "Charged") }
            if charging { return L(fr: "En charge", en: "Charging") }
            if pluggedIn { return L(fr: "Branchée", en: "Plugged in") }
            return L(fr: "Sur batterie", en: "On battery")
        }
    }

    private(set) var info = Info()
    private var timer: Timer?
    /// Ref-counted so the battery detail view and the Dynamic Island can both
    /// keep polling alive without one's `stop()` cutting off the other.
    private var subscribers = 0

    private init() {}

    func start() {
        subscribers += 1
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        timer?.invalidate(); timer = nil
    }
    func refresh() { info = Self.read() }

    /// Preview-only realistic values.
    func seedPreview() {
        info = Info(hasBattery: true, percent: 72, charging: true, pluggedIn: true,
                    fullyCharged: false, timeRemaining: 48, cycleCount: 142,
                    healthPercent: 94, condition: "Good", adapterWatts: 70, voltage: 12.6)
    }

    // MARK: IOKit read (nonisolated — pure C API)

    nonisolated private static func read() -> Info {
        var out = Info()

        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                        as? [String: Any] else { continue }
                if (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType { out.hasBattery = true }
                if let cur = desc[kIOPSCurrentCapacityKey] as? Int { out.percent = cur }
                if let charging = desc[kIOPSIsChargingKey] as? Bool { out.charging = charging }
                if let charged = desc[kIOPSIsChargedKey] as? Bool { out.fullyCharged = charged }
                out.pluggedIn = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
                out.condition = desc[kIOPSBatteryHealthKey] as? String
                let tte = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
                let ttf = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1
                out.timeRemaining = out.charging ? (ttf > 0 ? ttf : nil) : (tte > 0 ? tte : nil)
            }
        }

        // Battery health / cycles from the AppleSmartBattery IORegistry node. On
        // Apple Silicon the real mAh capacities live in the nested `BatteryData`
        // dict (top-level `MaxCapacity` is a percentage, not mAh — do not use it).
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            func prop(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue()
            }
            out.cycleCount = prop("CycleCount") as? Int
            if let mv = prop("AppleRawBatteryVoltage") as? Int { out.voltage = Double(mv) / 1000.0 }
            if let data = prop("BatteryData") as? [String: Any],
               let full = data["FullChargeCapacity"] as? Int,
               let design = data["DesignCapacity"] as? Int, design > 0 {
                out.healthPercent = min(100, Int((Double(full) / Double(design) * 100).rounded()))
            }
            // The Power Sources API rarely fills condition on Apple Silicon; derive
            // an honest label from measured health when it's missing.
            if out.condition == nil, let h = out.healthPercent {
                out.condition = h >= 80 ? "Good" : (h >= 50 ? "Fair" : "Poor")
            }
        }

        if let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            out.adapterWatts = adapter[kIOPSPowerAdapterWattsKey] as? Int
        }

        return out
    }
}
