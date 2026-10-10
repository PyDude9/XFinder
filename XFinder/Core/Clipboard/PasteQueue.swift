import Foundation

/// The Paste Stack's queue (B5): items pasted one per ⌘V, in order. Generic over the item so the
/// test package can exercise it (ClipboardRecord lives in an AppKit-bound file).
///
/// Measured before B5: `popNext()` had ZERO call sites — the stack could be started (⌘⇧C) and
/// shown, but nothing ever consumed it. The consumer is `ClipboardManager.pasteNextFromStack()`,
/// driven by the shelf's event tap intercepting ⌘V (the original ⌘V is let THROUGH after the
/// pasteboard is rewritten, so no keystroke is ever synthesized).
struct PasteQueue<Item: Equatable>: Equatable {
    private(set) var items: [Item] = []
    private(set) var active = false
    /// How many have been pasted since `start`, for the HUD.
    private(set) var pasted = 0

    var remaining: Int { items.count }
    var total: Int { items.count + pasted }

    mutating func start(with items: [Item]) {
        self.items = items
        self.active = !items.isEmpty
        self.pasted = 0
    }

    mutating func stop() {
        items = []
        active = false
    }

    /// Append at the end (⌘-click on a card while a stack is building). Activates an empty stack;
    /// a duplicate of an item already waiting is ignored, so double-clicking does not paste twice.
    mutating func append(_ item: Item) {
        guard !items.contains(item) else { return }
        items.append(item)
        active = true
    }

    mutating func remove(_ item: Item) {
        items.removeAll { $0 == item }
        if items.isEmpty { active = false }
    }

    /// The next item to paste; deactivates when drained. nil when inactive or empty.
    mutating func popNext() -> Item? {
        guard active, !items.isEmpty else { active = false; return nil }
        let next = items.removeFirst()
        pasted += 1
        if items.isEmpty { active = false }
        return next
    }
}
