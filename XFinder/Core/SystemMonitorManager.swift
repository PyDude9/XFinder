import Foundation
import Combine
import AppKit
import Darwin
import IOKit.ps

@MainActor
@Observable
final class SystemMonitorManager {
    static let shared = SystemMonitorManager()

    var currentMetrics = SystemMetrics()
    var metricsHistory: [SystemMetrics] = []
    var perInterfaceRates: [String: (down: Double, up: Double)] = [:]
    var sessionBytesRX: UInt64 = 0
    var sessionBytesTX: UInt64 = 0

    private var monitorTimer: Timer?

    // Previous samples needed to turn lifetime counters into rates.
    private var prevCPU: CPUSample?
    private var prevNet: NetSample?
    private var prevCoreTicks: [CoreTicks]?

    private init() {
        // Seed the counters so the first real reading is a delta, not a giant spike.
        prevCPU = Self.readCPUTicks()
        prevNet = Self.readNetworkBytes()
        prevCoreTicks = Self.readCoreTicks()
        if let b = Self.readNetworkBytes(), let saved = Self.loadBaselineBytes() {
            // Session totals = current counters minus the first-launch baseline.
            sessionBytesRX = b.rx >= UInt64(bitPattern: saved.0) ? b.rx - UInt64(bitPattern: saved.0) : 0
            sessionBytesTX = b.tx >= UInt64(bitPattern: saved.1) ? b.tx - UInt64(bitPattern: saved.1) : 0
        } else if let b = Self.readNetworkBytes() {
            Self.saveBaselineBytes(Int64(bitPattern: b.rx), Int64(bitPattern: b.tx))
        }
        // No timer at init — it starts on the first `retain()` from a page or
        // the menubar flyout that actually shows metrics.
        updateMetrics()
    }

    // MARK: - Lifecycle

    /// Pages that actually display metrics call `retain()` in `.onAppear` and
    /// `release()` in `.onDisappear`. Sampling every metric (battery, per-core
    /// CPU, disk, per-interface network) every 2 s with nothing on screen to
    /// show them cost ~2.3 % CPU forever — it is the app's largest idle draw.
    private var consumers = 0
    var hasConsumers: Bool { consumers > 0 }
    /// Fired after every metrics update (menu-bar readouts render from it). No Combine: Observation
    /// has no publishers, and the readout controller is not a view.
    var onUpdate: (() -> Void)?

    /// One sample, no timer — for a consumer that ticks on its own slow cadence.
    func sampleNow() { updateMetrics() }

    func retain() {
        consumers += 1
        if consumers == 1 { startMonitoring() }
    }

    func release() {
        consumers = max(0, consumers - 1)
        if consumers == 0 { stopMonitoring() }
    }

    func startMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: Self.updateInterval(), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMetrics() }
        }
        if let timer = monitorTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        updateMetrics()
    }

    /// Settings-wired cadence (`menubar.updateInterval`, 1/2/5 s).
    static func updateInterval() -> TimeInterval {
        TimeInterval(UserDefaults.standard.object(forKey: "menubar.updateInterval") as? Int ?? 2)
    }

    /// Live-reschedules the timer when the settings picker changes — but only
    /// if something is actually watching.
    func applyUpdateInterval() {
        guard consumers > 0 else { return }
        startMonitoring()
    }

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    // No `deinit`: this is a `shared` singleton that lives for the whole
    // process, so it never runs — and reaching main-actor state from a
    // nonisolated deinit is an error under strict concurrency.

    // MARK: - Sampling

    private func updateMetrics() {
        let metrics = collectMetrics()
        currentMetrics = metrics
        metricsHistory.append(metrics)
        if metricsHistory.count > 60 { metricsHistory.removeFirst() }
        onUpdate?()
    }

    /// GPU `Device Utilization %` from the IORegistry (public; measured to follow real load —
    /// see `GPUUtilization`). nil ⇒ the meter shows "Không khả dụng", never 0.
    private let gpuReader = GPUUtilizationReader()
    private let thermalReader = ThermalReader()

    private func collectMetrics() -> SystemMetrics {
        let now = Date()

        let cpuUsage = cpuUsagePercent(now: now)
        let gpuUsage = gpuReader.read()
        let soc = ThermalSensors.summary(of: thermalReader.read())
        let cpuPerCore = coreUsagePercents(now: now)
        let mem = Self.readMemoryBreakdown()
        let (diskUsed, diskTotal) = Self.readDisk()
        let (downKBs, upKBs) = networkKBs(now: now)
        refreshPerInterface(now: now)
        let (batteryLevel, isCharging, batteryMinutes) = Self.readBattery()
        let swapUsed = Self.readSwapUsed()

        return SystemMetrics(
            cpuUsage: cpuUsage,
            gpuUsage: gpuUsage,
            memoryUsed: mem.used,
            memoryTotal: mem.total,
            diskUsed: diskUsed,
            diskTotal: diskTotal,
            networkDownload: downKBs,
            networkUpload: upKBs,
            batteryLevel: batteryLevel,
            batteryTimeRemaining: batteryMinutes,
            timestamp: now,
            isCharging: isCharging,
            thermalState: Self.readThermalState(),
            uptime: ProcessInfo.processInfo.systemUptime,
            cpuPerCore: cpuPerCore,
            memoryActive: mem.active,
            memoryInactive: mem.inactive,
            memoryWired: mem.wired,
            memoryCompressed: mem.compressed,
            memoryCached: mem.cached,
            swapUsed: swapUsed,
            socTempAverage: soc?.socAverage,
            socTempMax: soc?.socMax
        )
    }

    // MARK: - CPU

    private func cpuUsagePercent(now: Date) -> Double {
        guard let sample = Self.readCPUTicks() else { return 0 }
        defer { prevCPU = sample; prevSampleTime = now }

        guard let prev = prevCPU, now > prevSampleTime else { return 0 }
        let dt = now.timeIntervalSince(prevSampleTime)
        guard dt > 0 else { return 0 }

        // Ticks are cumulative across all cores; sum the delta of busy vs total.
        let dUser = Double(sample.user &- prev.user)
        let dSys = Double(sample.system &- prev.system)
        let dIdle = Double(sample.idle &- prev.idle)
        let dNice = Double(sample.nice &- prev.nice)
        let busy = dUser + dSys + dNice
        let total = busy + dIdle
        guard total > 0 else { return 0 }
        return busy / total * 100.0
    }

    private var prevSampleTime = Date.distantPast

    private struct CPUSample { let user, system, idle, nice: UInt32 }

    private static func readCPUTicks() -> CPUSample? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { iptr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, iptr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return CPUSample(
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3
        )
    }

    // MARK: - Memory

    private struct MemBreakdown {
        let used: Int64; let total: Int64
        let active: Int64; let inactive: Int64
        let wired: Int64; let compressed: Int64; let cached: Int64
    }

    private static func readMemoryBreakdown() -> MemBreakdown {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { iptr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, iptr, &count)
            }
        }
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        guard kr == KERN_SUCCESS else {
            return MemBreakdown(used: 0, total: total, active: 0, inactive: 0, wired: 0, compressed: 0, cached: 0)
        }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let ps = UInt64(pageSize)
        let active = Int64(UInt64(stats.active_count) &* ps)
        let inactive = Int64(UInt64(stats.inactive_count) &* ps)
        let wired = Int64(UInt64(stats.wire_count) &* ps)
        let compressed = Int64(UInt64(stats.compressor_page_count) &* ps)
        let cached = Int64(UInt64(stats.inactive_count &+ stats.free_count) &* ps)
        let used = active &+ wired &+ compressed
        return MemBreakdown(used: used, total: total, active: active, inactive: inactive, wired: wired, compressed: compressed, cached: cached)
    }

    private static func readMemory() -> (used: Int64, total: Int64) {
        let m = readMemoryBreakdown(); return (m.used, m.total)
    }

    private static func readSwapUsed() -> Int64 {
        var xsw = xsw_usage()
        var len = MemoryLayout<xsw_usage>.size
        let ret = sysctlbyname("vm.swapusage", &xsw, &len, nil, 0)
        guard ret == 0 else { return 0 }
        return Int64(xsw.xsu_used)
    }

    // MARK: - Disk

    private static func readDisk() -> (used: Int64, total: Int64) {
        let attrs = (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())) ?? [:]
        let total = (attrs[.systemSize] as? Int64) ?? 0
        let free = (attrs[.systemFreeSize] as? Int64) ?? 0
        return (total &- free, total)
    }

    // MARK: - Network

    private struct NetSample { let rx: UInt64; let tx: UInt64 }

    private var prevPerIface: [String: NetSample] = [:]
    private var prevPerIfaceTime: Date = .distantPast

    private func refreshPerInterface(now: Date) {
        guard let dict = Self.readPerInterfaceBytes() else { return }
        defer { prevPerIface = dict; prevPerIfaceTime = now }
        guard now > prevPerIfaceTime, !prevPerIface.isEmpty else {
            // Seed: publish zeros for each iface.
            for k in dict.keys { perInterfaceRates[k] = (0, 0) }
            return
        }
        let dt = now.timeIntervalSince(prevPerIfaceTime)
        guard dt > 0 else { return }
        for (name, cur) in dict {
            guard let prev = prevPerIface[name] else { perInterfaceRates[name] = (0, 0); continue }
            let dRx = Double(cur.rx >= prev.rx ? cur.rx - prev.rx : 0) / 1024.0 / dt
            let dTx = Double(cur.tx >= prev.tx ? cur.tx - prev.tx : 0) / 1024.0 / dt
            perInterfaceRates[name] = (dRx, dTx)
        }
        // Drop stale interfaces.
        for k in perInterfaceRates.keys where dict[k] == nil { perInterfaceRates.removeValue(forKey: k) }
    }

    private static func readPerInterfaceBytes() -> [String: NetSample]? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return nil }
        defer { freeifaddrs(ifap) }
        var out: [String: NetSample] = [:]
        var ptr = ifap
        while let cur = ptr {
            if let addr = cur.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               let data = cur.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                let name = String(cString: cur.pointee.ifa_name)
                out[name] = NetSample(rx: UInt64(d.ifi_ibytes), tx: UInt64(d.ifi_obytes))
            }
            ptr = cur.pointee.ifa_next
        }
        return out
    }

    private static let baselineKeyRX = "XFinder.netBaselineRX"
    private static let baselineKeyTX = "XFinder.netBaselineTX"
    private static func loadBaselineBytes() -> (Int64, Int64)? {
        let ud = UserDefaults.standard
        guard ud.object(forKey: baselineKeyRX) != nil else { return nil }
        return (Int64(ud.integer(forKey: baselineKeyRX)), Int64(ud.integer(forKey: baselineKeyTX)))
    }
    private static func saveBaselineBytes(_ rx: Int64, _ tx: Int64) {
        UserDefaults.standard.set(Int(rx), forKey: baselineKeyRX)
        UserDefaults.standard.set(Int(tx), forKey: baselineKeyTX)
    }

    private func networkKBs(now: Date) -> (down: Double, up: Double) {
        guard let sample = Self.readNetworkBytes() else { return (0, 0) }
        defer { prevNet = sample }
        guard let prev = prevNet, now > prevSampleTime2 else { return (0, 0) }
        let dt = now.timeIntervalSince(prevSampleTime2)
        guard dt > 0 else { return (0, 0) }
        prevSampleTime2 = now

        let dRx = Double(sample.rx &- prev.rx)
        let dTx = Double(sample.tx &- prev.tx)
        return (dRx / 1024.0 / dt, dTx / 1024.0 / dt)
    }

    private var prevSampleTime2 = Date.distantPast

    private static func readNetworkBytes() -> NetSample? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return nil }
        defer { freeifaddrs(ifap) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var ptr = ifap
        while let cur = ptr {
            if let addr = cur.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               let data = cur.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                rx &+= UInt64(d.ifi_ibytes)
                tx &+= UInt64(d.ifi_obytes)
            }
            ptr = cur.pointee.ifa_next
        }
        return NetSample(rx: rx, tx: tx)
    }

    // MARK: - Battery

    private static func readBattery() -> (level: Double, charging: Bool, minutes: Int) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return (0, false, 0) }
        guard let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty else { return (0, false, 0) }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            guard let cur = desc[kIOPSCurrentCapacityKey] as? Int,
                  let maxCap = desc[kIOPSMaxCapacityKey] as? Int, maxCap > 0 else { continue }
            let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
            let timeKey = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = (desc[timeKey] as? Int) ?? -1
            return (Double(cur) / Double(maxCap) * 100.0, charging, Swift.max(minutes, 0))
        }
        return (0, false, 0)
    }

    // MARK: - Thermal

    private static func readThermalState() -> SystemThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }

    // MARK: - Per-core CPU (public: host_processor_info)

    private var prevCoreTime = Date.distantPast
    private struct CoreTicks { let user, system, idle, nice: UInt32 }

    private func coreUsagePercents(now: Date) -> [Double] {
        guard let cur = Self.readCoreTicks() else { return [] }
        defer { prevCoreTicks = cur; prevCoreTime = now }
        guard let prev = prevCoreTicks, prev.count == cur.count, now > prevCoreTime else { return [] }
        return zip(prev, cur).map { p, c in
            let dU = Double(c.user &- p.user), dS = Double(c.system &- p.system)
            let dI = Double(c.idle &- p.idle), dN = Double(c.nice &- p.nice)
            let busy = dU + dS + dN
            let total = busy + dI
            guard total > 0 else { return 0 }
            return busy / total * 100.0
        }
    }

    private static func readCoreTicks() -> [CoreTicks]? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        guard kr == KERN_SUCCESS, let base = info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: base), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)) }
        var out: [CoreTicks] = []
        out.reserveCapacity(Int(count))
        for i in 0..<Int(count) {
            let off = Int(CPU_STATE_MAX) * i
            out.append(CoreTicks(
                user: UInt32(bitPattern: base[off + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: base[off + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: base[off + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: base[off + Int(CPU_STATE_NICE)])
            ))
        }
        return out
    }
}
