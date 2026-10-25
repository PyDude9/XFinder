import CoreGraphics

/// XF-T28 (2026-10-24) — the split-pane tree behind the file browser window: a binary tree of panes, each leaf a
/// `PaneID`, each internal node an axis + split fraction. Pure geometry and tree surgery only; the view owns NSView
/// hierarchy and drag gestures.
///
/// Why `CGRect`/`CGPoint` need `import CoreGraphics` here even though the file is otherwise Foundation-only: measured
/// 2026-10-24 (see `EdgeNotesLayout.swift` for the precedent) — Foundation alone does not make `CGRect` conform to
/// `Equatable`/`Sendable` or provide its initializer; only `CoreGraphics` does.
///
/// `PaneID` needs an explicit `Comparable`: a plain `struct` does not synthesize it (only `Equatable`/`Hashable` are
/// synthesized from stored properties), so `panes.sorted()` or any ordering callers want has to go through `raw`.
struct PaneID: Hashable, Codable, Sendable, Comparable {
    let raw: Int
    static func < (lhs: PaneID, rhs: PaneID) -> Bool { lhs.raw < rhs.raw }
}

/// `horizontal`: the two children sit side by side, split by a vertical divider line.
/// `vertical`: the two children stack, split by a horizontal divider line.
enum SplitAxis: String, Codable, Sendable {
    case horizontal
    case vertical
}

enum SplitDirection: String, Codable, Sendable, CaseIterable {
    case right, left, down, up
}

enum PanePreset: String, Codable, Sendable, CaseIterable {
    case single, sideBySide, stacked, grid
}

indirect enum PaneNode: Codable, Equatable, Sendable {
    case leaf(PaneID)
    /// `fraction` is the share of the node's own rect given to `first` along `axis`.
    case split(axis: SplitAxis, fraction: Double, first: PaneNode, second: PaneNode)
}

/// A divider segment between two children of one split node, already placed in window coordinates.
struct PaneDivider: Equatable, Sendable {
    /// Path from the root to the split node this divider belongs to (false = first, true = second), so a caller can
    /// feed it straight back into `setFraction(at:_:)` while dragging.
    let path: [Bool]
    let axis: SplitAxis
    let rect: CGRect
    /// The split node's own rect, before the divider carved it into two children — useful for clamping a drag.
    let parent: CGRect
}

struct PaneTree: Codable, Equatable, Sendable {
    static let maxPanes = 16
    /// No pane may be squeezed below 8% of its parent node's extent along the split axis.
    static let minFraction = 0.08

    private(set) var root: PaneNode
    private(set) var nextID: Int
    private(set) var zoomed: PaneID?

    init() {
        root = .leaf(PaneID(raw: 0))
        nextID = 1
    }

    /// Depth-first, `first` before `second` — the read order every other file (history, snapshots, "other pane") relies on.
    var panes: [PaneID] {
        Self.leaves(of: root)
    }

    var count: Int { panes.count }

    var canSplit: Bool { count < Self.maxPanes }

    func contains(_ pane: PaneID) -> Bool {
        panes.contains(pane)
    }

    /// Splits `pane` in direction `dir`, inserting a fresh pane at a 50/50 fraction. `right`/`down` put the new pane
    /// on the `second` side (further right / further down); `left`/`up` put it on `first`. Returns `nil` when the
    /// tree is already full or `pane` is not present — the caller disables the split command at 16 panes rather than
    /// silently doing nothing, so this is the signal to do that.
    @discardableResult
    mutating func split(_ pane: PaneID, _ dir: SplitDirection) -> PaneID? {
        guard canSplit, contains(pane) else { return nil }
        let newID = PaneID(raw: nextID)
        let axis: SplitAxis = (dir == .left || dir == .right) ? .horizontal : .vertical
        let newIsSecond = (dir == .right || dir == .down)
        root = Self.replacing(pane, in: root) { leaf in
            let newLeaf = PaneNode.leaf(newID)
            return newIsSecond
                ? .split(axis: axis, fraction: 0.5, first: leaf, second: newLeaf)
                : .split(axis: axis, fraction: 0.5, first: newLeaf, second: leaf)
        }
        nextID += 1
        zoomed = nil
        return newID
    }

    /// Removes `pane`; its sibling (and the sibling's whole subtree) takes over the parent split node's spot. Never
    /// closes the last remaining pane (returns `nil` then, leaving the tree untouched). Returns the pane that should
    /// become selected next: the first leaf (depth-first) of the sibling that moved up.
    @discardableResult
    mutating func close(_ pane: PaneID) -> PaneID? {
        guard count > 1, contains(pane) else { return nil }
        guard let (newRoot, selected) = Self.removing(pane, from: root) else { return nil }
        root = newRoot
        if zoomed == pane { zoomed = nil }
        return selected
    }

    /// Rebuilds the tree to match `preset`, reusing existing pane ids in read order (`panes`) where possible, minting
    /// new ids only for panes the preset needs beyond what already existed, and dropping any surplus. Always leaves
    /// zoom mode.
    @discardableResult
    mutating func apply(_ preset: PanePreset) -> (kept: [PaneID], removed: [PaneID]) {
        let wanted: Int
        switch preset {
        case .single: wanted = 1
        case .sideBySide, .stacked: wanted = 2
        case .grid: wanted = 4
        }
        let existing = panes
        var ids = Array(existing.prefix(wanted))
        var minter = IDMinter(nextRaw: nextID)
        while ids.count < wanted {
            ids.append(minter.mint())
        }
        nextID = minter.nextRaw
        let removed = existing.filter { !ids.contains($0) }

        switch preset {
        case .single:
            root = .leaf(ids[0])
        case .sideBySide:
            root = .split(axis: .horizontal, fraction: 0.5, first: .leaf(ids[0]), second: .leaf(ids[1]))
        case .stacked:
            root = .split(axis: .vertical, fraction: 0.5, first: .leaf(ids[0]), second: .leaf(ids[1]))
        case .grid:
            let top = PaneNode.split(axis: .horizontal, fraction: 0.5, first: .leaf(ids[0]), second: .leaf(ids[1]))
            let bottom = PaneNode.split(axis: .horizontal, fraction: 0.5, first: .leaf(ids[2]), second: .leaf(ids[3]))
            root = .split(axis: .vertical, fraction: 0.5, first: top, second: bottom)
        }
        zoomed = nil
        return (kept: ids, removed: removed)
    }

    mutating func toggleZoom(_ pane: PaneID) {
        guard contains(pane) else { return }
        zoomed = (zoomed == pane) ? nil : pane
    }

    /// Resets every split node's fraction to the share of leaves on its `first` side, so a run of same-axis splits
    /// ends up dividing its space evenly between however many panes sit on each side.
    mutating func equalize() {
        root = Self.equalized(root)
    }

    /// `path` walks from the root (false = first, true = second) to a split node; `fraction` is clamped into
    /// `[minFraction, 1 - minFraction]` so no pane can be dragged to nothing. A path that does not land on a split
    /// node is ignored.
    ///
    /// `fraction.isNaN` is checked explicitly before the `min`/`max` clamp: unlike C's `fmax`/`fmin`, Swift's
    /// `max(Double.nan, x)` and `min(Double.nan, x)` both propagate NaN instead of picking `x` (measured), so a NaN
    /// divider-drag value — e.g. from a view computing a fraction as `0/0` on a zero-width rect — would otherwise
    /// sail through the clamp and get stored verbatim, silently corrupting layout math for the rest of the session.
    mutating func setFraction(at path: [Bool], _ fraction: Double) {
        guard !fraction.isNaN else { return }
        let clamped = min(max(fraction, Self.minFraction), 1 - Self.minFraction)
        root = Self.settingFraction(in: root, path: path[...], to: clamped)
    }

    /// Cyclic successor in read order; wraps from the last pane back to the first.
    func next(after pane: PaneID) -> PaneID {
        let all = panes
        guard let i = all.firstIndex(of: pane), !all.isEmpty else { return pane }
        return all[(i + 1) % all.count]
    }

    /// Cyclic predecessor in read order; wraps from the first pane to the last.
    func previous(before pane: PaneID) -> PaneID {
        let all = panes
        guard let i = all.firstIndex(of: pane), !all.isEmpty else { return pane }
        return all[(i - 1 + all.count) % all.count]
    }

    /// The pane that ⌃⇧⌘C / ⌃⇧⌘M should target: with one pane there is nowhere to send a copy (`nil`); with exactly
    /// two, the other one; with three or more, the next pane in read order (so repeated use cycles through them).
    func other(than pane: PaneID) -> PaneID? {
        let all = panes
        guard all.count > 1, all.contains(pane) else { return nil }
        if all.count == 2 {
            return all.first { $0 != pane }
        }
        return next(after: pane)
    }

    /// Lays every pane's rect out inside `rect` (top-left origin, AppKit-flipped), carving `divider` points of gap
    /// between siblings at every split. While zoomed, the zoomed pane alone fills the whole rect and every other pane
    /// is absent from the result.
    func frames(in rect: CGRect, divider: CGFloat) -> [PaneID: CGRect] {
        if let zoomed {
            return [zoomed: rect]
        }
        var result: [PaneID: CGRect] = [:]
        var noDividers: [PaneDivider]?
        Self.layout(root, in: rect, divider: divider, path: [], into: &result, dividers: &noDividers)
        return result
    }

    /// Every divider segment, in the same coordinate space as `frames(in:divider:)`. Empty while zoomed, since a
    /// zoomed pane has no visible siblings to divide from.
    func dividers(in rect: CGRect, divider: CGFloat) -> [PaneDivider] {
        guard zoomed == nil else { return [] }
        var frames: [PaneID: CGRect] = [:]
        var result: [PaneDivider]? = []
        Self.layout(root, in: rect, divider: divider, path: [], into: &frames, dividers: &result)
        return result ?? []
    }

    /// Hit-tests `point` against the current layout; `nil` outside every pane (e.g. the parent rect doesn't cover it)
    /// or on a divider's own gap.
    func pane(at point: CGPoint, in rect: CGRect, divider: CGFloat) -> PaneID? {
        let laid = frames(in: rect, divider: divider)
        for (id, frame) in laid where frame.contains(point) {
            return id
        }
        return nil
    }
}

// MARK: - Private tree surgery

private extension PaneTree {
    /// A small counter so `apply(_:)` can mint ids without repeatedly bumping `self.nextID` mid-loop.
    struct IDMinter {
        var nextRaw: Int
        mutating func mint() -> PaneID {
            defer { nextRaw += 1 }
            return PaneID(raw: nextRaw)
        }
    }

    static func leaves(of node: PaneNode) -> [PaneID] {
        switch node {
        case .leaf(let id):
            return [id]
        case .split(_, _, let first, let second):
            return leaves(of: first) + leaves(of: second)
        }
    }

    /// Returns a new tree with the leaf `target` rewritten by `transform`; other nodes are untouched. `target` is
    /// assumed to exist (callers check `contains` first).
    static func replacing(_ target: PaneID, in node: PaneNode, with transform: (PaneNode) -> PaneNode) -> PaneNode {
        switch node {
        case .leaf(let id):
            return id == target ? transform(node) : node
        case .split(let axis, let fraction, let first, let second):
            return .split(
                axis: axis,
                fraction: fraction,
                first: replacing(target, in: first, with: transform),
                second: replacing(target, in: second, with: transform)
            )
        }
    }

    /// Removes `target` from the subtree rooted at `node`, when it is present there at all. Carries the rebuilt node
    /// PLUS `promotedFirstLeaf` — the first leaf (depth-first) of whichever subtree took the removed pane's direct
    /// spot — separately from the overall rebuilt node, because once a rebuild bubbles up through an ancestor split,
    /// `leaves(of: wholeRebuiltNode)[0]` would read the UNTOUCHED sibling branch instead (bug found 2026-10-24: a
    /// close 3+ levels deep, off the leftmost spine, returned the wrong pane to select).
    enum RemovalOutcome {
        case absent
        case found(node: PaneNode, promotedFirstLeaf: PaneID)
    }

    /// Removes `target` from the tree. Returns `nil` when `target` is the sole leaf (nothing to remove into). On
    /// success, returns the rebuilt node plus the first leaf (depth-first) of whichever subtree took the removed
    /// pane's place — not the first leaf of the whole tree.
    static func removing(_ target: PaneID, from node: PaneNode) -> (node: PaneNode, selected: PaneID)? {
        switch removalOutcome(target, from: node) {
        case .absent:
            return nil
        case .found(let rebuilt, let promotedFirstLeaf):
            return (rebuilt, promotedFirstLeaf)
        }
    }

    private static func removalOutcome(_ target: PaneID, from node: PaneNode) -> RemovalOutcome {
        switch node {
        case .leaf(let id):
            // A bare leaf has no sibling to collapse to; the caller (a split one level up) handles collapsing.
            return id == target ? .found(node: node, promotedFirstLeaf: id) : .absent
        case .split(_, _, let first, let second):
            if case .leaf(let id) = first, id == target {
                return .found(node: second, promotedFirstLeaf: leaves(of: second)[0])
            }
            if case .leaf(let id) = second, id == target {
                return .found(node: first, promotedFirstLeaf: leaves(of: first)[0])
            }
            // The target is deeper in one side; recurse and keep the other side as-is, preserving this node's axis
            // and fraction (only leaves are ever spliced out directly at their parent split). The promoted leaf from
            // the recursive call is threaded through untouched — it names a pane inside the rebuilt subtree, not
            // anything about this node's untouched sibling.
            switch removalOutcome(target, from: first) {
            case .absent:
                break
            case .found(let newFirst, let promoted):
                return .found(node: .split(axis: axisOf(node), fraction: fractionOf(node), first: newFirst, second: second), promotedFirstLeaf: promoted)
            }
            switch removalOutcome(target, from: second) {
            case .absent:
                return .absent
            case .found(let newSecond, let promoted):
                return .found(node: .split(axis: axisOf(node), fraction: fractionOf(node), first: first, second: newSecond), promotedFirstLeaf: promoted)
            }
        }
    }

    static func axisOf(_ node: PaneNode) -> SplitAxis {
        if case .split(let axis, _, _, _) = node { return axis }
        return .horizontal
    }

    static func fractionOf(_ node: PaneNode) -> Double {
        if case .split(_, let fraction, _, _) = node { return fraction }
        return 0.5
    }

    static func equalized(_ node: PaneNode) -> PaneNode {
        switch node {
        case .leaf:
            return node
        case .split(let axis, _, let first, let second):
            let newFirst = equalized(first)
            let newSecond = equalized(second)
            let firstCount = leaves(of: newFirst).count
            let secondCount = leaves(of: newSecond).count
            let total = firstCount + secondCount
            let fraction = total > 0 ? Double(firstCount) / Double(total) : 0.5
            return .split(axis: axis, fraction: fraction, first: newFirst, second: newSecond)
        }
    }

    /// Walks `path` to find a split node and rewrite its fraction; a path that runs out before reaching a split, or
    /// that walks into a leaf, leaves the tree unchanged.
    static func settingFraction(in node: PaneNode, path: ArraySlice<Bool>, to fraction: Double) -> PaneNode {
        guard case .split(let axis, let currentFraction, let first, let second) = node else { return node }
        guard let goSecond = path.first else {
            return .split(axis: axis, fraction: fraction, first: first, second: second)
        }
        let rest = path.dropFirst()
        if goSecond {
            return .split(axis: axis, fraction: currentFraction, first: first, second: settingFraction(in: second, path: rest, to: fraction))
        } else {
            return .split(axis: axis, fraction: currentFraction, first: settingFraction(in: first, path: rest, to: fraction), second: second)
        }
    }

    /// Recursively lays `node` out in `rect`, recording leaf frames into `into` and, when `dividers` is non-nil,
    /// appending each split's divider segment (in the same pass, so the two never disagree about geometry).
    static func layout(
        _ node: PaneNode,
        in rect: CGRect,
        divider: CGFloat,
        path: [Bool],
        into frames: inout [PaneID: CGRect],
        dividers: inout [PaneDivider]?
    ) {
        switch node {
        case .leaf(let id):
            frames[id] = rect
        case .split(let axis, let fraction, let first, let second):
            switch axis {
            case .horizontal:
                let firstWidth = max(0, (rect.width - divider) * CGFloat(fraction))
                let secondWidth = max(0, rect.width - divider - firstWidth)
                let firstRect = CGRect(x: rect.minX, y: rect.minY, width: firstWidth, height: rect.height)
                let secondRect = CGRect(x: rect.minX + firstWidth + divider, y: rect.minY, width: secondWidth, height: rect.height)
                if dividers != nil {
                    let dividerRect = CGRect(x: rect.minX + firstWidth, y: rect.minY, width: divider, height: rect.height)
                    dividers?.append(PaneDivider(path: path, axis: axis, rect: dividerRect, parent: rect))
                }
                layout(first, in: firstRect, divider: divider, path: path + [false], into: &frames, dividers: &dividers)
                layout(second, in: secondRect, divider: divider, path: path + [true], into: &frames, dividers: &dividers)
            case .vertical:
                let firstHeight = max(0, (rect.height - divider) * CGFloat(fraction))
                let secondHeight = max(0, rect.height - divider - firstHeight)
                let firstRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstHeight)
                let secondRect = CGRect(x: rect.minX, y: rect.minY + firstHeight + divider, width: rect.width, height: secondHeight)
                if dividers != nil {
                    let dividerRect = CGRect(x: rect.minX, y: rect.minY + firstHeight, width: rect.width, height: divider)
                    dividers?.append(PaneDivider(path: path, axis: axis, rect: dividerRect, parent: rect))
                }
                layout(first, in: firstRect, divider: divider, path: path + [false], into: &frames, dividers: &dividers)
                layout(second, in: secondRect, divider: divider, path: path + [true], into: &frames, dividers: &dividers)
            }
        }
    }
}

// MARK: - XF-T30 W1: directional focus and keyboard resize

extension PaneTree {
    /// ⌃⇧⌘←→↑↓ (Pane on Left/Right/Above/Below): the pane adjacent to `pane` in `dir`, by the frames the layout gives
    /// in `rect` — grid-aware, never creation order. Among panes whose frame lies wholly on that side and touches or
    /// overlaps the source's span on the cross axis, the one with the largest overlap wins; a tie goes to the nearest
    /// centre. nil at the window edge. W1 builder: implement.
    func neighbor(of pane: PaneID, toward dir: SplitDirection, in rect: CGRect, divider: CGFloat) -> PaneID? {
        nil
    }

    /// Make Pane Wider / Narrower (axis `.horizontal` split, i.e. side-by-side) and Taller / Shorter (`.vertical`):
    /// moves the nearest ancestor divider of that axis by `step` of its parent so `pane` grows (`grow`) or shrinks,
    /// clamped to `minFraction`. No ancestor of that axis ⇒ no change. W1 builder: implement (and state which
    /// `SplitAxis` value means side-by-side by reading `split(_:_:)`).
    mutating func resize(_ pane: PaneID, axis: SplitAxis, grow: Bool, step: Double = 0.05) {}

    /// The preset this tree currently is, or nil for a custom layout — the toolbar's Pane Layout icon follows it
    /// (FileOctopus 1.0.3). Zoom does not count. W1 builder: implement.
    var currentPreset: PanePreset? { nil }
}
