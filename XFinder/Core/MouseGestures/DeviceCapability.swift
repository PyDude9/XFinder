import Foundation
import IOKit.hid

// ─────────────────────────────────────────────────────────────────────────────
//  The LIVE half of the single-mouse capability probe.
//
//  This file does one thing: ask IOHID what the connected pointing devices
//  declare, and hand the raw facts to `DeviceCapabilityProbe` for interpretation.
//  All the decisions — the button filter, the axis tokens, the feature derivation,
//  the confidence rule — live in `DeviceCapabilityTypes.swift`, which imports no
//  IOKit and is symlinked into the test package.
//
//  That split is deliberate. This file **cannot** be unit-tested honestly: a test
//  that opened an IOHID manager and asserted on whatever mouse happened to be
//  plugged in would pass on the author's desk and fail everywhere else. What CAN
//  be tested is every rule this file feeds, and that is where the tests are.
//
//  ── WHAT THE PROBE MUST NOT DO ───────────────────────────────────────────────
//  * Never fabricate identity. A device that declares no `kIOHIDVendorIDKey` gets
//    `nil`, not `-1` and not `0`. See the header of `DeviceCapabilityTypes.swift`
//    for why (the Apple Internal Trackpad is the real case).
//  * Never return a device it could not read as though it had read it. The
//    confidence rule in `descriptor(from:)` handles that.
//  * Never run on a timer. `IOHIDManagerOpen` plus the element copy costs
//    milliseconds per device for a descriptor with hundreds of elements (the Razer
//    mouse in this repo declares 898), so this is on-demand only.
// ─────────────────────────────────────────────────────────────────────────────

extension DeviceCapabilityProbe {

    /// Reads every connected pointing device (mouse or trackpad) through IOHID.
    ///
    /// Synchronous and safe to call off the main thread. Honest cost note: measured
    /// locally, `IOHIDManagerOpen` plus the element copy can take **a few
    /// milliseconds** per device for a descriptor with hundreds of elements. That is
    /// fine for an on-demand page load (the page calls this from a detached task),
    /// and it is not a call to make on a timer or once per frame.
    ///
    /// Returns `[]` on any failure rather than throwing: a probe that cannot read
    /// the hardware has nothing honest to report, and the caller's job is to render
    /// "not detected yet" — never a fabricated capability set. `DeviceCapabilityModel`
    /// turns `[]` into `.unknownUntilDetected`, not into `.unsupportedByMouse`.
    static func connectedPointingDevices() -> [CapabilityDescriptor] {
        // IOHIDManagerCopyDevices duplicates a single physical device — the probe
        // in this repo saw 2 identical Basilisk entries and 2 identical trackpad
        // entries. Dedupe last, on the full identity tuple, keeping first sight.
        deduplicated(readDevices().map(\.descriptor))
    }

    /// The raw `(usagePage, usage, type)` facts of every connected pointing device, as
    /// printable lines — the **"log the raw facts before any filter runs"** step (R1).
    ///
    /// It exists to keep the page falsifiable. Claims like "the descriptor declares five
    /// buttons" or "there is a vendor page with N button elements" are worth nothing
    /// unless the underlying elements can be read, so this returns exactly what
    /// `IOHIDDeviceCopyMatchingElements` reported, untransformed, for a human to check.
    /// The page shows it behind a disclosure, on demand — never on the idle path.
    static func connectedElementDump() -> [String] {
        var lines: [String] = []
        for read in readDevices() {
            let name = read.descriptor.productName.isEmpty ? "(no product name)" : read.descriptor.productName
            let transport = read.descriptor.transport.isEmpty ? "(no transport)" : read.descriptor.transport
            lines.append("— \(name) · \(transport)")
            lines.append(contentsOf: DeviceCapabilityProbe.elementDump(from: read.elements))
        }
        return lines.isEmpty ? ["(no pointing device could be read)"] : lines
    }

    /// One device's descriptor **and** the element facts it was derived from. Kept
    /// together so the raw dump shows the *input* to the derivation rather than a second
    /// read of the hardware that might disagree with it.
    private struct DeviceRead {
        var descriptor: CapabilityDescriptor
        var elements: [HIDElementFact]
    }

    /// Opens a manager, enumerates the matching devices and reads each one.
    private static func readDevices() -> [DeviceRead] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Pointer matching: Generic Desktop / Mouse (0x01, 0x02) and Generic
        // Desktop / Pointer (0x01, 0x01). This deliberately also matches the
        // Apple Internal Keyboard / Trackpad, which is why missing identity keys
        // must survive as `nil` rather than being coerced to a number.
        let matching: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey as String: usagePageGenericDesktop,
             kIOHIDDeviceUsageKey as String: 0x02],
            [kIOHIDDeviceUsagePageKey as String: usagePageGenericDesktop,
             kIOHIDDeviceUsageKey as String: 0x01],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        return deviceSet.map { read($0) }
    }

    /// Reads one device's identity and elements, returning both. Kept separate from the
    /// manager plumbing so the per-device work is readable on its own.
    private static func read(_ device: IOHIDDevice) -> DeviceRead {
        func intProperty(_ key: CFString) -> Int? {
            // A missing key stays nil. Never `?? -1`, never `?? 0` — the Apple
            // Internal Trackpad genuinely has neither vendor nor product key, and a
            // fabricated identity would let a wrong capability set look verified.
            (IOHIDDeviceGetProperty(device, key) as? NSNumber)?.intValue
        }
        func stringProperty(_ key: CFString) -> String? {
            IOHIDDeviceGetProperty(device, key) as? String
        }

        var elements: [HIDElementFact] = []
        if let raw = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone))
            as? [IOHIDElement] {
            // A `nil` matching dictionary returns every element in the descriptor,
            // so the filtering is entirely `buttonUsages(from:)`'s responsibility.
            // That is where the old 873-element filter bug lived; do not re-introduce
            // a predicate here.
            elements = raw.map {
                HIDElementFact(
                    usagePage: Int(IOHIDElementGetUsagePage($0)),
                    usage: Int(IOHIDElementGetUsage($0)),
                    type: IOHIDElementGetType($0).rawValue
                )
            }
        }

        let properties = HIDDeviceProperties(
            transport: stringProperty(kIOHIDTransportKey as CFString) ?? "",
            vendorID: intProperty(kIOHIDVendorIDKey as CFString),
            productID: intProperty(kIOHIDProductIDKey as CFString),
            productName: stringProperty(kIOHIDProductKey as CFString) ?? "",
            elements: elements,
            source: .detected
        )
        return DeviceRead(descriptor: descriptor(from: properties), elements: elements)
    }
}
