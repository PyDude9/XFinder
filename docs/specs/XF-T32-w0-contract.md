# XF-T32 W0 — contract: hiệu năng lõi của trình duyệt tệp

Spec tổng: `docs/specs/XF-T32-tilde-direction.md` §4 W0, mốc §5. Cơ chế chép từ Tilde (đo trong binary + DB của bản cài,
2026-10-26): `DirectoryListingDiskCache` (SQLite, `validation_token`), `FolderWatcher` + `WatcherBroker` (một watcher
mỗi thư mục, chia sẻ), `DirectoryWorkLimiter` + `DirectoryListingFlightGate`, `FileProjectionActor`,
`MainRunLoopHitchProbe`, `CacheMemoryPressureMonitor`. **Chép cơ chế, không chép code.**

Mỗi builder chỉ sửa **file của mình** (cột File). Tên/chữ ký dưới đây là cố định — không "nếu hợp thì đổi". pbxproj,
symlink test, tích hợp vào `PaneState`/`XFinderApp`, mutation harness là việc của người tích hợp (Claude). Stub của mọi file
đã có trên `main` (biên dịch được); builder thay thân stub, giữ nguyên chữ ký public.

Luật chung: Swift 6 strict; không `@unchecked Sendable`; không `Thread.sleep` trong Task; callback từ DispatchSource/thread
nền → `runOnMainActor`/`Task { @MainActor }`; không `rm` dữ liệu người dùng; mọi chuỗi UI (nếu có) qua `L10n.t` — W0 không có
UI. File thuần = chỉ `import Foundation`, symlink vào `Tests/XFinderLogicTests`, có test. Mỗi builder trả về: tên nhánh
`xf-t32-w0-<key>`, danh sách file, số test, 3 ca hỏng đã xử lý.

## A. Cache listing trên đĩa — builder `cache`

**File**: `XFinder/Core/Browser/ListingCacheRules.swift` (thuần) · `XFinder/Core/Browser/ListingDiskCache.swift` (actor,
`import SQLite3`; khai báo destructor transient **riêng tư** trong file — không dùng global `SQLITE_TRANSIENT` của
`DatabaseService.swift`, vì file này cũng được symlink vào gói test) · test `Tests/XFinderLogicTests/ListingCacheRulesTests.swift`
+ `ListingDiskCacheTests.swift` (DB trong thư mục tạm, không chạm DB thật).

```swift
/// Dấu vân tay của một thư mục lúc liệt kê: `lstat` của chính thư mục. Bằng nhau ⇒ listing trong cache còn đúng.
struct ListingToken: Equatable, Codable, Sendable {
    let modifiedNs: Int64      // st_mtimespec
    let changedNs: Int64       // st_ctimespec
    let size: Int64            // st_size của thư mục
    let inode: UInt64
}

/// Một dòng cache ↔ `DirectoryEntry` (mọi trường lưu trữ của entry; `nameKey` do `DirectoryEntry.init` tính lại).
struct ListingRow: Equatable, Codable, Sendable {
    init(_ entry: DirectoryEntry)
    func entry() -> DirectoryEntry       // round trip chính xác: name, path, kind, isPackage, isHidden, size, modified,
                                         // created, volumeID, hidesExtension, inode, added, lastOpened, tags
}

enum ListingCacheRules {
    static let maxCachedEntries: Int = 20_000        // thư mục lớn hơn không cache (đọc đĩa 101 ms/100 000 là đủ nhanh)
    static let budgetBytes: Int64 = 64 << 20         // tổng cỡ DB mục tiêu
    static let schemaVersion: Int32 = 1
    static func isFresh(stored: ListingToken, current: ListingToken?) -> Bool   // current nil (stat lỗi) ⇒ false
    static func shouldStore(entryCount: Int) -> Bool
    /// Thư mục cần bỏ (cũ nhất trước) để `totalBytes` về ≤ budget; mỗi phần tử (path, updatedAt, bytes).
    static func evictionOrder(folders: [(path: String, updatedAt: Date, bytes: Int64)], totalBytes: Int64) -> [String]
}

actor ListingDiskCache {
    static let shared: ListingDiskCache                 // ~/Library/Application Support/XFinder/Browser/listing-cache.sqlite
    init(databaseURL: URL)                               // probe/test
    /// nil khi không có, hỏng, hay schema khác version (khi đó xoá bảng và làm lại).
    func lookup(_ folderPath: String) -> (token: ListingToken, entries: [DirectoryEntry])?
    /// Thay toàn bộ dòng của thư mục trong MỘT transaction; bỏ qua khi `!shouldStore`; sau đó evict theo budget.
    func store(_ folderPath: String, token: ListingToken, entries: [DirectoryEntry])
    func invalidate(_ folderPath: String)
    func removeAll()
    func approximateBytes() -> Int64                      // page_count × page_size
    nonisolated static func currentToken(for folderPath: String) -> ListingToken?   // lstat, nil khi lỗi
}
```

Bảng: `listing_folders(folder_path TEXT PK, modified_ns, changed_ns, size, inode, item_count, bytes, updated_at)`,
`listing_items(folder_path, sort_order, name, path, kind, is_package, is_hidden, size, modified_ns, created_ns, volume_id,
hides_extension, inode, added_ns, last_opened_ns, tags_json, PK(folder_path, sort_order))`. WAL, `synchronous=NORMAL`,
`PRAGMA user_version`. Thứ tự dòng = thứ tự `entries` lúc `store` (chưa sắp — `PaneState.applyEntries` sắp).

Ca hỏng bắt buộc: DB hỏng/khoá ⇒ `lookup` nil, không crash; thư mục đổi tên (inode khác) ⇒ stale; `tags` nil vs `[]` giữ
nguyên; tên tệp có `\n`/NUL-free Unicode NFD; 20 001 mục ⇒ không lưu; evict khi vượt budget; hai `store` cùng thư mục
song song (actor tuần tự hoá). Probe: 100 000 mục `shouldStore` false; 5 000 mục `store` < 150 ms, `lookup` < 30 ms (đo, ghi số).

## B. Một listing / một watcher mỗi đường dẫn — builder `coordinator`

**File**: `XFinder/Core/Browser/LoadCoordinatorRules.swift` (thuần) · `XFinder/Core/Browser/DirectoryWorkLimiter.swift`
(actor, thuần) · `XFinder/Core/Browser/DirectoryLoadCoordinator.swift` (`@MainActor`, Foundation; dùng `DirectoryReader`,
`DirectoryWatcher`, `ListingDiskCache`, `DirectoryWorkLimiter`) · test `LoadCoordinatorRulesTests.swift`,
`DirectoryWorkLimiterTests.swift`, `DirectoryLoadCoordinatorTests.swift` (thư mục tạm thật, DB cache tạm).

```swift
enum ListingSource: Sendable { case cache, disk }

struct ListingDelivery: Sendable {
    let entries: [DirectoryEntry]
    let source: ListingSource
    let token: ListingToken?
    let isFinal: Bool          // false = bản cache cũ, bản đĩa sẽ tới sau (stale-while-revalidate)
}

enum LoadCoordinatorRules {
    static let diskReadConcurrency: Int = 4
    enum Decision: Equatable { case deliverCache(final: Bool), readDisk }
    /// Quyết định khi có người đăng ký mới: có cache + token khớp ⇒ [.deliverCache(final: true)];
    /// có cache + lệch ⇒ [.deliverCache(final: false), .readDisk]; không cache ⇒ [.readDisk].
    static func plan(hasCache: Bool, stored: ListingToken?, current: ListingToken?) -> [Decision]
    /// Sổ đăng ký thuần: subscribe/unsubscribe theo đường dẫn, trả về .started (phiên mới) / .joined / .left / .closed.
    struct SessionBook: Equatable { mutating func subscribe(path: String, id: UUID) -> Event; mutating func unsubscribe(path: String, id: UUID) -> Event; func count(path: String) -> Int; enum Event: Equatable { case started, joined, left, closed, unknown } }
}

actor DirectoryWorkLimiter {
    static let shared: DirectoryWorkLimiter               // maxConcurrent = diskReadConcurrency
    init(maxConcurrent: Int)
    /// FIFO; tối đa `maxConcurrent` thân chạy cùng lúc; huỷ Task đang chờ ⇒ thân không chạy.
    func run<T: Sendable>(_ body: @Sendable @escaping () async -> T) async -> T
    func inFlight() -> Int
}

@MainActor final class ListingSubscription {
    func cancel()          // idempotent; deinit cũng cancel
}

@MainActor final class DirectoryLoadCoordinator {
    static let shared: DirectoryLoadCoordinator
    init(cache: ListingDiskCache, limiter: DirectoryWorkLimiter, watcherFactory: @escaping @MainActor (String, @escaping @MainActor () -> Void, @escaping @MainActor () -> Void) -> DirectoryWatcher?)
    /// Đăng ký nhận listing của `path`. Người đăng ký sau nhận ngay bản đã giao gần nhất (nếu có) rồi các bản sau.
    func subscribe(path: String,
                   onListing: @escaping @MainActor (Result<ListingDelivery, DirectoryReadError>) -> Void,
                   onGone: @escaping @MainActor () -> Void) -> ListingSubscription
    /// Đọc đĩa lại cho mọi người đăng ký (⌘R, sau một thao tác tệp); gộp nếu đang đọc.
    func reload(path: String)
    func activeSessionCount() -> Int
}
```

Hành vi: phiên theo `path` (chuẩn hoá `standardizingPath`); người đầu tiên ⇒ `plan` → giao cache (nếu có) ngay trên main
→ nếu cần, đọc đĩa qua `limiter.run { DirectoryReader.list(path, timeout: 5) }` → giao `.disk` → `cache.store` nền.
Watcher (một, qua `watcherFactory`) `onChange` ⇒ `reload`; `onGone` ⇒ mọi `onGone` + đóng phiên. Đọc đang bay + `reload`
⇒ đánh dấu "cần đọc lại" và đọc tiếp sau, không chồng. Lỗi đĩa ⇒ giao `.failure` (kể cả khi vừa giao cache). Người cuối
huỷ ⇒ huỷ watcher + Task + xoá phiên. Log một dòng mỗi lần giao: `Logger(subsystem: "com.xfinder.app", category:
"listing").info("<path> source=cache|disk count=N ms=M")` — harness đo đọc dòng này.

Ca hỏng bắt buộc: hai pane cùng `~` ⇒ 1 `DirectoryReader.list`, 1 watcher (đếm bằng factory giả); subscribe rồi cancel
trước khi đọc xong ⇒ không callback; `onGone` ⇒ không giao thêm; `reload` ×5 trong 10 ms ⇒ ≤ 2 lần đọc; đường dẫn có `/..`
chuẩn hoá về một phiên; thư mục 5 s timeout ⇒ `.timedOut` giao đúng.

## C. Đo giật main thread — builder `hitch`

**File**: `XFinder/Core/Browser/HitchRules.swift` (thuần) · `XFinder/Core/Browser/MainThreadHitchProbe.swift` ·
test `HitchRulesTests.swift`.

```swift
enum HitchRules {
    static let pingInterval: TimeInterval = 0.1
    static let threshold: TimeInterval = 0.25
    static let maxSamplesPerHour: Int = 3
    struct Hitch: Equatable, Sendable { let at: Date; let latency: TimeInterval }
    static func isHitch(latency: TimeInterval) -> Bool
    /// Có được chạy `sample` cho hitch này không, cho trước các lần đã sample trong 1 h.
    static func shouldSample(now: Date, previousSamples: [Date]) -> Bool
    static func pruned(_ hitches: [Hitch], keep: Int = 50) -> [Hitch]
}

final class MainThreadHitchProbe: @unchecked Sendable   // KHÔNG: dùng OSAllocatedUnfairLock cho trạng thái, không @unchecked
@MainActor final class MainThreadHitchProbe {
    static let shared: MainThreadHitchProbe
    func start()          // #if DEBUG: thread nền ping main mỗi pingInterval; Release: no-op
    func stop()
    var recent: [HitchRules.Hitch] { get }
    var onHitch: ((HitchRules.Hitch) -> Void)?   // bảng Diagnostics nối vào
}
```

Khi hitch: `Logger(subsystem: "com.xfinder.app", category: "hitch").warning("main thread hitch \(ms) ms")`; nếu
`shouldSample` ⇒ chạy `/usr/bin/sample <pid> 1 -file ~/Library/Application Support/XFinder/Diagnostics/hitch-<ISO>.txt` từ
queue nền (đọc pipe trước `waitUntilExit`). Ca hỏng: máy ngủ/thức (latency khổng lồ một lần ⇒ bỏ qua nếu > 30 s);
`stop()` khi đang ping; không giữ `self` mạnh trong thread.

## D. Xả cache khi thiếu RAM — builder `pressure`

**File**: `XFinder/Core/Browser/PressureRules.swift` (thuần) · `XFinder/Core/Browser/MemoryPressureRelief.swift` ·
test `PressureRulesTests.swift`.

```swift
enum PressureRules {
    enum Level: Equatable, Sendable { case warning, critical }
    /// Kế hoạch xả theo mức: warning ⇒ giữ 50 % cache ảnh/thumbnail, bỏ phiên listing không ai đăng ký;
    /// critical ⇒ 0 % + xoá cache icon theo đường dẫn.
    struct Plan: Equatable { let keepFraction: Double; let dropIdleSessions: Bool; let dropPathIcons: Bool }
    static func plan(for level: Level) -> Plan
    static func level(fromDispatchMask raw: UInt) -> Level?   // DispatchSource.MemoryPressureEvent.rawValue
}

@MainActor final class MemoryPressureRelief {
    static let shared: MemoryPressureRelief
    func start()      // DispatchSource.makeMemoryPressureSource([.warning, .critical], queue: .main)
    func register(_ name: String, _ reliever: @escaping @MainActor (PressureRules.Plan) -> Void)
    func simulate(_ level: PressureRules.Level)    // test/Diagnostics
    private(set) var lastRelief: (level: PressureRules.Level, at: Date)?
}
```

Người tích hợp nối: `FileIconCache`, cache thumbnail Dock preview (`LRUThumbnailCache`), `DirectoryLoadCoordinator`
(phiên không người đăng ký), `CloudFactsCache` của các view (qua `register`).

## Nghiệm thu W0 (người tích hợp đo trên bản cài)
- Mở lại thư mục 58 mục đã mở: dòng log `source=cache` với `ms` ≤ 30; 5 000 mục ≤ 60.
- Side by Side cùng `~`: 1 dòng `source=disk` mỗi lần thay đổi (không phải 2).
- Tạo tệp ở `~` ⇒ hàng hiện ≤ 500 ms (h2h `watcher_add`).
- 10 phút dùng thường: 0 dòng `hitch` ≥ 250 ms (bản Debug).
- Mutation: ≥ 3 mutant mỗi file thuần, tất cả RED.
