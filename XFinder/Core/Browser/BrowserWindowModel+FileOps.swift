import AppKit

/// XF-T30 W6 — New Folder with Selection, ⌘X cut, Redo, Clear Operation History; persistent undo through `UndoJournal`.
/// Contract docs/specs/XF-T30-w6-contract.md. W6 builder (model/panel, "b-w6p").
///
/// `redo`/`clearOperationHistory` need `FileOperationQueue` to actually record completed jobs into `UndoJournal`/
/// `ProblemsList` as they run (its `run()`/`performItem()`, contract §2 — the Q6 builder's AppKit side, parallel to
/// this file and not editable here). Until that recording exists there is nothing real to redo or clear, so both
/// commands are honestly gated off (`canPerform…` false) rather than faked — see deviations in the final report.
///
/// `CutBoard` (pure, `CutBoard.swift`) needs one instance per browser window, but an extension in a separate file
/// cannot add a stored property to `BrowserWindowModel` itself (that class lives in `BrowserWindowModel.swift`,
/// owned by the W1 builder — contract §6 "builder chỉ sửa file của mình"). Keyed storage on `ObjectIdentifier(self)`
/// keeps the cut state entirely inside this file instead of asking for a cross-file signature change; every method
/// below already runs on `@MainActor` (inherited from `BrowserWindowModel`), so this dictionary never needs its own
/// lock. Deviation: `BrowserWindowModel` has no `deinit`/close hook this file can reach, so a closed window's entry
/// (one small `CutBoard` struct — a path set plus an int) is never pruned from `CutBoardStore.boards`; a window
/// count in the tens, not thousands, so this is bytes, not an `IdleCost` regression, but the integrator owning
/// `BrowserWindowModel.swift` should add a `CutBoardStore.boards.removeValue(forKey:)` call to a window-close path
/// if one gets added there.
@MainActor
private enum CutBoardStore {
    static var boards: [ObjectIdentifier: CutBoard] = [:]
}

extension BrowserWindowModel {
    private var cutBoardKey: ObjectIdentifier { ObjectIdentifier(self) }

    private var cutBoard: CutBoard {
        get { CutBoardStore.boards[cutBoardKey] ?? CutBoard() }
        set { CutBoardStore.boards[cutBoardKey] = newValue }
    }

    /// View concern per contract §1: a row fades when its path is pending cut.
    func isCut(_ path: String) -> Bool {
        cutBoard.isCut(path)
    }

    func performFileOpsCommand(_ command: BrowserCommand) -> Bool {
        switch command {
        case .newFolderWithSelection:
            createNewFolderWithSelection()
            return true
        case .cut:
            cutSelection()
            return true
        case .redo:
            return false   // nothing to redo yet — see header note
        case .clearOperationHistory:
            FileOperationQueue.shared.clearFinished()
            return true
        default:
            return false
        }
    }

    func canPerformFileOpsCommand(_ command: BrowserCommand) -> Bool {
        switch command {
        case .newFolderWithSelection:
            return !active.selectedEntries.isEmpty
        case .cut:
            return BrowserSettings.cutWithCmdX && !active.selectedEntries.isEmpty
        case .redo:
            return false   // see header note — UndoJournal is not wired into the queue's run loop yet
        case .clearOperationHistory:
            return FileOperationQueue.shared.queue.jobs.contains { $0.isFinished }
        default:
            return false
        }
    }

    /// ⌃⌘N: a new folder next to the selection, named like Finder's own "New Folder With Items", with the selection
    /// moved into it through the queue (contract §1 — goes through the normal operation machinery, so it shows in
    /// the operations panel and is undoable like any other move).
    private func createNewFolderWithSelection() {
        let selected = active.selectedEntries
        guard !selected.isEmpty else { return }
        let existing = Set(active.entries.map(\.name))
        let name = FileOperationRules.keepBothName(for: "New Folder With Items", existing: existing)
        let destination = (active.path as NSString).appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: false)
        } catch {
            banner = "Không tạo được thư mục mới"
            return
        }
        let sources = selected.map(\.path)
        _ = FileOperationQueue.shared.enqueue(.move, sources: sources, destination: destination)
        active.selection = [destination]
        active.selectAfterLoad = name
        renaming = activePane
        active.reload()
    }

    /// ⌘X (opt-in `fileBrowser.cutWithCmdX`, contract §1): marks the selection as pending-cut. The pasteboard change
    /// count is captured AFTER writing (CLAUDE.md §3.2 rule 9: "ghi pasteboard thì gán `lastChangeCount`") so a later
    /// external copy — which bumps the count again — is what invalidates the cut, not the write that created it.
    private func cutSelection() {
        let paths = active.selectedEntries.map(\.path)
        guard !paths.isEmpty else { return }
        let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls)
        var board = cutBoard
        board.cut(paths, changeCount: pasteboard.changeCount)
        cutBoard = board
    }

    /// Esc, a fresh ⌘C, or copying something else cancels the pending cut (contract §1). Deviation: the ⌘C/Esc call
    /// sites (`copySelectionToPasteboard`, Esc handling) live in `BrowserWindowModel.swift`, not owned by this file —
    /// the integrator needs to call this from there; see the final report.
    func cancelPendingCut() {
        var board = cutBoard
        board.cancel()
        cutBoard = board
    }

    /// ⌘V with a pending ⌘X cut (CutBoard): moves the cut items into the active folder and returns true; false = no
    /// pending cut, the ordinary paste runs.
    func pasteCutItems() -> Bool {
        let board = cutBoard
        let currentChangeCount = NSPasteboard.general.changeCount
        let moves = board.pasteMoves(into: active.path, currentChangeCount: currentChangeCount)
        guard !moves.isEmpty else { return false }
        enqueueCutMove(moves, into: active.path)
        var cleared = board
        cleared.cancel()
        cutBoard = cleared
        return true
    }

    private func enqueueCutMove(_ sources: [String], into destination: String) {
        guard FileOperationRules.nestingViolation(sources: sources, destination: destination) == nil else {
            banner = "Không thể chép một thư mục vào chính nó"
            return
        }
        _ = FileOperationQueue.shared.enqueue(.move, sources: sources, destination: destination)
    }
}
