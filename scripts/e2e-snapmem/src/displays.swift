import AppKit
import CoreGraphics
import Foundation

// displays
// Prints the CURRENT displays as JSON in the DisplayKey shape XFinder's
// SnapMemory.Store decodes, plus a visibleFrame (top-left/screen space, points)
// per display so write-rule.py / run-e2e.sh can compute expected snap rects
// without re-deriving the AppKit<->CG coordinate flip themselves.
//
//   uuid         - CGDisplayCreateUUIDFromDisplayID, as a UUID string
//   name         - localizedName from NSScreen (falls back to "Display <id>")
//   pixelWidth   - CGDisplayCopyDisplayMode().pixelWidth
//   pixelHeight  - CGDisplayCopyDisplayMode().pixelHeight
//   isBuiltin    - CGDisplayIsBuiltin(id) != 0
//   isMain       - id == CGMainDisplayID()
//   visibleFrame - NSScreen.visibleFrame converted from AppKit (bottom-left,
//                  relative to the PRIMARY screen's origin) into CG top-left/
//                  global-screen space (same space CGWindowList and the
//                  target app's NSWindow.frame conversion need), as
//                  {x,y,width,height} in points.

struct DisplayKey: Codable {
    let uuid: String
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
    let isBuiltin: Bool
    let isMain: Bool
    let visibleFrame: Rect
}

struct Rect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

// Global height of the whole virtual screen space, needed to flip AppKit's
// bottom-left coordinates into CG's top-left coordinates. AppKit's
// NSScreen.screens[0].frame always has origin (0,0) and spans the full
// virtual desktop height on the primary screen; menu-bar screen height is
// NSScreen.screens[0].frame.height for a single- or multi-display setup
// when every screen is referenced to the primary's bottom-left origin.
func globalFlipHeight() -> CGFloat {
    // The primary screen (NSScreen.screens[0]) has origin (0,0) in AppKit
    // space by definition; its height is the datum CGWindowList's top-left
    // space is measured against for every screen's y coordinate.
    return NSScreen.screens.first?.frame.height ?? 0
}

func appKitToCGTopLeft(_ r: NSRect, flipHeight: CGFloat) -> Rect {
    // AppKit: bottom-left origin, y increases upward.
    // CG (top-left/global): y increases downward, origin at top-left of the
    // primary screen's full frame.
    let topY = flipHeight - (r.origin.y + r.size.height)
    return Rect(x: Double(r.origin.x), y: Double(topY), width: Double(r.size.width), height: Double(r.size.height))
}

let mainID = CGMainDisplayID()
let flipHeight = globalFlipHeight()

var out: [DisplayKey] = []

for screen in NSScreen.screens {
    guard let numberObj = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
    let displayID = CGDirectDisplayID(numberObj.uint32Value)

    var uuidString = "unknown-\(displayID)"
    if let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID) {
        let cfUUID = uuidRef.takeRetainedValue()
        if let cfStr = CFUUIDCreateString(nil, cfUUID) {
            uuidString = cfStr as String
        }
    }

    var pxW = 0
    var pxH = 0
    if let mode = CGDisplayCopyDisplayMode(displayID) {
        pxW = mode.pixelWidth
        pxH = mode.pixelHeight
    }

    let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
    let isMain = displayID == mainID

    let name: String
    if #available(macOS 10.15, *) {
        name = screen.localizedName
    } else {
        name = "Display \(displayID)"
    }

    let vf = appKitToCGTopLeft(screen.visibleFrame, flipHeight: flipHeight)

    out.append(DisplayKey(
        uuid: uuidString,
        name: name,
        pixelWidth: pxW,
        pixelHeight: pxH,
        isBuiltin: isBuiltin,
        isMain: isMain,
        visibleFrame: vf
    ))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
let data = try! encoder.encode(out)
print(String(data: data, encoding: .utf8)!)
