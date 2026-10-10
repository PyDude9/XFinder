import Foundation
import CoreGraphics

/// Pure sizes, frames and trigger zones of the Notch surface, so the controller (window frame and
/// hit-testing) and the SwiftUI root (drawn shape) can never disagree. All rects are AppKit space
/// (origin bottom-left), like `SurfaceGeometry`.
enum NotchSurfaceLayout {

    struct Metrics: Equatable {
        /// Height of the count badge hanging below the notch while files are held and the surface is collapsed.
        var badgeLip: CGFloat = 18
        /// Extra width on EACH side of the notch for the peek strip.
        var peekWing: CGFloat = 56
        /// Height of the peek strip below the notch.
        var peekDrop: CGFloat = 40
        /// Expanded surface: width, and height below the notch (or total height at the pointer).
        var expandedWidth: CGFloat = 440
        var expandedDrop: CGFloat = 222   // B2d: + action row and result line
        /// Live activity strip (B4): extra width each side of the notch, and its depth below it.
        var activityWing: CGFloat = 130
        var activityDrop: CGFloat = 36
        /// Stand-in notch width on a screen without one (external display / iMac).
        var virtualNotchWidth: CGFloat = 185
        /// The drag zone reaches this far beyond each side of the notch, and this far below the top edge,
        /// so a file drag does not have to land on the notch to the pixel.
        var dragMargin: CGFloat = 60
        var dragDepth: CGFloat = 36
        /// A shaken-open tray sits this far below the pointer, as the old ShakePin tray did.
        var pointerGap: CGFloat = 24
        static let standard = Metrics()
    }

    /// The physical notch, or a zero-height stand-in centred at the top of a screen without one.
    static func notch(screen: CGRect, auxLeft: CGRect?, auxRight: CGRect?,
                      metrics m: Metrics = .standard) -> CGRect {
        if let n = SurfaceGeometry.notchRect(auxLeft: auxLeft, auxRight: auxRight) { return n }
        return CGRect(x: screen.midX - m.virtualNotchWidth / 2, y: screen.maxY, width: m.virtualNotchWidth, height: 0)
    }

    /// Size of the drawn surface for a state; nil ⇒ nothing is drawn. The collapsed badge needs a real
    /// notch to hang from — a pill for notch-less screens is a later phase (B7).
    static func size(for state: NotchSurfaceMachine.State, anchor: NotchSurfaceMachine.Anchor,
                     itemCount: Int, notch: CGRect, timerActive: Bool = false, metrics m: Metrics = .standard) -> CGSize? {
        switch state {
        case .collapsed:
            guard itemCount > 0 || timerActive, notch.height > 0 else { return nil }
            return CGSize(width: notch.width, height: notch.height + m.badgeLip)
        case .peek:
            return CGSize(width: notch.width + 2 * m.peekWing, height: notch.height + m.peekDrop)
        case .activity:
            return CGSize(width: notch.width + 2 * m.activityWing, height: notch.height + m.activityDrop)
        case .expanded where anchor == .pointer:
            return CGSize(width: m.expandedWidth, height: m.expandedDrop)
        case .expanded:
            return CGSize(width: max(m.expandedWidth, notch.width), height: notch.height + m.expandedDrop)
        }
    }

    /// Window frame for a state; nil ⇒ order the window out. At the notch: glued to the top of the
    /// screen, centred on the notch, clamped to the screen. At the pointer: centred under the pointer
    /// by `pointerGap`, clamped to the VISIBLE frame (it must never land under the menu bar or Dock).
    static func frame(for state: NotchSurfaceMachine.State, anchor: NotchSurfaceMachine.Anchor,
                      itemCount: Int, notch: CGRect, screen: CGRect, visible: CGRect,
                      pointer: CGPoint, timerActive: Bool = false, metrics m: Metrics = .standard) -> CGRect? {
        guard let size = size(for: state, anchor: anchor, itemCount: itemCount, notch: notch, timerActive: timerActive, metrics: m) else { return nil }
        if case .expanded = state, anchor == .pointer {
            let centre = CGPoint(x: pointer.x, y: pointer.y - m.pointerGap - size.height / 2)
            return SurfaceGeometry.frame(size: size, anchor: .pointer(centre), screen: screen, visible: visible)
        }
        return SurfaceGeometry.expandedNotchFrame(collapsed: notch, size: size, screen: screen)
    }

    /// Where the pointer must rest for a hover. Only the notch itself — plus the badge lip under it
    /// when files are held, so resting on the count peeks too. Without files the zone stays the bare
    /// notch: the strip under it is the centre of every window's title bar, and grabbing a title bar
    /// must never count as hovering the tray. Notch-less screen: an 8 pt strip at the top centre.
    static func hoverZone(notch: CGRect, screen: CGRect, itemCount: Int, metrics m: Metrics = .standard) -> CGRect {
        guard notch.height > 0 else {
            return CGRect(x: notch.minX, y: screen.maxY - 8, width: notch.width, height: 8)
        }
        let lip = itemCount > 0 ? m.badgeLip : 0
        return CGRect(x: notch.minX, y: notch.minY - lip, width: notch.width, height: notch.height + lip)
    }

    /// Where a FILE drag opens the surface: the notch widened by `dragMargin` each side and reaching
    /// `dragDepth` below the top edge (at least the notch's own height).
    static func dragZone(notch: CGRect, screen: CGRect, metrics m: Metrics = .standard) -> CGRect {
        let depth = max(notch.height, m.dragDepth)
        return CGRect(x: notch.minX - m.dragMargin, y: screen.maxY - depth,
                      width: notch.width + 2 * m.dragMargin, height: depth)
    }
}
