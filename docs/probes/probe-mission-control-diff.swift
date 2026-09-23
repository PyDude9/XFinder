// probe-mission-control-diff.swift — settle, by measurement, whether *either*
// mechanism actually opens Mission Control on this host.
//
// Why a time series and not a single before/after sample: the first version sampled
// once, 1.5 s after posting, and produced contradictory readings — a trial reported
// "no window change" while the census taken moments later had more than doubled
// (14 -> 33 windows). Mission Control animates in over roughly a second and adds a
// window per open application, so a single sample can land anywhere in the animation.
// Sampling every 0.25 s for 3 s turns that ambiguity into a visible curve.
//
// The signal is deliberately assumption-free: it counts *on-screen windows* and
// separately lists the Dock's own windows with their layers. Opening Mission Control
// makes every app's windows on-screen (the count jumps); closing it drops them back.
// A no-op stays flat.
//
// Run: swiftc -O -o /tmp/mc-diff docs/probes/probe-mission-control-diff.swift && /tmp/mc-diff
// Needs: Accessibility trust for the calling process, to post events.

import AppKit

func windows() -> [(number: Int, owner: String, name: String, layer: Int, w: Int, h: Int)] {
    guard let list = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return list.compactMap { w in
        guard let number = w[kCGWindowNumber as String] as? Int else { return nil }
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        return (number,
                w[kCGWindowOwnerName as String] as? String ?? "?",
                w[kCGWindowName as String] as? String ?? "",
                w[kCGWindowLayer as String] as? Int ?? 0,
                Int(b["Width"] as? Double ?? 0),
                Int(b["Height"] as? Double ?? 0))
    }
}

func dockWindows() -> String {
    let d = windows().filter { $0.owner == "Dock" }
    if d.isEmpty { return "none" }
    return d.map { "#\($0.number) L\($0.layer) \($0.w)x\($0.h)\($0.name.isEmpty ? "" : " \"\($0.name)\"")" }
        .joined(separator: ", ")
}

func postSystemKey(_ key: Int32, down: Bool) {
    let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
    let data1 = Int((key << 16) | (Int32(down ? 0xA : 0xB) << 8))
    guard let e = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                     timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                     data1: data1, data2: -1), let cg = e.cgEvent else { return }
    cg.post(tap: .cghidEventTap)
}

func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
    down?.flags = flags; up?.flags = flags
    down?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.02)
    up?.post(tap: .cghidEventTap)
}

/// Post, then print the window count every 0.25 s for 3 s.
func trial(_ label: String, act: () -> Void) {
    let base = windows().count
    act()
    var series: [Int] = []
    for _ in 0..<12 {
        Thread.sleep(forTimeInterval: 0.25)
        series.append(windows().count)
    }
    let peak = series.max() ?? base
    let settled = series.last ?? base
    print("\n=== \(label) ===")
    print("  base=\(base)  series=\(series)")
    print("  peak=\(peak) settled=\(settled)  Dock windows: \(dockWindows())")
    if peak > base + 2 {
        print("  RESULT: WINDOW COUNT ROSE by \(peak - base) — a full-screen UI opened")
    } else if peak < base - 2 {
        print("  RESULT: WINDOW COUNT FELL by \(base - peak) — something closed")
    } else {
        print("  RESULT: flat — nothing opened")
    }
}

print("AXIsProcessTrusted: \(AXIsProcessTrusted())")
print("baseline: \(windows().count) on-screen windows; Dock: \(dockWindows())")

trial("A — system key 32 (NX_KEYTYPE_MISSION_CONTROL) via NSEvent.systemDefined") {
    postSystemKey(32, down: true)
    Thread.sleep(forTimeInterval: 0.05)
    postSystemKey(32, down: false)
}

trial("B — keystroke ⌃↑ (the binding the user set for Mission Control)") {
    postKeystroke(keyCode: 126, flags: .maskControl)
}

trial("C — keystroke ⌃↓ (the binding for App Exposé)") {
    postKeystroke(keyCode: 125, flags: .maskControl)
}

trial("D — keystroke ⌃→ (the binding for Move right a space)") {
    postKeystroke(keyCode: 124, flags: .maskControl)
}

postKeystroke(keyCode: 53, flags: [])   // Esc, to leave a clean state
Thread.sleep(forTimeInterval: 1.0)
print("\nfinal: \(windows().count) on-screen windows; Dock: \(dockWindows())")
