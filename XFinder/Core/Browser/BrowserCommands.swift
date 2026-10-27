import Foundation

/// A key combination inside a browser window. `key` is either a literal lowercase character ("n", "1", "[",
/// ".", "=") or one of the named keys `display(_:)`'s `keyGlyphs` table lists — kept as a `String` (not a virtual
/// key code) because the view layer already normalizes `NSEvent.charactersIgnoringModifiers` to these same names
/// before calling in.
struct KeyChord: Hashable, Codable, Sendable {
    var key: String
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    init(_ key: String, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }
}

enum BrowserCommand: String, CaseIterable, Sendable {
    case newWindow, newFolder, open, openEnclosing, back, forward, rename, duplicate, moveToTrash, quickLook
    case copy, paste, pasteMove, copyPath, toggleHidden, selectAll, undo
    case viewIcons, viewList, viewColumns, viewGallery
    case filter, find, editLocation, goToFolder, quickOpen, commandPalette
    case splitRight, splitLeft, splitDown, splitUp, closePane, equalizePanes, zoomPane, nextPane, previousPane
    case presetSingle, presetSideBySide, presetStacked, presetGrid
    case copyToOtherPane, moveToOtherPane, addToShelf, toggleShelf, operations
    case batchRename, compress, saveWorkspace, openWorkspace, downloadNow, removeDownload, showInFinder, closeWindow
    case getInfo   // XF-T28 Wave 4: ⌘I, like Finder
    // XF-T30 W1 — pane tabs, window tabs, directional focus, keyboard resize, bars (contract XF-T30-w1-contract.md)
    case newWindowTab, newPaneTab, nextPaneTab, previousPaneTab, closePaneTab
    case moveTabToNextPane, moveTabToNewPaneRight, moveTabToNewPaneBelow, swapWithNextPane, moveTabToWindow
    case paneLeft, paneRight, paneAbove, paneBelow
    case makePaneWider, makePaneNarrower, makePaneTaller, makePaneShorter
    case toggleLocationBar, togglePathBar, toggleStatusBar, toggleToolbar, customizeToolbar, toggleSidebar
    case openInNewTab, openInNewWindow, useGroups
    // XF-T30 W2 views · W3 sidebar/Go · W4 settings · W6 file operations · W7 preview (stubs; owners in each contract)
    case makeAlias, showOriginal, addToSidebar, share, showViewOptions
    case goRecents, goDocuments, goDesktop, goDownloads, goHome, goAirDrop, goNetwork, goICloud, goApplications
    case goUtilities, goComputer, connectToServer, eject, clearRecentFolders
    case openBrowserSettings, showWelcome
    case newFolderWithSelection, cut, redo, clearOperationHistory
    case togglePreview, slideshow
}

/// XF-T28 — the file browser's ONE keyboard table (spec §2.3): every chord a browser window owns goes through here,
/// feeding both `performKeyEquivalent` and the command palette, instead of being scattered across view controllers.
/// Pure/Foundation-only so the "one chord, one command" and "every required chord present" rules are testable without
/// a window on screen (contract `docs/specs/XF-T28-contract.md`).
enum BrowserCommands {

    /// Fixed table (spec §2.3): every chord a `BrowserCommand` fires on. `open` has a SECOND chord (⌘↓) handled
    /// separately by `command(for:)` below, since a dictionary keyed by command can only hold the primary one that
    /// `chord(for:)` reports back to the UI (toolbar/menu labels show one chord per command, never two).
    private static let table: [BrowserCommand: KeyChord] = [
        .newWindow: KeyChord("n", command: true),
        .newFolder: KeyChord("n", command: true, shift: true),
        .open: KeyChord("o", command: true),
        .openEnclosing: KeyChord("up", command: true),
        .back: KeyChord("[", command: true),
        .forward: KeyChord("]", command: true),
        .rename: KeyChord("return"),
        .duplicate: KeyChord("d", command: true),
        .moveToTrash: KeyChord("delete", command: true),
        .quickLook: KeyChord("y", command: true),
        .copy: KeyChord("c", command: true),
        .paste: KeyChord("v", command: true),
        .pasteMove: KeyChord("v", command: true, option: true),
        .copyPath: KeyChord("c", command: true, option: true),
        .toggleHidden: KeyChord(".", command: true, shift: true),
        .selectAll: KeyChord("a", command: true),
        .undo: KeyChord("z", command: true),
        .viewIcons: KeyChord("1", command: true),
        .viewList: KeyChord("2", command: true),
        .viewColumns: KeyChord("3", command: true),
        .viewGallery: KeyChord("4", command: true),
        // filter: no chord (Q-T30-2 — ⌘F used to be split between filter and find; now ⌘F is Find alone, like
        // FileOctopus, and "filter current folder" is a palette/menu-only command).
        .find: KeyChord("f", command: true),
        .editLocation: KeyChord("l", command: true, control: true),
        .goToFolder: KeyChord("g", command: true, shift: true),
        .quickOpen: KeyChord("k", command: true),
        .commandPalette: KeyChord("p", command: true, shift: true, control: true),
        .splitRight: KeyChord("right", command: true, option: true, control: true),
        .splitLeft: KeyChord("left", command: true, option: true, control: true),
        .splitDown: KeyChord("down", command: true, option: true, control: true),
        .splitUp: KeyChord("up", command: true, option: true, control: true),
        .closePane: KeyChord("w", command: true, option: true, control: true),
        .equalizePanes: KeyChord("=", command: true, option: true, control: true),
        .zoomPane: KeyChord("return", command: true, shift: true),
        .nextPane: KeyChord("]", command: true, control: true),
        .previousPane: KeyChord("[", command: true, control: true),
        .copyToOtherPane: KeyChord("c", command: true, shift: true, control: true),
        .moveToOtherPane: KeyChord("m", command: true, shift: true, control: true),
        .addToShelf: KeyChord("s", command: true, control: true),
        .toggleShelf: KeyChord("b", command: true, option: true),
        .operations: KeyChord("o", command: true, option: true),
        .batchRename: KeyChord("r", command: true, control: true),
        .getInfo: KeyChord("i", command: true),
        .closeWindow: KeyChord("w", command: true),
        // XF-T30 W1 — pane tabs, window tabs, directional focus, keyboard resize, bars (contract XF-T30-w1-contract.md §2).
        .newWindowTab: KeyChord("t", command: true),
        .newPaneTab: KeyChord("t", command: true, option: true, control: true),
        .nextPaneTab: KeyChord("]", command: true, option: true),
        .previousPaneTab: KeyChord("[", command: true, option: true),
        .moveTabToNewPaneRight: KeyChord("right", command: true, shift: true, option: true),
        .moveTabToNewPaneBelow: KeyChord("down", command: true, shift: true, option: true),
        .paneLeft: KeyChord("left", command: true, shift: true, control: true),
        .paneRight: KeyChord("right", command: true, shift: true, control: true),
        .paneAbove: KeyChord("up", command: true, shift: true, control: true),
        .paneBelow: KeyChord("down", command: true, shift: true, control: true),
        .togglePathBar: KeyChord("p", command: true, option: true),
        .toggleStatusBar: KeyChord("/", command: true),
        .toggleToolbar: KeyChord("t", command: true, option: true),
        .toggleSidebar: KeyChord("s", command: true, option: true),
        .useGroups: KeyChord("0", command: true, control: true),
        // XF-T30 W2–W7 (FileOctopus Finder profile, spec-settings-keyboard §6)
        .makeAlias: KeyChord("a", command: true, control: true),
        .showOriginal: KeyChord("r", command: true),
        .addToSidebar: KeyChord("t", command: true, control: true),
        .showViewOptions: KeyChord("j", command: true),
        .goRecents: KeyChord("f", command: true, shift: true),
        .goDocuments: KeyChord("o", command: true, shift: true),
        .goDesktop: KeyChord("d", command: true, shift: true),
        .goDownloads: KeyChord("l", command: true, option: true),
        .goHome: KeyChord("h", command: true, shift: true),
        .goAirDrop: KeyChord("r", command: true, shift: true),
        .goNetwork: KeyChord("k", command: true, shift: true),
        .goICloud: KeyChord("i", command: true, shift: true),
        .goApplications: KeyChord("a", command: true, shift: true),
        .goUtilities: KeyChord("u", command: true, shift: true),
        .goComputer: KeyChord("c", command: true, shift: true),
        .eject: KeyChord("e", command: true),
        .openBrowserSettings: KeyChord(",", command: true),
        .newFolderWithSelection: KeyChord("n", command: true, control: true),
        .cut: KeyChord("x", command: true),
        .redo: KeyChord("z", command: true, shift: true),
        .togglePreview: KeyChord("p", command: true, shift: true),
        .slideshow: KeyChord("y", command: true, option: true),
        // No chord (spec §2.3 "không phím" + contract §2): presetSingle, presetSideBySide, presetStacked, presetGrid,
        // compress, saveWorkspace, openWorkspace, downloadNow, removeDownload, showInFinder, filter, closePaneTab,
        // moveTabToNextPane, swapWithNextPane, moveTabToWindow, makePaneWider/Narrower/Taller/Shorter,
        // toggleLocationBar, customizeToolbar, openInNewTab, openInNewWindow — menu/palette only.
    ]

    /// `open`'s secondary chord (⌘↓, Finder's own "open" convention) — recognized by `command(for:)` but not
    /// returned by `chord(for:)`, which only ever reports the one primary chord a toolbar/menu label shows.
    private static let openSecondary = KeyChord("down", command: true)

    static func chord(for command: BrowserCommand) -> KeyChord? {
        table[command]
    }

    /// The command a chord fires, or nil if unbound. At most one command per chord — `BrowserCommandsTests`
    /// asserts the fixed table never maps two commands to the same `KeyChord` (a dropped guard here would silently
    /// let a later command shadow an earlier one picked first by dictionary iteration order, which is undefined).
    /// Space is deliberately absent from this table: spec §2.3 reserves it for Quick Look only while the view is
    /// NOT in a text-entry field, a decision the view makes (it owns first-responder state), not this pure file.
    static func command(for chord: KeyChord) -> BrowserCommand? {
        if chord == KeyChord("p", command: true, control: true) { return .quickOpen }
        if chord == openSecondary { return .open }
        return table.first { $0.value == chord }?.key
    }

    /// L10n store key for a command's title — the Vietnamese sentence itself (CLAUDE.md §3.2: model returns the
    /// key, the view calls `L10n.t()`).
    static func titleKey(_ command: BrowserCommand) -> String {
        switch command {
        case .newWindow: return "Cửa sổ mới"
        case .newFolder: return "Thư mục mới"
        case .open: return "Mở"
        case .openEnclosing: return "Lên thư mục cha"
        case .back: return "Lùi lại"
        case .forward: return "Tiến tới"
        case .rename: return "Đổi tên"
        case .duplicate: return "Nhân bản"
        case .moveToTrash: return "Chuyển vào Thùng rác"
        case .quickLook: return "Xem nhanh"
        case .copy: return "Sao chép"
        case .paste: return "Dán"
        case .pasteMove: return "Dán và di chuyển"
        case .copyPath: return "Sao chép đường dẫn"
        case .toggleHidden: return "Hiện hoặc ẩn tệp ẩn"
        case .selectAll: return "Chọn tất cả"
        case .undo: return "Hoàn tác"
        case .viewIcons: return "Xem dạng biểu tượng"
        case .viewList: return "Xem dạng danh sách"
        case .viewColumns: return "Xem dạng cột"
        case .viewGallery: return "Xem dạng gallery"
        case .filter: return "Lọc thư mục hiện tại"
        case .find: return "Tìm kiếm"
        case .editLocation: return "Gõ đường dẫn"
        case .goToFolder: return "Đến thư mục"
        case .quickOpen: return "Mở nhanh"
        case .commandPalette: return "Bảng lệnh"
        case .splitRight: return "Chia ngăn sang phải"
        case .splitLeft: return "Chia ngăn sang trái"
        case .splitDown: return "Chia ngăn xuống dưới"
        case .splitUp: return "Chia ngăn lên trên"
        case .closePane: return "Đóng ngăn"
        case .equalizePanes: return "Chia đều các ngăn"
        case .zoomPane: return "Phóng to ngăn"
        case .nextPane: return "Ngăn kế tiếp"
        case .previousPane: return "Ngăn trước đó"
        case .presetSingle: return "Một ngăn"
        case .presetSideBySide: return "Cạnh nhau"
        case .presetStacked: return "Chồng lên nhau"
        case .presetGrid: return "Lưới 2×2"
        case .copyToOtherPane: return "Sao chép sang ngăn kia"
        case .moveToOtherPane: return "Di chuyển sang ngăn kia"
        case .addToShelf: return "Thêm vào Shelf"
        case .toggleShelf: return "Hiện hoặc ẩn Shelf"
        case .operations: return "Hàng đợi thao tác"
        case .batchRename: return "Đổi tên hàng loạt"
        case .compress: return "Nén thành ZIP"
        case .saveWorkspace: return "Lưu Workspace"
        case .openWorkspace: return "Mở Workspace"
        case .downloadNow: return "Tải về ngay"
        case .removeDownload: return "Gỡ bản tải"
        case .showInFinder: return "Hiện trong Finder"
        case .closeWindow: return "Đóng cửa sổ"
        case .getInfo: return "Lấy thông tin"
        case .newWindowTab: return "Tab cửa sổ mới"
        case .newPaneTab: return "Tab ngăn mới"
        case .nextPaneTab: return "Tab ngăn kế tiếp"
        case .previousPaneTab: return "Tab ngăn trước"
        case .closePaneTab: return "Đóng tab ngăn"
        case .moveTabToNextPane: return "Chuyển tab sang ngăn kế"
        case .moveTabToNewPaneRight: return "Chuyển tab sang ngăn mới bên phải"
        case .moveTabToNewPaneBelow: return "Chuyển tab sang ngăn mới bên dưới"
        case .swapWithNextPane: return "Đổi chỗ với ngăn kế"
        case .moveTabToWindow: return "Chuyển tab ra cửa sổ mới"
        case .paneLeft: return "Ngăn bên trái"
        case .paneRight: return "Ngăn bên phải"
        case .paneAbove: return "Ngăn phía trên"
        case .paneBelow: return "Ngăn phía dưới"
        case .makePaneWider: return "Làm ngăn rộng hơn"
        case .makePaneNarrower: return "Làm ngăn hẹp hơn"
        case .makePaneTaller: return "Làm ngăn cao hơn"
        case .makePaneShorter: return "Làm ngăn thấp hơn"
        case .toggleLocationBar: return "Hiện hoặc ẩn thanh vị trí"
        case .togglePathBar: return "Hiện hoặc ẩn thanh đường dẫn"
        case .toggleStatusBar: return "Hiện hoặc ẩn thanh trạng thái"
        case .toggleToolbar: return "Hiện hoặc ẩn thanh công cụ"
        case .customizeToolbar: return "Tuỳ biến thanh công cụ…"
        case .toggleSidebar: return "Hiện hoặc ẩn sidebar"
        case .openInNewTab: return "Mở trong tab mới"
        case .openInNewWindow: return "Mở trong cửa sổ mới"
        case .useGroups: return "Dùng nhóm"
        case .makeAlias: return "Tạo bí danh"
        case .showOriginal: return "Hiện bản gốc"
        case .addToSidebar: return "Thêm vào sidebar"
        case .share: return "Chia sẻ…"
        case .showViewOptions: return "Hiện tuỳ chọn xem"
        case .goRecents: return "Mục gần đây"
        case .goDocuments: return "Tài liệu"
        case .goDesktop: return "Màn hình nền"
        case .goDownloads: return "Thư mục Tải về"
        case .goHome: return "Thư mục nhà"
        case .goAirDrop: return "AirDrop"
        case .goNetwork: return "Mạng"
        case .goICloud: return "iCloud Drive"
        case .goApplications: return "Các ứng dụng"
        case .goUtilities: return "Tiện ích hệ thống"
        case .goComputer: return "Máy tính"
        case .connectToServer: return "Kết nối máy chủ…"
        case .eject: return "Đẩy ra"
        case .clearRecentFolders: return "Xoá menu"
        case .openBrowserSettings: return "Cài đặt trình duyệt…"
        case .showWelcome: return "Hiện cửa sổ Chào…"
        case .newFolderWithSelection: return "Thư mục mới chứa mục chọn"
        case .cut: return "Cắt tệp"
        case .redo: return "Làm lại"
        case .clearOperationHistory: return "Xoá lịch sử thao tác"
        case .togglePreview: return "Hiện hoặc ẩn xem trước"
        case .slideshow: return "Trình chiếu"
        }
    }

    /// Named-key glyphs shown in a chord label, e.g. `display(KeyChord("return", command: true, shift: true))`
    /// returns "⇧⌘↩". Keys outside this table (letters, digits, punctuation) display as their literal, uppercased
    /// for single-character keys so "n" reads as the "N" a keycap shows.
    private static let keyGlyphs: [String: String] = [
        "return": "↩", "delete": "⌫", "space": "Space", "left": "←", "right": "→",
        "up": "↑", "down": "↓", "escape": "Esc", "tab": "⇥",
    ]

    /// Modifier-then-key order is ⌃⌥⇧⌘ (System Settings' own convention, matched by `ShortcutCatalog.Chord.label`
    /// so a chord drawn here reads identically to one drawn on the Phím tắt page).
    static func display(_ chord: KeyChord) -> String {
        var s = ""
        if chord.control { s += "⌃" }
        if chord.option { s += "⌥" }
        if chord.shift { s += "⇧" }
        if chord.command { s += "⌘" }
        if let glyph = keyGlyphs[chord.key] {
            s += glyph
        } else {
            s += chord.key.uppercased()
        }
        return s
    }

    // MARK: - Command palette

    struct Candidate: Equatable, Sendable {
        let id: String
        let title: String
        let subtitle: String?
    }

    /// Normalizes a string for case/diacritic-insensitive matching — same fold `SidebarSearch`/`CrewGate` already
    /// use, so a Vietnamese title ("Thư mục mới") matches an unaccented query ("thu muc"). `.diacriticInsensitive`
    /// alone leaves "đ" untouched (it is not a combining-mark decomposition of "d" — verified: `"đ".folding(...)`
    /// returns "đ"), so "đổi"/"Đổi" must be flattened to "doi"/"Doi" by hand first, exactly like `SidebarSearch.fold`
    /// and `CrewGate`'s goal parser both already do — without this a query typed on a US keyboard ("doi ten") would
    /// never match "Đổi tên" (rename).
    private static func fold(_ s: String) -> String {
        s.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// Subsequence fuzzy score: every character of `query` must appear in `title`, in order, case/diacritic-folded.
    /// Higher is better (unlike `AppLauncher.fuzzyMatch`, which this file does not share state or scale with).
    /// Bonuses stack: a run of consecutive matched characters scores more per character than a scattered match: a
    /// match starting right after a space (a new "word") scores extra; and a match starting at title's index 0
    /// (the strongest signal — the user typed the start of the name) scores extra again. Returns nil when `query`
    /// is not a subsequence of `title`; an empty query matches everything at score 0 (spec: "Query rỗng ⇒ 0").
    static func score(query: String, candidate title: String) -> Int? {
        if query.isEmpty { return 0 }
        let q = Array(fold(query))
        let t = Array(fold(title))
        guard !t.isEmpty else { return nil }

        var qi = 0
        var total = 0
        var previousMatchIndex: Int?
        for ti in 0..<t.count {
            guard qi < q.count, t[ti] == q[qi] else { continue }
            var points = 10
            if let prev = previousMatchIndex, prev == ti - 1 {
                points += 8   // consecutive run
            }
            if ti == 0 {
                points += 6   // prefix of the whole title
            } else if t[ti - 1] == " " {
                points += 4   // start of a word
            }
            total += points
            previousMatchIndex = ti
            qi += 1
        }
        guard qi == q.count else { return nil }
        return total
    }

    /// Ranks `items` by `score(query:candidate:)` against `title`, dropping non-matches, highest first. `sorted`
    /// is a stable sort in Swift's standard library, so items tied on score keep their relative input order
    /// (spec: "ổn định khi bằng điểm") rather than the order a plain `Dictionary`/unstable sort would scramble them
    /// into.
    static func rank(_ query: String, _ items: [Candidate], limit: Int) -> [Candidate] {
        let scored: [(item: Candidate, score: Int)] = items.compactMap { item in
            guard let s = score(query: query, candidate: item.title) else { return nil }
            return (item, s)
        }
        let ranked = scored.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.score != rhs.element.score { return lhs.element.score > rhs.element.score }
                return lhs.offset < rhs.offset
            }
            .map(\.element.item)
        return limit >= 0 ? Array(ranked.prefix(limit)) : ranked
    }

    /// `>` as the first non-whitespace character switches the palette to commands-only mode (spec §2.3's "gõ `>`
    /// ... = chỉ lệnh"). Leading whitespace before `>` is stripped along with it, and the remainder is trimmed so
    /// "  > open" reads the same as ">open".
    static func commandMode(_ query: String) -> (isCommand: Bool, rest: String) {
        let trimmedLeading = query.drop { $0 == " " || $0 == "\t" }
        guard trimmedLeading.first == ">" else { return (false, query) }
        let rest = trimmedLeading.dropFirst().trimmingCharacters(in: .whitespaces)
        return (true, rest)
    }
}
