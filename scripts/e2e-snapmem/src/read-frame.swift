import AppKit
import CoreGraphics
import Foundation

// read-frame <bundle-id>
// Prints the CGWindowList bounds (kCGWindowBounds, top-left/screen space) of
// that app's on-screen, layer-0 windows as JSON:
// [{"pid":123,"x":300,"y":300,"width":600,"height":400,"name":"SnapMem Target"}, ...]
//
// This is the INDEPENDENT measurement of a window's frame — it must never be
// skipped in favor of trusting the target app's own self-reported FRAME line.

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: read-frame <bundle-id>\n".data(using: .utf8)!)
    exit(2)
}
let bundleID = CommandLine.arguments[1]

// Resolve pids for the bundle id via NSRunningApplication (no private API).
let pids = NSWorkspace.shared.runningApplications
    .filter { $0.bundleIdentifier == bundleID }
    .map { $0.processIdentifier }

guard !pids.isEmpty else {
    print("[]")
    exit(0)
}

guard let list = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: AnyObject]] else {
    print("[]")
    exit(0)
}

struct Entry: Codable {
    let pid: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let name: String
    let layer: Int
}

var entries: [Entry] = []

for win in list {
    guard let ownerPID = win[kCGWindowOwnerPID as String] as? Int,
          pids.contains(pid_t(ownerPID)) else { continue }
    guard let layer = win[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
    guard let boundsDict = win[kCGWindowBounds as String] as? [String: AnyObject] else { continue }
    guard let x = boundsDict["X"] as? Double,
          let y = boundsDict["Y"] as? Double,
          let w = boundsDict["Width"] as? Double,
          let h = boundsDict["Height"] as? Double else { continue }
    let name = (win[kCGWindowName as String] as? String) ?? ""
    entries.append(Entry(pid: ownerPID, x: x, y: y, width: w, height: h, name: name, layer: layer))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let data = try! encoder.encode(entries)
print(String(data: data, encoding: .utf8)!)
