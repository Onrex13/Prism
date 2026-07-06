import Foundation
import Darwin
import Observation

/// Live network throughput monitor. Reads per-interface byte counters from the
/// kernel routing table (`NET_RT_IFLIST2`) once a second and derives the up/down
/// rate — the same source `nettop`/iStat use. Also surfaces the primary local
/// IPv4. Fully local, no permission, no network calls.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var downBytesPerSec: UInt64 = 0
    private(set) var upBytesPerSec: UInt64 = 0
    private(set) var localIP = "—"
    private(set) var interfaceName = "—"

    private let ticker = PeriodicTask()
    private var lastRx: UInt64 = 0
    private var lastTx: UInt64 = 0
    private var hasBaseline = false

    private init() {}

    func start() {
        refreshInterface()
        sample()                      // establish the baseline counters
        ticker.start(every: 1) { [weak self] in self?.sample() }
    }

    func stop() { ticker.stop() }

    private func sample() {
        let (rx, tx) = Self.counters()
        if hasBaseline {
            // Counters are monotonic; guard against wraps/interface resets.
            downBytesPerSec = rx >= lastRx ? rx - lastRx : 0
            upBytesPerSec = tx >= lastTx ? tx - lastTx : 0
        }
        lastRx = rx; lastTx = tx; hasBaseline = true
    }

    func refreshInterface() {
        let (name, ip) = Self.primaryInterface()
        interfaceName = name
        localIP = ip
    }

    /// A compact rate like "3,4 Mo/s".
    static func rate(_ bytesPerSec: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSec), countStyle: .binary) + "/s"
    }

    // MARK: Kernel reads

    /// Total received/transmitted bytes across all non-loopback interfaces.
    nonisolated static func counters() -> (rx: UInt64, tx: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return (0, 0) }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return (0, 0) }

        var rx: UInt64 = 0, tx: UInt64 = 0
        buf.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            let hdrSize = MemoryLayout<if_msghdr>.size
            while offset + hdrSize <= len {
                let hdr = base.advanced(by: offset).assumingMemoryBound(to: if_msghdr.self).pointee
                let msglen = Int(hdr.ifm_msglen)
                if msglen <= 0 { break }
                if Int32(hdr.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= len {
                    let if2 = base.advanced(by: offset).assumingMemoryBound(to: if_msghdr2.self).pointee
                    if (if2.ifm_flags & IFF_LOOPBACK) == 0 {
                        rx += if2.ifm_data.ifi_ibytes
                        tx += if2.ifm_data.ifi_obytes
                    }
                }
                offset += msglen
            }
        }
        return (rx, tx)
    }

    /// The primary up, non-loopback IPv4 interface (prefers `en0`).
    nonisolated static func primaryInterface() -> (name: String, ip: String) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return ("—", "—") }
        defer { freeifaddrs(head) }

        var best: (name: String, ip: String)?
        var ptr = head
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            guard let addr = p.pointee.ifa_addr,
                  (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let bsd = String(cString: p.pointee.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)

            if bsd == "en0" { return (friendlyName(bsd), ip) }   // Wi-Fi on laptops
            if best == nil { best = (friendlyName(bsd), ip) }
        }
        return best ?? ("—", "—")
    }

    nonisolated static func friendlyName(_ bsd: String) -> String {
        bsd.hasPrefix("en") ? "Wi-Fi / Ethernet" : bsd
    }

    // MARK: Preview

    func seedPreview() {
        downBytesPerSec = 3_460_000
        upBytesPerSec = 512_000
        localIP = "192.168.1.42"
        interfaceName = "Wi-Fi / Ethernet"
        hasBaseline = true
    }
}
