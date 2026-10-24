# XF-T28 — Hợp đồng file thuần (Wave 1 + 2)

Mọi file dưới đây: `XFinder/Core/Browser/<Tên>.swift`, chỉ `import Foundation` — file nào dùng `CGRect`/`CGPoint`
(PaneTree, BrowserWorkspace) thêm `import CoreGraphics` (đo 2026-10-24: Foundation một mình KHÔNG cho `CGRect` Equatable/
Sendable/init; tiền lệ `EdgeNotesLayout.swift`); **không** SwiftUI/AppKit/UniformTypeIdentifiers, Swift 6 strict concurrency (mọi kiểu công khai `Sendable`), không
`@unchecked Sendable`, không `print`. Symlink `Tests/XFinderLogicTests/<Tên>.swift -> ../../XFinder/Core/Browser/<Tên>.swift`,
test ở `Tests/XFinderLogicTests/<Tên>Tests.swift` (XCTest). Chuỗi hiển thị: model trả **khoá L10n** (chính là câu tiếng
Việt gốc), view mới `L10n.t()`. Chữ ký dưới đây là **bắt buộc** (thêm hàm phụ `private`/`internal` thì được, đổi tên/
chữ ký công khai thì không).

## PaneTree.swift (Wave 1)

```swift
struct PaneID: Hashable, Codable, Sendable, Comparable {
    let raw: Int
    static func < (lhs: PaneID, rhs: PaneID) -> Bool { lhs.raw < rhs.raw }   // struct không tự sinh Comparable
}
enum SplitAxis: String, Codable, Sendable { case horizontal /* con cạnh nhau, vạch dọc */, vertical /* chồng, vạch ngang */ }
enum SplitDirection: String, Codable, Sendable, CaseIterable { case right, left, down, up }
enum PanePreset: String, Codable, Sendable, CaseIterable { case single, sideBySide, stacked, grid }
indirect enum PaneNode: Codable, Equatable, Sendable {
    case leaf(PaneID)
    case split(axis: SplitAxis, fraction: Double, first: PaneNode, second: PaneNode)   // fraction = phần của `first`
}
struct PaneDivider: Equatable, Sendable { let path: [Bool]; let axis: SplitAxis; let rect: CGRect; let parent: CGRect }
struct PaneTree: Codable, Equatable, Sendable {
    static let maxPanes = 16
    static let minFraction = 0.08                 // không ngăn nào nhỏ hơn 8 % trục của nút cha
    private(set) var root: PaneNode
    private(set) var nextID: Int
    private(set) var zoomed: PaneID?
    init()                                         // một ngăn PaneID(raw: 0), nextID = 1
    var panes: [PaneID] { get }                    // thứ tự đọc: duyệt sâu, first trước second
    var count: Int { get }
    var canSplit: Bool { get }                     // count < maxPanes
    func contains(_ pane: PaneID) -> Bool
    /// Ngăn mới ở bên `dir` của `pane` (right/down ⇒ là `second`, left/up ⇒ là `first`), tỉ lệ 0.5; nil nếu đủ 16 hoặc
    /// không có `pane`. Luôn thoát phóng to.
    mutating func split(_ pane: PaneID, _ dir: SplitDirection) -> PaneID?
    /// Bỏ `pane`, anh em chiếm chỗ. Không bao giờ đóng ngăn cuối (nil). Trả ngăn nên được chọn (lá đầu của anh em).
    /// Đóng ngăn đang phóng ⇒ hết phóng.
    mutating func close(_ pane: PaneID) -> PaneID?
    /// Preset dùng lại id cũ theo `panes` (thứ tự đọc), tạo id mới khi thiếu, bỏ phần thừa. grid = 2×2:
    /// split(vertical, .5, split(horizontal,.5,a,b), split(horizontal,.5,c,d)). Thoát phóng to.
    mutating func apply(_ preset: PanePreset) -> (kept: [PaneID], removed: [PaneID])
    mutating func toggleZoom(_ pane: PaneID)       // zoomed = (zoomed == pane) ? nil : pane (chỉ nếu contains)
    /// Mọi nút: fraction = số lá cùng trục của first / tổng (chuỗi cùng trục chia đều).
    mutating func equalize()
    /// `path`: từ gốc, false = first, true = second, tới một nút split. Kẹp vào [minFraction, 1 - minFraction].
    mutating func setFraction(at path: [Bool], _ fraction: Double)
    func next(after pane: PaneID) -> PaneID        // vòng
    func previous(before pane: PaneID) -> PaneID   // vòng
    /// "Ngăn kia" cho ⌃⇧⌘C/M: 1 ngăn ⇒ nil; 2 ⇒ ngăn còn lại; ≥3 ⇒ next(after:).
    func other(than pane: PaneID) -> PaneID?
    /// Khung từng ngăn trong `rect` (gốc trên-trái như AppKit flipped; vạch chia dày `divider` pt nằm giữa hai con).
    /// Đang phóng ⇒ chỉ ngăn phóng, chiếm cả rect.
    func frames(in rect: CGRect, divider: CGFloat) -> [PaneID: CGRect]
    func dividers(in rect: CGRect, divider: CGFloat) -> [PaneDivider]   // rỗng khi đang phóng
    func pane(at point: CGPoint, in rect: CGRect, divider: CGFloat) -> PaneID?
}
```

## PaneHistory.swift (Wave 1)

```swift
struct PaneHistory: Codable, Equatable, Sendable {
    static let limit = 50
    static let rememberLimit = 200
    private(set) var back: [String]
    private(set) var forward: [String]
    private(set) var current: String
    init(current: String)
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    /// Đi tới `path`: current vào back (nếu khác), xoá forward, back ≤ limit (bỏ cũ nhất).
    mutating func visit(_ path: String)
    mutating func goBack() -> String?              // current ↦ forward, trả đích mới
    mutating func goForward() -> String?
    /// ⌘↑: nhớ tên thư mục con vừa rời trong `parent` để chọn lại (≤ rememberLimit, bỏ cũ nhất).
    mutating func noteLeaving(child name: String, of parent: String)
    func childToSelect(in parent: String) -> String?
    /// Khôi phục phiên: bỏ khỏi back/forward mọi đường dẫn không còn; current không còn ⇒ current = `fallback`.
    mutating func removeMissing(exists: (String) -> Bool, fallback: String)
}
```

## BrowserPath.swift (Wave 1)

```swift
enum BrowserPath {
    struct Segment: Equatable, Sendable { let name: String; let path: String }
    enum Display: Equatable, Sendable { case segment(Int); case ellipsis(hidden: [Int]) }
    /// "/Users/a/Docs" với rootName "Macintosh HD" ⇒ [Macintosh HD:/, Users:/Users, a:/Users/a, Docs:/Users/a/Docs].
    /// Đường dẫn dưới "/Volumes/X" bắt đầu bằng đoạn "X" (path "/Volumes/X"), không có "/" và "Volumes".
    static func segments(of path: String, rootName: String) -> [Segment]
    /// Giữ đoạn đầu và (maxVisible - 2) đoạn cuối, giữa gộp thành một ellipsis; count <= maxVisible ⇒ không gộp.
    /// maxVisible < 3 coi như 3.
    static func collapse(count: Int, maxVisible: Int) -> [Display]
    /// Ô gõ đường dẫn: "~" và "~/x" theo home, tương đối theo current, chuẩn hoá "." ".." và "//"; không có "/" cuối
    /// (trừ "/"). Chuỗi rỗng ⇒ current.
    static func resolve(typed: String, current: String, home: String) -> String
    /// Gợi ý Tab: tên con có tiền tố = thành phần cuối của `typed` (không phân biệt hoa thường/dấu), sắp xếp tự nhiên.
    static func completions(typed: String, children: [String]) -> [String]
    static func commonPrefix(_ names: [String]) -> String   // tiền tố chung dài nhất, không phân biệt hoa thường, giữ hoa của tên đầu
}
```

## DirectoryEntry.swift (Wave 1)

```swift
struct DirectoryEntry: Hashable, Sendable, Identifiable {
    enum Kind: UInt8, Sendable { case file, directory, symlink, other }
    var id: String { path }
    let name: String
    let path: String
    let kind: Kind
    let isPackage: Bool
    let isHidden: Bool          // cờ UF_HIDDEN hoặc tên bắt đầu bằng "."
    let size: Int64             // tệp: logical size; thư mục: -1
    let modified: Date
    let created: Date
    let volumeID: Int32
    var ext: String { get }     // phần mở rộng chữ thường, "" nếu không có
    var isFolderLike: Bool { get }   // directory && !isPackage (đi vào được)
}
enum BrowserViewMode: String, Codable, CaseIterable, Sendable { case icons, list, columns, gallery }
enum SortKey: String, Codable, CaseIterable, Sendable { case name, modified, size, kind }
struct SortOrder: Codable, Equatable, Sendable { var key: SortKey; var ascending: Bool; static let finderDefault: SortOrder }  // name, ascending
enum EntryRules {
    /// Tên: localizedStandardCompare ("File 2" < "File 10"); bằng nhau ⇒ theo path. size: thư mục (-1) đứng trước tệp khi
    /// tăng dần, giữa thư mục theo tên. kind: theo `kindName(entry)` (tên loại đã dịch mà view hiển thị — như Finder
    /// sắp cột Loại; view cache theo UTType) bằng localizedStandardCompare, rồi theo tên. foldersFirst: thư mục
    /// (isFolderLike) luôn trước. Giảm dần = đảo thứ tự khoá chính, khoá phụ (tên) vẫn tăng dần.
    static func sorted(_ entries: [DirectoryEntry], by order: SortOrder, foldersFirst: Bool,
                       kindName: (DirectoryEntry) -> String) -> [DirectoryEntry]
    static func visible(_ entries: [DirectoryEntry], showHidden: Bool) -> [DirectoryEntry]
    /// Lọc thư mục hiện tại: tách query theo khoảng trắng, mọi từ phải nằm trong tên (không phân biệt hoa thường/dấu,
    /// "đ" ≡ "d"). Query rỗng ⇒ nguyên danh sách. 100 000 mục phải < 16 ms (-O) — không tạo String mới mỗi mục mỗi lần.
    static func filter(_ entries: [DirectoryEntry], query: String) -> [DirectoryEntry]
    /// Khoá so khớp đã chuẩn hoá của một tên (dùng chung cho filter và type-select; có thể cache theo entry).
    static func foldKey(_ name: String) -> String
    struct TypeSelect: Sendable, Equatable {
        static let timeout: TimeInterval = 1.0
        private(set) var buffer: String
        private(set) var last: Date?
        init()
        /// Thêm ký tự; quá timeout kể từ lần trước ⇒ bắt đầu bộ đệm mới. Trả bộ đệm hiện tại.
        mutating func type(_ chars: String, at now: Date) -> String
        /// Chỉ số mục đầu tiên có tiền tố = prefix (foldKey); không có ⇒ mục đầu tiên lớn hơn prefix theo thứ tự hiện có;
        /// không có nữa ⇒ mục cuối; danh sách rỗng ⇒ nil.
        static func match(prefix: String, in names: [String]) -> Int?
    }
}
```

## SearchQuery.swift (Wave 1)

```swift
enum KindFilter: String, Codable, CaseIterable, Sendable {
    case pdfs, images, videos, audio, documents, spreadsheets, presentations, archives, folders, applications, screenshots, code, text
}
enum DateRange: Hashable, Codable, Sendable {
    case today, yesterday, thisWeek, lastWeek, thisMonth, lastMonth, thisYear, lastYear
    case pastDays(Int), olderThanDays(Int), month(year: Int, month: Int)
}
enum SizeOp: String, Codable, Sendable { case greater, less, greaterOrEqual, lessOrEqual, equal }
struct SearchChip: Hashable, Codable, Sendable, Identifiable {
    enum Field: String, Codable, Sendable { case kind, modified, created, size, source, ext, tag, content }
    enum Value: Hashable, Codable, Sendable { case kind(KindFilter); case date(DateRange); case size(SizeOp, Int64); case text(String) }
    var field: Field
    var value: Value
    var uncertain: Bool          // tháng không có năm ⇒ chip đánh dấu "?"
    var id: String { get }       // ổn định: field + giá trị chuẩn hoá
}
struct ParsedSearch: Equatable, Sendable {
    var chips: [SearchChip]
    var terms: [String]          // từ tên tệp (AND)
    var phrases: [String]        // "cụm trong ngoặc" — khớp nguyên văn trong tên
    var excluded: [String]       // -từ hoặc !từ
    var warnings: [String]       // khoá L10n, vd "Toán tử không rõ: giữ là chữ"
    var isEmpty: Bool { get }
}
enum SearchQuery {
    /// Tiếng Anh + tiếng Việt. Quy tắc (FileOctopus, đo từ tài liệu): số nhiều/`kind:` mới là loại ("pdfs", "images",
    /// "ảnh", "tệp pdf"); số ít "pdf" là từ tên. Cỡ phải có đơn vị (KB/MB/GB/TB, KiB… coi như nhau, thập phân được;
    /// `size:` không đơn vị = byte). "from last week", "last week", "past 7 days", "older than 30 days", "today",
    /// "yesterday", "this week/month/year", "last month/year", tên tháng tiếng Anh/"tháng 3" không năm ⇒ năm gần nhất +
    /// uncertain. "created/edited/modified" chọn field created/modified (mặc định modified). "downloaded from github"
    /// ⇒ source "github". Ngoặc kép ⇒ phrase. Toán tử lạ ⇒ giữ là từ + warning. Tiếng Việt: "hôm nay", "hôm qua",
    /// "tuần này", "tuần trước", "tháng này", "tháng trước", "năm nay", "năm ngoái", "7 ngày qua", "cũ hơn 30 ngày",
    /// "lớn hơn 1 GB", "nhỏ hơn 10 MB", "tải từ github", loại: "ảnh", "video", "nhạc", "tài liệu", "bảng tính",
    /// "bản trình chiếu", "tệp nén", "thư mục", "ứng dụng", "ảnh chụp màn hình", "mã nguồn".
    static func parse(_ text: String, now: Date, calendar: Calendar) -> ParsedSearch
    /// Biểu thức mdfind (AND). Ngày tính tuyệt đối từ `now`/`calendar` (đầu ngày/tuần/tháng theo calendar), xuất
    /// `$time.iso(YYYY-MM-DDTHH:MM:SSZ)` UTC. Tên: kMDItemFSName == "*x*"cd; phrase: "*cụm*"c; excluded: !(…);
    /// kind ⇒ kMDItemContentTypeTree; source ⇒ kMDItemWhereFroms == "*x*"cd; content ⇒ kMDItemTextContent == "*x*"cd;
    /// tag ⇒ kMDItemUserTags == "x"cd; ext ⇒ kMDItemFSName == "*.x"c; size ⇒ kMDItemFSSize. Dấu " và \ trong giá trị
    /// được escape. Không có gì ⇒ "kMDItemFSName == \"*\"".
    static func mdfindExpression(_ search: ParsedSearch, now: Date, calendar: Calendar) -> String
    static func removing(chip id: String, from search: ParsedSearch) -> ParsedSearch
    /// Thay chip có id `oldID` bằng `chip` (giữ vị trí); không có `oldID` ⇒ thêm `chip` vào cuối.
    static func replacing(id oldID: String, with chip: SearchChip, in search: ParsedSearch) -> ParsedSearch
    /// Khoảng [start, end) của một DateRange (end = nil: tới nay; olderThanDays: start = nil).
    static func interval(of range: DateRange, now: Date, calendar: Calendar) -> (start: Date?, end: Date?)
}
```

## FileOperationRules.swift (Wave 1)

```swift
enum FileOperationKind: String, Codable, Sendable { case copy, move, duplicate, trash }
enum ConflictChoice: String, Codable, Sendable { case keepBoth, skip, replace, stop }
enum MoveStrategy: Equatable, Sendable { case rename, cloneOrCopy, copyVerifyTrash, trash }
enum JobState: String, Codable, Sendable { case waiting, running, pausing, paused, verifying, finishing, done, failed, cancelled }
struct FileJob: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: FileOperationKind
    let sources: [String]
    let destination: String?     // nil cho trash
    var state: JobState
    var bytesDone: Int64
    var bytesTotal: Int64
    var itemsDone: Int
    var itemsTotal: Int
    var errorKey: String?        // khoá L10n
    var errorDetail: String?     // mã lỗi máy, dòng "Chi tiết"
    init(id: UUID, kind: FileOperationKind, sources: [String], destination: String?)
    var isActive: Bool { get }   // running, pausing, paused, verifying, finishing
    var isFinished: Bool { get } // done, failed, cancelled
}
struct FileJobQueue: Codable, Equatable, Sendable {
    private(set) var jobs: [FileJob]
    init()
    var active: FileJob? { get }                  // tối đa một
    mutating func enqueue(_ job: FileJob)
    /// Không có việc active ⇒ việc waiting đầu tiên thành running, trả id; có việc active (kể cả paused) ⇒ nil.
    mutating func startNextIfIdle() -> UUID?
    @discardableResult mutating func pause(_ id: UUID) -> Bool     // chỉ từ running ⇒ pausing
    @discardableResult mutating func didPause(_ id: UUID) -> Bool  // pausing ⇒ paused
    @discardableResult mutating func resume(_ id: UUID) -> Bool    // paused/pausing ⇒ running
    @discardableResult mutating func cancel(_ id: UUID) -> Bool    // waiting/active ⇒ cancelled
    @discardableResult mutating func setPhase(_ id: UUID, _ state: JobState) -> Bool  // running→verifying→finishing; pausing không vào verifying
    mutating func finish(_ id: UUID, failedWith errorKey: String?, detail: String?)   // done hoặc failed
    mutating func progress(_ id: UUID, bytesDone: Int64, itemsDone: Int)
    mutating func pauseAll()                      // việc active running ⇒ pausing; mọi waiting giữ nguyên
    mutating func resumeAll()
    @discardableResult mutating func runNext(_ id: UUID) -> Bool   // waiting lên đầu hàng chờ
    @discardableResult mutating func moveUp(_ id: UUID) -> Bool    // chỉ giữa các waiting
    @discardableResult mutating func moveDown(_ id: UUID) -> Bool
    mutating func clearFinished()
}
enum JournalPhase: String, Codable, Sendable { case started, copied, verified, trashing, sourceRemoved, done }
struct JournalEntry: Codable, Equatable, Sendable {
    let job: UUID; let kind: FileOperationKind; let source: String; let destination: String?; var phase: JournalPhase; let at: Date
}
struct RecoveryItem: Equatable, Sendable { let source: String; let destination: String?; let messageKey: String }
enum FileOperationRules {
    /// Finder "Giữ cả hai": "Report.pdf" ⇒ "Report 2.pdf", "Report 3.pdf"…; "Report 2.pdf" có sẵn ⇒ "Report 3.pdf" (không
    /// "Report 2 2"); thư mục/không đuôi: "Folder 2"; tệp chấm ".zshrc" ⇒ ".zshrc 2"; chỉ đuôi cuối ("a.tar.gz" ⇒ "a.tar 2.gz").
    static func keepBothName(for name: String, existing: Set<String>) -> String
    /// Finder ⌘D: "Report copy.pdf", "Report copy 2.pdf"…; nhân bản "Report copy.pdf" ⇒ "Report copy 2.pdf".
    static func duplicateName(for name: String, existing: Set<String>) -> String
    /// Theo thành phần đường dẫn đã chuẩn hoá: "/a/bc" không nằm trong "/a/b".
    static func isInside(_ path: String, ancestor: String) -> Bool
    /// Nguồn đầu tiên mà destination == nguồn hoặc nằm trong nguồn (chép thư mục vào chính nó); nil nếu hợp lệ.
    static func nestingViolation(sources: [String], destination: String) -> String?
    static func strategy(kind: FileOperationKind, sameVolume: Bool) -> MoveStrategy
    /// a mới hơn b ít nhất 1 s (coarse = FAT/exFAT: 2 s).
    static func isNewer(_ a: Date, than b: Date, coarseTimestamps: Bool) -> Bool
    /// Chỉ tệp ↔ tệp (không thư mục, không gói) mới cho Thay thế.
    static func replaceAllowed(sourceIsFolder: Bool, destinationIsFolder: Bool) -> Bool
    /// Mục có pha cuối != done ⇒ một RecoveryItem: started ⇒ "Có thể còn tệp chép dở ở đích"; copied ⇒ "Bản sao chưa
    /// được kiểm"; verified (move) ⇒ "Bản gốc vẫn còn ở chỗ cũ"; trashing ⇒ "Bản gốc có thể đã vào Thùng rác — kiểm tra
    /// trước khi coi là mất"; sourceRemoved ⇒ không cần xem lại (coi như xong). Lấy pha MỚI NHẤT theo (job, source)
    /// — "mới nhất" = thứ tự trong mảng (nhật ký chỉ ghi nối), không theo `at`.
    static func recoveryReport(_ entries: [JournalEntry]) -> [RecoveryItem]
    /// Tạm dừng chỉ an toàn trong pha chép (callback copyfile — đo); verifying/finishing: nút Tạm dừng TẮT.
    static func canPause(_ state: JobState) -> Bool                          // chỉ running
    static func smoothedSpeed(previous: Double?, sample: Double) -> Double   // EMA alpha 0.2; previous nil ⇒ sample
    static func eta(bytesDone: Int64, bytesTotal: Int64, bytesPerSecond: Double) -> TimeInterval?   // nil nếu speed ≤ 0 hoặc xong
}
```

## BrowserCommands.swift (Wave 1)

```swift
struct KeyChord: Hashable, Codable, Sendable {
    var key: String              // ký tự thường ("n", "1", "[", ".", "=") hoặc tên: "return", "delete", "space", "left", "right", "up", "down", "escape", "tab"
    var command: Bool; var shift: Bool; var option: Bool; var control: Bool
    init(_ key: String, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false)
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
}
enum BrowserCommands {
    static func chord(for command: BrowserCommand) -> KeyChord?
    /// Mỗi chord tối đa một lệnh (test bắt trùng). Space chỉ là quickLook khi không gõ chữ (view quyết).
    static func command(for chord: KeyChord) -> BrowserCommand?
    static func titleKey(_ command: BrowserCommand) -> String          // khoá L10n, vd "Thư mục mới"
    static func display(_ chord: KeyChord) -> String                    // "⌃⌥⌘→", "⇧⌘↩", "⌘⌫"; thứ tự ⌃⌥⇧⌘
    struct Candidate: Equatable, Sendable { let id: String; let title: String; let subtitle: String? }
    /// So khớp mờ: query là dãy con của title (không phân biệt hoa thường/dấu); điểm cao hơn cho khớp liền, đầu từ, tiền
    /// tố; nil = không khớp. Query rỗng ⇒ 0.
    static func score(query: String, candidate title: String) -> Int?
    static func rank(_ query: String, _ items: [Candidate], limit: Int) -> [Candidate]   // ổn định khi bằng điểm
    /// ">" đầu (bỏ khoảng trắng đầu) ⇒ (true, phần còn lại đã trim).
    static func commandMode(_ query: String) -> (isCommand: Bool, rest: String)
}
```
Phím bắt buộc (spec §2): newWindow ⌘N · newFolder ⇧⌘N · open ⌘O (và ⌘↓) · openEnclosing ⌘↑ · back ⌘[ · forward ⌘] ·
rename return · duplicate ⌘D · moveToTrash ⌘⌫ · quickLook ⌘Y · copy ⌘C · paste ⌘V · pasteMove ⌥⌘V · copyPath ⌥⌘C ·
toggleHidden ⇧⌘. · selectAll ⌘A · undo ⌘Z · viewIcons ⌘1 · viewList ⌘2 · viewColumns ⌘3 · viewGallery ⌘4 · filter ⌘F ·
find ⌥⌘F · editLocation ⌃⌘L · goToFolder ⇧⌘G · quickOpen ⌃⌘P · commandPalette ⌃⇧⌘P · splitRight/Left/Down/Up ⌃⌥⌘→/←/↓/↑ ·
closePane ⌃⌥⌘W · equalizePanes ⌃⌥⌘= · zoomPane ⇧⌘↩ · nextPane ⌃⌘] · previousPane ⌃⌘[ · copyToOtherPane ⌃⇧⌘C ·
moveToOtherPane ⌃⇧⌘M · addToShelf ⌃⌘S · toggleShelf ⌥⌘B · operations ⌥⌘O · batchRename ⌃⌘R · closeWindow ⌘W ·
không phím: preset*, compress, saveWorkspace, openWorkspace, downloadNow, removeDownload, showInFinder.
(⌘↓ là chord phụ của open: `command(for: ⌘down) == .open`.)

## CloudBadge.swift (Wave 1)

```swift
enum CloudBadge: String, Sendable { case none, cloudOnly, downloading, uploading, downloadFailed, uploadFailed }
struct CloudFacts: Equatable, Sendable {
    var isUbiquitous: Bool?
    var downloadingStatus: String?   // rawValue URLUbiquitousItemDownloadingStatus: "NSURLUbiquitousItemDownloadingStatusCurrent" | "…Downloaded" | "…NotDownloaded"
    var isDownloading: Bool?
    var isUploading: Bool?
    var isUploaded: Bool?
    var hasDownloadError: Bool
    var hasUploadError: Bool
    init(isUbiquitous: Bool? = nil, downloadingStatus: String? = nil, isDownloading: Bool? = nil, isUploading: Bool? = nil,
         isUploaded: Bool? = nil, hasDownloadError: Bool = false, hasUploadError: Bool = false)
}
enum CloudRules {
    /// Ưu tiên: lỗi tải xuống > lỗi tải lên > đang tải xuống > đang tải lên > chỉ trên mây (NotDownloaded) > none.
    /// isUbiquitous != true và không có status ⇒ none.
    static func badge(_ facts: CloudFacts) -> CloudBadge
    static func canDownload(_ facts: CloudFacts) -> Bool    // NotDownloaded và chưa đang tải
    static func canEvict(_ facts: CloudFacts) -> Bool       // đã tải (Current/Downloaded), isUploaded == true, không đang tải lên
}
```

## ShelfModel.swift (Wave 1)

```swift
struct ShelfItem: Hashable, Codable, Sendable, Identifiable { var id: String { path }; let path: String; var size: Int64?; var missing: Bool }
struct ShelfModel: Codable, Equatable, Sendable {
    private(set) var items: [ShelfItem]
    init()
    /// Thêm theo thứ tự, bỏ trùng theo đường dẫn chuẩn hoá (standardized, bỏ "/" cuối). Trả số mục thật sự thêm.
    @discardableResult mutating func add(_ paths: [String], sizes: [String: Int64]) -> Int
    mutating func remove(_ paths: Set<String>)
    mutating func clear()
    mutating func refreshMissing(exists: (String) -> Bool)
    var count: Int { get }
    var totalBytes: Int64 { get }     // cỡ đã biết, bỏ mục missing
    /// Mục chọn (nếu có) hoặc tất cả, bỏ mục missing, theo thứ tự trong Shelf.
    func targets(selection: Set<String>) -> [String]
}
```

## BrowserWorkspace.swift (Wave 2 — sau khi PaneTree/PaneHistory/DirectoryEntry đã gộp)

```swift
struct PaneSnapshot: Codable, Equatable, Sendable {
    var id: PaneID; var path: String; var viewMode: BrowserViewMode; var sort: SortOrder; var history: PaneHistory; var showHidden: Bool
}
struct WindowSnapshot: Codable, Equatable, Sendable {
    var frame: CGRect?; var tree: PaneTree; var panes: [PaneSnapshot]; var activePane: PaneID; var shelfVisible: Bool
}
struct Workspace: Codable, Equatable, Identifiable, Sendable { var id: UUID; var name: String; var windows: [WindowSnapshot]; var savedAt: Date }
struct WorkspaceStore: Codable, Equatable, Sendable {
    private(set) var workspaces: [Workspace]
    init()
    /// Tên trùng ⇒ "Tên 2", "Tên 3"; tên rỗng (sau trim) ⇒ "Workspace".
    mutating func save(name: String, windows: [WindowSnapshot], now: Date) -> Workspace
    @discardableResult mutating func rename(_ id: UUID, to name: String) -> Bool   // rỗng hoặc trùng tên khác ⇒ false
    mutating func duplicate(_ id: UUID, now: Date) -> Workspace?                  // "Tên copy"
    mutating func delete(_ id: UUID)
    func exportJSON() -> Data                                                     // sortedKeys, prettyPrinted, ISO8601
    /// Đọc từng workspace riêng: bản hỏng bị bỏ qua, đếm vào skipped.
    static func decode(_ data: Data) -> (store: WorkspaceStore, skipped: Int)
}
enum SessionRestore {
    /// Ngăn có thư mục không còn ⇒ path = home (lịch sử giữ, mục mất bị lọc khỏi back/forward); trả danh sách mất.
    static func restored(_ window: WindowSnapshot, exists: (String) -> Bool, home: String) -> (window: WindowSnapshot, missing: [String])
    static func shouldRestore(shiftHeld: Bool, reopenEnabled: Bool) -> Bool
}
```
