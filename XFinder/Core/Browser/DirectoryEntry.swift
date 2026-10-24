import Foundation

/// XF-T28 (2026-10-24) — one row of a directory listing, plus the pure rules that sort, hide and
/// filter a pane's contents. The reader (`DirectoryReader`, AppKit-adjacent) fills these from
/// `getattrlistbulk` (measured 97 ms / 100 000 entries vs. `FileManager` 813 ms — spec §1); this
/// file never touches the disk.
struct DirectoryEntry: Hashable, Sendable, Identifiable {
    enum Kind: UInt8, Sendable {
        case file, directory, symlink, other
    }

    var id: String { path }
    let name: String
    let path: String
    let kind: Kind
    let isPackage: Bool
    /// `UF_HIDDEN` or a name starting with "." — matches Finder, not `FileManager`'s `._*` leak (spec §1).
    let isHidden: Bool
    /// Logical size in bytes for a file; -1 for a directory (no "size" to add up without walking it).
    let size: Int64
    let modified: Date
    let created: Date
    let volumeID: Int32

    /// Lowercased extension, "" when the name has none (dotfiles like ".gitignore" count as none).
    var ext: String {
        let dot = name.lastIndex(of: ".")
        guard let dot, dot != name.startIndex else { return "" }
        let start = name.index(after: dot)
        guard start < name.endIndex else { return "" }
        return name[start...].lowercased()
    }

    /// Whether opening this entry means navigating into it, rather than launching it. A `.app` or
    /// `.pages` is a directory on disk but Finder (and this browser) treats it as a double-click target.
    var isFolderLike: Bool { kind == .directory && !isPackage }
}

enum BrowserViewMode: String, Codable, CaseIterable, Sendable {
    case icons, list, columns, gallery
}

enum SortKey: String, Codable, CaseIterable, Sendable {
    case name, modified, size, kind
}

struct SortOrder: Codable, Equatable, Sendable {
    var key: SortKey
    var ascending: Bool

    static let finderDefault = SortOrder(key: .name, ascending: true)
}

enum EntryRules {

    /// Normalized match key for a name: case- and diacritic-insensitive, with Vietnamese "đ"/"Đ"
    /// folded to "d" like the rest of the sidebar (`SidebarSearch.fold`) since a non-Vietnamese
    /// keyboard layout cannot type "đ" at all. Shared by `filter` and `TypeSelect` so both treat a
    /// name the same way; callers filtering a stable list many times over should cache this per entry.
    static func foldKey(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
    }

    /// Sort used by every pane's List/Icon/Column/Gallery view. Each key has its own tie-break so the
    /// order is always fully determined (never "equal" → stable-sort luck):
    /// - `.name`: `localizedStandardCompare` ("File 2" < "File 10"); equal names (case variants on a
    ///   case-insensitive volume) break by `path`.
    /// - `.size`: directories (logical size -1) sort before files when ascending, and among
    ///   directories the order is by name (there is no size to compare). Files compare by `size`,
    ///   ties by name.
    /// - `.kind`: by `kindName(entry)` — the already-localized type name the column shows ("Thư mục",
    ///   "Tài liệu PDF"), exactly how Finder sorts its Kind column, not by raw extension — compared
    ///   with `localizedStandardCompare`, ties by name.
    /// - `.modified`: by `modified`, ties by name.
    ///
    /// `foldersFirst` (the "Ưu tiên thư mục" view option) is applied as a key ABOVE all of the above:
    /// every `isFolderLike` entry sorts before every non-folder one, regardless of `order.key`.
    ///
    /// `ascending == false` reverses the PRIMARY key's order only; the secondary (name) tie-break
    /// stays ascending, matching Finder (descending-by-size still lists same-size files A→Z).
    static func sorted(
        _ entries: [DirectoryEntry], by order: SortOrder, foldersFirst: Bool,
        kindName: (DirectoryEntry) -> String
    ) -> [DirectoryEntry] {
        // Precompute kind names once; calling the closure inside the comparator would re-derive the
        // localized string O(n log n) times instead of O(n).
        let kindNames: [String: String]
        if order.key == .kind {
            var map: [String: String] = [:]
            map.reserveCapacity(entries.count)
            for entry in entries where map[entry.path] == nil {
                map[entry.path] = kindName(entry)
            }
            kindNames = map
        } else {
            kindNames = [:]
        }

        func namesAscending(_ a: DirectoryEntry, _ b: DirectoryEntry) -> Bool {
            let cmp = a.name.localizedStandardCompare(b.name)
            if cmp != .orderedSame { return cmp == .orderedAscending }
            return a.path < b.path
        }

        func primaryOrder(_ a: DirectoryEntry, _ b: DirectoryEntry) -> ComparisonResult {
            switch order.key {
            case .name:
                return a.name.localizedStandardCompare(b.name)
            case .modified:
                if a.modified == b.modified { return .orderedSame }
                return a.modified < b.modified ? .orderedAscending : .orderedDescending
            case .size:
                let aDir = a.size < 0
                let bDir = b.size < 0
                if aDir != bDir { return aDir ? .orderedAscending : .orderedDescending }
                if aDir && bDir { return .orderedSame }  // both directories: fall through to name
                if a.size == b.size { return .orderedSame }
                return a.size < b.size ? .orderedAscending : .orderedDescending
            case .kind:
                let ak = kindNames[a.path] ?? ""
                let bk = kindNames[b.path] ?? ""
                return ak.localizedStandardCompare(bk)
            }
        }

        return entries.sorted { a, b in
            if foldersFirst {
                let aFolder = a.isFolderLike
                let bFolder = b.isFolderLike
                if aFolder != bFolder { return aFolder }
            }
            let cmp = primaryOrder(a, b)
            if cmp != .orderedSame {
                let ascendingResult = cmp == .orderedAscending
                return order.ascending ? ascendingResult : !ascendingResult
            }
            return namesAscending(a, b)
        }
    }

    /// `⇧⌘.` toggle: dotfiles and `UF_HIDDEN` entries are simply absent when off, present when on —
    /// no separate "ghost" styling tier (that's a view concern, not this rule's).
    static func visible(_ entries: [DirectoryEntry], showHidden: Bool) -> [DirectoryEntry] {
        showHidden ? entries : entries.filter { !$0.isHidden }
    }

    /// In-memory filter for the current folder's listing (⌘F). Splits `query` on whitespace; an entry
    /// survives only if its folded name contains EVERY word (any order) — same contract as
    /// `SidebarSearch`. An empty/blank query returns `entries` unchanged without walking it.
    ///
    /// Budget: 100 000 entries in < 16 ms (-O, one keystroke's worth of work — spec §6). Measured:
    /// `foldKey` (Foundation `.folding` + two `replacingOccurrences`) alone costs ~250 ms / 100 000
    /// names — the two string-literal replacements dominate, not the Unicode folding. Almost every
    /// real filename is pure ASCII (no "đ", no accents), so each entry's name is lowercased with a
    /// byte-level ASCII fast path (~9 ms / 100 000 total, words included) and only the rare non-ASCII
    /// name pays for the correct-but-slow `foldKey`. Both paths agree on ASCII input (folding ASCII
    /// text is just lowercasing it), so this is not a second, divergent notion of "folded".
    static func filter(_ entries: [DirectoryEntry], query: String) -> [DirectoryEntry] {
        // Slow-but-always-correct path, shared by the few non-ASCII cases below.
        func foldedFilter() -> [DirectoryEntry] {
            let words = foldKey(query).split(whereSeparator: { $0.isWhitespace })
            guard !words.isEmpty else { return entries }
            return entries.filter { entry in
                let key = foldKey(entry.name)
                for word in words where !key.contains(word) { return false }
                return true
            }
        }
        guard let queryBytes = asciiLowercasedUTF8(query) else {
            // Non-ASCII query (e.g. a literal "đ"): fold it instead of refusing to match.
            return foldedFilter()
        }
        let words = splitOnASCIIWhitespace(queryBytes)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            guard let key = asciiLowercasedUTF8(entry.name) else {
                // Non-ASCII entry name (e.g. "café.txt"): compare correctly rather than silently
                // excluding it — re-fold just the query against just this one name.
                let foldedKey = foldKey(entry.name)
                let foldedWords = foldKey(query).split(whereSeparator: { $0.isWhitespace })
                for word in foldedWords where !foldedKey.contains(word) { return false }
                return true
            }
            for word in words where !containsASCIIBytes(key, word) { return false }
            return true
        }
    }

    /// `name`'s UTF-8 bytes with A–Z lowercased to a–z, or nil the moment a non-ASCII byte is seen
    /// (the caller then falls back to `foldKey`, which is correct for any script but far slower).
    private static func asciiLowercasedUTF8(_ name: String) -> [UInt8]? {
        var buf = [UInt8]()
        buf.reserveCapacity(name.utf8.count)
        for byte in name.utf8 {
            guard byte < 0x80 else { return nil }
            buf.append(byte >= 65 && byte <= 90 ? byte + 32 : byte)
        }
        return buf
    }

    /// Splits already-ASCII-lowercased bytes on ASCII whitespace (space/tab), dropping empty runs —
    /// the byte-level equivalent of `String.split(whereSeparator: \.isWhitespace)`.
    private static func splitOnASCIIWhitespace(_ bytes: [UInt8]) -> [[UInt8]] {
        var words: [[UInt8]] = []
        var current: [UInt8] = []
        for byte in bytes {
            if byte == 0x20 || byte == 0x09 {
                if !current.isEmpty {
                    words.append(current)
                    current = []
                }
            } else {
                current.append(byte)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// Plain substring search over raw bytes (both already ASCII-lowercased) — a hand-rolled
    /// `contains` because `String.contains` walks grapheme clusters, which this hot path doesn't need.
    private static func containsASCIIBytes(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        if needle.isEmpty { return true }
        if needle.count > haystack.count { return false }
        let limit = haystack.count - needle.count
        var i = 0
        while i <= limit {
            var j = 0
            while j < needle.count && haystack[i + j] == needle[j] { j += 1 }
            if j == needle.count { return true }
            i += 1
        }
        return false
    }

    /// Finder's "type to select" (gõ để chọn): keystrokes within `timeout` of each other accumulate
    /// into one prefix; a pause longer than `timeout` starts a fresh buffer with just the new keys.
    struct TypeSelect: Sendable, Equatable {
        static let timeout: TimeInterval = 1.0

        private(set) var buffer: String
        private(set) var last: Date?

        init() {
            buffer = ""
            last = nil
        }

        /// Appends `chars` to the buffer, or starts over with just `chars` if `timeout` has elapsed
        /// since the previous keystroke. Returns the buffer as it stands after this call.
        mutating func type(_ chars: String, at now: Date) -> String {
            if let last, now.timeIntervalSince(last) > Self.timeout {
                buffer = ""
            }
            buffer += chars
            last = now
            return buffer
        }

        /// Index of the first `names` entry whose folded form has `prefix` (folded) as a prefix; if
        /// none matches, the first entry that sorts after `prefix` (so typing "z" in a list with no
        /// "z" lands near where one would be); if still none (prefix sorts after everything), the
        /// last entry; nil only when `names` is empty.
        ///
        /// "Sorts after" is `localizedStandardCompare` — the SAME natural-order comparator
        /// `EntryRules.sorted(by: .name)` uses (spec: "theo thứ tự hiện có", i.e. the order the pane
        /// already shows). A plain `String >` would disagree with it: in a naturally-sorted list like
        /// ["file2", "file10", "file99"], "file10" < "file99" lexically treats the digit '1' as less
        /// than '9' at the same position, so a prefix like "file5" would wrongly skip past "file10"
        /// (which should be the landing spot) straight to "file99".
        static func match(prefix: String, in names: [String]) -> Int? {
            guard !names.isEmpty else { return nil }
            let key = foldKey(prefix)
            guard !key.isEmpty else { return nil }
            for (index, name) in names.enumerated() where foldKey(name).hasPrefix(key) {
                return index
            }
            for (index, name) in names.enumerated() where prefix.localizedStandardCompare(name) == .orderedAscending {
                return index
            }
            return names.count - 1
        }
    }
}
