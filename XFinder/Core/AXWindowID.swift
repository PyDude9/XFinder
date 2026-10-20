import ApplicationServices
import CoreGraphics

/// The ONE declaration of the private `_AXUIElementGetWindow` symbol. It is a FREE function on
/// purpose: a `@_silgen_name` on a `static` method is compiled with the method convention (an extra
/// metatype argument), and with a second declaration of the same symbol elsewhere the Release
/// (whole-module) build fails with "function type mismatch" while Debug silently built — the app
/// could not be released until this was the only declaration.
@_silgen_name("_AXUIElementGetWindow")
func axGetWindowID(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

/// The CGWindowIDs of an app's real windows, from its Accessibility window list (tabs and hidden helper windows are not
/// in it). nil without the permission or when the app answers nothing.
func axWindowIDs(pid: pid_t) -> Set<CGWindowID>? {
    guard AXIsProcessTrusted() else { return nil }
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &ref) == .success,
          let wins = ref as? [AXUIElement] else { return nil }
    var ids = Set<CGWindowID>()
    for w in wins { var id: CGWindowID = 0; if axGetWindowID(w, &id) == .success, id != 0 { ids.insert(id) } }
    return ids.isEmpty ? nil : ids
}
