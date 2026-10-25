import Foundation

/// XF-T28 — per-pane Back/Forward history plus the "which child did I just leave" memory for ⌘↑.
///
/// Why per-pane and not one history for the window: the file browser's pane tree can hold up to 16 panes (`PaneTree`),
/// each navigating independently, same as separate Finder windows do; one shared stack would make ⌘[ in pane A jump
/// to a path pane B visited. `back`/`forward` are plain `[String]` paths (not `DirectoryEntry`) so a history entry
/// survives the target being renamed on disk between visits — resolving it again is the caller's job at navigation time.
struct PaneHistory: Codable, Equatable, Sendable {
    /// Finder's own Back list is effectively unbounded in practice but a bound keeps `Codable` session state small;
    /// 50 is far past what anyone scrolls back through in one session.
    static let limit = 50
    /// The "remembered child per parent" map (⌘↑) is keyed by parent path and can accumulate one entry per folder
    /// ever left upward across a long session — capped the same way as `back`, oldest insertion dropped first.
    static let rememberLimit = 200

    private(set) var back: [String]
    private(set) var forward: [String]
    private(set) var current: String
    /// Parent path -> child name last left via `noteLeaving`, insertion-ordered so the oldest can be evicted.
    private var rememberedOrder: [String]
    private var remembered: [String: String]

    init(current: String) {
        self.back = []
        self.forward = []
        self.current = current
        self.rememberedOrder = []
        self.remembered = [:]
    }

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    /// Navigate to `path`: push `current` onto `back` (unless it's already there, i.e. a no-op re-visit of the same
    /// folder), drop the forward stack (a fresh visit invalidates "redo"), and trim `back` to `limit` from the front.
    mutating func visit(_ path: String) {
        guard path != current else { return }
        back.append(current)
        if back.count > Self.limit {
            back.removeFirst(back.count - Self.limit)
        }
        forward.removeAll()
        current = path
    }

    /// ⌘[: current becomes the top of `forward` (so Forward can undo this), destination is popped off `back`.
    mutating func goBack() -> String? {
        guard let destination = back.popLast() else { return nil }
        forward.append(current)
        current = destination
        return destination
    }

    /// ⌘]: mirror of `goBack`.
    mutating func goForward() -> String? {
        guard let destination = forward.popLast() else { return nil }
        back.append(current)
        current = destination
        return destination
    }

    /// ⌘↑ leaves `name` inside `parent`; remember it so re-entering `parent` can reselect it, same as Finder.
    mutating func noteLeaving(child name: String, of parent: String) {
        if remembered[parent] == nil {
            rememberedOrder.append(parent)
        }
        remembered[parent] = name
        if rememberedOrder.count > Self.rememberLimit {
            let dropCount = rememberedOrder.count - Self.rememberLimit
            for key in rememberedOrder.prefix(dropCount) {
                remembered.removeValue(forKey: key)
            }
            rememberedOrder.removeFirst(dropCount)
        }
    }

    func childToSelect(in parent: String) -> String? {
        remembered[parent]
    }

    /// Session restore: drop any back/forward path whose target no longer exists on disk; if `current` itself is
    /// gone, fall back to `fallback` (the caller passes Home) instead of leaving the pane pointed at nothing.
    mutating func removeMissing(exists: (String) -> Bool, fallback: String) {
        back.removeAll { !exists($0) }
        forward.removeAll { !exists($0) }
        if !exists(current) {
            current = fallback
        }
    }

    /// XF-T30 W1 — press-and-hold on toolbar Back/Forward jumps several entries at once (FileOctopus: the menu lists the
    /// tab's history). `steps` ≥ 1; more steps than entries ⇒ nil and nothing changes. W1 builder (pure): implement.
    mutating func goBack(steps: Int) -> String? { nil }
    mutating func goForward(steps: Int) -> String? { nil }
}
