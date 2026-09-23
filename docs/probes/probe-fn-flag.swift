// probe-fn-flag.swift — does the `fn` bit in the modifier mask decide whether a
// synthetic arrow-key hotkey is matched?
//
// ── Why this exists ─────────────────────────────────────────────────────────────
// The Global preset's Mission Control / App Exposé arms have been measured as no-ops
// twice, through two different mechanisms:
//   * `⌃↑` posted as an ordinary CGEvent key event;
//   * key type 32 posted as an `NSEvent.systemDefined` event — and the SDK header
//     `IOKit/…/ev_keymap.h` has NO `NX_KEYTYPE_MISSION_CONTROL` (its highest value is
//     `NX_KEYTYPE_MENU = 25`), so 32 is not a defined keytype at all.
//
// The one thing both earlier runs had in common: the posted event's flag mask did not
// include `0x800000` (`maskSecondaryFn`). The user's own `com.apple.symbolichotkeys`
// stores every one of these bindings **with** that bit:
//
//     id 32 Mission Control  vk=126 mods=8650752 = 0x840000  (control | fn)
//     id 33 App Exposé       vk=125 mods=8650752 = 0x840000
//     id 79 Move left        vk=123 mods=8650752 = 0x840000
//     id 81 Move right       vk=124 mods=8650752 = 0x840000
//
// Apple's own factory encoding uses the same form, so the bit is not noise. This probe
// asks the one question that decides the implementation: is it load-bearing?
//
// Method: coarse whole-screen pixel diff (64x36 average-colour grid). Mission Control
// dims the desktop and lays every window out in a grid — a large whole-screen change.
// The positive control (`⌘[` in a browser-free context still repaints/scrolls) and the
// no-op (`Esc`) calibrate the two ends.
//
// Each trial posts Esc and waits for the system to settle BEFORE taking its "before"
// capture, so a panel left open by the previous trial cannot leak into the next reading.
//
// Run:  swift docs/probes/probe-fn-flag.swift
// Needs: Screen Recording (screencapture) and Accessibility (to post events).
//
// NOTE: this posts real Mission Control shortcuts, so the screen WILL flash. It is
// transient — no trial here switches Spaces, so nothing persists after the run.

import AppKit
import Foundation

let gridW = 64, gridH = 36

func capture(_ path: String) {
    let t = Process()
    t.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    t.arguments = ["-x", path]
    try? t.run(); t.waitUntilExit()
}

func fingerprint(_ path: String) -> [Double]? {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    var buf = [UInt8](repeating: 0, count: gridW * gridH * 4)
    guard let ctx = CGContext(data: &buf, width: gridW, height: gridH,
                              bitsPerComponent: 8, bytesPerRow: gridW * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .medium
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: gridW, height: gridH))
    return (0..<(gridW * gridH * 4)).map { Double(buf[$0]) }
}

func difference(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return -1 }
    return zip(a, b).reduce(0.0) { $0 + abs($1.0 - $1.1) } / Double(a.count)
}

func postKey(_ key: UInt16, _ flags: UInt64) {
    guard let src = CGEventSource(stateID: .hidSystemState) else { return }
    let d = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
    let u = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
    d?.flags = CGEventFlags(rawValue: flags); u?.flags = d!.flags
    d?.post(tap: .cghidEventTap); Thread.sleep(forTimeInterval: 0.03); u?.post(tap: .cghidEventTap)
}

let control: UInt64 = 1 << 18
let fnBit: UInt64 = 0x800000

/// Settle, take "before", act, settle, take "after".
func trial(_ label: String, _ act: () -> Void) {
    postKey(53, 0)                       // Esc: close anything a previous trial opened
    Thread.sleep(forTimeInterval: 1.4)
    capture("/tmp/fn-before.png")
    guard let before = fingerprint("/tmp/fn-before.png") else { print("\(label): capture failed"); return }
    act()
    Thread.sleep(forTimeInterval: 2.4)
    capture("/tmp/fn-after.png")
    guard let after = fingerprint("/tmp/fn-after.png") else { print("\(label): capture failed"); return }
    print(String(format: "%-46@ screenDiff=%6.2f", label as NSString, difference(before, after)))
}

print("grid \(gridW)x\(gridH) — settling with Esc before every trial.")
print("asked: is the fn bit (0x800000) load-bearing for an arrow-key hotkey?\n")

trial("1 no-op (Esc twice)") { postKey(53, 0) }
trial("2 ⌃↑  control only") { postKey(126, control) }
trial("3 ⌃↑  control | fn") { postKey(126, control | fnBit) }
trial("4 ⌃↑  control | fn (repeat)") { postKey(126, control | fnBit) }
trial("5 ⌃↓  control | fn (App Exposé)") { postKey(125, control | fnBit) }
trial("6 positive control ⌘[") { postKey(33, 1 << 20) }

postKey(53, 0)
Thread.sleep(forTimeInterval: 1.0)
print("\ndone. (Esc posted to leave a clean state.)")
