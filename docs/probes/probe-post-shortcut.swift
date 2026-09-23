// Probe: post the exact key event GestureEngine.perform() builds, and see whether
// the receiving app actually performs the bound action.
//
// The engine's dispatch is:
//     CGEvent(keyboardEventSource: nil, virtualKey: k, keyDown: true)
//     down.flags = CGEventFlags(rawValue: flags)
//     down.post(tap: .cgSessionEventTap)      // then the same for keyUp
//
// This probe reproduces that verbatim so "the gesture fires nothing" can be split
// into "the event never reaches the app" vs "the keys are not the action on macOS 27".
//
// Run:  swift docs/probes/probe-post-shortcut.swift ctrl-up
//       swift docs/probes/probe-post-shortcut.swift cmd-bracket-left
//
// Requires Accessibility for the *host terminal* (which is the point: it separates a
// terminal-held grant from an app-held grant).

import Cocoa

/// The values the user's stored Global override holds, read from
/// `mouseGestures.configuration.v1` on 2026-09-22:
///   up -> key 126 flags 262144   right -> key 124 flags 262144   left -> key 123 flags 262144
/// 262144 == 1 << 18 == .maskControl.
let cases: [String: (UInt16, UInt64, String)] = [
    "ctrl-up":           (126, 1 << 18, "⌃↑  (the stored Global 'up')"),
    "ctrl-left":         (123, 1 << 18, "⌃←  (the stored Global 'left')"),
    "ctrl-right":        (124, 1 << 18, "⌃→  (the stored Global 'right')"),
    "ctrl-down":         (125, 1 << 18, "⌃↓"),
    "cmd-bracket-left":  (33,  1 << 20, "⌘["),
    "cmd-bracket-right": (30,  1 << 20, "⌘]"),
]

let name = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ctrl-right"
guard let (key, flags, label) = cases[name] else {
    print("unknown case '\(name)'. options: \(cases.keys.sorted().joined(separator: ", "))")
    exit(2)
}

print("trusted (AXIsProcessTrusted): \(AXIsProcessTrusted())")
print("posting \(label) — key=\(key) flags=\(flags) to .cgSessionEventTap")
print("focus the target app within 3 seconds…")
Thread.sleep(forTimeInterval: 3)

// Exactly the engine's construction, including the up event carrying the same flags.
guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
      let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else {
    print("CGEvent construction FAILED"); exit(1)
}
down.flags = CGEventFlags(rawValue: flags)
up.flags = down.flags
down.post(tap: .cgSessionEventTap)
up.post(tap: .cgSessionEventTap)
print("posted down+up")

// Also post with an explicit event source, to test whether a nil source is the
// difference — a nil source inherits the *combined session* state, which can carry
// stale modifier bits from the physical keyboard.
guard let src = CGEventSource(stateID: .hidSystemState) else { exit(1) }
Thread.sleep(forTimeInterval: 1)
print("posting again via an explicit .hidSystemState source")
if let d2 = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true),
   let u2 = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) {
    d2.flags = CGEventFlags(rawValue: flags)
    u2.flags = d2.flags
    d2.post(tap: .cgSessionEventTap)
    u2.post(tap: .cgSessionEventTap)
    print("posted down+up (explicit source)")
}
print("done — did the target app change? report which of the two posts did it.")
