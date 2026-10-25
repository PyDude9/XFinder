import Foundation

/// XF-T30 W6 — Windows-style ⌘X (opt-in `fileBrowser.cutWithCmdX`): the pending cut and what cancels it. Pure, symlinked.
/// W6 builder (pure): implement.
struct CutBoard: Equatable, Sendable {
    private(set) var paths: Set<String> = []
    /// The pasteboard change count when the cut was made — any later copy (here or in another app) cancels it.
    private(set) var changeCount: Int = -1

    mutating func cut(_ paths: [String], changeCount: Int) {
        self.paths = Set(paths)
        self.changeCount = changeCount
    }

    mutating func cancel() { paths = []; changeCount = -1 }

    /// ⌘V into `folder`: the paths to MOVE (empty when the cut no longer applies). Pasting into the folder the items
    /// came from does nothing.
    ///
    /// The cut is cancelled by a newer copy (spec §2: "Esc / ⌘C mới / chép thứ khác ⇒ huỷ") — detected here by
    /// comparing `currentChangeCount` against the count recorded at cut time, since any copy (in this app or
    /// another) bumps NSPasteboard's change count. A stale/empty cut (`changeCount == -1`, i.e. never cut, or
    /// already cancelled) never matches.
    func pasteMoves(into folder: String, currentChangeCount: Int) -> [String] {
        guard changeCount != -1, currentChangeCount == changeCount, !paths.isEmpty else { return [] }
        let destinationStandard = (folder as NSString).standardizingPath
        // Pasting into the same folder the items came from is a no-op (spec §2) rather than a self-move — compare
        // each item's PARENT directory against the destination, not the item's own path, since the cut set is a
        // set of items, not of folders.
        return paths.filter { path in
            let parent = (path as NSString).deletingLastPathComponent
            let parentStandard = (parent as NSString).standardizingPath
            return parentStandard != destinationStandard
        }.sorted()
    }

    func isCut(_ path: String) -> Bool { paths.contains(path) }
}
