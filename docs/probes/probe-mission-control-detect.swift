// Probe: detect whether Mission Control opened, before vs after posting the system key.
//
// Why a separate observer: "did the screen change" is not visible to a terminal program,
// and the whole point of this pass is to stop *asserting* that a mechanism works. Mission
// Control makes the Dock own a large, high-layer window, so the window list is an
// objective signal.
//
// Run:  swiftc -O -o /tmp/mc-detect docs/probes/probe-mission-control-detect.swift && /tmp/mc-detect

import AppKit

/// A cheap signature of "Mission Control is showing": the Dock owns a window at a layer
/// above the normal desktop, sized to the screen. Named so the probe reads as a claim
/// rather than as magic numbers.
func missionControlWindow() -> (layer: Int, w: Int, h: Int)? {
    guard let list = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    for win in list {
        guard (win[kCGWindowOwnerName as String] as? String) == "Dock",
              let layer = win[kCGWindowLayer as String] as? Int, layer > 10,
              let bounds = win[kCGWindowBounds as String] as? [String: Any],
              let w = bounds["Width"] as? Int, let h = bounds["Height"] as? Int
        else { continue }
        // Full-width Dock window = the Mission Control / App Exposé surface.
        //
        // The comparison must be in **points**, matching `kCGWindowBounds`: measured on
        // this machine the surface is 1728x1117, while `CGDisplayPixelsWide` returns
        // 3456 (the Retina pixel width). Comparing against the pixel value made the
        // detector report "not open" for a Mission Control that was visibly on screen —
        // a broken probe reading as a negative result, which is the failure mode the
        // `Claude.md` menu-bar saga warns about.
        let pts = Int(CGDisplayBounds(CGMainDisplayID()).width)
        if w >= pts - 40 { return (layer, w, h) }
    }
    return nil
}

print("before: \(missionControlWindow().map { "MC OPEN layer=\($0.layer) \($0.w)x\($0.h)" } ?? "not open")")
print("posting system key 32 (Mission Control)…")
let key: Int32 = 32
func post(down: Bool) {
    let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
    let data1 = Int((key << 16) | (Int32(down ? 0xA : 0xB) << 8))
    guard let e = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                     timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                     data1: data1, data2: -1), let cg = e.cgEvent else { return }
    cg.post(tap: .cghidEventTap)
}
post(down: true); Thread.sleep(forTimeInterval: 0.05); post(down: false)
Thread.sleep(forTimeInterval: 1.2)
let after = missionControlWindow()
print("after:  \(after.map { "MC OPEN layer=\($0.layer) \($0.w)x\($0.h)" } ?? "not open")")
if after != nil { print("RESULT: the system key opened Mission Control") }
else { print("RESULT: no Mission Control window detected") }
