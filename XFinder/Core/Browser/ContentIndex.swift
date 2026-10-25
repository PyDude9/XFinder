import Foundation
import SQLite3

/// XF-T30 W5a — the opt-in content index (FileOctopus `ContentIndex`, FTS5 `unicode61 remove_diacritics 2`, `alt` column
/// for OCR text). Extraction runs in the `XFinder --vision` child (text-pdf / text-rich / ocr-index). Contract
/// docs/specs/XF-T30-w5a-contract.md §3. W5a builder (C5): implement.
actor ContentIndex {
    static let shared = ContentIndex()

    struct Hit: Equatable, Sendable {
        let path: String
        let snippet: String
        let rank: Double
    }

    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/XFinder/Browser/Search/content.sqlite")
    }

    // MARK: - State

    private var db: OpaquePointer?
    /// nil = use `Self.databaseURL`; set by the test hook so a probe never touches the real on-disk index.
    private let overrideURL: URL?
    private var roots: [IndexRoot] = []
    private var statuses: [String: IndexRootStatus] = [:]
    private var suspended = false
    /// Guards against overlapping `drainQueue()` loops (resume() + a root being added at the same time).
    private var draining = false
    private var queue: [QueueItem] = []
    /// doc paths already queued or indexed this generation, so re-scanning a root does not requeue work in flight.
    private var queuedPaths: Set<String> = []

    private struct QueueItem {
        let rootID: String
        let path: String
    }

    init(databaseURL: URL? = nil) {
        self.overrideURL = databaseURL
    }

    private var resolvedURL: URL { overrideURL ?? Self.databaseURL }

    // MARK: - Open / schema

    private func openIfNeeded() -> OpaquePointer? {
        if db != nil { return db }
        let url = resolvedURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else { return nil }
        sqlite3_exec(handle, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(handle, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
        sqlite3_exec(handle, "PRAGMA secure_delete=ON;", nil, nil, nil)
        createSchema(handle)
        db = handle
        return handle
    }

    private func createSchema(_ handle: OpaquePointer?) {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS documents (
                doc_id INTEGER PRIMARY KEY AUTOINCREMENT,
                root TEXT NOT NULL,
                path TEXT NOT NULL UNIQUE,
                inode INTEGER,
                fingerprint TEXT NOT NULL,
                status TEXT NOT NULL,
                skip_reason TEXT,
                truncated INTEGER NOT NULL DEFAULT 0,
                indexed_at REAL NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_documents_root ON documents(root);",
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS content_fts USING fts5(
                body, alt, path UNINDEXED, tokenize='unicode61 remove_diacritics 2'
            );
            """,
        ]
        for sql in statements {
            if sqlite3_exec(handle, sql, nil, nil, nil) != SQLITE_OK {
                print("ContentIndex schema error: \(String(cString: sqlite3_errmsg(handle)))")
            }
        }
    }

    // MARK: - Roots

    /// The approved roots changed: only roots with `contents` or `textInImages` on ever get crawled. A root that loses
    /// both, or is removed outright, has its rows erased (derived data — never the user's files).
    func setRoots(_ newRoots: [IndexRoot]) {
        let previous = Dictionary(uniqueKeysWithValues: roots.map { ($0.id, $0) })
        roots = newRoots
        let wanted = Set(newRoots.filter { $0.contents || $0.textInImages }.map(\.id))
        for (id, old) in previous where !wanted.contains(id) {
            eraseRoot(old.path)
            statuses[id] = nil
        }
        guard let handle = openIfNeeded() else { return }
        for root in newRoots {
            guard root.contents || root.textInImages else { continue }
            if root.paused {
                statuses[root.id] = .paused
                continue
            }
            statuses[root.id] = statuses[root.id] ?? .indexing(done: 0)
            enqueueCrawl(root)
        }
        _ = handle
        if !suspended { Task(priority: .utility) { await self.drainQueue() } }
    }

    func status() -> [String: IndexRootStatus] { statuses }

    func setPaused(_ rootID: String, _ paused: Bool) {
        guard let idx = roots.firstIndex(where: { $0.id == rootID }) else { return }
        roots[idx].paused = paused
        if paused {
            statuses[rootID] = .paused
            queue.removeAll { $0.rootID == rootID }
        } else {
            statuses[rootID] = .indexing(done: 0)
            enqueueCrawl(roots[idx])
            if !suspended { Task(priority: .utility) { await self.drainQueue() } }
        }
    }

    func rebuild(_ rootID: String) {
        guard let root = roots.first(where: { $0.id == rootID }) else { return }
        eraseRoot(root.path)
        statuses[rootID] = .indexing(done: 0)
        enqueueCrawl(root)
        if !suspended { Task(priority: .utility) { await self.drainQueue() } }
    }

    /// Derived data only: every root stays approved and re-indexes.
    func eraseAll() {
        guard let handle = openIfNeeded() else { return }
        sqlite3_exec(handle, "DELETE FROM documents;", nil, nil, nil)
        sqlite3_exec(handle, "INSERT INTO content_fts(content_fts) VALUES('delete-all');", nil, nil, nil)
        sqlite3_exec(handle, "INSERT INTO content_fts(content_fts) VALUES('optimize');", nil, nil, nil)
        queue.removeAll()
        queuedPaths.removeAll()
        for root in roots where root.contents || root.textInImages {
            statuses[root.id] = root.paused ? .paused : .indexing(done: 0)
            if !root.paused { enqueueCrawl(root) }
        }
        if !suspended { Task(priority: .utility) { await self.drainQueue() } }
    }

    /// No browser window open: stop background work. In-flight items stay queued so `resume()` continues, nothing
    /// already written is lost.
    func suspend() { suspended = true }

    /// A browser window opened: continue draining the queue.
    func resume() {
        suspended = false
        if !queue.isEmpty { Task(priority: .utility) { await self.drainQueue() } }
    }

    private func eraseRoot(_ rootPath: String) {
        guard let handle = openIfNeeded() else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT path FROM documents WHERE root = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, rootPath, -1, SQLITE_TRANSIENT)
        var paths: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let p = sqlite3_column_text(stmt, 0) { paths.append(String(cString: p)) }
        }
        sqlite3_finalize(stmt)
        for p in paths { deleteDocument(p, handle: handle) }
    }

    // MARK: - Crawl (filename discovery only — the queue extracts content)

    private func enqueueCrawl(_ root: IndexRoot) {
        let rootPath = root.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: rootPath), includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else { return }
        for case let url as URL in enumerator {
            let path = url.path
            if SearchIndexRules.isExcluded(path, home: home) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }
            let kind = SearchIndexRules.contentKind(forExtension: url.pathExtension.lowercased())
            let wantsContent = root.contents && (kind == .plainText || kind == .pdf || kind == .richText)
            let wantsImage = root.textInImages && kind == .image
            let wantsScannedPDF = root.textInImages && kind == .pdf
            guard wantsContent || wantsImage || wantsScannedPDF else { continue }
            if !queuedPaths.contains(path) {
                queuedPaths.insert(path)
                queue.append(QueueItem(rootID: root.id, path: path))
            }
        }
    }

    // MARK: - Queue drain (one-at-a-time, utility priority)

    /// Processes the queue one file at a time off the actor between awaits, so a huge backlog never blocks the actor
    /// from answering `search`/`status` in between files.
    private func drainQueue() async {
        guard !draining else { return }
        draining = true
        defer { draining = false }
        while !suspended {
            guard let item = queue.first else { break }
            queue.removeFirst()
            queuedPaths.remove(item.path)
            await indexOne(rootID: item.rootID, path: item.path)
            if queue.filter({ $0.rootID == item.rootID }).isEmpty, statuses[item.rootID] != nil {
                statuses[item.rootID] = .ready
            }
        }
    }

    private func indexOne(rootID: String, path: String) async {
        guard let root = roots.first(where: { $0.id == rootID }) else { return }
        let url = URL(fileURLWithPath: path)

        // iCloud placeholder: never force a download just to index it.
        if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
           values.isUbiquitousItem == true,
           values.ubiquitousItemDownloadingStatus != .current, values.ubiquitousItemDownloadingStatus != .downloaded {
            writeSkip(root: root.path, path: path, reason: "dataless")
            return
        }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64, let mtime = attrs[.modificationDate] as? Date else {
            writeSkip(root: root.path, path: path, reason: "unreadable")
            return
        }
        let fingerprint = "\(size)-\(mtime.timeIntervalSince1970)"
        if let existing = existingFingerprint(path: path), existing == fingerprint {
            return  // unchanged: skip re-extraction entirely
        }

        let ext = url.pathExtension.lowercased()
        let kind = SearchIndexRules.contentKind(forExtension: ext)
        let inode = (attrs[.systemFileNumber] as? Int).map(UInt64.init)

        switch kind {
        case .plainText:
            guard size <= SearchIndexRules.textReadCap else {
                writeSkip(root: root.path, path: path, reason: "too-large", inode: inode, fingerprint: fingerprint)
                return
            }
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                writeSkip(root: root.path, path: path, reason: "unreadable", inode: inode, fingerprint: fingerprint)
                return
            }
            var truncated = false
            if text.count > SearchIndexRules.storedCharacterCap {
                text = String(text.prefix(SearchIndexRules.storedCharacterCap))
                truncated = true
            }
            writeDocument(root: root.path, path: path, inode: inode, fingerprint: fingerprint,
                          body: text, alt: nil, truncated: truncated)

        case .pdf:
            guard root.contents || root.textInImages else { return }
            guard size <= SearchIndexRules.pdfSizeCap else {
                writeSkip(root: root.path, path: path, reason: "too-large", inode: inode, fingerprint: fingerprint)
                return
            }
            guard let bytes = VisionChild.fileBytes(url) else {
                writeSkip(root: root.path, path: path, reason: "unreadable", inode: inode, fingerprint: fingerprint)
                return
            }
            var body = ""
            var truncated = false
            if root.contents, let reply = VisionChild.run(.textPDF, imageData: bytes), Self.isTextReply(reply.status) {
                body = String(decoding: reply.output, as: UTF8.self)
                truncated = truncated || reply.status == VisionChild.Status.truncated
            }
            var alt: String?
            if root.textInImages {
                // The scanned-PDF path (no text layer) only pays off when the text layer above came back empty —
                // most PDFs with real text are never worth re-rendering and OCR-ing page images too.
                if body.isEmpty, let ocrReply = VisionChild.run(.ocrIndex, imageData: bytes), Self.isTextReply(ocrReply.status) {
                    alt = String(decoding: ocrReply.output, as: UTF8.self)
                    truncated = truncated || ocrReply.status == VisionChild.Status.truncated
                }
            }
            if body.isEmpty && (alt?.isEmpty ?? true) {
                writeSkip(root: root.path, path: path, reason: "no-text", inode: inode, fingerprint: fingerprint)
                return
            }
            writeDocument(root: root.path, path: path, inode: inode, fingerprint: fingerprint,
                          body: body, alt: alt, truncated: truncated)

        case .richText:
            guard root.contents else { return }
            guard size <= SearchIndexRules.textReadCap * 8 else {   // rich text can expand a lot after decode; generous cap before handing to child
                writeSkip(root: root.path, path: path, reason: "too-large", inode: inode, fingerprint: fingerprint)
                return
            }
            guard let bytes = VisionChild.fileBytes(url) else {
                writeSkip(root: root.path, path: path, reason: "unreadable", inode: inode, fingerprint: fingerprint)
                return
            }
            guard let reply = VisionChild.run(.textRich, imageData: bytes, extensionHint: ext), Self.isTextReply(reply.status) else {
                writeSkip(root: root.path, path: path, reason: "unreadable", inode: inode, fingerprint: fingerprint)
                return
            }
            let text = String(decoding: reply.output, as: UTF8.self)
            guard !text.isEmpty else {
                writeSkip(root: root.path, path: path, reason: "no-text", inode: inode, fingerprint: fingerprint)
                return
            }
            writeDocument(root: root.path, path: path, inode: inode, fingerprint: fingerprint,
                          body: text, alt: nil, truncated: reply.status == VisionChild.Status.truncated)

        case .image:
            guard root.textInImages else { return }
            guard size <= SearchIndexRules.ocrFileCap else {
                writeSkip(root: root.path, path: path, reason: "too-large", inode: inode, fingerprint: fingerprint)
                return
            }
            guard let bytes = VisionChild.fileBytes(url) else {
                writeSkip(root: root.path, path: path, reason: "unreadable", inode: inode, fingerprint: fingerprint)
                return
            }
            guard let reply = VisionChild.run(.ocrIndex, imageData: bytes), Self.isTextReply(reply.status) else {
                writeSkip(root: root.path, path: path, reason: "no-text", inode: inode, fingerprint: fingerprint)
                return
            }
            let text = String(decoding: reply.output, as: UTF8.self)
            guard !text.isEmpty else {
                writeSkip(root: root.path, path: path, reason: "no-text", inode: inode, fingerprint: fingerprint)
                return
            }
            writeDocument(root: root.path, path: path, inode: inode, fingerprint: fingerprint,
                          body: "", alt: text, truncated: reply.status == VisionChild.Status.truncated)

        case .none:
            return
        }
    }

    /// `ok` or `truncated` both carry usable `stdout` text; anything else (notAnImage, noSubject, visionFailed,
    /// usage) does not.
    private nonisolated static func isTextReply(_ status: Int32) -> Bool {
        status == VisionChild.Status.ok || status == VisionChild.Status.truncated
    }

    // MARK: - Writes

    private func existingFingerprint(path: String) -> String? {
        guard let handle = openIfNeeded() else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT fingerprint FROM documents WHERE path = ?", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW, let p = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: p)
    }

    private func deleteDocument(_ path: String, handle: OpaquePointer?) {
        var docID: Int64?
        var find: OpaquePointer?
        if sqlite3_prepare_v2(handle, "SELECT doc_id FROM documents WHERE path = ?", -1, &find, nil) == SQLITE_OK {
            sqlite3_bind_text(find, 1, path, -1, SQLITE_TRANSIENT)
            if sqlite3_step(find) == SQLITE_ROW { docID = sqlite3_column_int64(find, 0) }
        }
        sqlite3_finalize(find)
        if let id = docID {
            var delFTS: OpaquePointer?
            if sqlite3_prepare_v2(handle, "DELETE FROM content_fts WHERE rowid = ?", -1, &delFTS, nil) == SQLITE_OK {
                sqlite3_bind_int64(delFTS, 1, id)
                sqlite3_step(delFTS)
            }
            sqlite3_finalize(delFTS)
        }
        var del: OpaquePointer?
        if sqlite3_prepare_v2(handle, "DELETE FROM documents WHERE path = ?", -1, &del, nil) == SQLITE_OK {
            sqlite3_bind_text(del, 1, path, -1, SQLITE_TRANSIENT)
            sqlite3_step(del)
        }
        sqlite3_finalize(del)
    }

    private func writeSkip(root: String, path: String, reason: String, inode: UInt64? = nil, fingerprint: String = "") {
        guard let handle = openIfNeeded() else { return }
        deleteDocument(path, handle: handle)
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO documents (root, path, inode, fingerprint, status, skip_reason, truncated, indexed_at)
        VALUES (?, ?, ?, ?, 'skipped', ?, 0, ?)
        """
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, root, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, path, -1, SQLITE_TRANSIENT)
        if let inode { sqlite3_bind_int64(stmt, 3, Int64(bitPattern: inode)) } else { sqlite3_bind_null(stmt, 3) }
        sqlite3_bind_text(stmt, 4, fingerprint, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, reason, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 6, Date().timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    private func writeDocument(root: String, path: String, inode: UInt64?, fingerprint: String,
                                body: String, alt: String?, truncated: Bool) {
        guard let handle = openIfNeeded() else { return }
        deleteDocument(path, handle: handle)
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO documents (root, path, inode, fingerprint, status, skip_reason, truncated, indexed_at)
        VALUES (?, ?, ?, ?, 'indexed', NULL, ?, ?)
        """
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, root, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, path, -1, SQLITE_TRANSIENT)
        if let inode { sqlite3_bind_int64(stmt, 3, Int64(bitPattern: inode)) } else { sqlite3_bind_null(stmt, 3) }
        sqlite3_bind_text(stmt, 4, fingerprint, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 5, truncated ? 1 : 0)
        sqlite3_bind_double(stmt, 6, Date().timeIntervalSince1970)
        let stepped = sqlite3_step(stmt) == SQLITE_DONE
        sqlite3_finalize(stmt)
        guard stepped else { return }
        let docID = sqlite3_last_insert_rowid(handle)
        var ftsStmt: OpaquePointer?
        let ftsSQL = "INSERT INTO content_fts (rowid, body, alt, path) VALUES (?, ?, ?, ?)"
        guard sqlite3_prepare_v2(handle, ftsSQL, -1, &ftsStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(ftsStmt) }
        sqlite3_bind_int64(ftsStmt, 1, docID)
        sqlite3_bind_text(ftsStmt, 2, body, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(ftsStmt, 3, alt ?? "", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(ftsStmt, 4, path, -1, SQLITE_TRANSIENT)
        sqlite3_step(ftsStmt)
    }

    // MARK: - Search

    /// `bm25`-ranked snippet search over `body`/`alt`, filtered to `folders` (nil = every indexed root).
    func search(_ text: String, within folders: [String]?, limit: Int) -> [Hit] {
        guard let handle = openIfNeeded(), !text.isEmpty else { return [] }
        let escaped = ftsMatchQuery(text)
        var sql = """
        SELECT d.path, snippet(content_fts, -1, '', '', '…', 24), bm25(content_fts) AS rank
        FROM content_fts
        JOIN documents d ON d.doc_id = content_fts.rowid
        WHERE content_fts MATCH ?
        """
        if let folders, !folders.isEmpty {
            // ESCAPE '\' so a folder name that itself contains a literal "%" or "_" (both valid path
            // characters) cannot act as a LIKE wildcard and leak matches from a sibling folder, or fail to
            // match files inside the very folder being searched (bug found in review: escapeLike below).
            let clauses = folders.map { _ in "d.path LIKE ? ESCAPE '\\'" }.joined(separator: " OR ")
            sql += " AND (\(clauses))"
        }
        sql += " ORDER BY rank LIMIT ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var idx: Int32 = 1
        sqlite3_bind_text(stmt, idx, escaped, -1, SQLITE_TRANSIENT); idx += 1
        if let folders, !folders.isEmpty {
            for folder in folders {
                let prefix = folder.hasSuffix("/") ? folder : folder + "/"
                sqlite3_bind_text(stmt, idx, Self.escapeLikePattern(prefix) + "%", -1, SQLITE_TRANSIENT)
                idx += 1
            }
        }
        sqlite3_bind_int(stmt, idx, Int32(limit))
        var out: [Hit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let pathC = sqlite3_column_text(stmt, 0) else { continue }
            let snippet = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let rank = sqlite3_column_double(stmt, 2)
            out.append(Hit(path: String(cString: pathC), snippet: snippet, rank: rank))
        }
        return out
    }

    /// FTS5 MATCH syntax reserves `" * ^ ( ) -`; a plain phrase query quotes each word and ANDs them
    /// (default), so a literal colon or quote in the user's text cannot be mistaken for FTS syntax or
    /// break the query (`NSExpression`-style crash surface, rule 15).
    private func ftsMatchQuery(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " ")
    }

    /// `LIKE`'s own wildcards (`%`, `_`) are ordinary path characters too — a folder literally named
    /// `100%done` must not have its `%` read as "any characters" when used as a scope prefix. Escapes the
    /// backslash itself first, then both wildcards, for use with `LIKE ? ESCAPE '\'`.
    private nonisolated static func escapeLikePattern(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
