// Probe: does posting `NSEvent.systemDefined` key 32 actually trigger Mission Control?
//
// This is the mechanism `SystemKeySender` relies on, and the reason the Global preset was
// changed: `⌃↑` is bound to nothing on macOS 27 (measured), while keycode 232 is what
// `com.apple.symbolichotkeys` id 32 actually stores.
//
// Run:  swiftc -O -o /tmp/probe-syskey docs/probes/probe-system-key.swift && /tmp/probe-syskey
//
// Requires Accessibility for the host. Watch the screen: Mission Control should appear.

import AppKit

guard AXIsProcessTrusted() else {
    print("NOT TRUSTED — grant Accessibility to the terminal/this binary and retry")
    exit(1)
}

let key: Int32 = 32   // the NX_KEYTYPE stored by symbolic-hotkey id 32
func post(down: Bool) {
    let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
    let data1 = Int((key << 16) | (Int32(down ? 0xA : 0xB) << 8))
    guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                         modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                         context: nil, subtype: 8, data1: data1, data2: -1),
          let cg = event.cgEvent else {
        print("could not build event"); return
    }
    cg.post(tap: .cghidEventTap)
}

print("posting NSEvent.systemDefined key=32 down+up — watch for Mission Control…")
post(down: true)
Thread.sleep(forTimeInterval: 0.05)
post(down: false)
print("posted. Did Mission Control appear?")
