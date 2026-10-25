import Foundation

/// XF-T30 W5a — the rules of the opt-in local index (FileOctopus "Search" settings): which folders, what is skipped,
/// the content limits, what an FSEvents flag means, how a root's status reads. Pure, symlinked into the test package.
/// Contract docs/specs/XF-T30-w5a-contract.md §2.
struct IndexRoot: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var path: String
    /// Index file contents (text, PDF text layer, rich text).
    var contents: Bool
    /// OCR images and scanned PDFs (Text in Images).
    var textInImages: Bool
    var paused: Bool
    /// Identity when approved (device + inode) so a folder moved or replaced reads "Moved or replaced — add it again".
    var device: Int32?
    var inode: UInt64?
}

enum IndexRootStatus: Equatable, Sendable {
    case indexing(done: Int)
    case updating(changes: Int)
    case ready
    case paused
    case offline
    case noAccess
    case movedOrReplaced
    case failed
}

enum IndexContentKind: Equatable, Sendable { case plainText, pdf, richText, image, none }

enum SearchIndexRules {
    static let textReadCap = 2 * 1024 * 1024
    static let storedCharacterCap = 200_000
    static let pdfPageCap = 50
    static let pdfSizeCap = 64 * 1024 * 1024
    static let scannedPDFPageCap = 10
    static let ocrFileCap = 50 * 1024 * 1024

    static let excludedDirectoryNames: Set<String> = ["node_modules", ".git", "DerivedData", ".build", "build", "Pods", ".Trash"]

    /// Lexical path components: `/` splits, `.` dropped, `..` pops the last component, trailing/doubled slashes
    /// collapse away (empty subsequences omitted) — no disk access, so no live symlink resolution (that is the
    /// controller's job with `realpath`, same split as `CrewGate.StateChanging.pathInside`).
    private static func components(_ path: String) -> [String] {
        var out: [String] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { _ = out.popLast(); continue }
            out.append(String(part))
        }
        return out
    }

    /// `true` when `inner`'s components start with every component of `outer` (outer == inner counts as inside).
    private static func isInside(_ inner: [String], _ outer: [String]) -> Bool {
        inner.count >= outer.count && Array(inner.prefix(outer.count)) == outer
    }

    /// `~/Library` (itself and everything below it) or any path component equal to a name in `excludedDirectoryNames`
    /// — a whole-component match, not a substring: a folder literally named "node_modules-archive" is not excluded,
    /// but ".../node_modules/anything" is, and so is ".../node_modules" itself.
    static func isExcluded(_ path: String, home: String) -> Bool {
        let parts = components(path)
        let libraryParts = components(home + "/Library")
        if isInside(parts, libraryParts) { return true }
        return parts.contains { excludedDirectoryNames.contains($0) }
    }

    /// By lowercase extension. W5a builder (pure): implement (txt md csv json swift … ⇒ plainText; pdf; rtf rtfd doc docx
    /// odt html htm pages? (pages is a package — none); png jpg jpeg heic tiff gif bmp webp ⇒ image).
    static func contentKind(forExtension ext: String) -> IndexContentKind {
        switch ext.lowercased() {
        case "txt", "md", "markdown", "csv", "tsv", "json", "log", "swift", "c", "h", "m", "mm", "cpp", "hpp", "cc",
             "py", "js", "ts", "tsx", "jsx", "sh", "zsh", "rb", "go", "rs", "java", "kt", "yaml", "yml", "xml", "ini",
             "conf", "toml", "plist":
            return .plainText
        case "pdf":
            return .pdf
        case "rtf", "rtfd", "doc", "docx", "odt", "html", "htm":
            return .richText
        case "png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp", "webp":
            return .image
        default:
            return .none
        }
    }

    enum EventAction: Equatable, Sendable {
        case rescanSubtree(String), updatePath(String), removePath(String), rootChanged
    }

    /// One FSEvents event (`kFSEventStreamEventFlag*` raw values) → what the index does. Values confirmed against the
    /// live CoreServices SDK (probe, positive control: `kFSEventStreamEventFlagMustScanSubDirs == 0x1` etc. all true):
    /// MustScanSubDirs=0x1, UserDropped=0x2, KernelDropped=0x4, HistoryDone=0x10, RootChanged=0x20, ItemRemoved=0x200.
    /// `RootChanged` wins over everything else (the root itself moved or was replaced); `MustScanSubDirs`/`UserDropped`/
    /// `KernelDropped` all mean "the stream can't tell you every event, rescan this subtree" so they collapse to the
    /// same `rescanSubtree`; otherwise `ItemRemoved` deletes the one path; anything else is a plain update.
    /// W5a builder (pure): implement.
    static func action(path: String, flags: UInt32) -> EventAction {
        let mustScanSubDirs: UInt32 = 0x1
        let userDropped: UInt32 = 0x2
        let kernelDropped: UInt32 = 0x4
        let rootChanged: UInt32 = 0x20
        let itemRemoved: UInt32 = 0x200
        if flags & rootChanged != 0 { return .rootChanged }
        if flags & (mustScanSubDirs | userDropped | kernelDropped) != 0 { return .rescanSubtree(path) }
        if flags & itemRemoved != 0 { return .removePath(path) }
        return .updatePath(path)
    }

    enum RootValidation: Equatable, Sendable {
        case ok, notADirectory, excluded, alreadyCovered(by: String), coversExisting([String])
    }

    /// Adding `path` as a root. A root inside an existing one is `alreadyCovered`; one that contains existing roots is
    /// `coversExisting` (the caller merges them). W5a builder (pure): implement.
    static func validateNewRoot(_ path: String, isDirectory: Bool, existing: [IndexRoot], home: String) -> RootValidation {
        guard isDirectory else { return .notADirectory }
        if isExcluded(path, home: home) { return .excluded }
        let newParts = components(path)
        for root in existing {
            let rootParts = components(root.path)
            // `isInside` already covers the identical-path case (an array is trivially "inside" itself).
            if isInside(newParts, rootParts) { return .alreadyCovered(by: root.path) }
        }
        let covered = existing.filter { isInside(components($0.path), newParts) }.map(\.path)
        if !covered.isEmpty { return .coversExisting(covered) }
        return .ok
    }

    /// L10n key for a status. W5a builder (pure): implement.
    static func statusKey(_ status: IndexRootStatus) -> String {
        switch status {
        case .indexing: return "Đang đánh chỉ mục…"
        case .updating: return "Đang cập nhật…"
        case .ready: return "Sẵn sàng"
        case .paused: return "Đã tạm dừng"
        case .offline: return "Ngoại tuyến"
        case .noAccess: return "Không có quyền truy cập"
        case .movedOrReplaced: return "Đã di chuyển hoặc thay thế — thêm lại"
        case .failed: return "Thất bại"
        }
    }
}
