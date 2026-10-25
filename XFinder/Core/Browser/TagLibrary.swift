import AppKit
import Observation

/// XF-T30 W3 — Finder's tag names, colours and order (follows Finder within about a second, no timer).
/// W3 builder (AppKit).
@MainActor @Observable
final class TagLibrary {
    static let shared = TagLibrary()
    private(set) var tags: [FinderTag] = []

    func start() {}
    func stop() {}
}
