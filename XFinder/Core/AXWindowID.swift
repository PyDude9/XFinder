import ApplicationServices
import CoreGraphics

/// The ONE declaration of the private `_AXUIElementGetWindow` symbol. It is a FREE function on
/// purpose: a `@_silgen_name` on a `static` method is compiled with the method convention (an extra
/// metatype argument), and with a second declaration of the same symbol elsewhere the Release
/// (whole-module) build fails with "function type mismatch" while Debug silently built — the app
/// could not be released until this was the only declaration.
@_silgen_name("_AXUIElementGetWindow")
func axGetWindowID(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError
