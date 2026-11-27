import AppKit

/// XF-T41 — the notch's Drop Tray is the browser's shelf now (owner, 2026-11-09: the browser's own Shelf duplicated it;
/// FileOctopus has one shelf, XFinder had two). What the removed Shelf bar could do and the tray could not — copy or
/// move its items into the browser's active pane, batch-rename them — goes through here, so both the notch page and
/// the Khay thả page share one definition of "the active pane" and reuse `FileOperationQueue`.
@MainActor
enum DropTrayBrowserBridge {
    /// The folder shown in the active pane of the key (else most recent) browser window, when it is a real folder — nil
    /// with no browser window, during a search, or in a virtual location (Recents, a tag).
    static var activePaneFolder: String? {
        guard let model = BrowserWindowController.shared.frontmostModel, model.active.search == nil,
              VirtualLocation.parse(model.active.path) == nil else { return nil }
        return model.active.path
    }

    static var activePaneName: String? {
        activePaneFolder.map { ($0 as NSString).lastPathComponent }
    }

    /// Copies (`copy == true`) or moves `paths` into the active pane through the browser's own queue — the conflict
    /// sheet, progress and undo apply, exactly as a drop onto the pane.
    /// Reconciles `DropTrayStore` ONLY when the queue job finishes: moved items leave the tray ONLY if they succeeded;
    /// failed, skipped, or cancelled items stay in the tray with their failure reason recorded.
    @discardableResult
    static func send(
        _ paths: [String],
        copy: Bool,
        onComplete: (@MainActor (FileOperationQueue.JobCompletion) -> Void)? = nil
    ) -> Bool {
        guard !paths.isEmpty,
              let model = BrowserWindowController.shared.frontmostModel,
              let folder = activePaneFolder,
              let jobID = model.drop(paths, into: folder, copy: copy) else { return false }
        FileOperationQueue.shared.onJobComplete(jobID) { completion in
            DropTrayStore.shared.applyTransferOutcome(requestedPaths: paths, copy: copy, completion: completion)
            onComplete?(completion)
        }
        return true
    }

    /// Reuses `FileOperationQueue` directly for folder moves/copies and Trash actions from the Drop Tray,
    /// reconciling the tray only after the queued job completes.
    @discardableResult
    static func enqueueDirect(
        _ kind: FileOperationKind,
        paths: [String],
        destination: String?,
        onComplete: (@MainActor (FileOperationQueue.JobCompletion) -> Void)? = nil
    ) -> Bool {
        guard !paths.isEmpty,
              let jobID = FileOperationQueue.shared.enqueue(kind, sources: paths, destination: destination) else {
            return false
        }
        let isCopy = (kind == .copy || kind == .duplicate)
        FileOperationQueue.shared.onJobComplete(jobID) { completion in
            DropTrayStore.shared.applyTransferOutcome(requestedPaths: paths, copy: isCopy, completion: completion)
            onComplete?(completion)
        }
        return true
    }

    /// Batch rename of the tray's items in the browser's sheet (the one with Replace / Add / Format); opens a browser
    /// window when none is open.
    static func batchRename(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        let model = BrowserWindowController.shared.frontmostModel ?? BrowserWindowController.shared.openWindow(path: nil)
        model.batchRenameSources = paths
    }
}
