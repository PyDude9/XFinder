// probe-screen-diff.swift — "did the screen visibly change?" as a number.
//
// Every earlier detector failed for a reason worth keeping:
//   * the window census drifts on its own (14 -> 15 -> ... -> 36 across one run) and the
//     Dock's full-screen surface is not a reliable marker;
//   * OCR of a live news page is dominated by the page's own repainting, so an OCR diff
//     says "changed" for a gesture that did nothing;
//   * frontmost-app / focused-AX-element did not move at all.
//
// This probe compares the pixels themselves, coarsely. The screen is downscaled to a
// 64x36 grid of average colours and the mean absolute difference is reported per channel.
// Mission Control dims the entire desktop and lays every window out in a grid, which is a
// large whole-screen change; a page repaint inside one window is a small one. The control
// trials below calibrate both ends on this host.
//
// Run: swift docs/probes/probe-screen-diff.swift
// Needs: Screen Recording (screencapture) and Accessibility (to post).

import AppKit
import Foundation

let gridW = 64, gridH = 36

func capture(_ path: String) {
    let t = Process()
    t.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    t.arguments = ["-x", path]
    try? t.run(); t.waitUntilExit()
}

/// A coarse fingerprint: average colour of each cell of a gridW x gridH grid.
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
    let sum = zip(a, b).reduce(0.0) { $0 + abs($1.0 - $1.1) }
    return sum / Double(a.count)
}

func postKey(_ key: UInt16, _ flags: UInt64) {
    let src = CGEventSource(stateID: .hidSystemState)
    let d = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
    let u = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
    d?.flags = CGEventFlags(rawValue: flags); u?.flags = d!.flags
    d?.post(tap: .cghidEventTap); Thread.sleep(forTimeInterval: 0.02); u?.post(tap: .cghidEventTap)
}

func postSystemKey(_ key: Int32) {
    for down in [true, false] {
        let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
        let data1 = Int((key << 16) | (Int32(down ? 0xA : 0xB) << 8))
        if let e = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                      timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                      data1: data1, data2: -1), let cg = e.cgEvent {
            cg.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
}

/// Each trial takes its own "before" immediately beforehand, so a change made by an
/// earlier trial cannot leak into a later reading.
func trial(_ label: String, settle: Double = 1.6, _ act: () -> Void) {
    capture("/tmp/sd-before.png")
    guard let before = fingerprint("/tmp/sd-before.png") else { print("\(label): fingerprint failed"); return }
    act()
    Thread.sleep(forTimeInterval: settle)
    capture("/tmp/sd-after.png")
    guard let after = fingerprint("/tmp/sd-after.png") else { print("\(label): fingerprint failed"); return }
    print(String(format: "%-52@  screenDiff=%6.2f", label as NSString, difference(before, after)))
}

print("grid \(gridW)x\(gridH). Calibration + trials follow.")
print("(a whole-screen change — Mission Control, a Space switch — is a LARGE number;")
print(" a repaint inside one window is small. The first two trials calibrate the ends.)")

trial("1 no-op (Esc)", settle: 2.5) { postKey(53, 0) }
trial("2 ⌃↑  (control only)", settle: 2.5) { postKey(126, 1 << 18) }
trial("3 ⌃↑  (control|fn — exactly as stored)", settle: 2.5) { postKey(126, (1 << 18) | 0x800000) }
trial("4 ⌃↑  (control|fn) again", settle: 2.5) { postKey(126, (1 << 18) | 0x800000) }
trial("5 ⌃↓  (control|fn)", settle: 2.5) { postKey(125, (1 << 18) | 0x800000) }
trial("6 system key 32", settle: 2.5) { postSystemKey(32) }
trial("7 ⌃→  (control|fn)", settle: 2.5) { postKey(124, (1 << 18) | 0x800000) }
trial("8 ⌘[  (history back)", settle: 2.5) { postKey(33, 1 << 20) }

postKey(53, 0)
Thread.sleep(forTimeInterval: 1.0)
print("done. (Esc posted to leave a clean state.)")
