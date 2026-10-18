import CoreGraphics

/// XF-T24 (2026-10-18) — geometry of the screen-edge notes panel, as pure functions (symlinked into the test package).
///
/// Why it exists: the peek card was a fixed 186×118 pt with `lineLimit(6)`, and while peeking the panel was only as tall as the
/// pill stack + 24 pt — so with one or two notes the card was CLIPPED below six lines, and a nine-line note never showed whole.
/// The hit test also assumed the stack was centred in the panel while the view pinned it to the top (~12 pt off). Here the stack
/// lives in ONE fixed screen rect that never moves while peeking, the card is as tall as its text (up to a cap) and is pushed up
/// to stay on screen, and the panel is simply the union of the two.
///
/// All rects are AppKit space (origin bottom-left, y up).
enum EdgeNotesLayout {
    static let tabWidth: CGFloat = 9
    static let tabHeight: CGFloat = 28
    static let tabGap: CGFloat = 4
    /// Room around the stack for the pills' shadows.
    static let slack: CGFloat = 12
    static let cardWidth: CGFloat = 248
    static let cardGap: CGFloat = 6
    static let cardPadding: CGFloat = 10
    /// Title line + divider + spacing above the body, measured from the card's SwiftUI layout (11 pt semibold + 6 + 1 + 6).
    static let cardChrome: CGFloat = 2 * cardPadding + 14 + 13
    static let minCardHeight: CGFloat = 72
    /// Margin kept between the card and the visible frame's edges.
    static let screenMargin: CGFloat = 8

    static func stackHeight(count: Int) -> CGFloat {
        let n = max(count, 1)
        return CGFloat(n) * tabHeight + CGFloat(n - 1) * tabGap
    }

    /// The pills' rect, vertically centred on the visible frame and flush with the chosen edge — the same whatever is peeked.
    static func stackRect(count: Int, visible: CGRect, screen: CGRect, onLeft: Bool) -> CGRect {
        let h = stackHeight(count: count)
        let x = onLeft ? screen.minX : screen.maxX - tabWidth
        return CGRect(x: x, y: visible.midY - h / 2, width: tabWidth, height: h)
    }

    /// Which pill a pointer Y falls on (nil between the stack's ends only when outside it).
    static func index(at y: CGFloat, stack: CGRect, count: Int) -> Int? {
        guard count > 0, y <= stack.maxY, y >= stack.minY else { return nil }
        let i = Int((stack.maxY - y) / (tabHeight + tabGap))
        return (0..<count).contains(i) ? i : nil
    }

    /// The tallest a card may be: 60 % of the visible frame, never more than 520 pt, never less than the minimum.
    static func maxCardHeight(visible: CGRect) -> CGFloat {
        max(minCardHeight, min(520, visible.height * 0.6))
    }

    /// Card height for a body whose laid-out text is `bodyHeight` tall at `cardWidth`; `truncated` when the cap cut it.
    static func cardHeight(bodyHeight: CGFloat, visible: CGRect) -> (height: CGFloat, truncated: Bool) {
        let want = cardChrome + ceil(bodyHeight)
        let cap = maxCardHeight(visible: visible)
        return (min(max(want, minCardHeight), cap), want > cap)
    }

    struct Peek: Equatable {
        /// The panel's frame.
        var panel: CGRect
        /// Distance from the panel's top to the stack's top (SwiftUI top padding of the stack).
        var stackTopInset: CGFloat
        /// How far the card sits ABOVE its pill's top because it would otherwise leave the screen (≥ 0).
        var cardLift: CGFloat
    }

    /// Panel geometry while peeking pill `index` with a card `cardHeight` tall. The stack keeps its fixed rect; the card starts at
    /// its pill's top and is lifted just enough to stay inside the visible frame.
    static func peek(index: Int, count: Int, cardHeight: CGFloat, visible: CGRect, screen: CGRect, onLeft: Bool) -> Peek {
        let stack = stackRect(count: count, visible: visible, screen: screen, onLeft: onLeft)
        let rowTop = stack.maxY - CGFloat(max(0, min(index, count - 1))) * (tabHeight + tabGap)
        var cardTop = rowTop
        let floor = visible.minY + screenMargin
        if cardTop - cardHeight < floor { cardTop = floor + cardHeight }
        cardTop = min(cardTop, visible.maxY - screenMargin)
        let top = max(stack.maxY + slack, cardTop + slack)
        let bottom = min(stack.minY - slack, cardTop - cardHeight - slack)
        let width = tabWidth + cardGap + cardWidth + slack
        let x = onLeft ? screen.minX : screen.maxX - width
        return Peek(panel: CGRect(x: x, y: bottom, width: width, height: top - bottom),
                    stackTopInset: top - stack.maxY, cardLift: cardTop - rowTop)
    }

    /// Panel geometry with no card: just the stack and its slack.
    static func docked(count: Int, visible: CGRect, screen: CGRect, onLeft: Bool) -> Peek {
        let stack = stackRect(count: count, visible: visible, screen: screen, onLeft: onLeft)
        let x = onLeft ? screen.minX : screen.maxX - tabWidth
        return Peek(panel: CGRect(x: x, y: stack.minY - slack, width: tabWidth, height: stack.height + 2 * slack),
                    stackTopInset: slack, cardLift: 0)
    }
}
