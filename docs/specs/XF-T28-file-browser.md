# XF-T28 — Trình duyệt tệp (Finder nhiều ngăn, nhanh hơn)

> Chủ dự án 2026-10-24: "Cập nhật thêm tính năng App Finder cho tôi giống app FileOctopus nhưng cải thiện tối ưu tốc độ"
> (kèm prompt PRD: 4 kiểu xem, tới 16 ngăn, thanh đường dẫn có chevron, command palette, tìm kiếm ngôn ngữ tự nhiên +
> chip, Shelf, Workspaces, hàng đợi copy/move an toàn, đổi tên hàng loạt, ZIP, đám mây, phân tầng Free/PRO).
> Luật CLAUDE.md §1 "làm y X": chép **cơ chế + vị trí**, không chép code; đo trước. Bằng chứng: `docs/FILEOCTOPUS_EVIDENCE_2026-10-24.md`
> (4 agent, 2026-10-24) — tài liệu FileOctopus 1.0.3, kiểm toán tái dùng XFinder, số đo API trên máy này, checklist Finder.

## 0. Câu việc

**"Tôi duyệt, gom và chép tệp giữa nhiều thư mục trong MỘT cửa sổ — như Finder, nhưng chia được nhiều ngăn, tìm bằng một
câu thường, và không bao giờ mất dữ liệu khi chép/di chuyển."**

Không phải câu việc: thay Finder làm trình quản lý mặc định của hệ thống (không đụng `NSFileViewer`/LaunchServices).

## 1. Đo trước khi viết (2026-10-24, M3 Pro, macOS 27.0.1, APFS)

| Cơ chế | Số đo | Hệ quả |
|:--|:--|:--|
| Liệt kê 100 000 tệp có thuộc tính | `getattrlistbulk` **97 ms** · `fts` 110 ms · `readdir+lstat` 216 ms · `FileManager.contentsOfDirectory` 813 ms | engine = `getattrlistbulk`; FileManager **giấu `._*`** (positive control: 2/3 tệp) |
| Liệt kê 20 000 | `getattrlistbulk` 20 ms · FileManager 166 ms | |
| Báo thay đổi thư mục | `DispatchSource` fd **0,52 ms** · `FSEventStream` 11,9 ms | DispatchSource cho ngăn đang hiện; FSEvents không cần ở v1 |
| `copyfile` + `COPYFILE_STATE_STATUS_CB` | 1 GiB ≈ 1,1 GB/s; chặn trong callback **tạm dừng được** (500 ms đo 505 ms); `COPYFILE_QUIT` ⇒ `ECANCELED`, **không để tệp dở** | pause = chặn worker trong callback; huỷ = QUIT |
| Clone APFS | `copyfile(COPYFILE_ALL)` **không** tự clone (115 ms/256 MiB); `+COPYFILE_CLONE` 0,16 ms; `FileManager.copyItem` clone | cùng volume: truyền `COPYFILE_CLONE` |
| Kiểm bản sao | SHA-256 2 360 MB/s ≈ so byte 2 256 MB/s (positive control: lệch 1 byte bị bắt) | verify = SHA-256 theo khúc 4 MiB |
| Icon | `icon(forFile:)` 0,06 ms/tệp; cache theo UTType 0,0002 ms; QL thumbnail 5–7 ms/ảnh | icon theo UTType (từ phần mở rộng), riêng gói/app theo đường dẫn; thumbnail chỉ cho ô đang hiện |
| Đám mây iCloud | tệp chưa tải: `isUbiquitousItem=true`, `NotDownloaded`, size 183 024, alloc 0 | đọc badge bằng `URLResourceValues`, không tải gì |
| Đám mây OneDrive | thư mục gốc chỉ có xattr `com.apple.file-provider-domain-id`; **không có tệp thật trên máy ⇒ chưa đo** | T-T28-9; không tuyên bố "không có API" |
| Google Drive / Dropbox | không cài trên máy | Q-T28-6 |
| Chặn đẩy ổ (DiskArbitration) | ổ RAM của probe: `DARegisterDiskUnmountApprovalCallback`/`…EjectApprovalCallback` trả dissenter ⇒ `diskutil unmount` **exit 1** "failed to unmount: 'XFinder: a file operation is running' (PID …)", `diskutil eject` exit 1; positive control: không dissenter thì unmount chạy; không cần entitlement | khớp theo **đường dẫn volume** (`kDADiskDescriptionVolumePathKey`), không theo tên BSD (volume APFS là `disk7s1`, đĩa vật lý `disk6` — đo) |
| `QLThumbnailGenerator` giữ bộ nhớ? | 60 thumbnail: +3,7 MB, sau 10 s không đổi (dựng ngoài tiến trình) | dùng trong app được (khác Vision) |
| Tìm (FileOctopus tự công bố) | "0,27 s vs 7,7 s" trên 146 000 tệp, M3 Max | mục tiêu §6: ≤ 0,3 s và đo cùng cách |

## 2. Phạm vi

### 2.1 v1 (bản này)

1. **Cửa sổ** "Trình duyệt tệp": nhiều cửa sổ (⌘N), mở từ menu bar, trang cài đặt, deep link
   `xfinder://browser?path=<p>`, phím tắt toàn cục tuỳ chọn (mặc định **tắt**, trong `ShortcutCatalog`).
2. **Sidebar**: Mục ưa thích (Home, Desktop, Tài liệu, Tải về, Ứng dụng), Vị trí (ổ đĩa đã gắn + mọi thư mục trong
   `~/Library/CloudStorage` + iCloud Drive), có nút đẩy ổ ra (bị chặn khi có thao tác chạy trên ổ đó).
3. **Ngăn**: cây chia tối đa **16** ngăn; preset Một · Cạnh nhau · Chồng · Lưới 2×2; chia Phải/Trái/Dưới/Trên
   (⌃⌥⌘→/←/↓/↑); đóng ngăn ⌃⌥⌘W; kéo vạch chia; Bằng nhau ⌃⌥⌘=; **phóng to ngăn ⇧⌘↩** (lần nữa trả đúng bố cục cũ);
   ngăn kế/trước ⌃⌘] / ⌃⌘[; nút Back/Forward chuột và vuốt tác động **ngăn dưới con trỏ**.
4. **Bốn kiểu xem** mỗi ngăn: Danh sách (NSTableView, cột Tên/Ngày sửa/Cỡ/Loại, sắp xếp, tam giác mở thư mục **v2**),
   Biểu tượng (NSCollectionView), Cột (NSBrowser), Gallery (xem trước lớn + dải thumbnail). ⌘1–⌘4.
5. **Thanh đường dẫn** mỗi ngăn: breadcrumb, đoạn giữa gộp "…" khi hẹp; bấm đoạn = mở; chevron `▸` sau mỗi đoạn = menu
   thư mục con (Đang tải… / danh sách / Không có thư mục / Không xem được); chuột phải: Mở · Mở ở ngăn kia · **Sao chép
   đường dẫn** · Hiện trong Finder; ⌃⌘L hoặc bấm chỗ trống = gõ đường dẫn (Tab hoàn thành, ↑↓ chọn, Return mở); ⇧⌘G.
6. **Thao tác như Finder** (checklist §5): Return đổi tên (chọn phần tên, không đuôi), ⌘O/⌘↓ mở, ⌘↑ lên (chọn lại thư
   mục vừa rời), ⌘[ ⌘] lịch sử **theo ngăn**, ⌘⌫ vào Thùng rác, ⌘D nhân bản ("tên copy", "tên copy 2"), ⇧⌘N thư mục mới,
   Space/⌘Y Quick Look (nhiều tệp, ←→ chuyển), gõ để chọn (bộ đệm 1 s), ⇧⌘. hiện tệp ẩn, ⌥⌘C sao chép đường dẫn,
   ⌘C rồi ⌘V chép / ⌥⌘V di chuyển, kéo thả: cùng ổ = di chuyển, khác ổ = chép, ⌥ ép chép, ⌘ ép di chuyển.
7. **Lọc thư mục hiện tại** (⌘F lần đầu khi đang ở ô lọc… xem §2.3): lọc trong bộ nhớ, không quét thư mục con, mỗi phím
   ≤ 16 ms cho 100 000 mục.
8. **Tìm kiếm** (⌥⌘F): câu thường → **chip sửa được** (loại · thời gian · cỡ · nguồn tải · tạo/sửa) + cú pháp nâng cao
   (`ext:` `kind:` `size:` `modified:` `created:` `from:` `tag:` `content:` `"cụm"` `-loại_trừ`); phạm vi Thư mục này /
   Máy này / Các ngăn đang mở; chạy `mdfind` qua `NulRecords` (dừng sớm), `content:` dùng **chỉ mục Spotlight**
   (`kMDItemTextContent`) — không có chỉ mục riêng, không tốn gì lúc nghỉ.
9. **Hàng đợi thao tác**: chép/di chuyển/nhân bản/vào Thùng rác chạy **một việc một lúc** theo thứ tự; tạm dừng/tiếp tục
   tại chỗ **chỉ trong pha chép** (pha Kiểm/Hoàn tất: nút Tạm dừng tắt — `canPause`); Tạm dừng tất cả; đổi thứ tự việc chờ (Chạy kế tiếp/Lên/Xuống); tiến độ + tốc độ + ETA; hộp thoại trùng tên;
   **di chuyển khác ổ có kiểm**: chép → SHA-256 → đưa bản gốc vào Thùng rác (Q-T28-4); chặn thoát app và chặn đẩy ổ khi
   đang chạy; nhật ký thao tác ⇒ lần mở sau có **báo cáo khôi phục** cho việc bị cắt ngang.
10. **Chép/di chuyển sang ngăn kia** ⌃⇧⌘C / ⌃⇧⌘M (2 ngăn: ngăn còn lại; ≥ 3: ngăn kế theo thứ tự), không đổi tiêu điểm.
11. **Shelf** dưới đáy cửa sổ (⌥⌘B bật/tắt): kéo vào hoặc "Thêm vào Shelf" (⌃⌘S); giữ **tham chiếu**, theo cửa sổ;
    tổng số mục + dung lượng; Chép vào ngăn đang chọn · Di chuyển vào ngăn đang chọn · Đổi tên hàng loạt · Bỏ · Xoá hết.
12. **Workspaces**: Lưu / Mở / Đổi tên / Nhân bản / Xoá / Xuất JSON; **tự khôi phục** cửa sổ + cây ngăn + thư mục + lịch
    sử Back khi mở lại (thư mục đã mất ⇒ bỏ qua, không gắn ổ); **giữ Shift khi mở** ⇒ cửa sổ trống.
13. **Command palette**: ⌃⌘P Quick Open (thư mục gần đây, mục ưa thích, ngăn đang mở, workspace); gõ `>` hoặc ⌃⇧⌘P =
    chỉ lệnh, kèm phím tắt, chỉ lệnh đang dùng được.
14. **Đổi tên hàng loạt** (⌃⌘R): tái dùng `BatchRenameEngine` (xem trước TOÀN BỘ, va chạm chặn nút); **Nén ZIP** tái
    dùng `ArchiveRunner` (kiểm danh sách sau khi nén); cả hai **⌘Z** qua `ActionHistoryStore` (ZIP: ⌘Z đưa tệp ZIP vào
    Thùng rác).
15. **Đám mây**: badge ở cả 4 kiểu xem (chỉ trên mây · đang tải xuống/lên · lỗi tải xuống/lên), không bao giờ tự tải;
    menu Tải về ngay (`startDownloadingUbiquitousItem`) · Gỡ bản tải (`evictUbiquitousItem`, chỉ khi đã lên mây), cả
    nhiều tệp.

### 2.2 v2 (spec riêng, không làm ở đây)

Tab trong từng ngăn · tam giác mở trong Danh sách · Get Info riêng · chỉ mục nội dung/OCR riêng cho thư mục chọn
(Spotlight đã có `kMDItemTextContent`) · tìm kiếm đã lưu · gộp thư mục (Merge…) · "Mở trong Google Drive"/"Sao chép
liên kết" (Q-T28-6) · tiếp tục việc tạm dừng sau khi mở lại app.

### 2.3 Phím — bảng lệnh MỘT nơi

Mọi phím trong cửa sổ đi qua `BrowserCommands` (thuần) → `performKeyEquivalent` của cửa sổ, **không** qua menu chính
(XFinder có thể chạy `.accessory`, không có thanh menu — đo `DockController`). Cùng bảng nuôi palette `>` và toolbar.
⌘F = lọc thư mục hiện tại (như FileOctopus "Filter Current Folder" không có phím riêng — chọn ⌘F vì việc hay làm nhất);
⌥⌘F = tìm kiếm. Q-T28-3.

## 3. Kiến trúc (fan-out theo file — luật 18)

Thuần (Foundation, symlink vào `Tests/`, không `import SwiftUI`/AppKit):

| File | Nội dung |
|:--|:--|
| `Core/Browser/PaneTree.swift` | cây chia (lá = PaneID, nút = trục + 2 con + tỉ lệ), split/close/preset/zoom/equalize/resize/next/prev/other, Codable |
| `Core/Browser/PaneHistory.swift` | Back/Forward theo ngăn (≤ 50), nhớ thư mục con để chọn lại khi ⌘↑, Codable |
| `Core/Browser/BrowserPath.swift` | breadcrumb từ đường dẫn, gộp "…", phân tích ô gõ đường dẫn (~, tương đối), lọc gợi ý Tab |
| `Core/Browser/DirectoryEntry.swift` | `DirectoryEntry`, sắp xếp (tên tự nhiên `localizedStandardCompare`, ngày, cỡ, loại), lọc thư mục hiện tại, gõ-để-chọn, ẩn/hiện |
| `Core/Browser/SearchQuery.swift` | câu thường + cú pháp → `[SearchChip]` + từ tên → biểu thức `mdfind`; sửa/xoá chip |
| `Core/Browser/FileOperationRules.swift` | tên Keep Both / nhân bản, cùng ổ hay khác ổ, chặn lồng vào chính nó, máy trạng thái hàng đợi, nhật ký + báo cáo khôi phục, tiến độ/ETA |
| `Core/Browser/BrowserWorkspace.swift` | ảnh chụp bố cục Codable, kho workspace (lưu/đổi tên/nhân bản/xoá/xuất), luật khôi phục |
| `Core/Browser/BrowserCommands.swift` | bảng lệnh (id, nhãn = khoá L10n, phím), so khớp mờ palette, tiền tố `>` |
| `Core/Browser/CloudBadge.swift` | giá trị tài nguyên → badge + hành động được phép |
| `Core/Browser/ShelfModel.swift` | danh sách tham chiếu, chống trùng, tổng dung lượng, mục mất |

AppKit/SwiftUI (người tích hợp viết stub trước, mỗi agent thay đúng file của mình):
`Core/Browser/DirectoryReader.swift` (getattrlistbulk + DispatchSource), `Core/Browser/FileOperationQueue.swift`
(copyfile worker, verify, nhật ký, chặn thoát/đẩy ổ qua DiskArbitration), `Core/Browser/BrowserWindowModel.swift`
(@Observable trạng thái cửa sổ), `Core/Browser/BrowserWindowController.swift` (cửa sổ, phím, phiên, Quick Look),
`Core/Browser/FileIconCache.swift`, `Views/Browser/*` (root, lưới ngăn, danh sách, biểu tượng, cột, gallery, thanh
đường dẫn, chip, Shelf, bảng thao tác, hộp thoại trùng tên, palette, đổi tên hàng loạt), `Views/Detail/FileBrowserDetailView.swift`.

Đủ 8 thứ (CLAUDE.md §2): catalog `.fileBrowser` (`fileBrowser.enabled`, mặc định **bật**, không quyền bắt buộc —
Truy cập toàn ổ đĩa chỉ là gợi ý khi gặp thư mục bị chặn; IdleCost **mới** `onlyWhileOpen` "Chỉ chạy khi cửa sổ đang
mở": mỗi ngăn đang hiện có một DispatchSource, đóng cửa sổ là hết — `nothingAtRest` sẽ là khai sai, `watchesWindows`
cũng sai; `isBackgroundActive = false` vì khi không mở cửa sổ không có gì chạy; hotkey toàn cục mặc định tắt và có hàng
`ShortcutCatalog` để trang Phím tắt bắt trùng) · reader · view · FeatureKeyDefaults · FeatureContract `.pure([...10 file])` · FeatureHub ·
L10n `scripts/add-file-browser-l10n-entries.py` · harness `scripts/mutation-check-browser.sh`.

## 4. Ca hỏng

| Ca | Trả lời |
|:--|:--|
| Thư mục 100 000 tệp | liệt kê nền (getattrlistbulk), hàng đầu hiện ≤ 150 ms, cuộn mượt (NSTableView tái dùng ô), icon theo UTType |
| Thư mục bị TCC chặn (Desktop/Documents/khác) | báo trong ngăn "XFinder chưa được phép đọc thư mục này" + nút mở Cài đặt; không treo |
| Ổ mạng chậm / mất kết nối giữa chừng | mọi đọc đĩa ngoài main; hết 5 s ⇒ ngăn báo lỗi, ngăn khác vẫn chạy |
| Thư mục bị xoá/đổi tên khi đang mở | watcher báo ⇒ ngăn lên thư mục cha còn tồn tại gần nhất |
| `._*`, tệp ẩn | hiện đúng như Finder (ẩn theo cờ hidden + dấu chấm, ⇧⌘. bật); không dùng FileManager để liệt kê |
| Gói (.app, .pages) | hiện như tệp, mở bằng app; không đi vào trừ "Hiện nội dung gói" |
| Symlink / alias | symlink theo đích khi mở; alias Finder mở qua `NSWorkspace` |
| Kéo thư mục vào chính nó/con của nó | bị chặn trước khi xếp hàng |
| Trùng tên khi chép | hộp thoại: bản nào mới hơn (≥ 1 s; FAT/exFAT ≥ 2 s), **Giữ cả hai (Return, mặc định)** · Bỏ qua · Thay thế (phá huỷ, đỏ) · Dừng (Esc) · Áp dụng cho tất cả |
| Thay thế thư mục bằng tệp hoặc ngược lại | không cho Thay thế, chỉ Giữ cả hai/Bỏ qua |
| Di chuyển khác ổ, SHA-256 lệch | bản gốc giữ nguyên, bản đích vào Thùng rác, báo lỗi |
| App bị kill giữa lúc chép | nhật ký còn "đang chạy" ⇒ lần mở sau: báo cáo liệt kê mục cần xem lại; không tự làm lại |
| Đầy đĩa | dừng việc, báo tiếng thường + chi tiết mã lỗi; "Thử lại" chỉ khi chưa ghi gì ở đích |
| Tạm dừng rồi tệp nguồn đổi | báo, không chép bản đã đổi giữa chừng |
| Thoát app khi có việc chạy | hỏi: Đợi / Dừng việc và thoát |
| Đẩy ổ khi có việc chạy trên ổ đó | từ chối (DiskArbitration dissent) + thông báo |
| Tệp iCloud chưa tải | badge đám mây; đọc cỡ/ngày không tải; Quick Look có thể tải (như Finder) |
| 17 ngăn | lệnh chia bị tắt ở 16 |
| Phóng to ngăn rồi đóng ngăn đó | thoát chế độ phóng, cây còn lại giữ nguyên |
| Khôi phục phiên, thư mục đã mất | ngăn mở Home, báo một dòng |
| Workspace JSON hỏng | bỏ qua bản hỏng, giữ các bản khác, báo |
| Tìm "pdf" số ít | là từ tên tệp (như FileOctopus); "pdfs"/`kind:pdf` mới là loại |
| "over 5" không đơn vị | không thành chip cỡ, giữ là từ |
| Đổi tên có ":" hoặc "/" | từ chối với lý do (Finder hiện ":" thành "/") |
| Return trên nhiều mục | không đổi tên (như Finder) |
| ⌘⌫ | luôn Thùng rác, không bao giờ xoá hẳn |
| Đổi tên hàng loạt có va chạm | nút Đổi tên bị tắt, hàng va chạm tô đỏ |
| Quick Look khi đổi lựa chọn | panel theo lựa chọn mới |
| Bộ nhớ | đóng cửa sổ ⇒ không còn watcher; cache icon ≤ 512 mục; thumbnail chỉ ô đang hiện |
| Bấm Tạm dừng khi đang Kiểm (SHA-256) tệp 50 GB | nút đã tắt từ khi vào pha Kiểm; Dừng vẫn được (bản đích vào Thùng rác, gốc nguyên) |
| Bị kill đúng lúc đang đưa bản gốc vào Thùng rác | pha nhật ký `trashing` ⇒ báo cáo "Bản gốc có thể đã vào Thùng rác — kiểm tra" (không nói "vẫn còn") |
| `content:` trong thư mục Spotlight không lập chỉ mục (ngoài volume chỉ mục, danh sách Riêng tư, bị TCC) | 0 kết quả kèm một dòng "Spotlight có thể chưa lập chỉ mục nội dung ở đây", không im lặng như "không có" |

## 5. Checklist Finder phải giữ

Bảng phím và 25 ca hỏng: `docs/FILEOCTOPUS_EVIDENCE_2026-10-24.md` §4 ("Top 25") — chép phần v1 vào test tay T-T28-*.

## 6. Nghiệm thu (đo, không ước)

- Thuần: mọi file §3 có test; harness `mutation-check-browser.sh` mọi mutation đỏ.
- **Tốc độ** (probe trên bản cài, cùng máy, trung vị 5 lần sau 1 lần làm nóng — ghi rõ là đo nóng): liệt kê 100 000 tệp
  tới khi model có đủ mục ≤ 150 ms; lọc 100 000 mục ≤ 16 ms/phím; tìm "pdfs from last week" phạm vi Máy này ≤ 0,3 s tới
  100 kết quả đầu — chỉ đo khi chỉ mục Spotlight đã ổn định (số kết quả `mdfind -count` bằng nhau hai lần cách 5 s), ghi
  kèm số lần đầu (lạnh); mở cửa sổ ≤ 300 ms.
- Bộ nhớ: metric `footprint` (không phải vmmap dirty). Đo trước khi mở; mở 4 ngăn × 20 000 tệp ở Danh sách + 1 ngăn
  Gallery 60 ảnh; đóng cửa sổ; đợi 10 s; footprint ≤ trước + 10 MB.
- Hàng đợi: probe e2e trên thư mục thử — chép 1 GiB, tạm dừng/tiếp tục, huỷ không để tệp dở, trùng tên ra hộp thoại,
  di chuyển khác ổ (cần ổ thứ hai — ổ RAM `hdiutil attach -nomount ram://` trong scratchpad) có SHA-256.

## 7. Q / T

- **Q-T28-1** Free/PRO: XFinder không có hệ thống giấy phép ⇒ **mặc định mọi thứ miễn phí, 16 ngăn cho tất cả**; muốn
  phân tầng thì cần cơ chế giấy phép riêng (spec khác).
- **Q-T28-2** Tên/vị trí: "Trình duyệt tệp", trang trong FINDER & TÌM KIẾM, mục menu bar, hotkey toàn cục mặc định tắt.
- **Q-T28-3** ⌘F = lọc thư mục hiện tại, ⌥⌘F = tìm kiếm (FileOctopus: ⌘F = Find).
- **Q-T28-4** Di chuyển khác ổ đã kiểm: bản gốc vào **Thùng rác** (luật 9) thay vì xoá hẳn như FileOctopus.
- **Q-T28-5** Giữ macOS 14 (FileOctopus đòi 15).
- **Q-T28-6** Google Drive/Dropbox không cài trên máy: "Mở trong Google Drive"/"Sao chép liên kết" cần đo xattr của
  Drive (`com.google.drivefs.*`) trên máy có Drive — v2.
- **T-T28-1** Mở trình duyệt từ menu bar; chia 4 ngăn (Lưới), ⇧⌘↩ phóng/trả; kéo vạch chia.
- **T-T28-2** Thư mục 100 000 tệp (tạo: `python3 -c "import os; d='/tmp/xf-browser-100k'; os.makedirs(d, exist_ok=True); [open(f'{d}/f{i:06d}.dat','w').close() for i in range(100000)]"`): mở, cuộn, ⌘F lọc "999".
- **T-T28-3** Chép 1 GiB giữa hai ngăn ⌃⇧⌘C, tạm dừng/tiếp tục; trùng tên ⇒ hộp thoại, Return = Giữ cả hai.
- **T-T28-4** Tìm "pdfs from last week" và "ảnh hôm nay" ⇒ chip; xoá chip ⇒ kết quả rộng ra.
- **T-T28-5** Shelf: gom 3 tệp từ 2 ngăn, Chép vào ngăn đang chọn.
- **T-T28-6** Lưu workspace, thoát XFinder, mở lại ⇒ đủ cửa sổ/ngăn/thư mục; mở lại giữ Shift ⇒ cửa sổ trống.
- **T-T28-7** ⌃⌘P gõ tên thư mục; `>` "new folder".
- **T-T28-8** Đổi tên hàng loạt 10 tệp, ⌘Z; Nén ZIP, ⌘Z.
- **T-T28-9** Tệp OneDrive/iCloud chưa tải ⇒ badge; Tải về ngay; Gỡ bản tải.
- **T-T28-10** 25 ca Finder (`docs/FILEOCTOPUS_EVIDENCE_2026-10-24.md` §4 "Top 25") — phần v1.

## 8. Review spec + hợp đồng (2026-10-24, 3 góc × 2 người phản bác, 37 agent)

17 phát hiện → **11 giữ, 6 bác**. Đã sửa: `CGRect` cần `import CoreGraphics` (tái hiện: Foundation một mình không biên
dịch) · `PaneID` khai `<` (struct không tự sinh Comparable — tái hiện) · `replacing(id:with:in:)` (bản cũ tự mâu thuẫn với
`id` theo giá trị) · sắp cột Loại theo tên loại đã dịch (`kindName`), không theo đuôi · hotkey toàn cục vào `ShortcutCatalog`
· chặn đẩy ổ **đã đo** (§1) · pha nhật ký `trashing` · `canPause` (tắt nút khi Kiểm/Hoàn tất) · giao thức đo bộ nhớ và
tìm kiếm (§6) · `content:` 0 kết quả có cảnh báo · IdleCost `onlyWhileOpen`. Bác: hai phím cho một lệnh (đã có ⌘↓ qua
`command(for:)`), id chip trùng field, gộp thư mục (v2 + Giữ cả hai/Bỏ qua), type-select vòng lại, khoá L10n qua biến (đã có
luật test từ vựng). Dữ liệu: output workflow `xf-t28-spec-review`.

## 9. Gộp với trang cũ + phần còn thiếu + bẫy từ changelog FileOctopus (2026-10-24, Wave 4)

Chủ dự án: "một số tính năng trùng lặp có thể gộp luôn, nếu FileOctopus hiển thị trực quan hơn settings của XFinder cũ,
ví dụ Folder Sync, Remote Control". Đo: FileOctopus **không** có sync/remote (trang limitations của họ); Remote Connect của
XFinder là `scp`/`ssh` tải lên (không gắn ổ).

> **CHỈ LÀ ĐỀ XUẤT — chưa làm.** Chủ dự án 2026-10-24: "nếu bạn đổi nhiều thì phải hỏi ý tôi list gộp trước, ko được gộp
> hết tất cả vào trang Finder này". Mỗi dòng dưới đây chờ chủ dự án duyệt (Q-T28-MERGE); dòng nào không được duyệt thì
> trang cũ giữ nguyên, trình duyệt không thêm lối vào đó.

| Trang | Trong trình duyệt | Trang cũ |
|:--|:--|:--|
| Đồng bộ thư mục | nhóm sidebar "Đồng bộ": mỗi cặp ⇒ bố cục 2 ngăn nguồn \| đích + nút "Đồng bộ ngay" gọi CÙNG hàm của `FolderSyncController`; badge trên thư mục nguồn | giữ (cấu hình lịch, xoá phần thừa) |
| Kết nối từ xa | chuột phải "Tải lên ‹đích›" gọi `RemoteConnectController` | giữ (cấu hình máy) — gắn ổ mạng là tính năng mới, Q-T28-7 |
| Chia sẻ nhanh | lệnh "Chia sẻ qua QR" | giữ (thu hồi, hạn) |
| Đổi tên hàng loạt, Nén | sheet/lệnh trong trình duyệt (cùng engine) | giữ + `SettingsLinkRow` "Mở trong Trình duyệt tệp"; deep link `.batchRename` vẫn chạy |
| Tìm kiếm AI / Tìm kiếm | thanh tìm + chip (⌥⌘F) | thêm liên kết sang trình duyệt; phần Tìm nhanh ⌘K giữ |
| Dọn rác | lệnh "Dọn rác thư mục này" trên thư mục | giữ |
| Khay thả (notch) | lệnh "Gửi vào Khay thả" từ Shelf | giữ — Shelf theo cửa sổ, Khay thả lâu dài; KHÔNG gộp |
| Tiện ích Finder (ẩn/hiện tệp của Finder) | — | thêm câu phân biệt: ⇧⌘. của trình duyệt không đổi cài đặt Finder |

Còn thiếu so với FileOctopus 1.0.3 (phạm vi của chính trình duyệt — đề xuất Wave 4, cũng chờ duyệt): **Get Info** (⌘I: Chung · Thêm thông tin · Tên & đuôi · Thẻ ·
Chia sẻ & quyền; cỡ thư mục tính nền; ổ: định dạng/dung lượng/điểm gắn) · **Cài đặt ▸ Bàn phím** (mỗi lệnh: phím + phím
phụ + mặc định, ghi phím, chặn phím hệ thống/Return/Space/Tab/mũi tên, profile Finder/Windows Explorer/Total Commander,
xuất/nhập JSON có kiểm) · **tuỳ biến sidebar** (nhóm, đổi tên hiển thị, ẩn ổ — schema có phiên bản từ đầu) · **danh sách
Problems** có Thử lại · **thư mục gần đây** + giữ Back/Forward để hiện danh sách · **nút chuột 4/5** (tắt/đổi) ·
**hoàn tác bền** 20 bước/24 giờ, kiểm lại "vẫn là tệp đó, ở chỗ đó" trước khi làm.

Bẫy (bản sửa lỗi FileOctopus ⇒ ca kiểm của ta): kéo nhiều tệp crash — **kiểm từng kiểu xem riêng** (họ sửa một view, view
khác tái phát) · Quick Look phải theo **ngăn đang chọn** · chép **không** được làm ngăn nguồn tải lại · đẩy ổ từ ngoài
(Disk Utility) phải cập nhật **mọi** cửa sổ · đổi tên chỉ khác hoa/thường phải hiện là thay đổi · Esc khi đổi tên không huỷ
⌘X đang chờ · Cột ↔ Tìm kiếm/Thẻ không crash · menu chuột phải bật/tắt giống nhau ở 4 kiểu xem · tỉ lệ chia hỏng trong
workspace bị kẹp từng ngăn · không cấm `/tmp` · kiểm bản sao chỉ so **nội dung** (SHA-256), không ACL/xattr · bị kill đúng
lúc khởi động lại với nhật ký "đang chạy" không được crash (họ sửa hai lần) · thư mục hiện tại bị xoá ⇒ lên tổ tiên còn
tồn tại (kể cả ông/bà) · bộ nhớ sau **chuỗi thao tác nặng**, không chỉ một danh sách lớn · ô lọc của hai ngăn không giành
tiêu điểm của nhau · Thùng rác không bị nhận nhầm "cần quyền".
