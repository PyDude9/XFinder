import Foundation
import CoreGraphics

/// Pure HyprMac-inspired Binary Space Partitioning (dwindle) tiling geometry,
/// tree mutations, directional focus/swap solver, drop-zone resolver, and window filtering rules.
/// Foundation + CoreGraphics only (top-left AX origin for all rects and pointers) so every rule
/// is unit-tested in `Tests/XFinderLogicTests`.
enum BSPSplitAxis: String, Codable, Equatable, Sendable {
    case horizontal
    case vertical
}

enum FocusDirection: String, Equatable, CaseIterable, Sendable {
    case left, right, up, down
}

enum DropEdge: String, Equatable, Sendable {
    case left, right, top, bottom, center
}

enum HyprTilingAction: Equatable, Sendable {
    case retileAll
    case focus(FocusDirection)
    case swap(FocusDirection)
    case toggleSplit
    case toggleFloat
    case toggleMaximize
    case resizeGrow
    case resizeShrink
    case balanceSplits
}

indirect enum BSPNode: Equatable, Sendable {
    case empty
    case leaf(CGWindowID)
    case split(
        direction: BSPSplitAxis,
        ratio: CGFloat,
        userSetRatio: Bool,
        overrideDirection: Bool,
        first: BSPNode,
        second: BSPNode
    )
}

struct BSPTree: Equatable, Sendable {
    static let minRatio: CGFloat = 0.15
    static let maxRatio: CGFloat = 0.85
    static let defaultRatio: CGFloat = 0.50
    static let resizeStep: CGFloat = 0.05

    var root: BSPNode = .empty

    var windowIDs: [CGWindowID] {
        var result: [CGWindowID] = []
        collectIDs(from: root, into: &result)
        return result
    }

    func contains(_ id: CGWindowID) -> Bool {
        switch root {
        case .empty:
            return false
        case .leaf(let w):
            return w == id
        case .split:
            return Self.nodeContains(root, id: id)
        }
    }

    mutating func insert(
        _ id: CGWindowID,
        in rect: CGRect,
        gap: CGFloat,
        padding: CGFloat,
        preferredTarget: CGWindowID? = nil
    ) {
        guard !contains(id) else { return }
        if case .empty = root {
            root = .leaf(id)
            return
        }

        let slots = layout(in: rect, gap: gap, padding: padding)
        let targetID: CGWindowID? = {
            if let preferredTarget, slots[preferredTarget] != nil {
                return preferredTarget
            }
            return slots.max { lhs, rhs in
                let areaL = lhs.value.width * lhs.value.height
                let areaR = rhs.value.width * rhs.value.height
                if abs(areaL - areaR) > 0.5 { return areaL < areaR }
                return lhs.key > rhs.key
            }?.key ?? windowIDs.last
        }()

        guard let targetID, let targetRect = slots[targetID] else {
            root = .leaf(id)
            return
        }

        let dir: BSPSplitAxis = targetRect.width >= targetRect.height ? .horizontal : .vertical
        let replacement = BSPNode.split(
            direction: dir,
            ratio: Self.defaultRatio,
            userSetRatio: false,
            overrideDirection: false,
            first: .leaf(targetID),
            second: .leaf(id)
        )
        root = Self.replacingLeaf(targetID, in: root, with: replacement)
    }

    mutating func remove(_ id: CGWindowID) {
        root = Self.removingLeaf(id, from: root)
    }

    func layout(in usableRect: CGRect, gap: CGFloat, padding: CGFloat) -> [CGWindowID: CGRect] {
        let clampedPad = max(0, padding)
        let clampedGap = max(0, gap)
        let outerWidth = max(0, usableRect.width - 2 * clampedPad)
        let outerHeight = max(0, usableRect.height - 2 * clampedPad)
        let outer = CGRect(
            x: usableRect.minX + clampedPad,
            y: usableRect.minY + clampedPad,
            width: outerWidth,
            height: outerHeight
        )
        var out: [CGWindowID: CGRect] = [:]
        Self.collectLayout(node: root, rect: outer, gap: clampedGap, into: &out)
        return out
    }

    @discardableResult
    mutating func swap(_ a: CGWindowID, _ b: CGWindowID) -> Bool {
        guard a != b, contains(a), contains(b) else { return false }
        root = Self.swappingLeaves(a, b, in: root)
        return true
    }

    @discardableResult
    mutating func toggleSplit(for id: CGWindowID) -> Bool {
        guard contains(id) else { return false }
        var flipped = false
        root = Self.togglingSplit(for: id, in: root, flipped: &flipped)
        return flipped
    }

    @discardableResult
    mutating func resize(windowID id: CGWindowID, delta: CGFloat) -> Bool {
        guard contains(id), delta != 0 else { return false }
        var changed = false
        root = Self.resizingLeaf(id, delta: delta, in: root, changed: &changed)
        return changed
    }

    mutating func resetRatios() {
        root = Self.resettingRatios(in: root)
    }

    @discardableResult
    mutating func insertBeside(_ id: CGWindowID, target: CGWindowID, edge: DropEdge) -> Bool {
        guard id != target, contains(target) else { return false }
        if edge == .center {
            return swap(id, target)
        }
        if contains(id) {
            remove(id)
        }
        guard contains(target) else { return false }

        let dir: BSPSplitAxis = (edge == .left || edge == .right) ? .horizontal : .vertical
        let newIsFirst = (edge == .left || edge == .top)
        let replacement = BSPNode.split(
            direction: dir,
            ratio: Self.defaultRatio,
            userSetRatio: false,
            overrideDirection: true,
            first: newIsFirst ? .leaf(id) : .leaf(target),
            second: newIsFirst ? .leaf(target) : .leaf(id)
        )
        root = Self.replacingLeaf(target, in: root, with: replacement)
        return true
    }

    /// Top-left AX coordinate neighbor lookup: prioritizes windows in `direction` whose
    /// orthogonal projection overlaps `id`'s rect, then picks nearest gap / center distance.
    func neighbor(
        of id: CGWindowID,
        direction: FocusDirection,
        in usableRect: CGRect,
        gap: CGFloat,
        padding: CGFloat
    ) -> CGWindowID? {
        let slots = layout(in: usableRect, gap: gap, padding: padding)
        guard let src = slots[id] else { return nil }

        struct Candidate {
            let id: CGWindowID
            let overlapsOrthogonally: Bool
            let edgeGap: CGFloat
            let centerDist: CGFloat
            let origin: CGPoint
        }

        var candidates: [Candidate] = []
        for (otherID, dst) in slots where otherID != id {
            let matches: Bool
            let edgeGap: CGFloat
            let orthOverlap: CGFloat

            switch direction {
            case .left:
                matches = dst.midX < src.midX - 0.5
                edgeGap = max(0, src.minX - dst.maxX)
                orthOverlap = min(src.maxY, dst.maxY) - max(src.minY, dst.minY)
            case .right:
                matches = dst.midX > src.midX + 0.5
                edgeGap = max(0, dst.minX - src.maxX)
                orthOverlap = min(src.maxY, dst.maxY) - max(src.minY, dst.minY)
            case .up:
                matches = dst.midY < src.midY - 0.5
                edgeGap = max(0, src.minY - dst.maxY)
                orthOverlap = min(src.maxX, dst.maxX) - max(src.minX, dst.minX)
            case .down:
                matches = dst.midY > src.midY + 0.5
                edgeGap = max(0, dst.minY - src.maxY)
                orthOverlap = min(src.maxX, dst.maxX) - max(src.minX, dst.minX)
            }
            guard matches else { continue }
            let dx = dst.midX - src.midX
            let dy = dst.midY - src.midY
            candidates.append(
                Candidate(
                    id: otherID,
                    overlapsOrthogonally: orthOverlap > 1,
                    edgeGap: edgeGap,
                    centerDist: hypot(dx, dy),
                    origin: dst.origin
                )
            )
        }

        return candidates.min { a, b in
            if a.overlapsOrthogonally != b.overlapsOrthogonally {
                return a.overlapsOrthogonally
            }
            if abs(a.edgeGap - b.edgeGap) > 1 {
                return a.edgeGap < b.edgeGap
            }
            if abs(a.centerDist - b.centerDist) > 1 {
                return a.centerDist < b.centerDist
            }
            if abs(a.origin.y - b.origin.y) > 0.5 {
                return a.origin.y < b.origin.y
            }
            if abs(a.origin.x - b.origin.x) > 0.5 {
                return a.origin.x < b.origin.x
            }
            return a.id < b.id
        }?.id
    }

    // MARK: - Tree Helpers

    private func collectIDs(from node: BSPNode, into result: inout [CGWindowID]) {
        switch node {
        case .empty:
            break
        case .leaf(let w):
            result.append(w)
        case .split(_, _, _, _, let first, let second):
            collectIDs(from: first, into: &result)
            collectIDs(from: second, into: &result)
        }
    }

    private static func nodeContains(_ node: BSPNode, id: CGWindowID) -> Bool {
        switch node {
        case .empty:
            return false
        case .leaf(let w):
            return w == id
        case .split(_, _, _, _, let first, let second):
            return nodeContains(first, id: id) || nodeContains(second, id: id)
        }
    }

    private static func replacingLeaf(_ target: CGWindowID, in node: BSPNode, with replacement: BSPNode) -> BSPNode {
        switch node {
        case .empty:
            return .empty
        case .leaf(let w):
            return w == target ? replacement : node
        case .split(let dir, let ratio, let userSet, let overDir, let first, let second):
            return .split(
                direction: dir,
                ratio: ratio,
                userSetRatio: userSet,
                overrideDirection: overDir,
                first: replacingLeaf(target, in: first, with: replacement),
                second: replacingLeaf(target, in: second, with: replacement)
            )
        }
    }

    private static func removingLeaf(_ id: CGWindowID, from node: BSPNode) -> BSPNode {
        switch node {
        case .empty:
            return .empty
        case .leaf(let w):
            return w == id ? .empty : node
        case .split(let dir, let ratio, let userSet, let overDir, let first, let second):
            let nf = removingLeaf(id, from: first)
            let ns = removingLeaf(id, from: second)
            if case .empty = nf { return ns }
            if case .empty = ns { return nf }
            return .split(
                direction: dir,
                ratio: ratio,
                userSetRatio: userSet,
                overrideDirection: overDir,
                first: nf,
                second: ns
            )
        }
    }

    private static func swappingLeaves(_ a: CGWindowID, _ b: CGWindowID, in node: BSPNode) -> BSPNode {
        switch node {
        case .empty:
            return .empty
        case .leaf(let w):
            if w == a { return .leaf(b) }
            if w == b { return .leaf(a) }
            return node
        case .split(let dir, let ratio, let userSet, let overDir, let first, let second):
            return .split(
                direction: dir,
                ratio: ratio,
                userSetRatio: userSet,
                overrideDirection: overDir,
                first: swappingLeaves(a, b, in: first),
                second: swappingLeaves(a, b, in: second)
            )
        }
    }

    private static func togglingSplit(for id: CGWindowID, in node: BSPNode, flipped: inout Bool) -> BSPNode {
        guard case .split(let dir, let ratio, let userSet, _, let first, let second) = node else {
            return node
        }
        let directChild: Bool = {
            if case .leaf(let w) = first, w == id { return true }
            if case .leaf(let w) = second, w == id { return true }
            return false
        }()
        if directChild {
            flipped = true
            let nextDir: BSPSplitAxis = (dir == .horizontal) ? .vertical : .horizontal
            return .split(
                direction: nextDir,
                ratio: ratio,
                userSetRatio: userSet,
                overrideDirection: true,
                first: first,
                second: second
            )
        }
        let nf = togglingSplit(for: id, in: first, flipped: &flipped)
        let ns = flipped ? second : togglingSplit(for: id, in: second, flipped: &flipped)
        return .split(
            direction: dir,
            ratio: ratio,
            userSetRatio: userSet,
            overrideDirection: false,
            first: nf,
            second: ns
        )
    }

    private static func resizingLeaf(
        _ id: CGWindowID,
        delta: CGFloat,
        in node: BSPNode,
        changed: inout Bool
    ) -> BSPNode {
        guard case .split(let dir, let ratio, let userSet, let overDir, let first, let second) = node else {
            return node
        }
        if case .leaf(let w) = first, w == id {
            let next = clampRatio(ratio + delta)
            changed = true
            return .split(direction: dir, ratio: next, userSetRatio: true, overrideDirection: overDir, first: first, second: second)
        }
        if case .leaf(let w) = second, w == id {
            let next = clampRatio(ratio - delta)
            changed = true
            return .split(direction: dir, ratio: next, userSetRatio: true, overrideDirection: overDir, first: first, second: second)
        }
        let nf = resizingLeaf(id, delta: delta, in: first, changed: &changed)
        let ns = changed ? second : resizingLeaf(id, delta: delta, in: second, changed: &changed)
        return .split(direction: dir, ratio: ratio, userSetRatio: userSet, overrideDirection: overDir, first: nf, second: ns)
    }

    private static func resettingRatios(in node: BSPNode) -> BSPNode {
        switch node {
        case .empty, .leaf:
            return node
        case .split(let dir, _, _, let overDir, let first, let second):
            return .split(
                direction: dir,
                ratio: Self.defaultRatio,
                userSetRatio: false,
                overrideDirection: overDir,
                first: resettingRatios(in: first),
                second: resettingRatios(in: second)
            )
        }
    }

    private static func collectLayout(node: BSPNode, rect: CGRect, gap: CGFloat, into out: inout [CGWindowID: CGRect]) {
        switch node {
        case .empty:
            break
        case .leaf(let id):
            out[id] = rect
        case .split(let dir, let ratio, _, _, let first, let second):
            let r = clampRatio(ratio)
            let r1: CGRect
            let r2: CGRect
            switch dir {
            case .horizontal:
                let w1 = max(0, ((rect.width - gap) * r).rounded(.down))
                let w2 = max(0, rect.width - gap - w1)
                r1 = CGRect(x: rect.minX, y: rect.minY, width: w1, height: rect.height)
                r2 = CGRect(x: rect.minX + w1 + gap, y: rect.minY, width: w2, height: rect.height)
            case .vertical:
                let h1 = max(0, ((rect.height - gap) * r).rounded(.down))
                let h2 = max(0, rect.height - gap - h1)
                r1 = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h1)
                r2 = CGRect(x: rect.minX, y: rect.minY + h1 + gap, width: rect.width, height: h2)
            }
            collectLayout(node: first, rect: r1, gap: gap, into: &out)
            collectLayout(node: second, rect: r2, gap: gap, into: &out)
        }
    }

    private static func clampRatio(_ r: CGFloat) -> CGFloat {
        min(max(r, Self.minRatio), Self.maxRatio)
    }
}

struct TiledDropPlan: Equatable, Sendable {
    let targetID: CGWindowID
    let edge: DropEdge
    let previewRect: CGRect
}

enum TiledDropResolver {
    /// Resolves where a window dragged to `pointerAX` (top-left origin) should drop inside existing
    /// tiled `slots`. Returns center swap when `draggedID` is already tiled and hovers the center 50%,
    /// otherwise picks the nearest edge split with a half-gap preview rect.
    static func resolve(
        pointerAX: CGPoint,
        draggedID: CGWindowID,
        slots: [CGWindowID: CGRect],
        gap: CGFloat
    ) -> TiledDropPlan? {
        guard let (targetID, targetFrame) = slots.first(where: { $0.key != draggedID && $0.value.contains(pointerAX) }),
              targetFrame.width > 0, targetFrame.height > 0 else {
            return nil
        }

        let clampedGap = max(0, gap)
        let nx = (pointerAX.x - targetFrame.minX) / targetFrame.width
        let ny = (pointerAX.y - targetFrame.minY) / targetFrame.height

        if slots[draggedID] != nil, nx >= 0.25, nx <= 0.75, ny >= 0.25, ny <= 0.75 {
            return TiledDropPlan(targetID: targetID, edge: .center, previewRect: targetFrame)
        }

        let candidates: [(DropEdge, CGFloat)] = [
            (.left, nx),
            (.right, 1 - nx),
            (.top, ny),
            (.bottom, 1 - ny),
        ]
        let nearestEdge = candidates.min(by: { $0.1 < $1.1 })?.0 ?? .left

        let preview: CGRect
        switch nearestEdge {
        case .left:
            let w = max(0, ((targetFrame.width - clampedGap) / 2).rounded(.down))
            preview = CGRect(x: targetFrame.minX, y: targetFrame.minY, width: w, height: targetFrame.height)
        case .right:
            let w1 = max(0, ((targetFrame.width - clampedGap) / 2).rounded(.down))
            let w2 = max(0, targetFrame.width - clampedGap - w1)
            preview = CGRect(x: targetFrame.minX + w1 + clampedGap, y: targetFrame.minY, width: w2, height: targetFrame.height)
        case .top:
            let h = max(0, ((targetFrame.height - clampedGap) / 2).rounded(.down))
            preview = CGRect(x: targetFrame.minX, y: targetFrame.minY, width: targetFrame.width, height: h)
        case .bottom:
            let h1 = max(0, ((targetFrame.height - clampedGap) / 2).rounded(.down))
            let h2 = max(0, targetFrame.height - clampedGap - h1)
            preview = CGRect(x: targetFrame.minX, y: targetFrame.minY + h1 + clampedGap, width: targetFrame.width, height: h2)
        case .center:
            preview = targetFrame
        }

        return TiledDropPlan(targetID: targetID, edge: nearestEdge, previewRect: preview)
    }
}

struct HyprTilingHotkeyBinding: Equatable, Sendable {
    let id: UInt32
    let keyCode: UInt32
    let action: HyprTilingAction
    let label: String
}

enum HyprTilingRules {
    static let defaultExcludedBundleIDs: [String] = [
        "com.apple.systempreferences",
        "com.apple.calculator",
        "com.apple.ActivityMonitor",
        "com.apple.ScreenContinuity",
    ]

    static let systemBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.notificationcenterui",
    ]

    static let hotkeyBindings: [HyprTilingHotkeyBinding] = [
        HyprTilingHotkeyBinding(id: 1,  keyCode: 35,  action: .retileAll,      label: "⌃⌥⇧P"),
        HyprTilingHotkeyBinding(id: 2,  keyCode: 123, action: .swap(.left),    label: "⌃⌥⇧←"),
        HyprTilingHotkeyBinding(id: 3,  keyCode: 124, action: .swap(.right),   label: "⌃⌥⇧→"),
        HyprTilingHotkeyBinding(id: 4,  keyCode: 126, action: .swap(.up),      label: "⌃⌥⇧↑"),
        HyprTilingHotkeyBinding(id: 5,  keyCode: 125, action: .swap(.down),    label: "⌃⌥⇧↓"),
        HyprTilingHotkeyBinding(id: 6,  keyCode: 4,   action: .focus(.left),   label: "⌃⌥⇧H"),
        HyprTilingHotkeyBinding(id: 7,  keyCode: 37,  action: .focus(.right),  label: "⌃⌥⇧L"),
        HyprTilingHotkeyBinding(id: 8,  keyCode: 40,  action: .focus(.up),     label: "⌃⌥⇧K"),
        HyprTilingHotkeyBinding(id: 9,  keyCode: 38,  action: .focus(.down),   label: "⌃⌥⇧J"),
        HyprTilingHotkeyBinding(id: 10, keyCode: 1,   action: .toggleSplit,    label: "⌃⌥⇧S"),
        HyprTilingHotkeyBinding(id: 11, keyCode: 17,  action: .toggleFloat,    label: "⌃⌥⇧T"),
        HyprTilingHotkeyBinding(id: 12, keyCode: 46,  action: .toggleMaximize, label: "⌃⌥⇧M"),
        HyprTilingHotkeyBinding(id: 13, keyCode: 24,  action: .resizeGrow,     label: "⌃⌥⇧="),
        HyprTilingHotkeyBinding(id: 14, keyCode: 27,  action: .resizeShrink,   label: "⌃⌥⇧-"),
        HyprTilingHotkeyBinding(id: 15, keyCode: 29,  action: .balanceSplits,  label: "⌃⌥⇧0"),
    ]

    /// HyprMac chords strictly require `⌃⌥⇧` without `⌘`, keeping 100% disjoint from `SnapLayout`'s `⌃⌥`.
    static func acceptsHotkey(control: Bool, option: Bool, command: Bool, shift: Bool) -> Bool {
        control && option && shift && !command
    }

    static func action(forKeyCode keyCode: Int64) -> HyprTilingAction? {
        switch keyCode {
        case 35:  return .retileAll          // P
        case 123: return .swap(.left)        // ←
        case 124: return .swap(.right)       // →
        case 126: return .swap(.up)          // ↑
        case 125: return .swap(.down)        // ↓
        case 4:   return .focus(.left)       // H
        case 37:  return .focus(.right)      // L
        case 40:  return .focus(.up)         // K
        case 38:  return .focus(.down)       // J
        case 1:   return .toggleSplit        // S
        case 17:  return .toggleFloat        // T
        case 46:  return .toggleMaximize     // M
        case 24:  return .resizeGrow         // =
        case 27:  return .resizeShrink       // -
        case 29:  return .balanceSplits      // 0
        default:  return nil
        }
    }

    /// Safely converts AppKit `NSWindow.windowNumber` (signed `Int`, `-1` for deferred/off-screen windows)
    /// into a non-zero `CGWindowID` (`UInt32`), returning `nil` instead of trapping on negative/overflow values.
    static func windowID(fromNSWindowNumber number: Int) -> CGWindowID? {
        guard number > 0, let wid = CGWindowID(exactly: number) else { return nil }
        return wid
    }

    static func isEligibleWindow(
        layer: Int,
        alpha: Double,
        bounds: CGRect,
        subrole: String?,
        isResizable: Bool,
        bundleID: String,
        excludedBundleIDs: Set<String>,
        isOwnNonBrowser: Bool
    ) -> Bool {
        guard layer == 0, alpha > 0, bounds.width >= 200, bounds.height >= 150 else { return false }
        guard isResizable else { return false }
        if let subrole, subrole != "AXStandardWindow" { return false }
        guard !isOwnNonBrowser else { return false }
        guard !systemBundleIDs.contains(bundleID), !excludedBundleIDs.contains(bundleID) else { return false }
        return true
    }
}
