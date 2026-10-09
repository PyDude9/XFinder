import Foundation
import IOKit

/// Live block I/O counters via public `IOBlockStorageDriver` `"Statistics"`.
/// Also exposes `statfs`-based volume snapshots. Both are nil-safe: if no
/// storage driver advertises statistics the returned rates stay at 0 and the
/// UI shows the honest placeholder for SMART-style fields.
struct DiskStats {
    let bytesReadPerSec: Double
    let bytesWrittenPerSec: Double
}

struct VolumeInfo: Identifiable, Equatable {
    let id = UUID()
    let mount: String
    let total: Int64
    let free: Int64
    var used: Int64 { total - free }
    var percentUsed: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
    var volumeName: String { mount == "/" ? "Macintosh HD" : (mount as NSString).lastPathComponent }

    // `id` is regenerated every refresh, so compare by content — that lets
    // `.onChange(of: disk.volumes)` fire only when the set actually changes.
    static func == (lhs: VolumeInfo, rhs: VolumeInfo) -> Bool {
        lhs.mount == rhs.mount && lhs.total == rhs.total && lhs.free == rhs.free
    }
}

@MainActor
@Observable
final class DiskManager {
    static let shared = DiskManager()

    var volumes: [VolumeInfo] = []
    var readKBs: Double = 0
    var writeKBs: Double = 0
    var historyRead: [Double] = []
    var historyWrite: [Double] = []

    private var timer: Timer?
    private var prevRead: UInt64 = 0
    private var prevWrite: UInt64 = 0
    private var prevTime: Date = .distantPast
    private var seeded = false

    private init() {}

    func start() {
        refreshVolumes()
        let (r, w) = Self.readBlockStats()
        prevRead = r; prevWrite = w; prevTime = Date(); seeded = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
        tick()
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        refreshVolumes()
        let now = Date()
        let (r, w) = Self.readBlockStats()
        defer { prevRead = r; prevWrite = w; prevTime = now }
        guard seeded, now > prevTime else { return }
        let dt = now.timeIntervalSince(prevTime)
        guard dt > 0 else { return }
        let dR = Double(r >= prevRead ? r - prevRead : 0) / 1024.0 / dt
        let dW = Double(w >= prevWrite ? w - prevWrite : 0) / 1024.0 / dt
        readKBs = dR
        writeKBs = dW
        historyRead.append(dR); if historyRead.count > 60 { historyRead.removeFirst() }
        historyWrite.append(dW); if historyWrite.count > 60 { historyWrite.removeFirst() }
    }

    private func refreshVolumes() {
        var list: [VolumeInfo] = []
        // Primary volume via FileManager (guaranteed).
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            let total = (attrs[.systemSize] as? Int64) ?? 0
            let free = (attrs[.systemFreeSize] as? Int64) ?? 0
            if total > 0 { list.append(VolumeInfo(mount: "/", total: total, free: free)) }
        }
        // Extra mounts via getmntinfo (best-effort, skip pseudo filesystems).
        var mnt: UnsafeMutablePointer<statfs>?
        let n = getmntinfo(&mnt, MNT_NOWAIT)
        if n > 0, let mnt {
            for i in 0..<Int(n) {
                let s = mnt[i]
                let mount = withUnsafePointer(to: s.f_mntonname) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) { String(cString: $0) }
                }
                if mount == "/" { continue }
                let flags = s.f_flags
                if (flags & UInt32(MNT_DONTBROWSE)) != 0 { continue }
                let total = Int64(s.f_blocks) * Int64(s.f_bsize)
                let free = Int64(s.f_bfree) * Int64(s.f_bsize)
                if total > 0 && total < Int64.max / 2 { list.append(VolumeInfo(mount: mount, total: total, free: free)) }
            }
        }
        volumes = list
    }

    private static func readBlockStats() -> (read: UInt64, written: UInt64) {
        var totalR: UInt64 = 0, totalW: UInt64 = 0
        let iterPtr = UnsafeMutablePointer<io_iterator_t>.allocate(capacity: 1)
        defer { iterPtr.deallocate() }
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), iterPtr) == kIOReturnSuccess else {
            return (0, 0)
        }
        let iter = iterPtr.pointee
        defer { IOObjectRelease(iter) }
        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { service = IOIteratorNext(iter) }
            defer { IOObjectRelease(service) }
            guard let props = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0) else { continue }
            let dict = props.takeRetainedValue() as? [String: Any]
            if let v = dict?["Bytes (Read)"] as? UInt64 { totalR &+= v }
            else if let v = dict?["Bytes (Read)"] as? Int64 { totalR &+= UInt64(bitPattern: v) }
            if let v = dict?["Bytes (Write)"] as? UInt64 { totalW &+= v }
            else if let v = dict?["Bytes (Write)"] as? Int64 { totalW &+= UInt64(bitPattern: v) }
            if let v = dict?["Bytes Read"] as? UInt64 { totalR &+= v }
            if let v = dict?["Bytes Written"] as? UInt64 { totalW &+= v }
        }
        return (totalR, totalW)
    }

    // MARK: - SMART status (public, via diskutil)

    /// SMART health for the disk backing a mount point.
    ///
    /// This page used to claim SMART was "không khả dụng trên phần cứng này",
    /// which was **wrong** — `diskutil info <mount>` reports a real
    /// `SMART Status:` line (Verified / Failing / Not Supported), including on
    /// Apple Silicon internal storage. Verified on macOS 27: `diskutil info /`
    /// → "Verified". What is genuinely unavailable is the *detailed attribute
    /// table* (reallocated sectors, wear levelling, drive temperature) — that
    /// needs `smartctl` or a private IOKit path, so it is not shown.
    ///
    /// Runs off-main: `diskutil` is a subprocess and takes tens of ms.
    nonisolated static func smartStatus(forMount mount: String) async -> String? {
        await Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            p.arguments = ["info", mount]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return nil }
            // Read before waiting: a full pipe buffer would deadlock the child.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            // Extraction lives in SMARTStatus so a test can pin it against real diskutil text.
            return SMARTStatus.parse(diskutilOutput: text)
        }.value
    }

    // `smartLabel(_:)` moved to `SMARTStatus.label(forRaw:)`, which returns a STORE KEY the
    // view must wrap in `L10n.t`. The old version returned Vietnamese display strings from
    // Core and the page rendered them bare — a language leak no literal sweep could see.
}
