// Probe: does a CHECKED event tap see the synthetic keystroke the engine posts,
// with the right flags? This falsifies/confirms "the event is malformed" without
// needing a visible app reaction.
//
// Run:  swift docs/probes/probe-post-shortcut.swift ctrl-right
//       (that probe is the poster; this one is the observer)
//
// This observer is listening-only (.listenOnly) so it does not swallow anything.

import Cocoa

let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
    | CGEventMask(1) << CGEventType.keyUp.rawValue

print("observing keyDown/keyUp for 8 seconds — run the poster in another terminal now…")
let deadline = Date().addingTimeInterval(8)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
    eventsOfInterest: mask,
    callback: { _, type, event, _ in
        let vk = event.getIntegerValueField(.keyboardEventKeycode)
        let fl = event.flags.rawValue
        let list: [(UInt64, String)] = [
            (1 << 18, "⌃"), (1 << 19, "⌥"), (1 << 17, "⇧"), (1 << 20, "⌘"),
        ]
        let mods = list.filter { fl & $0.0 != 0 }.map(\.1).joined()
        let kind = type == .keyDown ? "down" : "up"
        print("  \(kind) vk=\(vk) flags=\(fl) mods=[\(mods)]")
        return Unmanaged.passUnretained(event)
    },
    userInfo: nil)
else {
    print("could not create observer tap — Accessibility missing for this host")
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(nil, tap, 0)!
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

while Date() < deadline {
    CFRunLoopRunInMode(.defaultMode, 0.25, false)
}
print("observer done")
