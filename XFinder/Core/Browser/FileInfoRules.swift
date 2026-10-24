import Foundation

/// XF-T28 Wave 4 §A (`docs/specs/XF-T28-wave4.md`) — the pure rules behind ⌘I "Get Info": turning the facts the
/// controller reads off disk (`FileInfoFacts`) into the display rows the window shows, the owner/group/everyone
/// permission model, and the multi-selection summary. Never touches disk itself — `GetInfoWindow.swift` (AppKit)
/// gathers `FileInfoFacts` via `stat`/`getattrlist`/`FileManager` and calls into this file to decide what to show.
struct FileInfoFacts: Equatable, Sendable {
    let name: String
    let path: String
    let isFolder: Bool
    let isPackage: Bool
    /// Sum of file sizes (bytes). For a plain file this is its own size; for a folder it is filled in later by
    /// `FileWalk.totalSize` run in the background — nil until that finishes.
    let logicalSize: Int64?
    /// Size on disk (allocated blocks × block size); like `logicalSize`, nil for a folder until walked.
    let physicalSize: Int64?
    let created: Date
    let modified: Date
    let accessed: Date?
    /// Lower 9 bits of `st_mode` (rwxrwxrwx), as returned by `stat`.
    let posixMode: UInt16
    let ownerName: String
    let groupName: String
    let ownerIsMe: Bool
    /// `UF_IMMUTABLE` (Finder's "Locked" checkbox).
    let locked: Bool
    let hidesExtension: Bool
    let tags: [String]
    /// Localized type name, e.g. "Tài liệu PDF", "Thư mục" — the same string the browser's Kind column shows
    /// (`FileIconCache.kindName`), passed in rather than recomputed here since that lookup needs UTType/AppKit.
    let kind: String

    init(name: String, path: String, isFolder: Bool, isPackage: Bool, logicalSize: Int64?, physicalSize: Int64?,
         created: Date, modified: Date, accessed: Date?, posixMode: UInt16, ownerName: String, groupName: String,
         ownerIsMe: Bool, locked: Bool, hidesExtension: Bool, tags: [String], kind: String) {
        self.name = name
        self.path = path
        self.isFolder = isFolder
        self.isPackage = isPackage
        self.logicalSize = logicalSize
        self.physicalSize = physicalSize
        self.created = created
        self.modified = modified
        self.accessed = accessed
        self.posixMode = posixMode
        self.ownerName = ownerName
        self.groupName = groupName
        self.ownerIsMe = ownerIsMe
        self.locked = locked
        self.hidesExtension = hidesExtension
        self.tags = tags
        self.kind = kind
    }
}

/// One permission level a POSIX triad can express — Finder's "Đọc & ghi" / "Chỉ đọc" / "Chỉ ghi" / "Không truy cập"
/// popup for owner/group/everyone.
enum Access: String, Sendable, CaseIterable {
    case readWrite, readOnly, writeOnly, none

    var titleKey: String {
        switch self {
        case .readWrite: return "Đọc & ghi"
        case .readOnly: return "Chỉ đọc"
        case .writeOnly: return "Chỉ ghi"
        case .none: return "Không truy cập"
        }
    }
}

/// Who a permission triad in `posixMode` belongs to — owner (bits 8-6), group (bits 5-3) or everyone (bits 2-0).
enum PermissionWho: Sendable, CaseIterable {
    case owner, group, everyone

    /// Bit shift of this triad's `r` bit within `st_mode`'s low 9 bits (owner 6, group 3, everyone 0).
    fileprivate var shift: UInt16 {
        switch self {
        case .owner: return 6
        case .group: return 3
        case .everyone: return 0
        }
    }
}

enum FileInfoRules {

    // MARK: - Permissions

    /// Reads the `who` triad out of `mode` and reports it as one `Access` case. `rwx` reduces to the `rw` pair Finder
    /// shows (execute isn't surfaced in the popup); `r--`/`rw-` → readWrite needs both r and w, so: rw or rwx →
    /// readWrite, r-- or r-x → readOnly, -w- or -wx → writeOnly, --- or --x → none (a lone execute bit grants no
    /// readable/writable access, so it still reports `.none`).
    static func access(mode: UInt16, who: PermissionWho) -> Access {
        let shift = who.shift
        let r = (mode >> (shift + 2)) & 1 == 1
        let w = (mode >> (shift + 1)) & 1 == 1
        switch (r, w) {
        case (true, true): return .readWrite
        case (true, false): return .readOnly
        case (false, true): return .writeOnly
        case (false, false): return .none
        }
    }

    /// Applies `setting` to `who`'s triad in `mode`, returning the new mode. Execute bits are left exactly as they
    /// were (Finder's popup only ever changes r/w, never x) except for `.none`, which clears x too — matching
    /// Finder, where "No Access" really means no access, not "executable but unreadable".
    static func mode(setting access: Access, for who: PermissionWho, in mode: UInt16) -> UInt16 {
        let shift = who.shift
        let rBit: UInt16 = 1 << (shift + 2)
        let wBit: UInt16 = 1 << (shift + 1)
        let xBit: UInt16 = 1 << shift
        var result = mode
        switch access {
        case .readWrite:
            result |= rBit; result |= wBit
        case .readOnly:
            result |= rBit; result &= ~wBit
        case .writeOnly:
            result &= ~rBit; result |= wBit
        case .none:
            result &= ~rBit; result &= ~wBit; result &= ~xBit
        }
        return result
    }

    // MARK: - Rows (Chung · Thêm thông tin · Tên & đuôi · Quyền)

    /// One labelled line in a Get Info section. `value` is already the final display string (dates/sizes formatted
    /// by the caller, which has `Locale`/`DateFormatter` — both AppKit-adjacent concerns this pure file avoids).
    struct Row: Equatable, Sendable {
        let labelKey: String
        let value: String
    }

    /// "Chung": kind, size (+ size on disk once known), created/modified/(accessed), where (parent folder), locked.
    /// `sizeText`/`dateText` are supplied by the caller (formatting needs `ByteCountFormatter`/`DateFormatter`,
    /// neither available to a Foundation-only file); `nil` size renders "Đang tính…" (folder size not walked yet).
    static func generalRows(_ facts: FileInfoFacts, sizeText: (Int64?) -> String, dateText: (Date) -> String) -> [Row] {
        let parent = (facts.path as NSString).deletingLastPathComponent
        var rows: [Row] = [
            Row(labelKey: "Loại:", value: facts.kind),
            Row(labelKey: "Kích thước:", value: sizeText(facts.logicalSize)),
        ]
        if let physical = facts.physicalSize {
            rows.append(Row(labelKey: "Dung lượng trên đĩa:", value: sizeText(physical)))
        }
        rows.append(Row(labelKey: "Nơi lưu:", value: parent))
        rows.append(Row(labelKey: "Ngày tạo:", value: dateText(facts.created)))
        rows.append(Row(labelKey: "Ngày sửa đổi:", value: dateText(facts.modified)))
        if let accessed = facts.accessed {
            rows.append(Row(labelKey: "Ngày mở gần nhất:", value: dateText(accessed)))
        }
        rows.append(Row(labelKey: "Khoá:", value: facts.locked ? "Có" : "Không"))
        return rows
    }

    /// "Thêm thông tin": caller-supplied extra facts the pure file has no way to know (pixel size, PDF page count,
    /// media duration) — this just formats whatever rows the controller already resolved, so a window with none of
    /// those (a plain text file) renders an empty section instead of three "Đang tính…" placeholders.
    static func additionalRows(pixelSize: (width: Int, height: Int)?, pdfPageCount: Int?,
                               mediaDuration: TimeInterval?, durationText: (TimeInterval) -> String) -> [Row] {
        var rows: [Row] = []
        if let pixelSize {
            rows.append(Row(labelKey: "Kích thước ảnh:", value: "\(pixelSize.width) × \(pixelSize.height)"))
        }
        if let pdfPageCount {
            rows.append(Row(labelKey: "Số trang:", value: "\(pdfPageCount)"))
        }
        if let mediaDuration {
            rows.append(Row(labelKey: "Thời lượng:", value: durationText(mediaDuration)))
        }
        return rows
    }

    // MARK: - Rename ("Tên & đuôi")

    /// Reused by `BrowserWindowModel.commitRename`'s own inline check (spec: "tái dùng luật đổi tên Finder"): a name
    /// is rejected only when it is empty after trimming, or contains "/" or ":" — Finder itself maps ":" to "/" on
    /// screen, so typing either is refused rather than silently rewritten. Returns the L10n key for the refusal
    /// reason, or nil when `name` is valid.
    static func renameRejectionKey(for name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Tên không được để trống." }
        if trimmed.contains("/") || trimmed.contains(":") {
            return "Tên không được chứa dấu hai chấm hoặc dấu gạch chéo."   // no quote characters inside an L10n key (rule 8)
        }
        return nil
    }

    /// Splits a file name into the part the rename field should select (stem) and the extension to leave alone —
    /// Get Info and the in-pane inline rename both select everything but the extension, like Finder's Return/⌘I.
    /// A folder (no extension concept here) or a dotfile ("`.zshrc`", nothing before the first dot) selects the
    /// whole name.
    static func renameSelection(for name: String, isFolder: Bool) -> (stem: String, ext: String) {
        guard !isFolder else { return (name, "") }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        let start = name.index(after: dot)
        guard start < name.endIndex else { return (name, "") }
        return (String(name[name.startIndex..<dot]), String(name[start...]))
    }

    // MARK: - Multi-selection summary

    struct Summary: Equatable, Sendable {
        let count: Int
        /// Sum of every item's logical size that is already known; nil items (folders still being walked) simply
        /// don't contribute yet — `isComplete` says whether the sum is final.
        let totalLogicalSize: Int64
        let isComplete: Bool
        /// The shared kind name when every item has the same one, or the L10n key "Nhiều loại" otherwise.
        let kindSummary: String
    }

    /// Builds the summary row set for a multi-item Get Info window: total size (so far — folders may still be
    /// walking) and a shared kind name, or "Nhiều loại" the moment two items disagree. `kinds` and `sizes` are
    /// parallel to the selection; a `nil` size means "not known yet" (a folder whose walk hasn't finished).
    static func summary(kinds: [String], sizes: [Int64?]) -> Summary {
        let total = sizes.reduce(into: Int64(0)) { $0 += $1 ?? 0 }
        let complete = sizes.allSatisfy { $0 != nil }
        let distinctKinds = Set(kinds)
        let kindSummary = distinctKinds.count == 1 ? (distinctKinds.first ?? "") : "Nhiều loại"
        return Summary(count: kinds.count, totalLogicalSize: total, isComplete: complete, kindSummary: kindSummary)
    }
}
