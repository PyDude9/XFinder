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

/// The ids of an app's MINIMISED windows: one Accessibility round trip per app. The two window listers asked once per
/// WINDOW instead (fetch the app's whole window list, walk it, read one flag), so an app with 30 CG windows — tabs,
/// helpers, other Spaces — cost 30 round trips on the main thread at every switcher open and Dock hover.
func axMinimizedWindowIDs(pid: pid_t) -> Set<CGWindowID> {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &ref) == .success,
          let wins = ref as? [AXUIElement] else { return [] }
    var ids = Set<CGWindowID>()
    for w in wins {
        var id: CGWindowID = 0
        var minimized: CFTypeRef?
        if axGetWindowID(w, &id) == .success, id != 0,
           AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minimized) == .success,
           minimized as? Bool == true { ids.insert(id) }
    }
    return ids
}

/// One answer per app for the length of one listing (pure, tested): `memo(pid)` asks `fetch` the first time only.
struct PerPIDMemo<Value> {
    private var values: [pid_t: Value] = [:]
    private let fetch: (pid_t) -> Value
    init(_ fetch: @escaping (pid_t) -> Value) { self.fetch = fetch }
    mutating func callAsFunction(_ pid: pid_t) -> Value {
        if let cached = values[pid] { return cached }
        let value = fetch(pid)
        values[pid] = value
        return value
    }
}
