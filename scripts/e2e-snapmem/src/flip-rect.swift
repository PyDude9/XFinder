import AppKit
import Foundation

// flip-rect <x> <y> <w> <h>
// Converts an AppKit bottom-left-origin rect (as reported by NSWindow.frame)
// into CG top-left/global-screen space (the same space CGWindowList's
// kCGWindowBounds and displays.swift's visibleFrame use), using the primary
// screen's AppKit frame height as the flip datum -- the same convention
// displays.swift documents and uses.

guard CommandLine.arguments.count == 5,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2]),
      let w = Double(CommandLine.arguments[3]),
      let h = Double(CommandLine.arguments[4]) else {
    FileHandle.standardError.write("usage: flip-rect <x> <y> <w> <h>\n".data(using: .utf8)!)
    exit(2)
}

let flipHeight = NSScreen.screens.first?.frame.height ?? 0
let topY = Double(flipHeight) - (y + h)
print("\(x) \(topY) \(w) \(h)")
