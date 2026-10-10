import Foundation
import CoreGraphics

/// Pure placement rules for every floating surface (toasts, HUDs, the notch, the switcher, the
/// shelf). Three controllers used to re-derive "which screen, which corner, how far from the edge"
/// by hand with slightly different numbers; one function, tested, replaces them.
///
/// All rects are AppKit space (origin bottom-left) — the space `NSWindow.setFrame` wants.
enum SurfaceGeometry {

    enum Anchor: Equatable {
        /// Centred under the menu bar, `inset` below the top of the visible area (toasts).
        case topCenter(inset: CGFloat)
        /// Top-right corner, `inset` from both edges (alert banners).
        case topRight(inset: CGFloat)
        /// Centred horizontally at the physical notch, hugging the top screen edge (Notch surface).
        case notch
        /// Spotlight-style: centred horizontally, top at 28 % of the screen height (⌘K, switcher).
        case spotlight
        /// Centred on the pointer, clamped to the visible frame (edge/notes panels, color pick).
        case pointer(CGPoint)
        /// Dead centre of the visible frame.
        case center
    }

    /// Where a `size` panel goes on a screen whose full frame is `screen` and whose visible (minus
    /// menu bar / Dock) frame is `visible`. Result is always clamped inside `visible` so a toast
    /// can never be born half off-screen on a small display.
    static func frame(size: CGSize, anchor: Anchor, screen: CGRect, visible: CGRect) -> CGRect {
        var origin: CGPoint
        switch anchor {
        case .topCenter(let inset):
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - inset)
        case .topRight(let inset):
            origin = CGPoint(x: visible.maxX - size.width - inset, y: visible.maxY - size.height - inset)
        case .notch:
            // Hugs the TOP of the full screen frame (over the menu bar), not the visible frame.
            origin = CGPoint(x: screen.midX - size.width / 2, y: screen.maxY - size.height)
        case .spotlight:
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - visible.height * 0.28)
        case .pointer(let p):
            origin = CGPoint(x: p.x - size.width / 2, y: p.y - size.height / 2)
        case .center:
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        }
        let bounds = (anchor == .notch) ? screen : visible
        return clamp(CGRect(origin: origin, size: size), into: bounds)
    }

    /// Keep `rect` inside `bounds`; if it is larger than the bounds, align to the bounds' origin.
    static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        var r = rect
        r.origin.x = min(max(r.minX, bounds.minX), max(bounds.minX, bounds.maxX - r.width))
        r.origin.y = min(max(r.minY, bounds.minY), max(bounds.minY, bounds.maxY - r.height))
        return r
    }

    /// The physical notch, in AppKit space, from the two `auxiliaryTop*Area` rects macOS reports
    /// (nil on a screen without one). Measured on this MacBook Pro: left (0,1085,771.5×32),
    /// right (956.5,1085,771.5×32) ⇒ notch x 771.5…956.5, 185 pt wide, 32 pt tall.
    static func notchRect(auxLeft: CGRect?, auxRight: CGRect?) -> CGRect? {
        guard let l = auxLeft, let r = auxRight, r.minX > l.maxX else { return nil }
        return CGRect(x: l.maxX, y: l.minY, width: r.minX - l.maxX, height: max(l.height, r.height))
    }

    /// Frame of the Notch surface in its collapsed state: exactly the notch when there is one,
    /// else a pill of `pill` size centred at the top edge (external display / iMac).
    static func collapsedNotchFrame(screen: CGRect, notch: CGRect?, pill: CGSize) -> CGRect {
        if let notch { return notch }
        return CGRect(x: screen.midX - pill.width / 2, y: screen.maxY - pill.height, width: pill.width, height: pill.height)
    }

    /// Frame of the expanded surface: grows symmetrically around the collapsed frame's centre,
    /// keeps its top glued to the screen top, and never exceeds the screen width.
    static func expandedNotchFrame(collapsed: CGRect, size: CGSize, screen: CGRect) -> CGRect {
        let w = min(size.width, screen.width)
        let r = CGRect(x: collapsed.midX - w / 2, y: screen.maxY - size.height, width: w, height: size.height)
        return clamp(r, into: screen)
    }
}
