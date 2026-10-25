# XF-T30 W3 — contract (sidebar đủ mục, menu Đi, thư mục gần đây, Kết nối máy chủ, đẩy ổ)

Spec tổng §2 hàng W3. Hành vi: `scratchpad/claude/t30/spec-window-views-sidebar.md` §7, `spec-productivity.md` §3–§4
(Go to Folder, Recent Folders), `spec-file-operations.md` §11 (Eject R66–R70), `spec-settings-keyboard.md` §6 (phím menu
Đi), `spec-limits-changes.md` 1.0.4 (Connect to Server, AirDrop, Tags, All Tags). Ảnh chủ dự án: Recents · Favorites
(AirDrop, Desktop, Applications, Documents, Downloads) · Locations (iCloud Drive, OneDrive, home, Macintosh HD, ổ ngoài có
nút đẩy) · Tags (+ All Tags…). Stub thêm SAU khi W1 gộp.

## 1. Thuần (builder S3 — `SidebarLayout.swift`, `SidebarSections.swift` (mới), `RecentFolders.swift` (mới), test)

- `SidebarSections`: thứ tự và luật hiện của các mục: Gần đây, AirDrop, Mục ưa thích (người dùng), nhóm riêng, iCloud (khi
  iCloud Drive bật trên máy), Vị trí (ổ trong / ổ ngoài / đám mây / máy chủ đã nối; tuỳ chọn "Nhóm Vị trí theo loại" ⇒ bốn
  tiêu đề con Cục bộ / Ngoài / Đám mây / Mạng), Mạng (Bonjour, mặc định tắt), Thẻ (theo tên + thứ tự Finder) + "Tất cả thẻ…"
  cuối nhóm. Ẩn một hàng không bao giờ xoá dữ liệu. Mỗi loại có công tắc riêng (khoá `fileBrowser.sidebar.<loại>`, W4 vẽ
  control; W3 đọc qua `BrowserSettings`). `SidebarLayout` lên schema 2: thêm thứ tự thẻ người dùng kéo, mục ưa thích mặc định
  (AirDrop, Desktop, Applications, Documents, Downloads) đánh dấu "mặc định" để Đặt lại; v1 giải mã được.
- `RecentFolders`: 10 thư mục khác nhau gần nhất mở ở bất kỳ ngăn nào, mới nhất trên cùng, mở lại đưa lên đầu, bỏ thư mục
  không còn, "Xoá menu"; chỉ lưu trên máy (`fileBrowser.recentFolders`, mảng chuỗi — ONE reader/writer trong `BrowserSettings`).
- Vị trí ảo: `enum VirtualLocation { recents, tag(String), allTags }` + đường dẫn giả `xfinder-virtual://recents`,
  `…/tag/<tên>` để tab/phiên lưu được; danh sách lấy bằng `mdfind` (Gần đây: `kMDItemLastUsedDate >= $time.today(-30)` trong
  thư mục người dùng, ≤ 500; Thẻ: `kMDItemUserTags == "<tên>"`), qua `NulRecords` (dừng sớm). Ngăn đang ở vị trí ảo: Chép/
  Chuyển sang ngăn kia xám (FileOctopus R30).

## 2. AppKit (builder V3 — `BrowserSidebarView.swift`, `SidebarSources.swift` (mới), `TagLibrary.swift` (mới), `EjectGuard.swift`, `ConnectToServer.swift` (mới))

- `SidebarSources` (`@MainActor @Observable`): ổ (`NSWorkspace.didMount/didUnmount/didRename` ⇒ mọi cửa sổ cập nhật ngay —
  sửa lỗ XF-T28), `~/Library/CloudStorage/*` theo nhà cung cấp (biểu tượng của app khi có), iCloud Drive, máy chủ đã nối
  (`/Volumes` có `ATTR_VOL` mạng), Bonjour (`NetServiceBrowser` `_smb._tcp`/`_afpovertcp._tcp` — chỉ khi mục Mạng bật; tắt ⇒
  không duyệt).
- `TagLibrary`: tên + màu + thứ tự thẻ Finder (đọc `~/Library/SyncedPreferences/com.apple.finder.plist` `FinderTagDict`
  bằng `plistlib`-tương đương `PropertyListSerialization`; thiếu ⇒ 7 thẻ màu mặc định), đồng bộ ~1 s qua theo dõi file
  (DispatchSource, không timer).
- `BrowserSidebarView`: đủ mục §1; AirDrop: thả tệp ⇒ `NSSharingService(named: .sendViaAirDrop)`, bấm ⇒ mở cửa sổ AirDrop của
  Finder (FileOctopus: macOS không cho app khác hiện thiết bị gần — ghi đúng như vậy trên UI); nút đẩy cạnh ổ ngoài/mạng;
  chuột phải mục ưa thích đúng 5 mục: Mở trong tab mới · Mở trong cửa sổ mới · Hiện trong thư mục chứa · Lấy thông tin ·
  Đổi tên…; kéo thả sắp xếp mục ưa thích và thẻ, ⌘Z hoàn tác bỏ/sắp; tô sáng hàng chứa thư mục hiện tại (tuỳ chọn, mặc định
  tắt); thư mục bật mở khi giữ kéo trên hàng (dùng `DragDropCoordinator` của W2 nếu đã có, không thì luật cùng thời gian hệ
  thống).
- **Đẩy ổ** ⌘E / nút / chuột phải: ổ có nhiều volume ⇒ hỏi "Chỉ đẩy volume này" / "Đẩy mọi volume" (⌥ = mọi, ⌃ = chỉ
  này); ổ bận ⇒ tên ứng dụng đang giữ (DiskArbitration dissent) + Thử lại / Buộc đẩy (cảnh báo mất dữ liệu của app kia),
  Buộc đẩy chỉ đúng volume đã chọn, **không bao giờ** ổ trong; thao tác tệp của XFinder đang chạy/tạm dừng trên ổ ⇒ từ chối.
- **Kết nối máy chủ** ⌘K: sheet nhập `smb://` / `afp://` / `nfs://` / `ftp://` / `webdav`, máy chủ gần đây + ưa thích (JSON),
  `NetFSMountURLAsync` (hỏi mật khẩu do hệ thống — XFinder không đọc/không lưu mật khẩu), gắn xong mở trong tab.

## 3. Menu Đi + lệnh (stub sau W1)

`BrowserCommand`: `goRecents` ⇧⌘F · `goDocuments` ⇧⌘O · `goDesktop` ⇧⌘D · `goDownloads` ⌥⌘L · `goHome` ⇧⌘H · `goAirDrop` ⇧⌘R
· `goNetwork` ⇧⌘K · `goICloud` ⇧⌘I · `goApplications` ⇧⌘A · `goUtilities` ⇧⌘U · `goComputer` ⇧⌘C (xám — FileOctopus giữ phím,
đích chưa hỗ trợ) · `connectToServer` ⌘K · `eject` ⌘E · `clearRecentFolders`. Đụng phím cũ: ⇧⌘C hiện không dùng; ⌥⌘L chưa
dùng; ⇧⌘D/⇧⌘O/⇧⌘H/⇧⌘A/⇧⌘U/⇧⌘I/⇧⌘R/⇧⌘K/⇧⌘F chưa dùng (kiểm bảng). `BrowserMainMenu` (W1) thêm menu Đi từ các lệnh này +
"Thư mục gần đây ▸".

## 4. Nghiệm thu W3

Test thuần (thứ tự mục, nhóm Vị trí theo loại, recent 10 + dedupe + bỏ mất, đường dẫn ảo round-trip qua phiên, layout v1→v2),
harness thêm mutant. T-T30-13…18: sidebar có Gần đây/AirDrop/Thẻ/Tất cả thẻ; cắm USB ⇒ hiện ngay ở mọi cửa sổ; ⌘E ổ hai
volume hỏi; thả tệp lên AirDrop mở bảng gửi; ⇧⌘D/⌥⌘L/⇧⌘H đi đúng; ⌘K gắn smb.
