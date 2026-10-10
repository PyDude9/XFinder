import Foundation
import IOKit

/// Live reader for `ThermalSensors`. The HID event-system calls are not in any public header, so
/// they are resolved with `dlsym`; if any symbol is missing (a future macOS), `read()` returns
/// `[]` and the UI shows "unavailable" — it never crashes and never invents a number.
final class ThermalReader {
    private typealias CreateF = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatchF = @convention(c) (CFTypeRef, CFDictionary) -> Int32
    private typealias CopyServicesF = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyEventF = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias GetFloatF = @convention(c) (CFTypeRef, Int32) -> Double
    private typealias CopyPropF = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?

    private let client: CFTypeRef?
    private let copyServices: CopyServicesF?
    private let copyEvent: CopyEventF?
    private let getFloat: GetFloatF?
    private let copyProp: CopyPropF?

    /// `kIOHIDEventTypeTemperature` and its level field (`type << 16`).
    private static let temperatureEventType: Int64 = 15
    private static let temperatureLevelField: Int32 = 15 << 16

    init() {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let handle, let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let create = sym("IOHIDEventSystemClientCreate", CreateF.self),
              let setMatch = sym("IOHIDEventSystemClientSetMatching", SetMatchF.self),
              let services = sym("IOHIDEventSystemClientCopyServices", CopyServicesF.self),
              let event = sym("IOHIDServiceClientCopyEvent", CopyEventF.self),
              let float = sym("IOHIDEventGetFloatValue", GetFloatF.self),
              let prop = sym("IOHIDServiceClientCopyProperty", CopyPropF.self),
              let c = create(kCFAllocatorDefault)?.takeRetainedValue() else {
            client = nil; copyServices = nil; copyEvent = nil; getFloat = nil; copyProp = nil
            return
        }
        // Vendor usage page 0xFF00, usage 5 = temperature sensors.
        _ = setMatch(c, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 5] as CFDictionary)
        client = c; copyServices = services; copyEvent = event; getFloat = float; copyProp = prop
    }

    /// Every temperature sensor right now; `[]` when the interface is unavailable.
    func read() -> [ThermalSensors.Reading] {
        guard let client, let copyServices, let copyEvent, let getFloat, let copyProp,
              let services = copyServices(client)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        return services.compactMap { s in
            let name = (copyProp(s, "Product" as CFString)?.takeRetainedValue() as? String) ?? ""
            guard let ev = copyEvent(s, Self.temperatureEventType, 0, 0)?.takeRetainedValue() else { return nil }
            return ThermalSensors.Reading(name: name, celsius: getFloat(ev, Self.temperatureLevelField))
        }
    }
}
