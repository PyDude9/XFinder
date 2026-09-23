// probe-mc-state.swift — is Mission Control open? asked of the window server, not of pixels.
//
// Three earlier attempts failed for recorded reasons: the Dock's full-screen surface is
// sometimes listed and sometimes not (count both rose and stayed flat across runs), and
// an OCR diff of a live news page is dominated by the page's own repainting. This probe
// asks a different question — *which application owns the front of the session?* — because
// Mission Control is drawn by the Dock, so opening it changes the frontmost application
// and the system-wide focused element.
//
// Run: swift docs/probes/probe-mc-state.swift
// Needs: Accessibility trust to post.

import AppKit

func state() -> String {
    let front = NSWorkspace.shared.frontmostApplication
    let frontName = front?.localizedName ?? "?"
    let frontID = front?.bundleIdentifier ?? "?"
    var focused = "?"
    let sys = AXUIElementCreateSystemWide()
    var v: CFTypeRef?
    if AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &v) == .success,
       let el = v {
        let ax = el as! AXUIElement
        func s(_ a: String) -> String {
            var x: CFTypeRef?
            return AXUIElementCopyAttributeValue(ax, a as CFString, &x) == .success ? (x as? String ?? "") : ""
        }
        focused = "role=\(s(kAXRoleAttribute)) subrole=\(s(kAXSubroleAttribute)) desc=\"\(s(kAXDescriptionAttribute))\" title=\"\(s(kAXTitleAttribute))\""
    }
    let count = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]])?.count ?? -1
    return "frontmost=\(frontName) [\(frontID)]  windows=\(count)\n      focused AX: \(focused)"
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

func sample(_ label: String, _ act: () -> Void) {
    print("\n=== \(label) ===")
    print("  before: \(state())")
    act()
    for i in 1...4 {
        Thread.sleep(forTimeInterval: 0.6)
        print("  +\(Double(i) * 0.6)s: \(state())")
    }
}

print("AXIsProcessTrusted: \(AXIsProcessTrusted())")
print("start: \(state())")

sample("A — keystroke ⌃↑ (Mission Control binding)") { postKey(126, 1 << 18) }
sample("B — system key 32 (NX_KEYTYPE_MISSION_CONTROL)") { postSystemKey(32) }
sample("C — keystroke ⌃↓ (App Exposé binding)") { postKey(125, 1 << 18) }
sample("D — keystroke ⌃→ (Move right a space binding)") { postKey(124, 1 << 18) }

postKey(53, 0)   // Esc
Thread.sleep(forTimeInterval: 1.0)
print("\nfinal: \(state())")
