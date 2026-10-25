import AppKit

/// XF-T30 W2 — drag-and-drop rules shared by the four views and the sidebar: default verb by volume, ⌥ copy / ⌘ move,
/// file promises, stacked drag image with a count, Finder-style drop highlight, spring-loaded folders on the system's
/// timing, Escape / leaving the window reverts. W2 builder (menu).
@MainActor
enum DragDropCoordinator {
    enum Verb: Equatable { case copy, move, none }

    /// The operation a drop of `sources` onto `folder` performs with `modifiers` held.
    static func verb(sources: [String], folder: String, modifiers: NSEvent.ModifierFlags) -> Verb { .none }
    /// Whether spring-loading is on in System Settings, and its delay.
    static var springLoading: (enabled: Bool, delay: TimeInterval) { (false, 0.5) }
}
