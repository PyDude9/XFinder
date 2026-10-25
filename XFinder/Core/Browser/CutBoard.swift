import Foundation

/// XF-T30 W6 — Windows-style ⌘X (opt-in `fileBrowser.cutWithCmdX`): the pending cut and what cancels it. Pure, symlinked.
/// W6 builder (pure): implement.
struct CutBoard: Equatable, Sendable {
    private(set) var paths: Set<String> = []
    /// The pasteboard change count when the cut was made — any later copy (here or in another app) cancels it.
    private(set) var changeCount: Int = -1

    mutating func cut(_ paths: [String], changeCount: Int) {}
    mutating func cancel() { paths = []; changeCount = -1 }
    /// ⌘V into `folder`: the paths to MOVE (empty when the cut no longer applies). Pasting into the folder the items
    /// came from does nothing.
    func pasteMoves(into folder: String, currentChangeCount: Int) -> [String] { [] }
    func isCut(_ path: String) -> Bool { paths.contains(path) }
}
