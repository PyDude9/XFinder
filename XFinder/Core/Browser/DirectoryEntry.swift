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
    /// The name folded once (case, diacritics, "đ" → "d") as UTF-8 bytes — what filter, sort and type-select compare.
    /// Measured 2026-10-24 (-O, 100 000 entries, two thirds Vietnamese names): folding inside every filter keystroke cost
    /// 363–440 ms and `localizedStandardCompare` sorting 735 ms; on this precomputed key: filter 1 ms, sort ~60 ms.
    let nameKey: [UInt8]
    /// XF-T30 W2 — Date Added (`ATTR_CMN_ADDEDTIME`), Date Last Opened (Spotlight `kMDItemLastUsedDate`) and Finder tags.
    /// nil = not read yet (filled lazily by `FileMetadataCache` / the reader), never "none".
    var added: Date? = nil
    var lastOpened: Date? = nil
    var tags: [String]? = nil
    /// The file's own "hide extension" flag (Finder flags bit 0x0010 in `ATTR_CMN_FNDRINFO` — measured 2026-10-25:
    /// `URLResourceValues.hasHiddenExtension = true` sets exactly that bit, the extended flags stay 0).
    var hidesExtension: Bool = false
    /// XF-T30 W5a — the real on-disk file id (`ATTR_CMN_FILEID`, a `u_int64_t`), read by `DirectoryReader.list`
    /// in the same `getattrlistbulk` pass as everything else (contract W5a "real inodes via ATTR_CMN_FILEID").
    /// nil only for a `DirectoryEntry` built without going through the reader (tests, `VirtualLocations`,
    /// `BrowserWindowModel` synthetic rows) — never a sentinel like 0, which IS a valid file id on some filesystems.
    var inode: UInt64? = nil

    init(name: String, path: String, kind: Kind, isPackage: Bool, isHidden: Bool, size: Int64, modified: Date,
         created: Date, volumeID: Int32) {
        self.name = name
        self.path = path
        self.kind = kind
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.size = size
        self.modified = modified
        self.created = created
        self.volumeID = volumeID
        self.nameKey = EntryRules.foldBytes(name)
    }

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
    /// XF-T30 W2 — Sort By (FileOctopus: Name, Kind, Date Added, Date Modified, Date Created, Date Last Opened, Size).
    case created, added, lastOpened
}

struct SortOrder: Codable, Equatable, Sendable {
    var key: SortKey
    var ascending: Bool

    static let finderDefault = SortOrder(key: .name, ascending: true)
}

enum EntryRules {

    /// Finder's rule for a shown name: with "Show all filename extensions" off, a FILE (or package) whose own
    /// hide-extension flag is set shows without its extension; folders and names without an extension never change.
    static func displayName(_ entry: DirectoryEntry, showAllExtensions: Bool) -> String {
        guard !showAllExtensions, entry.hidesExtension, entry.kind != .directory || entry.isPackage else { return entry.name }
        let ext: String = (entry.name as NSString).pathExtension
        guard !ext.isEmpty else { return entry.name }
        let base: String = (entry.name as NSString).deletingPathExtension
        return base.isEmpty ? entry.name : base
    }

    /// Normalized match key for a name: case- and diacritic-insensitive, with Vietnamese "đ"/"Đ"
    /// folded to "d" like the rest of the sidebar (`SidebarSearch.fold`) since a non-Vietnamese
    /// keyboard layout cannot type "đ" at all. Shared by `filter` and `TypeSelect` so both treat a
    /// name the same way; callers filtering a stable list many times over should cache this per entry.
    static func foldKey(_ name: String) -> String {
        String(decoding: foldBytes(name), as: UTF8.self)
    }

    /// `foldKey` as UTF-8 bytes, fast: ASCII is lowercased byte by byte; Latin-1, Latin Extended-A/B and Latin Extended
    /// Additional (every Vietnamese letter) come from `foldTable`, each scalar folded by Foundation ONCE; anything else
    /// (CJK, emoji…) keeps its own lowercase bytes. Same result as Foundation's diacritic+case folding for those ranges.
    static func foldBytes(_ name: String) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(name.utf8.count)
        var ascii = true
        for b in name.utf8 {
            if b >= 0x80 { ascii = false; break }
            out.append(b >= 65 && b <= 90 ? b + 32 : b)
        }
        if ascii { return out }
        out.removeAll(keepingCapacity: true)
        for scalar in name.unicodeScalars {
            let v = scalar.value
            if v < 0x80 {
                let b = UInt8(v)
                out.append(b >= 65 && b <= 90 ? b + 32 : b)
            } else if let folded = foldTable[v] {
                out.append(contentsOf: folded)
            } else {
                out.append(contentsOf: String(scalar).lowercased().utf8)
            }
        }
        return out
    }

    /// U+0080–U+024F and U+1E00–U+1EFF folded once by Foundation (case + diacritics) plus "đ"/"Đ" → "d", which Foundation
    /// leaves alone (a base letter, not a combining mark).
    private static let foldTable: [UInt32: [UInt8]] = {
        var table: [UInt32: [UInt8]] = [:]
        for range in [0x80...0x24F, 0x1E00...0x1EFF] {
            for v in range {
                guard let scalar = Unicode.Scalar(UInt32(v)) else { continue }
                let folded = String(scalar).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                table[UInt32(v)] = Array(folded.utf8)
            }
        }
        table[0x0110] = Array("d".utf8)   // Đ
        table[0x0111] = Array("d".utf8)   // đ
        return table
    }()

    /// Natural ("File 2" < "File 10") three-way compare of two folded keys: digit runs compare by value (shorter run of
    /// significant digits is smaller), everything else byte by byte; digits sort before letters, as in Finder.
    static func naturalCompare(_ a: [UInt8], _ b: [UInt8]) -> Int {
        var i = 0, j = 0
        let na = a.count, nb = b.count
        while i < na && j < nb {
            let ca = a[i], cb = b[j]
            let da = ca >= 0x30 && ca <= 0x39, db = cb >= 0x30 && cb <= 0x39
            if da && db {
                var si = i; while si < na && a[si] == 0x30 { si += 1 }
                var sj = j; while sj < nb && b[sj] == 0x30 { sj += 1 }
                var ei = si; while ei < na && a[ei] >= 0x30 && a[ei] <= 0x39 { ei += 1 }
                var ej = sj; while ej < nb && b[ej] >= 0x30 && b[ej] <= 0x39 { ej += 1 }
                let la = ei - si, lb = ej - sj
                if la != lb { return la < lb ? -1 : 1 }
                var k = 0
                while k < la {
                    if a[si + k] != b[sj + k] { return a[si + k] < b[sj + k] ? -1 : 1 }
                    k += 1
                }
                i = ei; j = ej
                continue
            }
            if ca != cb { return ca < cb ? -1 : 1 }
            i += 1; j += 1
        }
        if na - i == nb - j { return 0 }
        return na - i < nb - j ? -1 : 1
    }

    /// Sort used by every pane's List/Icon/Column/Gallery view. Each key has its own tie-break so the
    /// order is always fully determined (never "equal" → stable-sort luck):
    /// - `.name`: `naturalCompare` on the folded `nameKey` ("File 2" < "File 10", case- and accent-insensitive like
    ///   Finder's primary collation); equal keys break by `path`.
    /// - `.size`: directories (logical size -1) sort before files when ascending, and among
    ///   directories the order is by name (there is no size to compare). Files compare by `size`,
    ///   ties by name.
    /// - `.kind`: by `kindName(entry)` — the already-localized type name the column shows ("Thư mục",
    ///   "Tài liệu PDF"), exactly how Finder sorts its Kind column, not by raw extension — folded once per distinct
    ///   kind and compared with `naturalCompare`, ties by name.
    /// - `.modified`: by `modified`, ties by name.
    ///
    /// `foldersFirst` (the "Ưu tiên thư mục" view option, "Keep folders on top") is applied as a key ABOVE all of the
    /// above, but ONLY when `order.key == .name` (FileOctopus R18 / Finder: "In windows when sorting by name") — sorting
    /// by kind, size or any date already groups folders with other same-key entries in a way the user chose, and
    /// `foldersFirst` does not override that for any other key.
    ///
    /// `ascending == false` reverses the PRIMARY key's order only; the secondary (name) tie-break
    /// stays ascending, matching Finder (descending-by-size still lists same-size files A→Z).
    static func sorted(
        _ entries: [DirectoryEntry], by order: SortOrder, foldersFirst: Bool,
        kindName: (DirectoryEntry) -> String
    ) -> [DirectoryEntry] {
        // Everything the comparator reads is pulled out first and an array of indices is sorted; the folded names (and
        // kind names) live in ONE contiguous byte buffer read through a pointer. Measured 2026-10-24, 100 000 entries:
        // comparing `DirectoryEntry` values moved whole structs per comparison (145 ms by name), and even `[[UInt8]]`
        // paid a retain/release per access (137 ms); the flat buffer is what makes this cheap.
        let n = entries.count
        var names = FlatKeys(capacity: n)
        var folders = [Bool](); folders.reserveCapacity(n)
        for e in entries { names.append(e.nameKey); folders.append(e.isFolderLike) }
        let paths = entries.map(\.path)
        var kinds = FlatKeys(capacity: order.key == .kind ? n : 0)
        var dates: [Date?] = []
        var sizes: [Int64] = []
        switch order.key {
        case .kind:
            var folded: [String: [UInt8]] = [:]
            for e in entries {
                let k = kindName(e)
                if let f = folded[k] { kinds.append(f) } else { let f = foldBytes(k); folded[k] = f; kinds.append(f) }
            }
        case .modified: dates = entries.map { $0.modified as Date? }
        case .created: dates = entries.map { $0.created as Date? }
        case .added: dates = entries.map(\.added)
        case .lastOpened: dates = entries.map(\.lastOpened)
        case .size: sizes = entries.map(\.size)
        case .name: break
        }

        var indices = Array(0..<n)
        names.bytes.withUnsafeBufferPointer { nameBytes in
            kinds.bytes.withUnsafeBufferPointer { kindBytes in
                func nameCompare(_ x: Int, _ y: Int) -> Int {
                    naturalCompare(nameBytes, names.starts[x], names.starts[x + 1], names.starts[y], names.starts[y + 1])
                }
                // nil dates (Date Added / Date Last Opened not yet read) always sort LAST, in both ascending and
                // descending order — nil-ness is handled in the `indices.sort` closure below, BEFORE the ascending
                // flip, so it is never reversed by it; `primary` only compares two entries that both have a date.
                func primary(_ x: Int, _ y: Int) -> Int {
                    switch order.key {
                    case .name:
                        return nameCompare(x, y)
                    case .modified, .created, .added, .lastOpened:
                        guard let dx = dates[x], let dy = dates[y] else { return 0 }   // nil handled before the ascending flip
                        return dx == dy ? 0 : (dx < dy ? -1 : 1)
                    case .size:
                        let xDir = sizes[x] < 0, yDir = sizes[y] < 0
                        if xDir != yDir { return xDir ? -1 : 1 }
                        if xDir { return 0 }                         // both directories: fall through to name
                        return sizes[x] == sizes[y] ? 0 : (sizes[x] < sizes[y] ? -1 : 1)
                    case .kind:
                        return naturalCompare(kindBytes, kinds.starts[x], kinds.starts[x + 1], kinds.starts[y], kinds.starts[y + 1])
                    }
                }
                let isDateKey = [SortKey.modified, .created, .added, .lastOpened].contains(order.key)
                indices.sort { x, y in
                    if foldersFirst, order.key == .name, folders[x] != folders[y] { return folders[x] }
                    if isDateKey {
                        switch (dates[x], dates[y]) {
                        case (nil, nil): break                      // fall through to the name tie-break below
                        case (nil, _): return false                 // x has no date: x is never "less than" y
                        case (_, nil): return true                  // y has no date: x (which has one) sorts first
                        default: break                              // both present: compare normally below
                        }
                    }
                    let c = primary(x, y)
                    if c != 0 { return order.ascending ? c < 0 : c > 0 }
                    if order.key != .name {
                        let t = nameCompare(x, y)
                        if t != 0 { return t < 0 }
                    }
                    return paths[x] < paths[y]
                }
            }
        }
        return indices.map { entries[$0] }
    }

    /// Keys packed end to end; key `i` is `bytes[starts[i] ..< starts[i + 1]]`.
    private struct FlatKeys {
        var bytes: [UInt8] = []
        var starts: [Int] = [0]
        init(capacity: Int) {
            bytes.reserveCapacity(capacity * 24)
            starts.reserveCapacity(capacity + 1)
        }
        mutating func append(_ key: [UInt8]) {
            bytes.append(contentsOf: key)
            starts.append(bytes.count)
        }
    }

    /// `naturalCompare` on two ranges of one buffer (the sort's hot path — no array per key).
    private static func naturalCompare(_ buf: UnsafeBufferPointer<UInt8>, _ a0: Int, _ a1: Int, _ b0: Int, _ b1: Int) -> Int {
        var i = a0, j = b0
        while i < a1 && j < b1 {
            let ca = buf[i], cb = buf[j]
            let da = ca >= 0x30 && ca <= 0x39, db = cb >= 0x30 && cb <= 0x39
            if da && db {
                var si = i; while si < a1 && buf[si] == 0x30 { si += 1 }
                var sj = j; while sj < b1 && buf[sj] == 0x30 { sj += 1 }
                var ei = si; while ei < a1 && buf[ei] >= 0x30 && buf[ei] <= 0x39 { ei += 1 }
                var ej = sj; while ej < b1 && buf[ej] >= 0x30 && buf[ej] <= 0x39 { ej += 1 }
                let la = ei - si, lb = ej - sj
                if la != lb { return la < lb ? -1 : 1 }
                var k = 0
                while k < la {
                    if buf[si + k] != buf[sj + k] { return buf[si + k] < buf[sj + k] ? -1 : 1 }
                    k += 1
                }
                i = ei; j = ej
                continue
            }
            if ca != cb { return ca < cb ? -1 : 1 }
            i += 1; j += 1
        }
        if a1 - i == b1 - j { return 0 }
        return a1 - i < b1 - j ? -1 : 1
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
    /// Budget: 100 000 entries in < 16 ms (-O, one keystroke — spec §6). The name was folded once when the entry was
    /// made (`nameKey`); a keystroke only folds the query and runs a byte search per entry (measured 1 ms / 100 000).
    static func filter(_ entries: [DirectoryEntry], query: String) -> [DirectoryEntry] {
        let words = splitOnASCIIWhitespace(foldBytes(query))
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            for word in words where !containsASCIIBytes(entry.nameKey, word) { return false }
            return true
        }
    }

    /// Splits folded bytes on ASCII whitespace (space/tab), dropping empty runs —
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

    /// Plain substring search over folded bytes — a hand-rolled
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
        /// "Sorts after" is `naturalCompare` on folded keys — the SAME comparator `EntryRules.sorted(by: .name)` uses
        /// (spec: "theo thứ tự hiện có", i.e. the order the pane already shows). A plain `String >` would disagree with it: in a naturally-sorted list like
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
            let prefixKey = foldBytes(prefix)
            for (index, name) in names.enumerated() where naturalCompare(prefixKey, foldBytes(name)) < 0 {
                return index
            }
            return names.count - 1
        }
    }
}
