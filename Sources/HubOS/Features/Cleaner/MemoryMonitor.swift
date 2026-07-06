import Foundation
import Darwin
import Observation

/// Live physical-memory monitor. Reads real VM statistics from the Mach kernel
/// (`host_statistics64`) — the same numbers Activity Monitor shows — and can run
/// the system `purge` to free file-backed/inactive pages. No cleaning here is
/// snake-oil: the figures are honest and `purge` is Apple's own tool.
@MainActor
@Observable
final class MemoryMonitor {
    static let shared = MemoryMonitor()

    struct Sample {
        var total: UInt64 = 0
        var app: UInt64 = 0
        var wired: UInt64 = 0
        var compressed: UInt64 = 0
        var free: UInt64 = 0
        /// Activity-Monitor-style "used" = app + wired + compressed.
        var used: UInt64 { app + wired + compressed }
        var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    /// Kernel memory-pressure level, mirroring Activity Monitor's colour bar.
    enum Pressure: Int { case normal = 1, warning = 2, critical = 4
        @MainActor var label: String {
            self == .normal ? L(fr: "Normale", en: "Normal")
                : self == .warning ? L(fr: "Élevée", en: "High")
                : L(fr: "Critique", en: "Critical")
        }
    }

    private(set) var sample = Sample()
    private(set) var pressure: Pressure = .normal
    private(set) var isPurging = false
    private(set) var lastFreed: Int64 = 0

    private var timer: Timer?

    private init() {}

    /// Preview-only sample so the Mémoire tab renders realistically off-screen.
    func seedPreview() {
        sample = Sample(total: 16 * 1_073_741_824, app: 7 * 1_073_741_824,
                        wired: 3 * 1_073_741_824, compressed: 2 * 1_073_741_824,
                        free: 4 * 1_073_741_824)
        pressure = .warning
        lastFreed = 0
    }

    // MARK: Polling

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        sample = Self.readSample()
        pressure = Self.readPressure()
    }

    // MARK: Purge

    /// Runs `/usr/sbin/purge` (frees inactive/file-cache pages) and reports how
    /// much the "used" figure dropped. Effects are temporary — the OS refills
    /// caches as needed — so this is framed honestly in the UI.
    func purge() async {
        guard !isPurging, FileManager.default.isExecutableFile(atPath: "/usr/sbin/purge") else { return }
        isPurging = true
        let before = sample.used
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")
            try? p.run()
            p.waitUntilExit()
        }.value
        refresh()
        lastFreed = max(0, Int64(before) - Int64(sample.used))
        isPurging = false
    }

    var purgeAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/sbin/purge")
    }

    // MARK: Kernel reads

    nonisolated private static func readSample() -> Sample {
        let host = mach_host_self()
        var pageSize: vm_size_t = 0
        host_page_size(host, &pageSize)

        var vm = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &vm) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return Sample() }

        let ps = UInt64(pageSize)
        var s = Sample()
        s.total = ProcessInfo.processInfo.physicalMemory
        s.free = (UInt64(vm.free_count) + UInt64(vm.speculative_count)) * ps
        s.wired = UInt64(vm.wire_count) * ps
        s.compressed = UInt64(vm.compressor_page_count) * ps
        // App memory ≈ internal pages minus purgeable, as Activity Monitor reports.
        let internalPages = UInt64(vm.internal_page_count)
        let purgeable = UInt64(vm.purgeable_count)
        s.app = (internalPages > purgeable ? internalPages - purgeable : 0) * ps
        return s
    }

    nonisolated private static func readPressure() -> Pressure {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            return Pressure(rawValue: Int(level)) ?? .normal
        }
        return .normal
    }
}
