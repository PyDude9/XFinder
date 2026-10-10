import Foundation

/// Decides whether the CURRENT mouse press is dragging files — the guard every drag-based open
/// path depends on.
///
/// Why this is its own type: the drag pasteboard is NOT cleared when a drag ends. Measured on
/// macOS 27 with no button down, 77 minutes after the last drag: `NSPasteboard(name: .drag)` still
/// listed `public.file-url` and `com.apple.finder.node` from an old Finder drag. Reading its types
/// alone (the old `dragCarriesFiles()`) therefore says "files!" for every later drag — a text
/// selection, a window dragged by its title bar up to the notch. Only the shake requirement hid
/// that. The fix: remember the pasteboard's `changeCount` at mouse-down, and trust its types only
/// once a NEW drag session has written to it during this press.
///
/// Cost: reading the drag pasteboard is a round trip to the pasteboard server, and a drag produces
/// a mouse event per pixel. So the verdict is cached for the rest of the press, and while it is
/// still undecided the change count is read at most once per `recheckInterval`.
struct NotchDragSession: Equatable {
    static let recheckInterval: TimeInterval = 0.05

    private var changeCountAtPress: Int
    private var decided: Bool?
    private var lastCheck: Date?

    init(currentChangeCount: Int) {
        changeCountAtPress = currentChangeCount
    }

    /// Call on every left mouse-down.
    mutating func pressBegan(changeCount: Int) {
        changeCountAtPress = changeCount
        decided = nil
        lastCheck = nil
    }

    /// Call while the button is held. Both closures are consulted lazily: never once the verdict is
    /// known, the change count at most once per `recheckInterval`, the types only after it moved.
    mutating func carriesFiles(now: Date, changeCount: () -> Int, types: () -> [String]) -> Bool {
        if let decided { return decided }
        if let lastCheck, now.timeIntervalSince(lastCheck) < Self.recheckInterval { return false }
        lastCheck = now
        guard changeCount() != changeCountAtPress else { return false }   // no new drag session yet
        let t = types()
        let verdict = t.contains("public.file-url") || t.contains("NSFilenamesPboardType")
        decided = verdict
        return verdict
    }
}
