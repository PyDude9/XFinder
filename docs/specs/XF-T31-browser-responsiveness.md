# XF-T31 — Trình duyệt tệp phản hồi tức thì (đo trên bản cài, 2026-10-26)

**Người dùng vào đây để** duyệt và chọn tệp mà không bao giờ phải chờ cửa sổ "hồi" lại.

## 1. Triệu chứng và số đo

| Khi | Đo (sample(1) bản cài, chủ dự án đang dùng Side by Side trên `~`, 58 mục) | Nguyên nhân đo được |
|:--|:--|:--|
| Mở app | 5 s CPU 100 %, footprint 76 → 318 MB rồi về 119 | parse 70 MB log hook agent trên main thread, `ISO8601DateFormatter` 57 µs/dòng |
| Dùng vài phút | main thread bận 3,3 s / 5,5 s: `NSTableView layout` → `viewFor` 618 mẫu, `NSScrollView _setWindow:` 139 | watcher `~` bắn ~2 lần/phút ⇒ `loadState = .loading` ⇒ cả List bị thay bằng spinner rồi dựng lại; mỗi ô ngày tạo `DateFormatter` (170), mỗi hàng hỏi iCloud qua XPC (~100) |
| Build11 (sau 3 sửa) | main thread bận 9–12 % | `AgentEvents.eventsFileName` tạo `DateFormatter` mỗi sự kiện hook (475/935 mẫu) |

Đối chiếu FileOctopus 1.0.4 cùng máy: footprint 133 MB / đỉnh 257 MB sau 22 h; main thread idle 100 % khi không dùng. Binary của
họ tham chiếu `insertItemsAtIndexes:inParent:withAnimation:`, `removeItemsAtIndexes:…`, `reloadItem:reloadChildren:`,
`beginUpdates`/`endUpdates`, các kiểu `DirectoryLoadCoordinator`, `DirectoryChangeMonitor`, `CloudLookupBatch`,
`MainThreadWatchdog`, `Throttle`, `debounceTask` (đo bằng `strings`/`nm`, không dịch ngược).

## 2. Cơ chế áp dụng (theo thứ tự đã làm)

1. **Khởi động**: log hook đọc nền, `autoreleasepool` từng dòng, ngày giờ bằng số học (`33dd6ec`, `5a4ae31`). Đo: 4,3 s/305 MB → 1,1 s nền/104 MB; khởi động thật 375 → 74 MB đỉnh.
2. **Nạp lại cùng thư mục giữ danh sách** (`LoadRules.isRefresh`, `90ccd0f`): spinner chỉ khi đổi thư mục.
3. **Chi phí mỗi hàng**: một `DateFormatter`; `CloudFactsCache` hỏi thư mục một lần, chỉ hỏi tệp trong thư mục đám mây (`456e090`).
4. **Vá outline tại chỗ** (`ListingDiff`, commit này): cùng thư mục, không nhóm, không tìm kiếm ⇒ `removeItems`/`insertItems` trong
   `beginUpdates`; kept rows đổi thứ tự (resort) hay > 500 thay đổi ⇒ `reloadData`. `PaneState.listingRevision` thay fingerprint
   count/first/last (fingerprint bỏ sót đổi tên giữa danh sách).

## 3. Bảng ca hỏng

| Ca | Kỳ vọng |
|:--|:--|
| Tệp xuất hiện/biến mất trong thư mục đang xem khi đang chọn hàng khác | hàng chọn giữ nguyên, không nháy, không cuộn |
| Đổi tên tệp giữa danh sách (giữ vị trí sắp xếp) | hàng cập nhật tên, không reload toàn bộ |
| Đổi tên làm đổi vị trí | `.reload` (kept rows đổi thứ tự) |
| Đổi tiêu chí sắp xếp | `.reload` |
| Bật Nhóm theo / đang tìm kiếm | đường cũ (`reloadData`) |
| 100 000 tệp, xoá 1 | `ListingDiff.plan` < 0,5 s, vá 1 hàng |
| Thư mục con đang mở rộng bị xoá | watcher của nó bị huỷ, không rò |
| Hai ngăn cùng thư mục | mỗi ngăn vá riêng (chưa chia sẻ listing — Q-T31-1) |

## 4. Nghiệm thu

Test thuần `ListingDiffTests` (6), `LoadRulesTests`, `CloudFactsCacheTests`; harness browser `ListingDiff-01…04`, `LoadRules-01…03`,
`CloudCache-01…05`; harness agents R4–R11. Chạy thật: harness `scratchpad/claude/perf/h2h` (click → chọn, tạo tệp → hàng hiện, xoá →
hàng mất, chọn có giữ) đo cả FileOctopus lẫn XFinder cùng điều kiện; T-T31-1…3 trong pending list.

## 5. Còn lại

- Q-T31-1 `DirectoryLoadCoordinator`: hai ngăn/tab cùng đường dẫn dùng chung một listing + một watcher (refcount). Mặc định: làm sau khi
  h2h cho số.
- Q-T31-2 `CloudLookupBatch`: trong thư mục đám mây, đọc trạng thái theo lô 50 ở nền rồi vẽ badge sau; hiện vẫn đồng bộ trên main cho tệp
  trong thư mục đám mây.
- Q-T31-3 `MainThreadWatchdog` (Debug): ghi log + sample khi main thread > 250 ms để chủ dự án báo lỗi kèm bằng chứng.
- Hoãn nạp lại khi đang kéo/đổi tên (FileOctopus có `Throttle`/`debounceTask`).
