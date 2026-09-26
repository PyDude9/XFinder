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

    // ── PATCH v10 R1 ───────────────────────────────────────────────────────────────
    // The vendor-page scan, exactly as `DeviceCapabilityProbe.vendorButtonUsages` performs
    // it: element type Input_Button, page >= 0xFF00, and usage inside 1...0x3F. The range
    // guard is what excludes the 0xFFFFFFFF "no usage" sentinel — measured on the Apple
    // Internal Trackpad, which declares 1753 such elements. Without it this line reports
    // 1753 "buttons" and numbers one of them -1.
    var vendorUsages = Set<Int>()
    var sentinelCount = 0
    var vendorNonButtonCount = 0
    for el in raw where Int(IOHIDElementGetUsagePage(el)) >= 0xFF00 {
        let type = IOHIDElementGetType(el).rawValue
        let usage = Int(IOHIDElementGetUsage(el))
        if usage == 0xFFFF_FFFF { sentinelCount += 1; continue }
        guard type == 0x02 else { vendorNonButtonCount += 1; continue }
        if (1...0x3F).contains(usage) { vendorUsages.insert(usage) }
    }
    print("  v10 vendor scan (type 0x02 && page >= 0xFF00 && usage 1...0x3F): \(vendorUsages.sorted())")
    print("    excluded: \(sentinelCount) elements with usage 0xFFFFFFFF, \(vendorNonButtonCount) non-button elements")

    // The event-button numbers the UI will print, and the figure it will draw.
    let eventButtons = shipped.sorted().map { $0 - 1 }.filter { $0 >= 0 }
    let style = shipped.count >= 3 ? "archetype (6 positions)" : "generic (declared only)"
    print("  v10 event buttons shown in the UI: \(eventButtons)")
    print("  v10 figure: \(style)")
    if shipped.count < 6 {
        print("    note: the figure has 6 positions and this descriptor declares \(shipped.count).")
        print("    XFinder reports that as a fact and offers Record; it does NOT invent a number.")
    }

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
