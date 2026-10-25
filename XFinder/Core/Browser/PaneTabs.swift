import Foundation
import CoreGraphics

/// XF-T30 W1 — tabs inside one pane (FileOctopus "pane tabs", ⌃⌥⌘T): the pure list a pane keeps and the drop rules for
/// a dragged tab. Pure (Foundation + CoreGraphics), symlinked into the test package. Contract:
/// `docs/specs/XF-T30-w1-contract.md`.
struct TabID: Hashable, Codable, Sendable {
    let raw: UUID
    init() { raw = UUID() }
    init(raw: UUID) { self.raw = raw }
}

/// One pane's ordered tabs and which one shows. Never empty: a pane always has at least one tab.
struct PaneTabList: Codable, Equatable, Sendable {
    private(set) var tabs: [TabID]
    private(set) var selected: Int

    init(first: TabID) {
        tabs = [first]
        selected = 0
    }

    var selectedTab: TabID { tabs[selected] }
    var count: Int { tabs.count }

    /// A new tab goes right after the selected one and becomes selected (Finder and FileOctopus).
    mutating func add(_ tab: TabID) {
        // W1 builder: implement.
    }

    @discardableResult
    mutating func select(_ tab: TabID) -> Bool {
        false   // W1 builder: implement.
    }

    /// Cyclic.
    mutating func selectNext() {}
    mutating func selectPrevious() {}

    /// Removes `tab`. Refuses (returns false) when it is the only tab — the caller decides whether that closes the pane
    /// (Q-T30-4). Selection moves to the right neighbour, else the left one; removing an unselected tab keeps the
    /// selected tab selected.
    @discardableResult
    mutating func remove(_ tab: TabID) -> Bool {
        false   // W1 builder: implement.
    }

    /// Inserts at `index` (clamped to 0...count). An id already in the list is moved instead of duplicated.
    mutating func insert(_ tab: TabID, at index: Int, select: Bool) {}

    /// Reorders within the list; the selected tab stays selected.
    mutating func move(_ tab: TabID, to index: Int) {}
}

enum PaneTabRules {
    /// Where a tab dragged over a pane lands.
    enum DropTarget: Equatable, Sendable {
        /// On the pane's tab strip: insert at this index.
        case strip(index: Int)
        /// In an edge zone: split the pane that way and put the tab in the new pane.
        case edge(SplitDirection)
        /// Anywhere else in the pane: append as the last tab.
        case center
    }

    /// An edge zone is this fraction of the pane's width/height, capped at `edgeZoneMax` points — FileOctopus 1.0.4 had to
    /// tighten its edge docking ("dragging a pane tab onto the edge of another pane docked it there"), so the zone is
    /// a deliberate thin band, not a quarter of the pane.
    static let edgeZoneFraction: CGFloat = 0.18
    static let edgeZoneMax: CGFloat = 56

    /// `point` and `paneRect` in the same top-left coordinate space; the strip is the top `stripHeight` points of the
    /// pane; `tabFrames` are the tabs' frames on that strip, in order. On the strip ⇒ `.strip(index)` where the index is
    /// the slot whose midpoint the point is before; in an edge band (outside the strip) ⇒ `.edge`; ties between two
    /// bands (a corner) go to the nearer edge; else `.center`.
    static func dropTarget(point: CGPoint, paneRect: CGRect, stripHeight: CGFloat, tabFrames: [CGRect]) -> DropTarget {
        .center   // W1 builder: implement.
    }
}
