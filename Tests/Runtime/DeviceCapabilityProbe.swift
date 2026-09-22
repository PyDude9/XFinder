import AppKit
import CoreGraphics
import os

/// Answers one question for the "capability" UI: can this Mac's event-tap layer
/// tell us which mouse a button came from, and what kind of button it is?
///
/// Prints, per event: the button number, whether CoreGraphics can name a device
/// for it, and every device-side fact publicly reachable. Run with
/// `swift tests/Runtime/DeviceCapabilityProbe.swift` (or via scripts/probe-device.sh)
/// and press the physical buttons when prompted.
@main struct DeviceCapabilityProbe {
    /// Event-tap callbacks are C function pointers and cannot capture context.
    nonisolated(unsafe) static var probeSeen = OSAllocatedUnfairLock(initialState: Set<Int>())
    nonisolated(unsafe) static var seen = OSAllocatedUnfairLock(initialState: Set<Int>())

    static func main() {
        print("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("Accessibility trusted: \(AXIsProcessTrusted())")

        // 1. Are there any *device* facts attached to an event tap event?
        print("\n--- CGEvent fields that could identify a device ---")
        let e = CGEvent(source: nil)!
        for field in [CGEventField.mouseEventButtonNumber,
                      .mouseEventNumber, .mouseEventClickState,
                      .mouseEventDeltaX, .mouseEventDeltaY] {
            print("  \(field.rawValue): \(e.getIntegerValueField(field))")
        }
        print("  (no vendor/product/device field exists on CGEvent:",
              "CGEventField has \(CGEventField.mouseEventButtonNumber.rawValue) as the highest mouse field)")

        // 2. What can IOHID tell us about connected pointing devices?
        print("\n--- IOHID devices (pointing, primary usage 1/2 or 1/1) ---")
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey as String: 0x01, kIOHIDDeviceUsageKey as String: 0x02],
            [kIOHIDDeviceUsagePageKey as String: 0x01, kIOHIDDeviceUsageKey as String: 0x01],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        print("  IOHIDManagerOpen: \(opened == kIOReturnSuccess ? "ok" : "failed \(opened)")")
        if let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            print("  \(set.count) device(s)")
            for d in set {
                let name = IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String ?? "?"
                let vid = IOHIDDeviceGetProperty(d, kIOHIDVendorIDKey as CFString) as? Int ?? -1
                let pid = IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int ?? -1
                let transport = IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String ?? "?"
                // The interesting question: does the device declare its buttons?
                print("  - \(name) vid=\(vid) pid=\(pid) transport=\(transport)")
                let elements = IOHIDDeviceCopyMatchingElements(d, nil, IOOptionBits(kIOHIDOptionsTypeNone))
                var buttons = 0
                if let list = elements as? [IOHIDElement] {
                    for el in list where IOHIDElementGetType(el) == kIOHIDElementTypeInput_Button { buttons += 1 }
                }
                print("      input-button elements declared by this device: \(buttons)")
            }
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        // 3. What does a real event tap actually see? This is the load-bearing
        //    question: even if IOHID knows the device, is it linked to the event?
        print("\n--- live event tap for 30 s: press every mouse button ---")
        let stop = Date().addingTimeInterval(30)
        let seen = OSAllocatedUnfairLock(initialState: Set<Int>())
        let mask: CGEventMask = (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)
        // The callback is a C function pointer, so it cannot capture the lock;
        // stash it in a file-scope global. Probe-only, single-threaded use.
        probeSeen = seen
        DeviceCapabilityProbe.seen = seen
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, _ in
                let b = Int(event.getIntegerValueField(.mouseEventButtonNumber))
                if type == .scrollWheel {
                    let cont = event.getIntegerValueField(.scrollWheelEventIsContinuous)
                    let a1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                    let a2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
                    let a3 = event.getIntegerValueField(.scrollWheelEventDeltaAxis3)
                    print("  scroll: continuous=\(cont) axis1=\(a1) axis2=\(a2) axis3=\(a3)")
                } else {
                    let first = DeviceCapabilityProbe.seen.withLock { s -> Bool in
                        let wasNew = !s.contains(b); s.insert(b); return wasNew
                    }
                    if first { print("  button number \(b)  (type \(type.rawValue))  <- NEW") }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: nil) else {
            print("  tapCreate FAILED (permission/service)")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        while Date() < stop { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2)) }
        print("  distinct button numbers seen: \(seen.withLock { $0.sorted() })")
    }
}
