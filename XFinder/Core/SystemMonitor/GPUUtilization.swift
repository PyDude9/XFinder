import Foundation
#if canImport(IOKit)
import IOKit
#endif

/// GPU utilization from the IORegistry — the public read the app once claimed did not exist.
///
/// `IOAccelerator` services (`AGXAcceleratorG15X` on this M3 Pro) publish a
/// `PerformanceStatistics` dictionary with `Device Utilization %`, readable by any process
/// through `IORegistryEntryCreateCFProperty` — no entitlement, no private framework.
/// Measured 2026-10-09 on macOS 27.0 with `docs`-style probes: idle 0–22 %, a Metal compute
/// burn 99–100 %, back to ~1.5 % after the burn. The number follows real load, so showing it
/// is honest; an earlier CLAUDE.md row said "`IOAccelerator` not public" and was wrong
/// (the Honesty Rule cuts both ways).
///
/// Split in two so the rule is testable without a GPU: `percent(from:)` is pure and
/// returns `nil` whenever the key is absent or not a number — the UI renders that as
/// "Không khả dụng", never as a fabricated 0 %.
enum GPUUtilization {
    /// The key macOS publishes; `Renderer`/`Tiler Utilization %` sit beside it.
    static let deviceUtilizationKey = "Device Utilization %"
    static let performanceStatisticsKey = "PerformanceStatistics"
    static let serviceClass = "IOAccelerator"

    /// `Device Utilization %` as a 0…100 Double, or nil when the dictionary does not carry a
    /// usable number. Accepts the bridged `NSNumber` shapes a CF dictionary produces.
    static func percent(from performanceStatistics: [String: Any]?) -> Double? {
        guard let value = performanceStatistics?[deviceUtilizationKey] else { return nil }
        let raw: Double
        switch value {
        case let n as NSNumber: raw = n.doubleValue
        case let i as Int: raw = Double(i)
        case let d as Double: raw = d
        default: return nil
        }
        guard raw.isFinite else { return nil }
        return min(100, max(0, raw))
    }
}

#if canImport(IOKit)
/// Live reader. Resolves the first `IOAccelerator` service that carries
/// `PerformanceStatistics`, keeps that `io_service_t` for later ticks, and re-resolves if a
/// read fails (e.g. an eGPU came or went). Cheap enough for the 2 s metrics tick, and the tick
/// only runs while a metrics page is visible (`SystemMonitorManager.retain/release`).
final class GPUUtilizationReader {
    private var service: io_service_t = 0

    deinit {
        if service != 0 { IOObjectRelease(service) }
    }

    /// `Device Utilization %` right now, or nil if no accelerator publishes it.
    func read() -> Double? {
        if service == 0 { service = Self.resolveService() }
        guard service != 0 else { return nil }
        if let p = Self.readPercent(service) { return p }
        // Stale handle: drop it and try once more with a fresh lookup.
        IOObjectRelease(service)
        service = Self.resolveService()
        guard service != 0 else { return nil }
        return Self.readPercent(service)
    }

    private static func readPercent(_ svc: io_service_t) -> Double? {
        guard let cf = IORegistryEntryCreateCFProperty(
            svc, GPUUtilization.performanceStatisticsKey as CFString, kCFAllocatorDefault, 0)
        else { return nil }
        let dict = cf.takeRetainedValue() as? [String: Any]
        return GPUUtilization.percent(from: dict)
    }

    /// First `IOAccelerator` whose `PerformanceStatistics` yields a number. Caller owns the
    /// returned object (retained); 0 when nothing matches.
    private static func resolveService() -> io_service_t {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching(GPUUtilization.serviceClass),
                                           &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }
        var candidate = IOIteratorNext(iterator)
        while candidate != 0 {
            if readPercent(candidate) != nil { return candidate }
            IOObjectRelease(candidate)
            candidate = IOIteratorNext(iterator)
        }
        return 0
    }
}
#endif
