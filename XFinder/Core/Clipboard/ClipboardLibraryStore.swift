import AppKit
import Foundation
import Observation

/// Piece B of the D3 "Thư viện Clipboard" contract: the sidebar page's data source. Reads EVERY
/// row in SQLite (not `ClipboardManager`'s capped in-memory history) through its own store, so a
/// clip that aged out of the notch/shelf's window is still findable here.
///
/// Performance: `facets` and `filtered` are MEMOISED (review of D3 found the footer alone re-ran the
/// filter+sort pass five times per render and the rail re-ran `facets` nine times). The caches are
/// `@ObservationIgnored` so refreshing them inside a view body never re-invalidates that body; they are
/// keyed on `recordsVersion` (bumped by every mutation of `records`), the boards, the query and — for
/// `filtered`, whose periods depend on the clock — the current minute.
@MainActor
@Observable
final class ClipboardLibraryStore {
    static let shared = ClipboardLibraryStore()

    private(set) var records: [ClipboardRecord] = [] {
        didSet { recordsVersion &+= 1 }
    }
    private(set) var isLoading = false
    private(set) var lastLoaded: Date?

    var query = ClipboardLibrary.Query() {
        didSet { pagesShown = 1 }
    }
    var pagesShown = 1
    var selectedID: UUID?
    var inspectorOpen = false

    /// A STORE KEY (Vietnamese literal), or nil. The view wraps it in `L10n.t` and clears it after
    /// showing it — this type never renders a sentence itself (Core must not return display text).
    var notice: String?

    private init() {}

    var boards: [Pinboard] { ClipboardManager.shared.pinboards }

    @ObservationIgnored private var recordsVersion = 0
    @ObservationIgnored private var facetsCache: (version: Int, boards: [Pinboard], value: ClipboardLibrary.Facets)?
    @ObservationIgnored private var filteredCache: (version: Int, boards: [Pinboard], query: ClipboardLibrary.Query,
                                                     minute: Int, value: [ClipboardRecord])?

    var facets: ClipboardLibrary.Facets {
        let b = boards
        if let c = facetsCache, c.version == recordsVersion, c.boards == b { return c.value }
        let value = ClipboardLibrary.facets(records, boards: b)
        facetsCache = (recordsVersion, b, value)
        return value
    }

    var filtered: [ClipboardRecord] {
        let b = boards
        let now = Date()
        let minute = Int(now.timeIntervalSinceReferenceDate / 60)
        if let c = filteredCache, c.version == recordsVersion, c.boards == b, c.query == query, c.minute == minute {
            return c.value
        }
        let value = ClipboardLibrary.apply(query, to: records, boards: b, now: now, calendar: .current)
        filteredCache = (recordsVersion, b, query, minute, value)
        return value
    }

    var visible: [ClipboardRecord] {
        let all = filtered
        let count = ClipboardLibrary.visibleCount(total: all.count, pagesShown: pagesShown)
        return Array(all.prefix(count))
    }

    /// Replace one row in `records` in place (keeps order), e.g. after a pin or usage change, so the
    /// page reflects the edit without re-reading the whole table — and without racing the manager's
    /// own asynchronous write (review: a reload could read the OLD row before that write landed).
    private func replaceLocal(_ r: ClipboardRecord) {
        guard let i = records.firstIndex(where: { $0.id == r.id }) else { return }
        records[i] = r
    }

    private func withMetadata(_ r: ClipboardRecord, _ edit: (inout [String: String]) -> Void) -> ClipboardRecord {
        var meta = r.metadata
        edit(&meta)
        return ClipboardRecord(id: r.id, type: r.type, timestamp: r.timestamp,
                               sourceBundleID: r.sourceBundleID, sourceAppName: r.sourceAppName,
                               textSnippet: r.textSnippet, thumbnailPath: r.thumbnailPath,
                               payloadPath: r.payloadPath, ocrText: r.ocrText,
                               pinboardID: r.pinboardID, metadata: meta)
    }

    /// "Đã dùng" counts uses from THIS page too (review: it never incremented from the library). In-cap
    /// rows go through the manager (in-memory + its async persist); rows outside the capped history are
    /// persisted here. Either way the local copy is patched, never re-read.
    private func bumpUsage(_ r: ClipboardRecord) {
        let bumped = withMetadata(r) { $0["usageCount"] = "\((Int($0["usageCount"] ?? "0") ?? 0) + 1)" }
        if ClipboardManager.shared.history.contains(where: { $0.id == r.id }) {
            ClipboardManager.shared.incrementUsage(r.id)
        } else {
            Task { _ = await DatabaseService.shared.updateClipboardRecord(bumped) }
        }
        replaceLocal(bumped)
    }

    var selected: ClipboardRecord? {
        guard let id = selectedID else { return nil }
        return records.first { $0.id == id }
    }

    // MARK: - Loading

    /// Coalesces concurrent calls: a `reload()` fired while one is already in flight does not start
    /// a second fetch — it marks a pending reload that runs once the first finishes, so a burst of
    /// calls (e.g. a copy arriving while the page is still loading) settles on one extra fetch, not N.
    private var isFetching = false
    private var reloadPending = false

    func reload() {
        if isFetching {
            reloadPending = true
            return
        }
        isFetching = true
        isLoading = true
        Task { [weak self] in
            await self?.performReload()
        }
    }

    private func performReload() async {
        let rows = await DatabaseService.shared.fetchAllClipboardRecords()
        records = rows
        let keepID = selectedID
        if let keepID, records.contains(where: { $0.id == keepID }) {
            // Selection survives a reload that still contains it.
        } else {
            selectedID = nil
            inspectorOpen = false
        }
        lastLoaded = Date()
        isLoading = false
        isFetching = false
        if reloadPending {
            reloadPending = false
            reload()
        }
    }

    func loadMore() {
        pagesShown += 1
    }

    // MARK: - Selection

    func select(_ id: UUID?) {
        selectedID = id
        inspectorOpen = (id != nil)
    }

    func closeInspector() {
        inspectorOpen = false
    }

    /// Uses `ClipboardLibrary.MoveDirection` / `ClipboardLibrary.move` — the Library's own mirror of
    /// the notch's grid rule, NOT `NotchClipboardRules.Direction` (a different enum in a different
    /// file; see the contract's note in `ClipboardLibraryRules.swift`). Nothing selected yet selects
    /// the first item, matching every other "move with no selection" rule in this codebase.
    func move(_ direction: ClipboardLibrary.MoveDirection, columns: Int) {
        let items = visible
        guard !items.isEmpty else { return }
        guard let currentIndex = selectedID.flatMap({ id in items.firstIndex { $0.id == id } }) else {
            select(items[0].id)
            return
        }
        let next = ClipboardLibrary.move(currentIndex, direction: direction, count: items.count, columns: columns)
        select(items[next].id)
    }

    // MARK: - Text

    /// The whole text for a text-like clip (payload file preferred over the 200-char preview); nil
    /// for image/file, which have no text body.
    func fullText(of r: ClipboardRecord) -> String? {
        switch r.type {
        case .image, .file:
            return nil
        case .text, .code, .markdown, .color, .link, .merged:
            return ClipboardText.fullText(snippet: r.textSnippet, payloadPath: r.payloadPath) ?? r.ocrText
        }
    }

    // MARK: - Actions

    func copy(_ r: ClipboardRecord, plainText: Bool = false) {
        guard ClipboardPasteEngine.writeToPasteboard(record: r, plainText: plainText) else { return }
        ClipboardSounds.playCopy()
        bumpUsage(r)
        notice = "Đã sao chép."
    }

    /// Hides XFinder so the app the user was in comes forward, reads WHICH app that is, and pastes
    /// into it. `ClipboardPasteEngine.paste(to: nil)` only copies (it never synthesizes ⌘V without a
    /// target, to avoid pasting into XFinder itself), so the pid must be resolved here — after the
    /// hide has settled, from the frontmost application. No other app ⇒ the clip is copied and the
    /// notice says so; no Accessibility ⇒ same, since ⌘V cannot be posted (Part 0 §6: the button must
    /// not claim a paste that did not happen).
    func pasteIntoPreviousApp(_ r: ClipboardRecord, plainText: Bool = false) {
        // Known before hiding: without Accessibility no ⌘V can be posted, so do not hide the window
        // for an attempt that cannot succeed (review) — copy, say so, stay put.
        guard WindowManager.isTrusted else {
            _ = ClipboardPasteEngine.writeToPasteboard(record: r, plainText: plainText)
            notice = "Chưa cấp quyền Trợ năng nên chỉ sao chép, chưa dán."
            return
        }
        let mine = ProcessInfo.processInfo.processIdentifier
        NSApp.hide(nil)
        // Only knowable AFTER the hide settles: which app came forward. Reading it before the hide
        // would return XFinder itself.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != mine else {
                _ = ClipboardPasteEngine.writeToPasteboard(record: r, plainText: plainText)
                self.notice = "Không có app nào để dán — đã sao chép."
                return
            }
            if ClipboardPasteEngine.paste(record: r, to: pid, plainText: plainText) {
                self.bumpUsage(r)
            }
        }
    }

    /// `ClipboardManager.togglePin` only knows records inside its capped in-memory history. For a
    /// record the library loaded that is NOT in that capped window, flip the metadata flag here and
    /// persist directly, then reload so `records`/`facets` reflect it.
    func togglePin(_ r: ClipboardRecord) {
        let updated = withMetadata(r) { $0["isPinned"] = ($0["isPinned"] != "true") ? "true" : "false" }
        if ClipboardManager.shared.history.contains(where: { $0.id == r.id }) {
            // The manager flips its copy synchronously and persists asynchronously. The page must NOT
            // re-read the table here: a reload racing that write could show the old state for a beat
            // (review, split verdict). Patch the local row instead — same value the manager now holds.
            ClipboardManager.shared.togglePin(r.id)
        } else {
            Task { _ = await DatabaseService.shared.updateClipboardRecord(updated) }
        }
        replaceLocal(updated)
    }

    func toggleMembership(_ r: ClipboardRecord, board: Pinboard) {
        if ClipboardLibrary.isMember(r, of: board) {
            ClipboardManager.shared.removeItemFromPinboard(r.id, pinboardID: board.id)
        } else {
            ClipboardManager.shared.addItemToPinboard(r.id, pinboardID: board.id)
        }
        reload()
    }

    /// Mirrors `NotchSurfaceController.applyTransform` (does not call the notch controller): run a
    /// transform on the record's FULL text, copy the result. A transform that changes nothing, or
    /// cannot run, reports why instead of silently doing nothing.
    func applyTransform(_ t: ClipboardTransform, to r: ClipboardRecord) {
        let text = ClipboardText.fullText(snippet: r.textSnippet, payloadPath: r.payloadPath) ?? ""
        switch t.apply(to: text) {
        case .success(let out):
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(out, forType: .string)
            ClipboardSounds.playCopy()
            notice = "Đã sao chép kết quả."
        case .failure(let f):
            notice = f.messageKey
        }
    }

    /// Removes from the capped history (if present) AND the DB row, then drops it from this store's
    /// own `records` and fixes the selection so the inspector does not point at a deleted clip.
    func delete(_ r: ClipboardRecord) {
        let before = visible
        let index = before.firstIndex { $0.id == r.id }
        ClipboardManager.shared.deleteRecord(r.id)
        records.removeAll { $0.id == r.id }
        guard selectedID == r.id else { return }
        if let index, let newIndex = NotchClipboardRules.selectionAfterDeleting(index: index, newCount: visible.count) {
            select(visible[newIndex].id)
        } else {
            select(nil)
        }
    }

    /// Mirrors `NotchSurfaceController.openSourceApp`: bring the source app forward if it is running,
    /// else launch it.
    func openSourceApp(_ r: ClipboardRecord) {
        guard let bundleID = r.sourceBundleID, !bundleID.isEmpty else { return }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate(options: [.activateAllWindows])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// The page a clip came from — same two keys `NotchClipboardView.sourcePage` checks, in the same
    /// order: `"sourceURL"` (Chromium's `org.chromium.source-url`, captured at copy time; Safari's
    /// equivalent is unverified so nothing is guessed for it) then `"url"` (a copied link itself).
    /// For a `.link` record with neither key set, the snippet is tried last since that IS the link.
    func sourcePageURL(_ r: ClipboardRecord) -> URL? {
        for key in ["sourceURL", "url"] {
            if let s = r.metadata[key], !s.isEmpty, let u = URL(string: s), ["http", "https"].contains(u.scheme ?? "") {
                return u
            }
        }
        if r.type == .link, let snippet = r.textSnippet, let u = URL(string: snippet),
           ["http", "https"].contains(u.scheme ?? "") {
            return u
        }
        return nil
    }

    func openSourcePage(_ r: ClipboardRecord) {
        guard let url = sourcePageURL(r) else { return }
        NSWorkspace.shared.open(url)
    }

    /// A file on disk this record points at — the payload path, or `metadata["path"]` when that
    /// exists on disk (the same two sources `NotchClipboardView.revealablePath` checks).
    func fileURL(_ r: ClipboardRecord) -> URL? {
        if let p = r.payloadPath, FileManager.default.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        if let p = r.metadata["path"], FileManager.default.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        return nil
    }

    func revealFile(_ r: ClipboardRecord) {
        guard let url = fileURL(r) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private let qlController = ClipboardQLController()
    private let qlTempDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("XFinderLibraryQuickLook", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Mirrors how the notch/shelf present Quick Look (`ClipboardQLController` + the system
    /// `QLPreviewPanel`): image/file clips preview their file directly; text-like clips are written
    /// to a temp `.txt` first, since `QLPreviewPanel` previews files, not strings.
    func quickLook(_ r: ClipboardRecord) {
        if let url = fileURL(r), r.type == .image || r.type == .file {
            qlController.present(url: url)
            return
        }
        guard let text = fullText(of: r), !text.isEmpty else {
            notice = "Mục này không có tệp để xem nhanh."
            return
        }
        let url = qlTempDir.appendingPathComponent("\(r.id.uuidString).txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            qlController.present(url: url)
        } catch {
            notice = "Mục này không có tệp để xem nhanh."
        }
    }
}
