import Foundation

/// D1 #44 / #43 / #47 — which pages the notch hub shows and in what order, the two-finger swipe that
/// changes page, and the named accent colours. Pure, so the three settings are tested without AppKit.
enum NotchPages {
    typealias Page = NotchSurfaceMachine.Page

    // MARK: - Order and visibility (`notch.pages`, a comma list)

    static let key = "notch.pages"
    static let defaultOrder: [Page] = [.files, .clipboard, .nowPlaying, .agents, .calendar, .timer, .aiUsage]
    static let defaultRaw = "files,clipboard,nowPlaying,agents,calendar,timer,aiUsage"

    /// The stored list → pages. Unknown tokens are dropped, duplicates collapse to their first position,
    /// order is kept. An EMPTY result falls back to the default: a hub with no page is not a state the
    /// surface can draw, so "hide everything" reads as "default", never as a dead surface.
    static func parse(_ raw: String?) -> [Page] {
        var out: [Page] = []
        for token in (raw ?? "").split(separator: ",") {
            let t = token.trimmingCharacters(in: .whitespaces)
            if let p = Page(rawValue: t), !out.contains(p) { out.append(p) }
        }
        return out.isEmpty ? defaultOrder : out
    }

    static func serialize(_ pages: [Page]) -> String { pages.map(\.rawValue).joined(separator: ",") }

    /// Every page, shown or not, in display order — the settings list. Hidden pages trail in default order.
    static func allInOrder(shown: [Page]) -> [Page] { shown + defaultOrder.filter { !shown.contains($0) } }

    /// A request for a hidden page lands on the first shown one (the badge click asks for `.files`;
    /// if the tray tab is hidden the hub still has to open on something).
    static func resolve(_ page: Page, shown: [Page]) -> Page {
        shown.contains(page) ? page : (shown.first ?? defaultOrder[0])
    }

    /// Hide a shown page (never the last one) or show a hidden page at the end.
    static func toggled(_ page: Page, in shown: [Page]) -> [Page] {
        if let i = shown.firstIndex(of: page) {
            return shown.count > 1 ? Array(shown[..<i] + shown[(i + 1)...]) : shown
        }
        return shown + [page]
    }

    /// Move a page one step; the ends stay put.
    static func moved(_ page: Page, by delta: Int, in shown: [Page]) -> [Page] {
        guard let i = shown.firstIndex(of: page) else { return shown }
        let j = i + delta
        guard j >= 0, j < shown.count else { return shown }
        var out = shown
        out.swapAt(i, j)
        return out
    }

    // MARK: - Swipe (two fingers, horizontal, over the tab band)

    /// Sums horizontal scroll deltas and fires once per gesture past the threshold. On a trackpad with
    /// natural scrolling the fingers moving RIGHT give a positive delta, which — like a page curl — means
    /// "previous page"; fingers moving left means "next". Tested with the sign spelled out.
    struct SwipeAccumulator: Equatable {
        static let threshold: Double = 60
        private(set) var total: Double = 0
        private(set) var fired = false

        /// +1 = next page, −1 = previous, nil = nothing yet (or already fired in this gesture).
        mutating func feed(deltaX: Double) -> Int? {
            guard !fired else { return nil }
            total += deltaX
            if total <= -Self.threshold { fired = true; return 1 }
            if total >= Self.threshold { fired = true; return -1 }
            return nil
        }

        /// The gesture ended (fingers lifted): the next one starts from zero.
        mutating func reset() { total = 0; fired = false }
    }

    /// P1 (OneNotch grammar, measured): the hub has two ways in. The page DOTS in the left wing are a swipeable
    /// sequence of content pages; the TOOLBAR capsule in the right wing holds fixed tools that are not part of the
    /// sequence (a lit icon = that tool is open, and no dot is lit then). P2: the calendar, Hẹn giờ and Hạn mức AI.
    static let toolbarPages: Set<Page> = [.calendar, .timer, .aiUsage]
    static func dots(_ shown: [Page]) -> [Page] { shown.filter { !toolbarPages.contains($0) } }
    static func toolbar(_ shown: [Page]) -> [Page] { shown.filter { toolbarPages.contains($0) } }

    /// What a two-finger swipe over the band does on `current`: walk the dots, or nothing while a TOOL is open — the
    /// calendar is not in the sequence, and `pageAfterSwipe`'s "not shown ⇒ first page" fallback would otherwise throw
    /// the user from the calendar to the first dot whichever way they swiped (P1 review).
    static func swipeTarget(from current: Page, direction: Int, pages: [Page]) -> Page? {
        guard !toolbarPages.contains(current) else { return nil }
        return pageAfterSwipe(current, direction: direction, shown: dots(pages))
    }

    /// ONE title key and ONE symbol per page, for the hub's dots/toolbar AND the settings list (P2: the two views each kept
    /// their own copy, and the copies had already drifted — the tray had two different icons). The key goes through
    /// `L10n.t` at the call site; `testEveryPageTitleIsInTheStore` walks `Page.allCases`, because a variable-passed key
    /// is invisible to the literal sweeps.
    static func titleKey(_ p: Page) -> String {
        switch p {
        case .files: return "Khay"
        case .clipboard: return "Clipboard"
        case .nowPlaying: return "Đang phát"
        case .agents: return "Agent AI"
        case .calendar: return "Lịch"
        case .timer: return "Hẹn giờ"
        case .aiUsage: return "Hạn mức AI"
        }
    }

    static func symbol(_ p: Page) -> String {
        switch p {
        case .files: return "tray.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .nowPlaying: return "music.note"
        case .agents: return "terminal.fill"
        case .calendar: return "calendar"
        case .timer: return "timer"
        case .aiUsage: return "gauge.with.dots.needle.50percent"
        }
    }

    /// The page a swipe lands on, or nil at either end (no wrap: an end must feel like an end).
    static func pageAfterSwipe(_ current: Page, direction: Int, shown: [Page]) -> Page? {
        guard let i = shown.firstIndex(of: current) else { return shown.first }
        let j = i + direction
        return (j >= 0 && j < shown.count) ? shown[j] : nil
    }
}

/// D1 #47 — the accent colour of the notch surfaces (`notch.accent`). "system" means the app's own accent.
enum NotchAccent {
    static let key = "notch.accent"
    static let choices = ["system", "blue", "purple", "pink", "orange", "green", "teal"]

    /// sRGB in 0…1; nil for "system" and for anything unknown (which then also means "system").
    static func rgb(named name: String) -> (red: Double, green: Double, blue: Double)? {
        switch name {
        case "blue":   return (10 / 255.0, 132 / 255.0, 255 / 255.0)
        case "purple": return (191 / 255.0, 90 / 255.0, 242 / 255.0)
        case "pink":   return (255 / 255.0, 55 / 255.0, 95 / 255.0)
        case "orange": return (255 / 255.0, 159 / 255.0, 10 / 255.0)
        case "green":  return (48 / 255.0, 209 / 255.0, 88 / 255.0)
        case "teal":   return (100 / 255.0, 210 / 255.0, 255 / 255.0)
        default:       return nil
        }
    }
}
