import Foundation
import IOKit.hid

// Raw HID element dump for PATCH v7 R1.
// Dumps usagePage / usage / type for EVERY element before any filter, so we can
// tell whether buttons live on a Vendor Defined Page (0xFF00+) or whether the
// declared set really is [1,2,3,4,5].

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matching: [[String: Any]] = [
    [kIOHIDDeviceUsagePageKey as String: 0x01, kIOHIDDeviceUsageKey as String: 0x02],
    [kIOHIDDeviceUsagePageKey as String: 0x01, kIOHIDDeviceUsageKey as String: 0x01],
]
IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
print("IOHIDManagerOpen kIOReturn: \(openResult)")

guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
    print("no devices")
    exit(1)
}

func str(_ d: IOHIDDevice, _ k: CFString) -> String {
    (IOHIDDeviceGetProperty(d, k) as? String) ?? "-"
}
func num(_ d: IOHIDDevice, _ k: CFString) -> String {
    if let n = IOHIDDeviceGetProperty(d, k) as? NSNumber { return "0x" + String(n.intValue, radix: 16) }
    return "nil"
}

print("raw device count BEFORE dedupe: \(deviceSet.count)")

for device in deviceSet {
    print("")
    print("=== device ===")
    print("  product:   \(str(device, kIOHIDProductKey as CFString))")
    print("  transport: \(str(device, kIOHIDTransportKey as CFString))")
    print("  vendorID:  \(num(device, kIOHIDVendorIDKey as CFString))")
    print("  productID: \(num(device, kIOHIDProductIDKey as CFString))")

    guard let raw = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
        print("  (no elements)")
        continue
    }
    print("  TOTAL elements: \(raw.count)")

    // Tally by (usagePage, type) so we can see every page that carries elements.
    var tally: [String: Int] = [:]
    for el in raw {
        let key = String(format: "page=0x%04X type=0x%02X",
                         Int(IOHIDElementGetUsagePage(el)),
                         IOHIDElementGetType(el).rawValue)
        tally[key, default: 0] += 1
    }
    print("  --- tally by (page, type) ---")
    for (k, v) in tally.sorted(by: { $0.key < $1.key }) {
        print("    \(k)  ×\(v)")
    }

    // Every element on ANY Button page or any Vendor Defined page, listed raw.
    print("  --- raw elements on Button page 0x09 or Vendor Defined page >= 0xFF00 ---")
    var listed = 0
    for el in raw {
        let page = Int(IOHIDElementGetUsagePage(el))
        guard page == 0x09 || page >= 0xFF00 else { continue }
        listed += 1
        if listed <= 60 {
            print(String(format: "    page=0x%04X usage=0x%04X (%d) type=0x%02X",
                         page, Int(IOHIDElementGetUsage(el)), Int(IOHIDElementGetUsage(el)),
                         IOHIDElementGetType(el).rawValue))
        }
    }
    if listed == 0 { print("    (none)") }
    if listed > 60 { print("    ... \(listed - 60) more") }

    // What the CURRENT shipped filter yields.
    var shipped = Set<Int>()
    for el in raw where IOHIDElementGetType(el).rawValue == 0x02 && Int(IOHIDElementGetUsagePage(el)) == 0x09 {
        shipped.insert(Int(IOHIDElementGetUsage(el)))
    }
    print("  CURRENT filter (type 0x02 && page 0x09) buttons: \(shipped.sorted())")

    // What v7's proposal ("all page 0x09 regardless of collection") would yield.
    var v7 = Set<Int>()
    for el in raw where Int(IOHIDElementGetUsagePage(el)) == 0x09 {
        v7.insert(Int(IOHIDElementGetUsage(el)))
    }
    print("  v7 PROPOSED filter (page 0x09 only) buttons: \(v7.sorted())  count=\(v7.count)")

    // Any button-typed element at all, whatever page.
    var anyButtonType = Set<String>()
    for el in raw where IOHIDElementGetType(el).rawValue == 0x02 {
        anyButtonType.insert(String(format: "page=0x%04X usage=0x%04X", Int(IOHIDElementGetUsagePage(el)), Int(IOHIDElementGetUsage(el))))
    }
    print("  ALL button-typed elements (any page): \(anyButtonType.sorted())")
}

IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
