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
        let insertAt = selected + 1
        if let existing = tabs.firstIndex(of: tab) {
            tabs.remove(at: existing)
            let adjusted = existing < insertAt ? insertAt - 1 : insertAt
            tabs.insert(tab, at: min(adjusted, tabs.count))
        } else {
            tabs.insert(tab, at: insertAt)
        }
        selected = tabs.firstIndex(of: tab) ?? insertAt
    }

    @discardableResult
    mutating func select(_ tab: TabID) -> Bool {
        guard let i = tabs.firstIndex(of: tab) else { return false }
        selected = i
        return true
    }

    /// Cyclic.
    mutating func selectNext() {
        guard !tabs.isEmpty else { return }
        selected = (selected + 1) % tabs.count
    }

    mutating func selectPrevious() {
        guard !tabs.isEmpty else { return }
        selected = (selected - 1 + tabs.count) % tabs.count
    }

    /// Removes `tab`. Refuses (returns false) when it is the only tab — the caller decides whether that closes the pane
    /// (Q-T30-4). Selection moves to the right neighbour, else the left one; removing an unselected tab keeps the
    /// selected tab selected.
    @discardableResult
    mutating func remove(_ tab: TabID) -> Bool {
        guard tabs.count > 1, let i = tabs.firstIndex(of: tab) else { return false }
        let wasSelected = tabs[selected]
        tabs.remove(at: i)
        if wasSelected == tab {
            // Right neighbour first (same index now holds what used to be the right neighbour), else left.
            selected = min(i, tabs.count - 1)
        } else if let newIndex = tabs.firstIndex(of: wasSelected) {
            selected = newIndex
        }
        return true
    }

    /// Inserts at `index` (clamped to 0...count). An id already in the list is moved instead of duplicated.
    mutating func insert(_ tab: TabID, at index: Int, select: Bool) {
        let wasSelected = tabs[selected]
        if let existing = tabs.firstIndex(of: tab) {
            tabs.remove(at: existing)
        }
        let clamped = min(max(index, 0), tabs.count)
        tabs.insert(tab, at: clamped)
        if select {
            selected = clamped
        } else if let i = tabs.firstIndex(of: wasSelected) {
            selected = i
        }
    }

    /// Reorders within the list; the selected tab stays selected.
    mutating func move(_ tab: TabID, to index: Int) {
        guard let from = tabs.firstIndex(of: tab) else { return }
        let wasSelected = tabs[selected]
        tabs.remove(at: from)
        let clamped = min(max(index, 0), tabs.count)
        tabs.insert(tab, at: clamped)
        if let i = tabs.firstIndex(of: wasSelected) {
            selected = i
        }
    }
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
        // The tab strip sits at the top of the pane; a point there (even if it's also within the top edge band)
        // always inserts into the strip — the strip claims that space entirely.
        let stripRect = CGRect(x: paneRect.minX, y: paneRect.minY, width: paneRect.width, height: stripHeight)
        if stripRect.contains(point) {
            return .strip(index: stripIndex(for: point, tabFrames: tabFrames))
        }

        let edgeZone = min(edgeZoneMax, edgeZoneFraction * min(paneRect.width, paneRect.height))
        // Distance inward from each of the four edges; negative means outside paneRect on that side.
        let distLeft = point.x - paneRect.minX
        let distRight = paneRect.maxX - point.x
        let distTop = point.y - paneRect.minY
        let distBottom = paneRect.maxY - point.y

        guard paneRect.contains(point) else { return .center }

        // Candidate edges the point is within the edge band of (below the top strip for the top edge, since the
        // strip already claimed that band above).
        var candidates: [(SplitDirection, CGFloat)] = []
        if distLeft <= edgeZone { candidates.append((.left, distLeft)) }
        if distRight <= edgeZone { candidates.append((.right, distRight)) }
        if distTop - stripHeight <= edgeZone, distTop >= stripHeight { candidates.append((.up, distTop - stripHeight)) }
        if distBottom <= edgeZone { candidates.append((.down, distBottom)) }

        guard let nearest = candidates.min(by: { $0.1 < $1.1 }) else { return .center }
        return .edge(nearest.0)
    }

    /// The slot index `point.x` falls before, measured against each tab frame's horizontal midpoint — a drop past
    /// the last tab's midpoint lands at `count` (append at the end of the strip).
    private static func stripIndex(for point: CGPoint, tabFrames: [CGRect]) -> Int {
        for (i, frame) in tabFrames.enumerated() {
            let midX = frame.midX
            if point.x < midX {
                return i
            }
        }
        return tabFrames.count
    }
}
