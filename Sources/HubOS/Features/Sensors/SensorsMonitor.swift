import Foundation
import Darwin
import Observation

/// Live system load — CPU %, RAM %, load average and uptime — the read-only core
/// of what Stats surfaces. All from the Mach kernel; permission-free, no calls.
@MainActor
@Observable
final class SensorsMonitor {
    static let shared = SensorsMonitor()

    private(set) var cpu: Double = 0            // 0…1 busy fraction
    private(set) var ramFraction: Double = 0    // 0…1 used
    private(set) var ramUsed: UInt64 = 0
    private(set) var ramTotal: UInt64 = 0
    private(set) var load: (Double, Double, Double) = (0, 0, 0)  // 1 / 5 / 15 min
    private(set) var uptime: TimeInterval = 0
    private(set) var bluetooth: [BTDevice] = []

    struct BTDevice: Identifiable {
        let id = UUID()
        let name: String
        let percent: Int
        var symbol: String {
            let l = name.lowercased()
            if l.contains("airpod") { return "airpods" }
            if l.contains("beats") { return "beats.headphones" }
            if l.contains("mouse") || l.contains("magic mouse") { return "magicmouse" }
            if l.contains("keyboard") || l.contains("clavier") { return "keyboard" }
            if l.contains("trackpad") { return "trackpad" }
            if l.contains("controller") || l.contains("manette") { return "gamecontroller" }
            return "cable.connector"
        }
    }

    private let ticker = PeriodicTask()
    private var lastBusy: UInt64 = 0
    private var lastTotal: UInt64 = 0
    private var hasBaseline = false
    private var tickCount = 0

    private init() {}

    func start() {
        sample()
        ticker.start(every: 2) { [weak self] in self?.sample() }
    }
    func stop() { ticker.stop() }

    private func sample() {
        let (busy, total) = Self.cpuTicks()
        if hasBaseline, total > lastTotal {
            cpu = Double(busy - lastBusy) / Double(total - lastTotal)
        }
        lastBusy = busy; lastTotal = total; hasBaseline = true

        let mem = MemoryMonitor.shared
        mem.refresh()
        ramFraction = mem.sample.usedFraction
        ramUsed = mem.sample.used
        ramTotal = mem.sample.total

        var l = [Double](repeating: 0, count: 3)
        getloadavg(&l, 3)
        load = (l[0], l[1], l[2])
        uptime = ProcessInfo.processInfo.systemUptime

        // Bluetooth battery changes slowly and needs a subprocess — poll it every
        // ~20s, not every tick.
        if tickCount % 10 == 0 {
            Task.detached {
                let devices = Self.readBluetooth()
                await MainActor.run { SensorsMonitor.shared.bluetooth = devices }
            }
        }
        tickCount += 1
    }

    /// Battery levels of connected Bluetooth devices, parsed from `ioreg`.
    nonisolated static func readBluetooth() -> [BTDevice] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        p.arguments = ["-r", "-l", "-k", "BatteryPercent"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [] }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        var devices: [BTDevice] = []
        var name = "Bluetooth"
        for raw in out.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let n = quoted(line, key: "\"Product\"") ?? quoted(line, key: "\"BatteryName\"") ?? quoted(line, key: "\"DeviceName\"") {
                name = n
            }
            if line.contains("\"BatteryPercent\""),
               let eq = line.firstIndex(of: "="),
               let pct = Int(line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)) {
                devices.append(BTDevice(name: name, percent: pct))
            }
        }
        return devices
    }

    /// Extracts the value of a `"key" = "value"` ioreg line.
    nonisolated private static func quoted(_ line: String, key: String) -> String? {
        guard line.hasPrefix(key), let eq = line.firstIndex(of: "=") else { return nil }
        let rest = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix("\""), rest.count > 2 else { return nil }
        return String(rest.dropFirst().dropLast())
    }

    /// Cumulative busy / total CPU ticks across all cores.
    nonisolated static func cpuTicks() -> (busy: UInt64, total: UInt64) {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, 0) }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        return (busy, busy + idle)
    }

    static func uptimeString(_ t: TimeInterval) -> String {
        let d = Int(t) / 86400, h = (Int(t) % 86400) / 3600, m = (Int(t) % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    func seedPreview() {
        cpu = 0.34
        ramFraction = 0.71
        ramUsed = 11 * 1_073_741_824
        ramTotal = 16 * 1_073_741_824
        load = (2.1, 1.8, 1.5)
        uptime = 3 * 86400 + 4 * 3600
        bluetooth = [BTDevice(name: "AirPods Pro", percent: 82),
                     BTDevice(name: "Magic Mouse", percent: 47)]
        hasBaseline = true
    }
}
