import Foundation

enum SystemThermalState: String, Codable, Sendable {
    case nominal, fair, serious, critical
    var label: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        }
    }
}

struct SystemMetrics: Codable, Sendable {
    let cpuUsage: Double
    /// GPU `Device Utilization %` from `IOAccelerator/PerformanceStatistics`. Optional on
    /// purpose: nil means the hardware publishes no such key, and the meter must say
    /// "Không khả dụng" rather than draw a fabricated 0 % (Honesty Rule).
    let gpuUsage: Double?
    /// SoC die temperature (°C) from the HID thermal sensors — nil when none is readable. Mean and
    /// hottest of the `PMU tdie*` sensors; deliberately NOT called CPU (see `ThermalSensors`).
    let socTempAverage: Double?
    let socTempMax: Double?
    let memoryUsed: Int64
    let memoryTotal: Int64
    let diskUsed: Int64
    let diskTotal: Int64
    let networkDownload: Double
    let networkUpload: Double
    let batteryLevel: Double
    let batteryTimeRemaining: Int
    let timestamp: Date
    let isCharging: Bool
    let thermalState: SystemThermalState

    // Same-cadence extended readouts. All derived from public APIs; the
    // corresponding collectors are nil-safe so absent data degrades to 0,
    // which the views render as a placeholder (never a fabricated number).
    let uptime: TimeInterval
    let cpuPerCore: [Double]
    let memoryActive: Int64
    let memoryInactive: Int64
    let memoryWired: Int64
    let memoryCompressed: Int64
    let memoryCached: Int64
    let swapUsed: Int64

    init(
        cpuUsage: Double = 0,
        gpuUsage: Double? = nil,
        memoryUsed: Int64 = 0,
        memoryTotal: Int64 = 0,
        diskUsed: Int64 = 0,
        diskTotal: Int64 = 0,
        networkDownload: Double = 0,
        networkUpload: Double = 0,
        batteryLevel: Double = 100,
        batteryTimeRemaining: Int = 0,
        timestamp: Date = Date(),
        isCharging: Bool = false,
        thermalState: SystemThermalState = .nominal,
        uptime: TimeInterval = 0,
        cpuPerCore: [Double] = [],
        memoryActive: Int64 = 0,
        memoryInactive: Int64 = 0,
        memoryWired: Int64 = 0,
        memoryCompressed: Int64 = 0,
        memoryCached: Int64 = 0,
        swapUsed: Int64 = 0,
        socTempAverage: Double? = nil,
        socTempMax: Double? = nil
    ) {
        self.cpuUsage = cpuUsage
        self.gpuUsage = gpuUsage
        self.socTempAverage = socTempAverage
        self.socTempMax = socTempMax
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.diskUsed = diskUsed
        self.diskTotal = diskTotal
        self.networkDownload = networkDownload
        self.networkUpload = networkUpload
        self.batteryLevel = batteryLevel
        self.batteryTimeRemaining = batteryTimeRemaining
        self.timestamp = timestamp
        self.isCharging = isCharging
        self.thermalState = thermalState
        self.uptime = uptime
        self.cpuPerCore = cpuPerCore
        self.memoryActive = memoryActive
        self.memoryInactive = memoryInactive
        self.memoryWired = memoryWired
        self.memoryCompressed = memoryCompressed
        self.memoryCached = memoryCached
        self.swapUsed = swapUsed
    }

    // MARK: - Formatted strings

    var memoryUsedString: String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .memory
        return f.string(fromByteCount: memoryUsed)
    }

    var memoryTotalString: String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .memory
        return f.string(fromByteCount: memoryTotal)
    }

    var memoryPercentage: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal) * 100
    }

    var diskUsedString: String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useTB]
        f.countStyle = .file
        return f.string(fromByteCount: diskUsed)
    }

    var diskTotalString: String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useTB]
        f.countStyle = .file
        return f.string(fromByteCount: diskTotal)
    }

    var diskPercentage: Double {
        guard diskTotal > 0 else { return 0 }
        return Double(diskUsed) / Double(diskTotal) * 100
    }

    var networkDownloadString: String {
        if networkDownload < 1024 { return String(format: "%.1f KB/s", networkDownload) }
        if networkDownload < 1024 * 1024 { return String(format: "%.1f MB/s", networkDownload / 1024) }
        return String(format: "%.1f GB/s", networkDownload / (1024 * 1024))
    }

    var networkUploadString: String {
        if networkUpload < 1024 { return String(format: "%.1f KB/s", networkUpload) }
        if networkUpload < 1024 * 1024 { return String(format: "%.1f MB/s", networkUpload / 1024) }
        return String(format: "%.1f GB/s", networkUpload / (1024 * 1024))
    }

    var batteryTimeString: String {
        let h = batteryTimeRemaining / 60, m = batteryTimeRemaining % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var uptimeString: String {
        guard uptime > 60 else { return L10n.t("Vừa khởi động") }
        let s = Int(uptime)
        let days = s / 86400
        let hours = (s % 86400) / 3600
        let mins = (s % 3600) / 60
        if days > 0 { return "\(days)\(L10n.t(" ngày "))\(hours)\(L10n.t(" giờ"))" }
        if hours > 0 { return "\(hours)\(L10n.t(" giờ "))\(mins)\(L10n.t(" phút"))" }
        return "\(mins)\(L10n.t(" phút"))"
    }
}
