// probe-action-ocr-diff.swift — "did the screen actually change?" answered by reading it.
//
// The window-census probes could not settle Mission Control: the Dock's full-screen
// surface is sometimes on the list and sometimes not, so the count both rises and stays
// flat across runs. This probe sidesteps the question of *how* the UI is implemented and
// reads the pixels: capture, post the action, capture again, and diff the recognised
// text. A real UI change shows up as text that was not there before; a no-op produces an
// empty diff.
//
// Usage:
//   swift docs/probes/probe-action-ocr-diff.swift ctrl-up
//   swift docs/probes/probe-action-ocr-diff.swift ctrl-right
//   swift docs/probes/probe-action-ocr-diff.swift system-32
//
// Needs Screen Recording (for `screencapture`) and Accessibility (to post).

import AppKit
import Foundation
import Vision

let actions: [String: (UInt16, UInt64, String)] = [
    "ctrl-up":    (126, 1 << 18, "⌃↑"),
    "ctrl-down":  (125, 1 << 18, "⌃↓"),
    "ctrl-left":  (123, 1 << 18, "⌃←"),
    "ctrl-right": (124, 1 << 18, "⌃→"),
    "cmd-[":      (33,  1 << 20, "⌘["),
    "cmd-]":      (30,  1 << 20, "⌘]"),
]

func capture(_ path: String) {
    let t = Process()
    t.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    t.arguments = ["-x", path]
    try? t.run(); t.waitUntilExit()
}

func text(of path: String) -> [String] {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = false
    guard (try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])) != nil else { return [] }
    return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
}

func postKey(_ key: UInt16, _ flags: UInt64) {
    let src = CGEventSource(stateID: .hidSystemState)
    let d = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
    let u = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
    d?.flags = CGEventFlags(rawValue: flags); u?.flags = d!.flags
    d?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.02)
    u?.post(tap: .cghidEventTap)
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

let arg = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ctrl-up"
let beforePath = "/tmp/ocr-before.png"
let afterPath = "/tmp/ocr-after.png"

print("AXIsProcessTrusted: \(AXIsProcessTrusted())")
capture(beforePath)
let before = text(of: beforePath)
print("baseline text lines: \(before.count)")

if arg.hasPrefix("system-"), let key = Int32(arg.dropFirst("system-".count)) {
    print("posting system-defined key \(key)")
    postSystemKey(key)
} else if let (key, flags, label) = actions[arg] {
    print("posting \(label)")
    postKey(key, flags)
} else {
    print("unknown action '\(arg)'. options: \(actions.keys.sorted().joined(separator: ", ")), system-<n>")
    exit(2)
}

Thread.sleep(forTimeInterval: 2.0)
capture(afterPath)
let after = text(of: afterPath)
print("after text lines: \(after.count)")

let beforeSet = Set(before)
let afterSet = Set(after)
let appeared = after.filter { !beforeSet.contains($0) }
let vanished = before.filter { !afterSet.contains($0) }

print("\n--- APPEARED (\(appeared.count)) ---")
for l in appeared.prefix(60) { print("  + \(l)") }
print("--- VANISHED (\(vanished.count)) ---")
for l in vanished.prefix(60) { print("  - \(l)") }
print("\nVERDICT: \(appeared.isEmpty && vanished.isEmpty ? "NO screen change" : "screen CHANGED")")
