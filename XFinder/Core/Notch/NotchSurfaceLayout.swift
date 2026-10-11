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
        /// B6: the peek of a playing track (no files held) needs room for title, artist and three controls.
        var nowPlayingPeekWing: CGFloat = 118
        /// Height of the peek strip below the notch.
        var peekDrop: CGFloat = 40
        /// Expanded surface: width, and height below the notch (or total height at the pointer).
        var expandedWidth: CGFloat = 440
        var expandedDrop: CGFloat = 222   // B2d: + action row and result line
        /// D0: the clipboard page follows the OneNotch reference the user supplied — a WIDE hub whose top
        /// band sits either side of the notch (tabs left, search right), a chip row, then ONE horizontal row
        /// of four 174×122 cards. 752 = 4 × 174 + 3 × 8 + 2 × 12 (hub inset); its drop is 200 (band 32 +
        /// chips + deck + footer). The hub's size follows the page; the other pages keep 440 × 222.
        var clipboardExpandedWidth: CGFloat = 752
        var clipboardExpandedDrop: CGFloat = 200

        func expandedWidth(for page: NotchSurfaceMachine.Page) -> CGFloat {
            page == .clipboard ? clipboardExpandedWidth : expandedWidth
        }

        func expandedDrop(for page: NotchSurfaceMachine.Page) -> CGFloat {
            page == .clipboard ? clipboardExpandedDrop : expandedDrop
        }
        /// Live activity strip (B4): extra width each side of the notch, and its depth below it.
        var activityWing: CGFloat = 130
        var activityDrop: CGFloat = 36
        /// Stand-in notch width on a screen without one (external display / iMac).
        var virtualNotchWidth: CGFloat = 185
        /// B7: on a screen without a notch the collapsed state is a free-standing pill hanging under the
        /// menu bar (there is no notch to hang a lip from, and the menu bar centre must stay clickable).
        var pillWidth: CGFloat = 170
        var pillHeight: CGFloat = 22
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

    /// Size of the drawn surface for a state; nil ⇒ nothing is drawn. Collapsed: a badge under a real
    /// notch, or (B7, `pillOnPlainScreens`) a pill under the menu bar of a screen without one.
    static func size(for state: NotchSurfaceMachine.State, anchor: NotchSurfaceMachine.Anchor,
                     itemCount: Int, notch: CGRect, timerActive: Bool = false, nowPlayingActive: Bool = false,
                     pillOnPlainScreens: Bool = true, metrics m: Metrics = .standard) -> CGSize? {
        switch state {
        case .collapsed:
            guard itemCount > 0 || timerActive || nowPlayingActive else { return nil }
            if notch.height > 0 { return CGSize(width: notch.width, height: notch.height + m.badgeLip) }
            guard pillOnPlainScreens else { return nil }
            return CGSize(width: m.pillWidth, height: m.pillHeight)
        case .peek:
            // Files take precedence in the strip; the wider now-playing strip only when none are held.
            let wing = (itemCount == 0 && nowPlayingActive) ? m.nowPlayingPeekWing : m.peekWing
            return CGSize(width: notch.width + 2 * wing, height: notch.height + m.peekDrop)
        case .activity:
            return CGSize(width: notch.width + 2 * m.activityWing, height: notch.height + m.activityDrop)
        case .expanded(let page) where anchor == .pointer:
            return CGSize(width: m.expandedWidth(for: page), height: m.expandedDrop(for: page))
        case .expanded(let page):
            return CGSize(width: max(m.expandedWidth(for: page), notch.width), height: notch.height + m.expandedDrop(for: page))
        }
    }

    /// Window frame for a state; nil ⇒ order the window out. At a real notch: glued to the top of the
    /// screen, centred on the notch. On a screen WITHOUT a notch (B7): the same shapes hang from the
    /// bottom of the menu bar instead — the top edge there is the menu bar, which must stay usable.
    /// At the pointer: centred under the pointer by `pointerGap`, clamped to the VISIBLE frame.
    static func frame(for state: NotchSurfaceMachine.State, anchor: NotchSurfaceMachine.Anchor,
                      itemCount: Int, notch: CGRect, screen: CGRect, visible: CGRect,
                      pointer: CGPoint, timerActive: Bool = false, nowPlayingActive: Bool = false,
                      pillOnPlainScreens: Bool = true, metrics m: Metrics = .standard) -> CGRect? {
        guard let size = size(for: state, anchor: anchor, itemCount: itemCount, notch: notch,
                              timerActive: timerActive, nowPlayingActive: nowPlayingActive,
                              pillOnPlainScreens: pillOnPlainScreens, metrics: m) else { return nil }
        if case .expanded = state, anchor == .pointer {
            let centre = CGPoint(x: pointer.x, y: pointer.y - m.pointerGap - size.height / 2)
            return SurfaceGeometry.frame(size: size, anchor: .pointer(centre), screen: screen, visible: visible)
        }
        if notch.height > 0 { return SurfaceGeometry.expandedNotchFrame(collapsed: notch, size: size, screen: screen) }
        let w = min(size.width, screen.width)
        return SurfaceGeometry.clamp(CGRect(x: notch.midX - w / 2, y: visible.maxY - size.height, width: w, height: size.height), into: screen)
    }

    /// The pill's own rect on a plain screen (what the hover zone becomes while it is shown).
    static func pillRect(notch: CGRect, visible: CGRect, metrics m: Metrics = .standard) -> CGRect {
        CGRect(x: notch.midX - m.pillWidth / 2, y: visible.maxY - m.pillHeight, width: m.pillWidth, height: m.pillHeight)
    }

    /// Where the pointer must rest for a hover. Only the notch itself — plus the badge lip under it
    /// when files are held (or a track is playing — B6), so resting on the badge peeks too. Otherwise
    /// the zone stays the bare notch: the strip under it is the centre of every window's title bar,
    /// and grabbing a title bar must never count as hovering the tray. Notch-less screen: an 8 pt
    /// strip at the top centre.
    static func hoverZone(notch: CGRect, screen: CGRect, itemCount: Int, nowPlayingActive: Bool = false,
                          visible: CGRect? = nil, pillShown: Bool = false, metrics m: Metrics = .standard) -> CGRect {
        guard notch.height > 0 else {
            // B7: while the pill hangs under the menu bar it IS the hover target; otherwise the bare
            // 8 pt strip in the menu bar (never the title-bar strip below it).
            if pillShown, let visible { return pillRect(notch: notch, visible: visible, metrics: m) }
            return CGRect(x: notch.minX, y: screen.maxY - 8, width: notch.width, height: 8)
        }
        let lip = (itemCount > 0 || nowPlayingActive) ? m.badgeLip : 0
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
