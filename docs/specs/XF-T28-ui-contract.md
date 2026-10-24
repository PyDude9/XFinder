# XF-T28 — Hợp đồng lớp AppKit/SwiftUI (Wave 3)

Người tích hợp (Claude) đã viết **stub biên dịch được** cho mọi file dưới đây trên `main`, với đúng chữ ký công khai này.
Mỗi agent thay ruột **đúng các file của cụm mình**, build cả app (`XF_ROOT=<worktree> XF_OUT=<scratch> sh
scripts/build-and-check.sh`) với stub của cụm khác còn nguyên. Không đổi chữ ký công khai; cần thêm thì thêm `internal`
mới trong file của mình. Không sửa pbxproj/catalog/L10n/FeatureHub/XFinderApp (người tích hợp làm). Mọi chuỗi:
`L10n.t("câu tiếng Việt")` trực tiếp trong view (khoá mới được người tích hợp thêm sau bằng cách quét literal). Kiểu
dáng: chỉ `XFinderTokens` (không số/màu literal trong view — `scripts/audit-ui-tokens.py`), trừ AppKit thuần (NSTableView
row height dùng hằng có tên trong file, có comment). Swift 6: không `@unchecked Sendable`; callback ngoài main →
`Task { @MainActor in }`; `MainActor.assumeIsolated` chỉ khi nguồn chắc chắn là main queue/run loop.

## Cụm A — I/O lõi (`Core/Browser/DirectoryReader.swift`, `Core/Browser/FileIconCache.swift`)

```swift
enum DirectoryReadError: Error, Equatable, Sendable {
    case notPermitted, notFound, notDirectory, timedOut, other(Int32)
    var messageKey: String { get }        // "XFinder chưa được phép đọc thư mục này" …
}
enum DirectoryReader {
    /// getattrlistbulk(2) một cấp (đo: 100 000 tệp 97 ms; FileManager giấu `._*`). Đồng bộ — gọi ngoài main.
    /// Thuộc tính: tên, loại (VDIR/VREG/VLNK), cờ (UF_HIDDEN), cỡ logic (ATTR_FILE_DATALENGTH), mtime, crtime, devid;
    /// isPackage: thư mục có đuôi gói đã biết (.app .bundle .framework .pages .numbers .key .rtfd .photoslibrary .xcodeproj
    /// .playground …) HOẶC cờ bundle Finder (ATTR_CMN_FNDRINFO kHasBundle).
    static func list(_ path: String) -> Result<[DirectoryEntry], DirectoryReadError>
    /// Cùng việc, chạy trên một luồng nền, quá `timeout` ⇒ .timedOut (ổ mạng treo không chặn ai).
    static func list(_ path: String, timeout: TimeInterval) async -> Result<[DirectoryEntry], DirectoryReadError>
    /// Thư mục con (không gói), cho menu chevron + gợi ý Tab; ẩn theo showHidden.
    static func subfolders(of path: String, showHidden: Bool, timeout: TimeInterval) async -> Result<[String], DirectoryReadError>
    static func volumeID(of path: String) -> Int32?
    static func volumePath(of path: String) -> String?          // điểm gắn (statfs f_mntonname)
    static func hasCoarseTimestamps(_ path: String) -> Bool      // statfs f_fstypename msdos/exfat
    static func freeSpace(of path: String) -> Int64?
}
/// Một fd O_EVTONLY + DispatchSource trên main queue (đo: 0,52 ms). Gộp sự kiện 80 ms rồi gọi onChange; thư mục bị
/// xoá/đổi tên (.delete/.rename) ⇒ onGone. cancel() đóng fd. Không còn tham chiếu ⇒ deinit huỷ.
@MainActor final class DirectoryWatcher {
    init?(path: String, onChange: @escaping @MainActor () -> Void, onGone: @escaping @MainActor () -> Void)
    func cancel()
}
@MainActor final class FileIconCache {
    static let shared: FileIconCache
    /// Theo UTType từ đuôi (đo: 0,0002 ms/lần khi cache), thư mục thường = icon thư mục chung, gói/app/thư mục có icon
    /// riêng/volume = icon(forFile:) cache theo đường dẫn (LRU 512).
    func icon(for entry: DirectoryEntry) -> NSImage
    func icon(forPath path: String) -> NSImage
    /// Tên loại đã dịch như cột Loại của Finder (UTType.localizedDescription, cache theo đuôi; thư mục ⇒ L10n "Thư mục").
    func kindName(for entry: DirectoryEntry) -> String
    /// QLThumbnailGenerator (đo: dựng ngoài tiến trình, +3,7 MB/60 ảnh, không giữ) — LRU 256; gọi lại trên main.
    func thumbnail(forPath path: String, side: CGFloat, scale: CGFloat, completion: @escaping @MainActor (NSImage?) -> Void)
    func purge()                                                  // đóng cửa sổ cuối
}
```

## Cụm B — Thao tác tệp (`Core/Browser/FileOperationQueue.swift`, `Core/Browser/EjectGuard.swift`)

```swift
struct ConflictPrompt: Identifiable, Equatable {
    struct Side: Equatable { let path: String; let size: Int64; let modified: Date; let isFolder: Bool; let isNewer: Bool }
    let id: UUID; let jobID: UUID; let source: Side; let destination: Side; let replaceAllowed: Bool; let remaining: Int
}
@MainActor @Observable final class FileOperationQueue {
    static let shared: FileOperationQueue
    private(set) var queue: FileJobQueue
    private(set) var pendingConflict: ConflictPrompt?
    private(set) var speed: Double?                 // byte/s của việc active (EMA)
    private(set) var eta: TimeInterval?
    private(set) var recovery: [RecoveryItem]       // nạp lúc khởi động từ nhật ký
    private(set) var lastErrorKey: String?
    var hasActiveWork: Bool { get }
    /// Kiểm nestingViolation, đích ghi được; lỗi ⇒ nil + lastErrorKey. Chạy nối tiếp (một việc một lúc).
    @discardableResult func enqueue(_ kind: FileOperationKind, sources: [String], destination: String?) -> UUID?
    func pause(_ id: UUID); func resume(_ id: UUID); func cancel(_ id: UUID)
    func pauseAll(); func resumeAll(); func runNext(_ id: UUID); func moveUp(_ id: UUID); func moveDown(_ id: UUID)
    func clearFinished()
    func resolveConflict(_ choice: ConflictChoice, applyToAll: Bool)
    func loadRecovery()                             // gọi một lần lúc khởi động
    func clearRecovery()
    /// ⌘Z cho thao tác cuối của trình duyệt (rename/move/copy/duplicate/trash/zip) qua ActionHistoryStore.
    func undoLast() -> String?                      // thông báo (đã L10n) hoặc nil nếu không có gì
}
```
Worker: `copyfile(3)` + `COPYFILE_STATE_STATUS_CB` trên một Thread riêng; cùng volume dùng `COPYFILE_CLONE` (đo: không
có cờ thì không clone); tạm dừng = chặn trong callback chờ cờ (OSAllocatedUnfairLock + semaphore); huỷ = `COPYFILE_QUIT`
(đo: không để tệp dở). Di chuyển cùng volume = `rename(2)`; khác volume = chép → SHA-256 (CryptoKit, khúc 4 MiB) cả hai
→ `trashItem` bản gốc (pha nhật ký started/copied/verified/trashing/sourceRemoved/done ghi nối vào
`~/Library/Application Support/XFinder/Browser/operations.jsonl`, fsync). Trùng tên: hỏi qua `pendingConflict` (chờ tới khi
resolveConflict). Vào Thùng rác: `FileManager.trashItem`, nhớ URL trong Thùng rác cho ⌘Z. Lỗi: khoá L10n tiếng thường +
`errorDetail` mã máy. Không bao giờ `removeItem` dữ liệu người dùng (chỉ tệp dở của chính mình khi copyfile chưa tự dọn).
```swift
/// DiskArbitration (đo 2026-10-24: dissenter chặn `diskutil unmount/eject`, không cần entitlement). Khớp theo điểm gắn.
@MainActor final class EjectGuard {
    static let shared: EjectGuard
    func setBusyVolumes(_ mountPoints: Set<String>)   // rỗng ⇒ huỷ đăng ký callback
}
```

## Cụm C — Mô hình cửa sổ (`Core/Browser/BrowserWindowModel.swift`, `Core/Browser/BrowserWindowController.swift`)

```swift
enum PaneLoadState: Equatable { case idle, loading, loaded, failed(DirectoryReadError) }
struct PaneSearchState: Equatable {
    enum Scope: String, CaseIterable { case folder, mac, panes }
    var text: String; var parsed: ParsedSearch; var scope: Scope; var results: [DirectoryEntry]; var running: Bool; var truncated: Bool
}
@MainActor @Observable final class PaneState: Identifiable {
    let id: PaneID
    private(set) var path: String
    private(set) var history: PaneHistory
    var viewMode: BrowserViewMode
    var sort: SortOrder
    var showHidden: Bool
    var foldersFirst: Bool
    private(set) var entries: [DirectoryEntry]          // đã ẩn/lọc/sắp — nguồn của mọi kiểu xem
    private(set) var loadState: PaneLoadState
    var selection: Set<String>                          // đường dẫn
    var filterText: String                              // ⌘F: lọc trong bộ nhớ
    var search: PaneSearchState?                        // ⌥⌘F: nil = duyệt thư mục
    var selectAfterLoad: String?                        // ⌘↑ chọn lại thư mục vừa rời
    init(id: PaneID, path: String, viewMode: BrowserViewMode, sort: SortOrder, showHidden: Bool, history: PaneHistory?)
    func navigate(to path: String)                      // ghi lịch sử, nạp, đặt watcher
    func goBack(); func goForward(); func goUp()
    func reload()
    func open(_ entry: DirectoryEntry)                  // thư mục ⇒ navigate; tệp/gói ⇒ NSWorkspace.open
    func runSearch(_ text: String, scope: PaneSearchState.Scope)
    func endSearch()
    var selectedEntries: [DirectoryEntry] { get }
    func stopWatching()
}
@MainActor @Observable final class BrowserWindowModel {
    var tree: PaneTree
    private(set) var panes: [PaneID: PaneState]
    var activePane: PaneID
    var shelf: ShelfModel
    var shelfVisible: Bool
    var palette: PaletteMode?           enum PaletteMode: Equatable { case quickOpen, commands }
    var editingLocation: PaneID?
    var renaming: PaneID?               // ngăn đang đổi tên inline (mục = selection đơn)
    var batchRenameSources: [String]?   // sheet đổi tên hàng loạt
    var banner: String?                 // khoá L10n một dòng (lỗi/thông báo), view tự ẩn sau 4 s
    init(snapshot: WindowSnapshot?, initialPath: String?)
    var active: PaneState { get }
    /// Bộ điều phối DUY NHẤT cho phím, palette, toolbar, menu chuột phải.
    @discardableResult func perform(_ command: BrowserCommand) -> Bool
    func canPerform(_ command: BrowserCommand) -> Bool
    func focus(_ pane: PaneID)
    func snapshot(frame: CGRect?) -> WindowSnapshot
    func commitRename(_ path: String, to newName: String) -> Bool   // từ chối ":" "/" rỗng, trùng ⇒ banner
    func drop(_ paths: [String], into folder: String, copy: Bool?)   // copy nil ⇒ cùng ổ = move, khác ổ = copy
    func tearDown()                                                   // dừng mọi watcher (đóng cửa sổ)
}
/// Mọi cửa sổ trình duyệt; phiên; phím; chuột Back/Forward theo ngăn dưới con trỏ; Quick Look.
@MainActor final class BrowserWindowController: NSObject {
    static let shared: BrowserWindowController
    func openWindow(path: String?)                    // ⌘N, menu bar, deep link
    func restoreSessionAtLaunch()                     // fileBrowser.reopenWindows && !Shift
    func saveSession()                                // đóng cửa sổ, thoát app
    func closeAllWindows()                            // tính năng bị tắt: lưu phiên, đóng hết, dừng watcher
    func confirmQuit() -> Bool                        // applicationShouldTerminate: false = ở lại đợi
    var windowCount: Int { get }
    func toggleQuickLook(for model: BrowserWindowModel)
}
/// NSWindow con: performKeyEquivalent ⇒ BrowserCommands.command(for:) ⇒ model.perform; otherMouseDown nút 3/4 và swipe
/// ⇒ ngăn tại con trỏ (tree.pane(at:)) goBack/goForward.
final class BrowserWindow: NSWindow { }
```
Phiên: `~/Library/Application Support/XFinder/Browser/session.json` ([WindowSnapshot]); workspaces: `workspaces.json`
(WorkspaceStore). Thoát app khi `FileOperationQueue.hasActiveWork` ⇒ hỏi Đợi / Dừng và thoát (applicationShouldTerminate
— người tích hợp nối vào AppDelegate; controller cung cấp `func confirmQuit() -> Bool`).

## Cụm D — Kiểu xem (`Views/Browser/FileListView.swift`, `FileIconView.swift`, `FileColumnView.swift`, `FileGalleryView.swift`)

```swift
struct FileListView: NSViewRepresentable { let pane: PaneState; let model: BrowserWindowModel }       // NSTableView view-based
struct FileIconView: NSViewRepresentable { let pane: PaneState; let model: BrowserWindowModel }       // NSCollectionView
struct FileColumnView: NSViewRepresentable { let pane: PaneState; let model: BrowserWindowModel }     // NSBrowser
struct FileGalleryView: View { let pane: PaneState; let model: BrowserWindowModel }                   // xem trước lớn + dải thumbnail
```
Chung: nguồn = `pane.entries`; lựa chọn hai chiều với `pane.selection`; nhấp đúp/Return-mở theo luật (Return = đổi tên
qua `model.renaming`, ⌘O/⌘↓ mở); gõ-để-chọn (`EntryRules.TypeSelect`); kéo ra (NSPasteboardItem fileURL) và thả vào
(thư mục đích = thư mục dưới con trỏ hoặc thư mục của ngăn; modifier ⌥ ép chép, ⌘ ép di chuyển ⇒ `model.drop`); menu chuột
phải gồm lệnh của `BrowserCommands` (titleKey qua `L10n.t`); badge đám mây (`CloudRules` từ URLResourceValues, đọc lười cho
hàng đang hiện); icon/thumbnail qua `FileIconCache`; cột Danh sách: Tên · Ngày sửa · Cỡ · Loại, bấm tiêu đề = sắp xếp
(`pane.sort`), Loại dùng `FileIconCache.kindName`. 100 000 hàng phải cuộn mượt (tái dùng ô, không SwiftUI List).

## Cụm E — Khung giao diện (`Views/Browser/BrowserRootView.swift`, `BrowserSidebarView.swift`, `PaneGridView.swift`,
`PaneView.swift`, `LocationBarView.swift`, `SearchBarView.swift`, `ShelfBarView.swift`, `OperationsPanelView.swift`,
`ConflictSheet.swift`, `CommandPaletteView.swift`, `BrowserBatchRenameSheet.swift`, `RecoveryReportSheet.swift`)

```swift
struct BrowserRootView: View { let model: BrowserWindowModel }        // toolbar + sidebar + lưới ngăn + Shelf + sheet/popover
struct BrowserSidebarView: View { let model: BrowserWindowModel }     // Mục ưa thích, Vị trí (ổ + CloudStorage + iCloud), nút đẩy ổ
struct PaneGridView: View { let model: BrowserWindowModel }           // tree.frames + vạch chia kéo được (setFraction)
struct PaneView: View { let pane: PaneState; let model: BrowserWindowModel; let isActive: Bool }  // thanh đường dẫn + thanh tìm/lọc + kiểu xem + dòng trạng thái
struct LocationBarView: View { let pane: PaneState; let model: BrowserWindowModel }  // breadcrumb, chevron NSMenu thư mục con, chuột phải, ô gõ
struct SearchBarView: View { let pane: PaneState; let model: BrowserWindowModel }    // ô lọc ⌘F + ô tìm ⌥⌘F + chip (popover sửa) + phạm vi
struct ShelfBarView: View { let model: BrowserWindowModel }
struct OperationsPanelView: View { let queue: FileOperationQueue }    // popover: tiến độ, tốc độ, ETA, Tạm dừng (canPause), Dừng, thứ tự
struct ConflictSheet: View { let prompt: ConflictPrompt; let queue: FileOperationQueue }  // Giữ cả hai (Return, mặc định) · Bỏ qua · Thay thế (đỏ, tắt khi !replaceAllowed) · Dừng (Esc) · Áp dụng cho tất cả
struct CommandPaletteView: View { let model: BrowserWindowModel; let mode: BrowserWindowModel.PaletteMode }
struct BrowserBatchRenameSheet: View { let sources: [String]; let model: BrowserWindowModel }  // BatchRenameEngine.plan/execute + recordRenames
struct RecoveryReportSheet: View { let queue: FileOperationQueue }
```
Thanh công cụ: Back/Forward, kiểu xem (`.segmented` 4 biểu tượng), menu Preset/Chia, ô tìm, nút Shelf, nút Thao tác (đếm
việc), nút Workspace (Lưu/Mở/Quản lý). Cửa sổ nhỏ nhất 720×460.

## Người tích hợp (Claude)

`Views/Detail/FileBrowserDetailView.swift` (trang cài đặt: công tắc bật, mở lại cửa sổ khi mở app, hotkey toàn cục, hiện
tệp ẩn mặc định, thư mục trước, nút Mở trình duyệt), `SidebarDestination.fileBrowser`, `FeatureCatalog` + `IdleCost.onlyWhileOpen`,
`FeatureHub`, `ShortcutCatalog`, deep link `xfinder://browser?path=`, mục menu bar, `applicationShouldTerminate`, khôi phục phiên
lúc khởi động, L10n, harness, pbxproj.
