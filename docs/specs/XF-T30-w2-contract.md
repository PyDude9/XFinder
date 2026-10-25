# XF-T30 W2 — contract (kiểu xem: List có tam giác, nhóm, cột, tuỳ chọn xem, menu chuột phải chung, kéo-thả chung)

Spec tổng §2 hàng W2. Hành vi: `scratchpad/claude/t30/spec-window-views-sidebar.md` §2, §5, §6; `spec-productivity.md`
§8–§11 (Copy as Pathname, Open With, Show Original, Share); `spec-file-operations.md` (kéo-thả, Trash: Share / Duplicate /
Compress / Make Alias xám — sửa lỗi 1.0.4). Stub được thêm SAU khi W1 gộp (chạm `BrowserCommands`/model).

## 1. Thuần (builder A2 — `GroupBy.swift`, `FolderViewOptions.swift` (mới), `DirectoryEntry.swift`, test)

- `DirectoryEntry` thêm `added: Date?` (getattrlistbulk `ATTR_CMN_ADDEDTIME`), `lastOpened: Date?`, `tags: [String]?`
  (nil = chưa đọc, không phải "không có"). `SortKey` thêm `created`, `added`, `lastOpened`. `EntryRules.sorted` xếp nil
  sau cùng, rồi theo tên tự nhiên; "Thư mục lên đầu" chỉ khi sắp theo tên (FileOctopus R18).
- `GroupBy.sections(_:by:sort:now:calendar:kindName:appName:) -> [EntrySection]`, `EntrySection { titleKey: String;
  titleArg: String?; entries: [DirectoryEntry] }`. Ngày (sửa/tạo/thêm/mở): Hôm nay · Hôm qua · 7 ngày trước · 30 ngày trước ·
  từng tháng trong năm nay (titleArg = tên tháng theo locale) · từng năm trước · "Chưa có ngày". Tên: theo chữ cái đầu đã gập
  (A…Z, "#" cho số/ký hiệu, chữ có dấu về chữ gốc). Loại / Ứng dụng: theo tên (appName nil ⇒ "Không rõ"). Cỡ: Không byte ·
  < 100 KB · 100 KB – 1 MB · 1 – 100 MB · 100 MB – 1 GB · > 1 GB · Thư mục. Thẻ: mỗi thẻ một nhóm (mục nhiều thẻ xuất hiện ở
  nhóm thẻ đầu theo thứ tự thẻ Finder), "Không có thẻ" cuối. Nhóm rỗng không hiện. Trong nhóm: theo `sort`.
- `FolderViewOptions` (mới, thuần): `struct FolderViewPrefs: Codable { viewMode, sort, groupBy, useGroups, iconSize (32…128,
  bước 16, mặc định 64), textSize (10…16, mặc định 13), columns: [ListColumn], showIconPreview: Bool }`, `enum ListColumn:
  String, Codable, CaseIterable { name, dateModified, dateCreated, dateAdded, dateLastOpened, size, kind, tags }` (name luôn
  có), `struct FolderViewStore { prefs(for path) -> FolderViewPrefs?; set(_, for path); LRU 500 đường dẫn; encode/decode
  bỏ phần hỏng }`. File `~/Library/Application Support/XFinder/Browser/folder-views.json` (ghi ở model, không ở đây).

## 2. Đọc thêm thông tin (builder R2 — `DirectoryReader.swift`, `FileMetadataCache.swift` (mới))

- `DirectoryReader.list` đọc thêm `ATTR_CMN_ADDEDTIME` (đo lại 100 000 tệp: không quá +15 ms).
- `FileMetadataCache` (`@MainActor`, đọc nền): `tags(for:)` (xattr `com.apple.metadata:_kMDItemUserTags`, bplist, bỏ hậu tố
  "\n<số màu>" lấy màu), `lastOpened(for:)` / `appName(for:)` (`MDItemCreate` + `kMDItemLastUsedDate`; `NSWorkspace.urlForApplication(toOpen:)`
  tên ứng dụng), batch theo danh sách đường dẫn, LRU 20 000, `@Observable` phiên bản tăng khi có lô mới. Màu thẻ:
  `TagColor` 0…7 (không, xám, xanh lá, tím, xanh dương, vàng, đỏ, cam).

## 3. View (builder L2 — `FileListView.swift`; I2 — `FileIconView.swift`, `FileColumnView.swift`, `FileGalleryView.swift`; M2 — `BrowserContextMenu.swift` (mới), `DragDropCoordinator.swift` (mới), `ViewOptionsPanel.swift` (mới))

- **List = `NSOutlineView`**: tam giác ở thư mục (gói = lá); → mở, ← đóng hoặc chọn thư mục cha, ⌥→/⌥← đệ quy (trần
  10 000 mục mở thêm, quá trần dừng + banner); con tải nền bằng `DirectoryReader`, có watcher riêng cho mỗi thư mục đang mở,
  đóng là huỷ; hàng tiêu đề nhóm (`isGroupItem`), không chọn được, phím mũi tên bỏ qua; cột theo `FolderViewPrefs.columns`,
  chuột phải tiêu đề = bật/tắt cột + "Vừa cỡ cột này / Vừa cỡ mọi cột riêng / Vừa cỡ mọi cột bằng nhau", nhấp đúp mép cột =
  vừa cỡ cột; chấm màu thẻ + badge đám mây ở cột tên; vùng trống dưới hàng cuối dùng màu nền chuẩn (lỗi 1.0.4); cuộn sâu
  trong thư mục mở không crash (lỗi 1.0.4). Giữ: đổi tên tại chỗ, type-select, kéo-thả, Quick Look, 100 000 hàng mượt.
- **Icon**: section + header khi có nhóm; cỡ biểu tượng / chữ theo prefs; chấm thẻ dưới tên; badge đám mây; ổn định khi ngăn rất
  hẹp (lỗi 1.0.2); nhận thả lên biểu tượng thư mục (lỗi 1.0.4).
- **Column**: badge + chấm thẻ; hàng tiêu đề nhóm giả (không chọn, mũi tên bỏ qua); Esc huỷ kéo; không có dải trống sau cột xem
  trước (lỗi 1.0.4); khôi phục cả đường cột (`TabSnapshot.columnPath`, Q-T30-7) — model ghi/đọc qua API §4.
- **Gallery**: badge; chỉ "Sắp theo".
- **`BrowserContextMenu`** — MỘT nơi dựng menu cho cả 4 kiểu xem + nút "…" toolbar: Mở · Mở trong tab mới · Mở bằng ▸
  (ứng dụng mở được, mặc định trên cùng) — Chuyển vào Thùng rác — Lấy thông tin · Đổi tên · Nén · Nhân bản · Tạo bí danh ·
  Xem nhanh — Sao chép (giữ ⌥ ⇒ "Sao chép "tên" dưới dạng đường dẫn" / "Sao chép N mục dưới dạng đường dẫn") · Chia sẻ… —
  Thẻ (7 màu Finder + "Thẻ…") — Thêm vào sidebar · Thêm vào Shelf · Hiện bản gốc (bí danh/symlink; trong kết quả tìm là
  "Hiện trong thư mục chứa") · Hiện trong Finder · Tải về ngay / Gỡ bản tải (đám mây). Nền (không chọn): Thư mục mới ·
  Lấy thông tin · Dán · Xem dạng ▸ · Sắp theo ▸ · Nhóm theo ▸ · Tuỳ chọn xem. Mục trong Thùng rác: Chia sẻ / Nhân bản / Nén /
  Tạo bí danh xám. Mọi mục đi qua `model.perform` / `canPerform`.
- **`DragDropCoordinator`** — luật kéo-thả chung cho 4 kiểu xem + sidebar: cùng volume = chuyển, khác = chép, ⌥ chép, ⌘
  chuyển (vẫn qua kiểm an toàn); nhận file promise; ảnh kéo nhiều mục = chồng + số; thả lên thư mục = biểu tượng hoặc tên;
  tô sáng đích như Finder; **thư mục bật mở khi giữ kéo** theo thời gian của Cài đặt hệ thống (`NSSpringLoadingHighlight` /
  `UserDefaults` `com.apple.springing.enabled`/`.delay`), tắt ở hệ thống ⇒ tắt; Esc hoặc kéo ra ngoài cửa sổ ⇒ về chỗ cũ.
- **`ViewOptionsPanel`** ⌘J: panel nổi theo ngăn đang chọn: kiểu xem, cỡ biểu tượng, cỡ chữ, cột (List), Nhóm theo, Sắp theo,
  "Luôn mở theo kiểu này" (nhớ cho thư mục), "Dùng làm mặc định".

## 4. API mới (stub sau W1)

`BrowserCommand`: `makeAlias` ⌃⌘A · `showOriginal` ⌘R · `addToSidebar` ⌃⌘T · `share` · `showViewOptions` ⌘J · `copyAsPathname`
(= `copyPath`, đổi nhãn) · `setTag(color)` qua model method. `PaneState`: `folderPrefs: FolderViewPrefs`, `sections:
[EntrySection]` (dựng lại khi `entries`/nhóm đổi — W2 builder model), `columnPath: [String]`. `BrowserWindowModel`:
`openWith(_ app: URL)`, `setTag(_ color: TagColor, on paths:)`, `makeAlias()`, `showOriginal()`, `addSelectionToSidebar()`.

## 5. Nghiệm thu W2

Test thuần (nhóm theo ngày với `now` cố định, ranh tháng/năm, tên có dấu, cỡ, thẻ nhiều; prefs LRU + giải mã hỏng; sort
mới), harness thêm mutant, đo 100 000 hàng: mở List ≤ 150 ms, nhóm theo ngày ≤ 30 ms. T-T30-7…12: tam giác + ⌥→, nhóm theo
ngày có Hôm nay/Hôm qua, chuột phải tiêu đề thêm cột Ngày thêm, ⌘J đổi cỡ biểu tượng và nhớ theo thư mục, chấm thẻ ở cả 4 kiểu
xem, kéo giữ trên thư mục thì nó mở.
