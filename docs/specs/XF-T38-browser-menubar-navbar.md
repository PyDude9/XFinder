# XF-T38 — Trình duyệt tệp: menu bar + thanh điều hướng theo FileOctopus 1.0.10 (2026-11-08)

**Câu việc:** "Người dùng tìm thấy mọi lệnh của trình duyệt trên menu bar (Tệp, Sửa, Xem, Đi, Cửa sổ) và trên thanh
công cụ đúng chỗ như FileOctopus, kèm phím tắt — không phải nhớ hay mò chuột phải."

Lệnh chủ dự án (2026-11-08): "Nhớ làm cả Menubar, Navigation Bar cho XFinder nhé" + 7 ảnh FileOctopus 1.0.10 (menu File,
View, Go, Window + Workspace ▸, menu ứng dụng, cửa sổ chính có bảng lệnh ">"). Ảnh của chủ dự án thắng guide (XF-T30 §0).

## 0. Hiện trạng đo được

- Ảnh helper Atlas (bản `f5a12d4`, 2026-11-08 20:26): thanh menu khi cửa sổ trình duyệt ở trước = **"XFinder · Edit ·
  View · Đi · Window · Help" — không có menu File**. XFinder là app SwiftUI không khai báo File, nên `BrowserMainMenu`
  chèn "Mới cửa sổ / Đóng" vào File **không bao giờ hiện** (code im lặng bỏ qua khi không tìm thấy menu).
- View chỉ có 4 kiểu xem + 5 công tắc thanh; Window chỉ có tab ngăn mới + đóng ngăn; Đi thiếu Lùi/Tiến, thứ tự khác ảnh.
- Thanh công cụ mặc định: Lùi/Tiến · Xem · Nhóm · Bố cục ngăn · (khoảng) · Tải về · Chia sẻ · Tác vụ · Tìm. FileOctopus
  (ảnh + định danh trong binary `toolbar.viewMode/group/share/editTags/action/search/newFolder/quickLook/paneLayout`,
  `HistoryToolbarItem`): nút sidebar · Lùi/Tiến · tên thư mục · Xem · Nhóm/Sắp · Chia sẻ · **Thẻ** · Tác vụ · Tìm.
- Bảng lệnh: XFinder đã có chế độ ">" (lệnh) — FileOctopus hiện thêm **tên menu** dưới mỗi lệnh ("FileOctopus", "File").

## 1. Cấu trúc menu (một nguồn: `Core/Browser/BrowserMenuLayout.swift`, thuần, có test)

Mỗi mục là một `BrowserCommand` (phím hiển thị lấy từ bảng phím đang dùng — **không đổi phím** trong đợt này, Q-T38-2),
một menu con dựng khi mở, hoặc một liên kết tới trang XFinder sẵn có (Q-T37-4: "XFinder có hết rồi").

| Menu | Mục (thứ tự như ảnh; `—` = vạch ngăn) |
|:--|:--|
| **Tệp** (mới, chèn sau menu app) | Cửa sổ mới · Thư mục mới · Thư mục mới chứa mục chọn · Tab mới · Mở · Mở bằng ▸ · Đóng ngăn — Lấy thông tin · Đổi tên · Nén · Nhân bản · Tạo bí danh · Chép sang ngăn kia · Chuyển sang ngăn kia · So sánh thư mục… (→ trang Đồng bộ) · Tìm tệp trùng… (→ trang Tìm tệp trùng) · Xem nhanh · — Chia sẻ… — Hiện bản gốc · Hiện trong Finder · Thêm vào sidebar · Thêm vào Shelf — Chuyển vào Thùng rác · Đẩy ra — Thẻ… — Tìm · Lưu tìm kiếm… |
| **Sửa** (chèn sau mục hệ thống) | — Sao chép đường dẫn · Chuyển mục vào đây · Đổi tên hàng loạt… · Xoá lịch sử thao tác tệp… |
| **Xem** (chèn đầu menu) | 4 kiểu xem — Dùng nhóm · Nhóm theo ▸ · Sắp theo ▸ — Ẩn/hiện sidebar · Lọc thư mục hiện tại · Ẩn/hiện xem trước · Shelf ▸ — Ẩn/hiện thanh công cụ · thanh đường dẫn · thanh trạng thái · thanh vị trí · Sửa vị trí · Làm mới · Hiện tệp ẩn — Bố cục ngăn ▸ · Ngăn ▸ — Tuỳ biến thanh công cụ… — Tuỳ chọn xem — Bảng lệnh… (Tab bar / Toàn màn hình: hệ thống tự thêm) |
| **Đi** | Lùi · Tiến · Thư mục cha — Gần đây · Tài liệu · Màn hình nền · Tải về · Nhà · Máy tính · AirDrop · Mạng · iCloud Drive · Ứng dụng · Tiện ích — Thư mục gần đây ▸ — Đến thư mục… · Kết nối máy chủ… · Kết nối từ xa… (→ trang Kết nối từ xa) · Mở nhanh… — Tìm kiếm đã lưu ▸ |
| **Cửa sổ** (chèn sau mục hệ thống, trước danh sách cửa sổ) | Tiến trình thao tác — Tab ngăn trước · Tab ngăn sau · Chuyển tab ra cửa sổ mới — Lưu workspace… · Mở workspace ▸ · Đổi tên workspace ▸ · Nhân bản workspace ▸ · Xoá workspace ▸ · Xuất các workspace… |
| **Menu XFinder** | Cài đặt trình duyệt… (⌘, khi trình duyệt ở trước) |

Không làm: Kiểm tra cập nhật, License, "Free", Server Transfers / Server Log (XFinder không có), **In ⌘P** và **Đổ Thùng
rác ⇧⌘⌫** (Q-T38-3).

## 2. Thanh điều hướng (toolbar)

Mặc định theo ảnh: **Sidebar** · Lùi/Tiến · Xem · Nhóm · Bố cục ngăn · (khoảng) · Tải về · Chia sẻ · **Thẻ** · Tác vụ ·
Tìm. Thêm vào bộ tuỳ biến: **Thư mục mới**, **Xem nhanh**. Thẻ = menu 7 màu + thẻ gần đây, gắn/bỏ cho mục đang chọn
(dùng `FinderTags`), xám khi không chọn gì. Nút Sidebar = `toggleSidebar`.

## 3. Bảng lệnh

Chế độ ">" hiện **tên menu** của lệnh dưới tiêu đề (lấy từ `BrowserMenuLayout`), lệnh không nằm trong menu nào hiện
"Trình duyệt".

## 4. Ca hỏng

| Ca | Phải |
|:--|:--|
| Cửa sổ trình duyệt mất focus / đóng | mọi menu và mục chèn biến mất, menu của XFinder trở lại như cũ |
| Hai cửa sổ trình duyệt | menu tác động đúng cửa sổ đang key |
| Mục không áp dụng (không chọn gì, ngăn đang tìm) | xám, không chạy |
| Mở menu con Nhóm theo / Sắp theo | dấu ✓ đúng trạng thái ngăn hiện tại |
| Phím tắt | hiện đúng phím của hồ sơ phím đang dùng (Finder / Windows / Total Commander), không hiện phím đã bị gỡ |
| Bấm phím tắt | cửa sổ xử lý trước (như cũ), menu không chạy lệnh lần hai |

## 5. Quyết định (mặc định đang theo)

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| Q-T38-1 | "Navigation Bar" là gì | Thanh công cụ của cửa sổ (theo ảnh cửa sổ chính) + thanh vị trí từng ngăn giữ như hiện có |
| Q-T38-2 | Phím khác FileOctopus (Mở nhanh ⌘K vs ⌃⌘P, Đóng ngăn ⌃⌥⌘W vs ⌘W, Sidebar ⌥⌘S vs ⌃⌘S) | Giữ phím XFinder (thói quen + ⌘K của Tilde); menu hiện phím thật |
| Q-T38-3 | In ⌘P, Đổ Thùng rác ⇧⌘⌫ | Chưa làm: in cần Apple Event tới app khác (quyền Automation), đổ Thùng rác là xoá vĩnh viễn |

## 6. Đo khi làm (Atlas helper, 2026-11-08)

1. **Mục chèn từ ngoài vào menu của SwiftUI (Edit/View/Window) bị xoá** ở lần SwiftUI dựng lại menu — bản đầu của đợt này
   (và code cũ, ghi "UNMEASURED") cho View chỉ còn "Hide Tab Bar / Show All Tabs / Enter Full Screen". ⇒ Các khối đó khai
   báo qua chính `.commands` của SwiftUI (`BrowserMenuCommands` + `BrowserMenuState`, chỉ hiện khi một cửa sổ trình duyệt
   đang key). Đo lại: View có đủ khối, dấu ✓ đúng (danh sách, sidebar, thanh đường dẫn/trạng thái/vị trí); Window có
   "Hàng đợi thao tác", tab ngăn, khối Workspace trước danh sách cửa sổ.
2. **Mở app bằng `xfinder://browser`**: cửa sổ trình duyệt thành key TRƯỚC khi SwiftUI dựng xong thanh menu ⇒ Tệp/Đi bị
   rơi (thanh menu chỉ "XFinder · Edit · View · Window · Help") cho tới khi một cửa sổ trình duyệt khác thành key. ⇒
   `BrowserMainMenu` kiểm lại ở `NSApplication.didUpdateNotification` (chỉ chạy sau sự kiện, không chạy lúc nghỉ; tối đa 2
   lần/giây cho cùng một thanh menu). Đo lại trên lần mở mới: "Apple · XFinder · Tệp · Edit · View · Đi · Window · Help".
3. Menu Tệp đúng thứ tự ảnh, mục không áp dụng thì xám (không chọn gì: Mở, Đổi tên, Nhân bản, Chia sẻ…); "So sánh thư
   mục…" / "Tìm tệp trùng…" bấm được. Thanh công cụ có nút Sidebar mới.

## 7. Nghiệm thu

Build xanh; test `BrowserMenuLayoutTests` (mọi mục có tiêu đề dịch được; không lệnh nào lặp trong cùng menu; mỗi lệnh
trong menu có trong bảng lệnh; liên kết trỏ tới trang có thật); gate L10n 0; chạy thật trong Atlas: đọc thanh menu qua AX
khi cửa sổ trình duyệt ở trước (có "Tệp", "Đi"), mở menu Tệp thấy đủ mục, đóng cửa sổ thì "Tệp"/"Đi" biến mất; thanh
công cụ có nút Sidebar và Thẻ. Test tay T-T38-1…3.
