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

    /// D4 — clips the user has unlocked (Touch ID) THIS opening of the page, in memory only. Keyed by
    /// record id so a reload (which replaces `records` wholesale) does not lose an in-flight unlock.
    private(set) var unlocked: [UUID: BoardLock.UnlockedClip] = [:]

    /// Display string for the Touch ID sheet. `L10n` is a SwiftUI-side type the store cannot import
    /// (Core must stay Foundation/AppKit, not SwiftUI), so the VIEW sets this once on appear.
    var unlockReason: String = ""

    @ObservationIgnored private var screenLockObserver: NSObjectProtocol?

    private init() {
        // D4 — a locked screen must forget every unlocked clip; nothing decrypted stays in memory
        // past the point the Mac itself is locked.
        screenLockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.relockAll() }
        }
    }

    var boards: [Pinboard] { ClipboardManager.shared.pinboards }

    @ObservationIgnored private var recordsVersion = 0
    @ObservationIgnored private var facetsCache: (version: Int, boards: [Pinboard], value: ClipboardLibrary.Facets)?
    @ObservationIgnored private var filteredCache: (version: Int, boards: [Pinboard], query: ClipboardLibrary.Query,
                                                     minute: Int, value: [ClipboardRecord])?
    @ObservationIgnored private var proGateCache: (version: Int, limit: Int?, value: [ClipboardRecord])?

    // MARK: - Free/Pro (XF-T29)

    /// `records` (every SQLite row), gated by `ProLimit.clipboardItems`: this store reads EVERY row —
    /// unlike `ClipboardManager.history`, which is already capped by `clipboard.maxHistory` — so without
    /// this gate the Library would be a loophole around the Free limit. `facets`/`filtered`/`visible` all
    /// build on this, never on `records` directly; search (through `filtered`) therefore also only
    /// covers the visible part in Free, per spec XF-T29 §2. Keyed on the limit too (not just
    /// `recordsVersion`): activating a licence or flipping `pro.simulateTier` must take effect without a
    /// reload of `records`.
    private var proGatedRecords: [ClipboardRecord] {
        let limit = LicenseManager.shared.limit(.clipboardItems)
        if let c = proGateCache, c.version == recordsVersion, c.limit == limit { return c.value }
        let value = ClipboardProGate.visible(records, limit: limit)
        proGateCache = (recordsVersion, limit, value)
        return value
    }

    /// How many rows the Free limit hides right now — the "N mục cũ hơn" notice.
    var hiddenByProLimit: Int {
        ClipboardProGate.hiddenCount(records, limit: LicenseManager.shared.limit(.clipboardItems))
    }

    var facets: ClipboardLibrary.Facets {
        let b = boards
        if let c = facetsCache, c.version == recordsVersion, c.boards == b { return c.value }
        let value = ClipboardLibrary.facets(proGatedRecords, boards: b)
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
        let value = ClipboardLibrary.apply(query, to: proGatedRecords, boards: b, now: now, calendar: .current)
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

    // MARK: - Board lock (D4)

    func isLockedBoard(_ scope: ClipboardLibrary.Scope) -> Bool {
        guard case .board(let id) = scope else { return false }
        return boards.first { $0.id == id }?.isLocked ?? false
    }

    /// Opens the Secure Enclave key (prompts Touch ID / password via a FRESH `LAContext` each call —
    /// `BoardLockKeys.recipient` never reuses one) and decrypts THIS clip into memory only. A
    /// cancelled prompt shows no notice (the user just changed their mind); any other failure does.
    func unlock(_ r: ClipboardRecord) {
        guard r.isLocked else { return }
        guard let boardID = r.lockedBoardID, let board = boards.first(where: { $0.id == boardID }),
              let keyData = board.lockKeyData else {
            notice = "Không mở khoá được."
            return
        }
        do {
            let recipient = try BoardLockKeys.recipient(keyData: keyData, reason: unlockReason)
            let clip = try BoardLock.unlock(r, with: recipient, ops: BoardLockKeys.fileOps)
            unlocked[r.id] = clip
        } catch BoardLockKeys.Error.cancelled {
            // User backed out of the prompt — not a failure worth a notice.
        } catch let error where BoardLockKeys.isCancellation(error) {
            // The enclave's own refusal when the sheet is dismissed arrives through CryptoKit/Security,
            // not as BoardLockKeys.Error — same meaning, same silence.
        } catch {
            notice = "Không mở khoá được."
        }
    }

    /// Clears every in-memory decrypted clip and deletes any Quick Look temp file written for one.
    /// Called when the page disappears and when the screen locks — a decrypted clip that outlives
    /// either of those is exactly what the lock exists to prevent.
    func relockAll() {
        // Review: the old loop removed only "<id>.txt", but Quick Look of an unlocked image/file writes
        // "<id>.<original ext>" — those plaintext copies survived every relock. Remove EVERYTHING in the
        // temp folder, whatever it is called and whether or not its clip is still in `unlocked`.
        if let names = try? FileManager.default.contentsOfDirectory(atPath: qlTempDir.path) {
            for name in names { try? FileManager.default.removeItem(at: qlTempDir.appendingPathComponent(name)) }
        }
        unlocked = [:]
    }

    /// The record to RENDER: the unlocked (plain) version if this page has decrypted it this
    /// session, else the row as stored (locked rows render their placeholder body).
    func display(_ r: ClipboardRecord) -> ClipboardRecord {
        unlocked[r.id]?.record ?? r
    }

    func unlockedImage(_ r: ClipboardRecord) -> NSImage? {
        guard let clip = unlocked[r.id] else { return nil }
        if let data = clip.payloadData, let img = NSImage(data: data) { return img }
        if let data = clip.thumbnailData, let img = NSImage(data: data) { return img }
        return nil
    }

    /// "Khoá bảng này…": creates the enclave key and seals every member. Reloads afterward since
    /// many rows change at once — the local-patch rules above are for single-row edits.
    func lockBoard(_ board: Pinboard) {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await ClipboardManager.shared.lockBoard(board.id)
                self.unlocked = [:]
                self.notice = "Đã khoá bảng."
                self.reload()
            } catch BoardLockFailure.partialLock {
                // The board IS locked; the clips that could not be sealed were detached, never left readable.
                self.unlocked = [:]
                self.notice = "Đã khoá bảng. Một số clip không mã hoá được và đã bị bỏ khỏi bảng."
                self.reload()
            } catch {
                self.notice = "Không khoá được bảng."
            }
        }
    }

    /// "Gỡ khoá (giải mã lại)": one Touch ID prompt, decrypts every member back to plain rows/files,
    /// drops the key. Reloads afterward (every member's row shape changed).
    func unlockBoardPermanently(_ board: Pinboard) {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await ClipboardManager.shared.unlockBoardPermanently(board.id)
                self.unlocked = [:]
                self.notice = "Đã gỡ khoá bảng."
                self.reload()
            } catch BoardLockFailure.partialUnlock {
                // Some rows came back plain, some did not open; the key is kept so they still can.
                self.unlocked = [:]
                self.notice = "Một số clip chưa giải mã được — bảng vẫn khoá."
                self.reload()
            } catch BoardLockKeys.Error.cancelled {
                // The user dismissed the Touch ID sheet: nothing changed, nothing to say.
            } catch {
                self.notice = "Không gỡ khoá được."
            }
        }
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

    /// `r` may be either the raw stored row or its display (post-unlock) version — both carry the same
    /// `id`, which is what `isLockedForActions` keys on. Checking the id's unlock state rather than
    /// `r.isLocked` is load-bearing: the Library passes `store.display(record)` into most call sites,
    /// and the display version has already had its lock metadata stripped.
    private func isLockedForActions(_ r: ClipboardRecord) -> Bool {
        records.first(where: { $0.id == r.id })?.isLocked ?? r.isLocked
    }

    func copy(_ r: ClipboardRecord, plainText: Bool = false) {
        if isLockedForActions(r) {
            guard let clip = unlocked[r.id] else { notice = "Mở khoá thẻ này trước."; return }
            guard ClipboardPasteEngine.writeToPasteboard(unlocked: clip, plainText: plainText) else { return }
            ClipboardSounds.playCopy()
            notice = "Đã sao chép."
            return
        }
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
        if isLockedForActions(r) {
            guard let clip = unlocked[r.id] else { notice = "Mở khoá thẻ này trước."; return }
            pasteUnlockedIntoPreviousApp(clip, plainText: plainText)
            return
        }
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

    /// Same shape as `pasteIntoPreviousApp`, but for an already-unlocked clip — no usage bump (the
    /// underlying row's metadata was stripped of everything but flags; bumping it here would write a
    /// usage count onto a sealed row for no visible benefit).
    private func pasteUnlockedIntoPreviousApp(_ clip: BoardLock.UnlockedClip, plainText: Bool) {
        guard WindowManager.isTrusted else {
            _ = ClipboardPasteEngine.writeToPasteboard(unlocked: clip, plainText: plainText)
            notice = "Chưa cấp quyền Trợ năng nên chỉ sao chép, chưa dán."
            return
        }
        let mine = ProcessInfo.processInfo.processIdentifier
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != mine else {
                _ = ClipboardPasteEngine.writeToPasteboard(unlocked: clip, plainText: plainText)
                self.notice = "Không có app nào để dán — đã sao chép."
                return
            }
            _ = ClipboardPasteEngine.paste(unlocked: clip, to: pid, plainText: plainText)
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

    /// Adding to a locked board seals the clip (public key only, no prompt) — `addItemToPinboard`
    /// already does that. Removing a locked clip FROM a locked board needs to decrypt it first (so the
    /// row the user ends up with elsewhere is plain again), which needs a prompt — `removeItemFromPinboard`
    /// does not do that, so a locked board's removal goes through `removeItemFromLockedBoard` instead.
    func toggleMembership(_ r: ClipboardRecord, board: Pinboard) {
        let isMember = ClipboardLibrary.isMember(r, of: board)
        if isMember, board.isLocked, isLockedForActions(r) {
            guard let keyData = board.lockKeyData else { notice = "Không gỡ được khỏi bảng."; return }
            Task { [weak self] in
                guard let self else { return }
                do {
                    let recipient = try BoardLockKeys.recipient(keyData: keyData, reason: self.unlockReason)
                    try await ClipboardManager.shared.removeItemFromLockedBoard(r.id, pinboardID: board.id, recipient: recipient)
                    self.reload()
                } catch BoardLockKeys.Error.cancelled {
                    // User backed out of the prompt.
                } catch {
                    self.notice = "Không gỡ được khỏi bảng."
                }
            }
            return
        }
        if isMember {
            ClipboardManager.shared.removeItemFromPinboard(r.id, pinboardID: board.id)
        } else if !ClipboardManager.shared.addItemToPinboard(r.id, pinboardID: board.id) {
            notice = "Không thêm được vào bảng khoá."   // sealing failed ⇒ the clip was NOT added
        }
        reload()
    }

    /// Mirrors `NotchSurfaceController.applyTransform` (does not call the notch controller): run a
    /// transform on the record's FULL text, copy the result. A transform that changes nothing, or
    /// cannot run, reports why instead of silently doing nothing.
    func applyTransform(_ t: ClipboardTransform, to r: ClipboardRecord) {
        let text: String
        if isLockedForActions(r) {
            guard let clip = unlocked[r.id] else { notice = "Mở khoá thẻ này trước."; return }
            text = ClipboardText.fullText(snippet: clip.record.textSnippet, payloadPath: clip.record.payloadPath) ?? ""
        } else {
            text = ClipboardText.fullText(snippet: r.textSnippet, payloadPath: r.payloadPath) ?? ""
        }
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
        ClipboardManager.shared.deleteRecord(r)   // the record itself: its sealed files must go even when it is outside the capped history
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
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir
    }()

    /// Mirrors how the notch/shelf present Quick Look (`ClipboardQLController` + the system
    /// `QLPreviewPanel`): image/file clips preview their file directly; text-like clips are written
    /// to a temp `.txt` first, since `QLPreviewPanel` previews files, not strings. A locked, still
    /// unopened clip needs to be unlocked first — Quick Look of ciphertext is not a preview.
    func quickLook(_ r: ClipboardRecord) {
        if isLockedForActions(r) {
            guard let clip = unlocked[r.id] else { notice = "Mở khoá thẻ này trước."; return }
            quickLookUnlocked(clip)
            return
        }
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

    /// Writes the decrypted bytes to a temp file in the 0700 QL folder (deleted on relock by
    /// `relockAll()`) and previews that — never the sealed envelope on disk.
    private func quickLookUnlocked(_ clip: BoardLock.UnlockedClip) {
        let r = clip.record
        if r.type == .image || r.type == .file, let data = clip.payloadData ?? clip.thumbnailData {
            let ext = (clip.originalPayloadFileName as NSString?)?.pathExtension
            let name = "\(r.id.uuidString).\(ext?.isEmpty == false ? ext! : (r.type == .image ? "png" : "bin"))"
            let url = qlTempDir.appendingPathComponent(name)
            do {
                try data.write(to: url, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                qlController.present(url: url)
            } catch {
                notice = "Mục này không có tệp để xem nhanh."
            }
            return
        }
        guard let text = ClipboardText.fullText(snippet: r.textSnippet, payloadPath: nil) ?? (clip.payloadData.flatMap { String(data: $0, encoding: .utf8) }),
              !text.isEmpty else {
            notice = "Mục này không có tệp để xem nhanh."
            return
        }
        let url = qlTempDir.appendingPathComponent("\(r.id.uuidString).txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            qlController.present(url: url)
        } catch {
            notice = "Mục này không có tệp để xem nhanh."
        }
    }
}
