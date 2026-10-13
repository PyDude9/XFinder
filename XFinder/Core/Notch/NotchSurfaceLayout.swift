import Foundation
import CoreGraphics

/// Pure sizes, frames and trigger zones of the Notch surface, so the controller (window frame and
/// hit-testing) and the SwiftUI root (drawn shape) can never disagree. All rects are AppKit space
/// (origin bottom-left), like `SurfaceGeometry`.
enum NotchSurfaceLayout {

    /// P1 (2026-10-13, measured on the owner's OneNotch screenshots: the collapsed shape is 262 × 32 — exactly
    /// the notch's height, nothing hangs below it — with one icon in each WING beside the camera). What can sit
    /// in a wing: the left one carries agents and held files, the right one the track and a countdown.
    enum WingItem: Equatable { case agent, files, music, timer }

    struct Metrics: Equatable {
        /// Collapsed wings: the narrowest wing (262 = 185 + 2 × 38.5, measured), the gap between its content and
        /// the shape's outer edge, the gap between two items, and each item's slot.
        var wingMin: CGFloat = 38.5
        var wingInset: CGFloat = 14
        var wingSpacing: CGFloat = 6
        func wingItemWidth(_ item: WingItem) -> CGFloat {
            switch item {
            case .agent: return 20
            case .files: return 34      // tray glyph + a two-digit count
            case .music: return 24      // the waveform bars, or an 18-pt artwork thumb (one item ⇒ the measured 38.5 wing)
            case .timer: return 50      // timer glyph + "12:34"
            }
        }
        /// The collapsed shape flares into the top edge too, but only a little (measured 275 top edge vs 262 body).
        var collapsedFillet: CGFloat = 6.5
        var collapsedFilletDepth: CGFloat = 4
        /// Measured: a circular arc of r ≈ 14.6 fits the collapsed corners (RMSE 0.5 px); continuous 12 matches it.
        var collapsedBottomRadius: CGFloat = 12
        /// Extra width on EACH side of the notch for the peek strip.
        var peekWing: CGFloat = 56
        /// B6: the peek of a playing track (no files held) needs room for title, artist and three controls.
        var nowPlayingPeekWing: CGFloat = 118
        /// Height of the peek strip below the notch.
        var peekDrop: CGFloat = 40
        /// P1, measured on the owner's OneNotch screenshots (pt = px / 2 of the 700 × 745 window at 2×): every
        /// expanded page has the same 32-pt top BAND (page dots in the left wing, the toolbar in the right one),
        /// and one of two bodies — NARROW 382 × 168 (Now Playing; the tray and the calendar here) or WIDE
        /// 612 × 182 (Clipboard, Agents). The calendar view is taller (188, estimated from a screenshot that is not
        /// on disk). The width follows the page, never the content, so a page switch can only jump between two sizes.
        var bandHeight: CGFloat = 32
        var narrowWidth: CGFloat = 382
        var wideWidth: CGFloat = 612
        var narrowDrop: CGFloat = 136     // 168 − 32
        var wideDrop: CGFloat = 150       // 182 − 32
        var calendarDrop: CGFloat = 156   // 188 − 32
        /// The expanded shape flares into the top edge: the top edge is 650 / 420 for a 612 / 382 body (measured),
        /// so 19 pt each side, settling within a few points of height. The flares sit OUTSIDE the content, so a hub
        /// at the notch is 2 × 19 pt wider than its body. A pointer tray has no top edge to flare into.
        var topFillet: CGFloat = 19
        var topFilletDepth: CGFloat = 8
        /// Measured per-row insets of the tall shapes fit a continuous corner of ≈ 30 (a circle needs r ≈ 35).
        var expandedBottomRadius: CGFloat = 30

        static func isWide(_ page: NotchSurfaceMachine.Page) -> Bool { page == .clipboard || page == .agents }

        /// P1 page budgets. Two pages fill their body to the point, so the numbers live HERE, the views read them, and
        /// `testPageBudgetsFillTheirBodiesExactly` asserts they add up (P1 review: the two halves of each sum had lived in
        /// different files with nothing tying them together).
        /// Clipboard (wide body, 150): 2 + chip row 22 + 6 + card 112 + 8. OneNotch's cards are 163 × 123 in a hub with no
        /// chip row; XFinder keeps its filters, so the card gives up 11 pt of height.
        var clipboardTopInset: CGFloat = 2
        var chipRowHeight: CGFloat = 22
        var chipToDeckGap: CGFloat = 6
        var clipCardWidth: CGFloat = 162
        var clipCardHeight: CGFloat = 112
        var clipCardGap: CGFloat = 11
        var clipboardBottomInset: CGFloat = 8
        /// Every other page: 4 on top, 12 below. Now Playing (narrow body, 136): 4 + artwork 88 + 6 + progress 26 + 12.
        /// (OneNotch's artwork was measured "115" wide, but 115 + the bar + the times cannot fit a 136-pt body.)
        var pageTopInset: CGFloat = 4
        var pageBottomInset: CGFloat = 12
        var artworkSide: CGFloat = 88
        var artworkToProgressGap: CGFloat = 6
        var progressAreaHeight: CGFloat = 26

        func expandedWidth(for page: NotchSurfaceMachine.Page) -> CGFloat {
            Self.isWide(page) ? wideWidth : narrowWidth
        }

        /// Height of the body below the band.
        func expandedDrop(for page: NotchSurfaceMachine.Page) -> CGFloat {
            switch page {
            case .clipboard, .agents: return wideDrop
            case .calendar: return calendarDrop
            case .files, .nowPlaying: return narrowDrop
            }
        }
        /// Live activity strip (B4): extra width each side of the notch, and its depth below it.
        var activityWing: CGFloat = 130
        var activityDrop: CGFloat = 36
        /// Stand-in notch width on a screen without one (external display / iMac).
        var virtualNotchWidth: CGFloat = 185
        /// A screen without a notch: the collapsed state is a pill at the top edge (the virtual notch, D0c). OneNotch's
        /// own default on this Mac's external display: 120 pt wide, ~24 pt tall, widening only when its content needs it.
        var pillWidth: CGFloat = 120
        var pillHeight: CGFloat = 24
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

    /// What sits in each collapsed wing: agents and held files on the left, the track and a countdown on the right.
    static func wingItems(itemCount: Int, timerActive: Bool, nowPlayingActive: Bool,
                          agentActive: Bool) -> (left: [WingItem], right: [WingItem]) {
        var left: [WingItem] = [], right: [WingItem] = []
        if agentActive { left.append(.agent) }
        if itemCount > 0 { left.append(.files) }
        if nowPlayingActive { right.append(.music) }
        if timerActive { right.append(.timer) }
        return (left, right)
    }

    /// Width the items of one side need, edge to edge.
    static func sideWidth(_ items: [WingItem], metrics m: Metrics = .standard) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        return items.map(m.wingItemWidth).reduce(0, +) + m.wingSpacing * CGFloat(items.count - 1)
    }

    /// Both wings are as wide as the fuller side, so the notch stays centred; never narrower than measured.
    static func wingWidth(left: [WingItem], right: [WingItem], metrics m: Metrics = .standard) -> CGFloat {
        guard !(left.isEmpty && right.isEmpty) else { return 0 }
        return max(m.wingMin, max(sideWidth(left, metrics: m), sideWidth(right, metrics: m)) + m.wingInset)
    }

    /// Size of the drawn surface for a state; nil ⇒ nothing is drawn. Collapsed: the notch widened by a wing on
    /// each side and exactly as tall as it (P1), or (`pillOnPlainScreens`) a pill on a screen without a notch.
    static func size(for state: NotchSurfaceMachine.State, anchor: NotchSurfaceMachine.Anchor,
                     itemCount: Int, notch: CGRect, timerActive: Bool = false, nowPlayingActive: Bool = false,
                     agentActive: Bool = false, pillOnPlainScreens: Bool = true, metrics m: Metrics = .standard) -> CGSize? {
        switch state {
        case .collapsed:
            let (left, right) = wingItems(itemCount: itemCount, timerActive: timerActive,
                                          nowPlayingActive: nowPlayingActive, agentActive: agentActive)
            guard !(left.isEmpty && right.isEmpty) else { return nil }
            if notch.height > 0 {
                let wing = wingWidth(left: left, right: right, metrics: m)
                return CGSize(width: notch.width + 2 * wing + 2 * m.collapsedFillet, height: notch.height)
            }
            guard pillOnPlainScreens else { return nil }
            // No camera to keep clear: both sides sit together in the middle of the pill.
            let both = !left.isEmpty && !right.isEmpty
            let content = sideWidth(left, metrics: m) + sideWidth(right, metrics: m) + (both ? 2 * m.wingSpacing : 0)
            return CGSize(width: max(m.pillWidth, content + 2 * m.wingInset), height: m.pillHeight)
        case .peek:
            // Files take precedence in the strip; the wider now-playing strip only when none are held.
            let wing = (itemCount == 0 && nowPlayingActive) ? m.nowPlayingPeekWing : m.peekWing
            return CGSize(width: notch.width + 2 * wing, height: notch.height + m.peekDrop)
        case .activity:
            return CGSize(width: notch.width + 2 * m.activityWing, height: notch.height + m.activityDrop)
        case .expanded(let page) where anchor == .pointer:
            return CGSize(width: m.expandedWidth(for: page), height: m.bandHeight + m.expandedDrop(for: page))
        case .expanded(let page):
            // The band is the notch's own strip — at least 32 pt, also on a screen without a notch.
            return CGSize(width: max(m.expandedWidth(for: page), notch.width) + 2 * m.topFillet,
                          height: max(notch.height, m.bandHeight) + m.expandedDrop(for: page))
        }
    }

    /// Window frame for a state; nil ⇒ order the window out. At a real notch: glued to the top of the
    /// screen, centred on the notch. On a screen WITHOUT a notch (B7): the same shapes hang from the
    /// bottom of the menu bar instead — the top edge there is the menu bar, which must stay usable.
    /// At the pointer: centred under the pointer by `pointerGap`, clamped to the VISIBLE frame.
    static func frame(for state: NotchSurfaceMachine.State, anchor: NotchSurfaceMachine.Anchor,
                      itemCount: Int, notch: CGRect, screen: CGRect, visible: CGRect,
                      pointer: CGPoint, timerActive: Bool = false, nowPlayingActive: Bool = false,
                      agentActive: Bool = false, pillOnPlainScreens: Bool = true, metrics m: Metrics = .standard) -> CGRect? {
        guard let size = size(for: state, anchor: anchor, itemCount: itemCount, notch: notch,
                              timerActive: timerActive, nowPlayingActive: nowPlayingActive, agentActive: agentActive,
                              pillOnPlainScreens: pillOnPlainScreens, metrics: m) else { return nil }
        if case .expanded = state, anchor == .pointer {
            let centre = CGPoint(x: pointer.x, y: pointer.y - m.pointerGap - size.height / 2)
            return SurfaceGeometry.frame(size: size, anchor: .pointer(centre), screen: screen, visible: visible)
        }
        if notch.height > 0 { return SurfaceGeometry.expandedNotchFrame(collapsed: notch, size: size, screen: screen) }
        // D0c (user, 2026-10-12, after the OneNotch reference): a screen WITHOUT a notch gets a VIRTUAL one —
        // every state hangs from the top edge over the menu bar's centre, exactly as at a real notch, so the
        // surface looks the same on an external display. (B7 hung it under the menu bar; that is withdrawn.)
        let w = min(size.width, screen.width)
        return SurfaceGeometry.clamp(CGRect(x: notch.midX - w / 2, y: notch.maxY - size.height, width: w, height: size.height), into: screen)
    }

    /// N1 (2026-10-13, after measuring OneNotch: its notch window is ONE fixed 700×745 panel whose frame
    /// never changes while the content animates inside it). The surface at a notch now lives in a fixed
    /// window big enough for EVERY notch-anchored state — collapsed badge, peek, activity strip, every
    /// hub page — centred on the notch and glued to the top edge, so a state change never calls
    /// `setFrame` (the grow / shrink-after-0.32 s / union dance of D0c is gone with it). The transparent
    /// part of the window must let clicks through (measured with `NSWindow.windowNumber(at:)`), and the
    /// drop target / hit-tests use `frame(for:)` of the DRAWN state, never this frame.
    static func panelSize(notch: CGRect, timerActive: Bool = false, metrics m: Metrics = .standard) -> CGSize {
        let all: [WingItem] = [.agent, .files, .music, .timer]
        let fullWing = wingWidth(left: [.agent, .files], right: [.music, .timer], metrics: m)
        let widths: [CGFloat] = [
            max(m.wideWidth, m.narrowWidth, notch.width) + 2 * m.topFillet,          // every hub page, flares included
            notch.width + 2 * fullWing + 2 * m.collapsedFillet,                      // the fullest collapsed wings
            notch.width + 2 * m.nowPlayingPeekWing, notch.width + 2 * m.activityWing,
            max(m.pillWidth, sideWidth(all, metrics: m) + 2 * m.wingSpacing + 2 * m.wingInset),
        ]
        let drops: [CGFloat] = [m.narrowDrop, m.wideDrop, m.calendarDrop, m.peekDrop, m.activityDrop]
        let band = max(notch.height, m.bandHeight)
        return CGSize(width: widths.max() ?? 0, height: max(band + (drops.max() ?? 0), m.pillHeight))
    }

    /// The fixed window frame at a notch (real or virtual): `panelSize`, centred on the notch, top glued to
    /// the screen's top edge, never wider than the screen.
    static func panelFrame(notch: CGRect, screen: CGRect, metrics m: Metrics = .standard) -> CGRect {
        let size = panelSize(notch: notch, metrics: m)
        let w = min(size.width, screen.width)
        return SurfaceGeometry.clamp(CGRect(x: notch.midX - w / 2, y: notch.maxY - size.height, width: w, height: size.height), into: screen)
    }

    /// The pill's own rect on a plain screen (what the hover zone becomes while it is shown): at the top edge.
    static func pillRect(notch: CGRect, visible: CGRect, width: CGFloat? = nil, metrics m: Metrics = .standard) -> CGRect {
        let w = width ?? m.pillWidth
        return CGRect(x: notch.midX - w / 2, y: notch.maxY - m.pillHeight, width: w, height: m.pillHeight)
    }

    /// Where the pointer must rest for a hover: the collapsed shape as drawn — the notch plus its wings while
    /// something sits in them (P1: the wings are BESIDE the camera, in the menu-bar strip, never below it), else
    /// the bare notch. Nothing under the notch ever counts: that strip is the centre of every window's title bar,
    /// and grabbing a title bar must never count as hovering the tray. Notch-less screen: the pill while it is
    /// shown, else an 8-pt strip at the top centre.
    static func hoverZone(notch: CGRect, screen: CGRect, itemCount: Int, nowPlayingActive: Bool = false,
                          timerActive: Bool = false, agentActive: Bool = false,
                          visible: CGRect? = nil, pillShown: Bool = false, metrics m: Metrics = .standard) -> CGRect {
        let collapsed = size(for: .collapsed, anchor: .notch, itemCount: itemCount, notch: notch, timerActive: timerActive,
                             nowPlayingActive: nowPlayingActive, agentActive: agentActive, metrics: m)
        guard notch.height > 0 else {
            if pillShown, let visible { return pillRect(notch: notch, visible: visible, width: collapsed?.width, metrics: m) }
            return CGRect(x: notch.minX, y: screen.maxY - 8, width: notch.width, height: 8)
        }
        guard let c = collapsed else { return notch }
        return CGRect(x: notch.midX - c.width / 2, y: notch.minY, width: c.width, height: notch.height)
    }

    /// Where a FILE drag opens the surface: the notch widened by `dragMargin` each side and reaching
    /// `dragDepth` below the top edge (at least the notch's own height).
    static func dragZone(notch: CGRect, screen: CGRect, metrics m: Metrics = .standard) -> CGRect {
        let depth = max(notch.height, m.dragDepth)
        return CGRect(x: notch.minX - m.dragMargin, y: screen.maxY - depth,
                      width: notch.width + 2 * m.dragMargin, height: depth)
    }
}
