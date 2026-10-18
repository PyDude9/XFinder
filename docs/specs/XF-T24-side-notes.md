# XF-T24 — Ghi chú mép: preview vừa nội dung, phím tắt toàn cục mở ghi chú, sao lưu tự động có ngày

## 0. Câu việc

"Rê chuột vào mép là **đọc hết** một ghi chú ngắn; muốn viết thì một phím từ bất kỳ app nào; và lỡ hỏng thì vẫn còn bản sao
lưu tự động có ngày để lấy lại."

## 1. Đo trước khi viết (2026-10-18)

| | XFinder (code `b146563`) | Antinote 2.1.3 (đo trên máy này) |
|:--|:--|:--|
| Preview | thẻ **cố định 186×118 pt**, `lineLimit(6)`, chữ 10 pt; panel lúc peek chỉ cao `stack + 24` ⇒ 1–2 ghi chú thì thẻ bị **cắt** dưới 6 dòng; hit-test giả định stack ở **giữa** panel trong khi view ghim stack ở **trên** (lệch ~12 pt) | không có preview mép — một cửa sổ |
| Mở để viết | chỉ rê mép; ⌥⌘N/L/P chỉ khi XFinder ở trước | phím toàn cục ⌥A |
| Lưu | UserDefaults JSON, cả app 26,7 MB footprint | Core Data SQLite, **199 MB** footprint, idle 0,36 s/30 s |
| Sao lưu | Xuất tay MD/TXT/JSON (trang Ghi chú) | **tự chép DB có ngày**: `cd-v1-notes_cdbackup_<ngày>.sqlite` (6 bản trên máy này) |

Không có gì để học về tốc độ thô; học **cách truy cập** (phím toàn cục) và **sao lưu tự động có ngày**.

## 2. Thiết kế

**2.1 Preview vừa nội dung.** `Core/EdgeNotesLayout.swift` (thuần, symlink test): stack ghim vào một rect cố định giữa màn hình
(không đổi khi peek), thẻ rộng 248 pt cao **theo nội dung** đo bằng `NSString.boundingRect` (chữ 11 pt), trần
`min(520, 60 % visibleFrame)`; thẻ đặt cạnh viên của nó, bị đẩy lên nếu tràn đáy màn hình; panel lúc peek là hợp của stack và
thẻ; `noteID(at:)` đọc rect cố định của stack, không đọc khung panel. Vượt trần ⇒ cắt cuối bằng "…" và dòng "còn N dòng nữa".

**2.2 Phím tắt toàn cục (tuỳ chọn, mặc định tắt).** `notes.globalHotkey` (Bool, false; ONE reader `EdgeNotesController`) đăng ký
Carbon `RegisterEventHotKey` ⌃⌥N (không cần quyền, signature riêng 'XFnt'): mở editor mép trên ghi chú gần nhất (chưa lưu
trữ), không có ⇒ tạo ghi chú mới. Hàng trong `ShortcutCatalog` (scope global, gate key) để trang Phím tắt + kiểm tra trùng.
Mặc định tắt vì nó chiếm một tổ hợp phím của mọi app.

**2.3 Sao lưu tự động có ngày (mặc định bật).** `notes.autoBackup` (Bool, true). Mỗi lần `NoteStore` lưu, nếu hôm nay chưa có
bản sao lưu ⇒ ghi `~/Library/Application Support/XFinder/Notes Backups/notes-YYYY-MM-DD.json` (đủ để Nhập lại) +
`.md` (đọc được bằng mắt), giữ **14 ngày** gần nhất, xoá bản cũ hơn bằng Trash. Không timer. Trang Ghi chú: công tắc + nút
"Mở thư mục sao lưu". Dữ liệu chỉ ở máy này.

## 3. Ca hỏng

| Ca | Trả lời |
|:--|:--|
| Ghi chú rỗng | thẻ một dòng "Ghi chú trống" (cao tối thiểu) |
| Ghi chú 500 dòng | trần chiều cao, "…" + "còn N dòng nữa" |
| Viên cuối gần đáy màn hình | thẻ bị đẩy lên trong `visibleFrame`, viên không dịch |
| Peek đổi ghi chú | panel đổi chiều cao, stack đứng yên (rect cố định) — hit-test không trượt |
| ⌃⌥N đã bị app khác giữ | `RegisterEventHotKey` trả lỗi ⇒ trang ghi "không đăng ký được"; không giả vờ bật |
| Không có ghi chú | phím tạo ghi chú mới và mở |
| Thư mục sao lưu không ghi được | log + trang hiện lỗi; lưu ghi chú vẫn thành công |
| Đổi ngày lúc đang mở | bản đầu tiên của ngày mới được ghi ở lần lưu kế tiếp |

## 4. Nghiệm thu

Thuần: layout (stack cố định khi peek, thẻ trong visibleFrame, chiều cao theo dòng, index theo Y); retention 14 ngày;
tên file theo ngày. Mutation trong harness mới hoặc agents-style. Live: probe AX đọc chiều cao thẻ khi peek ghi chú 9 dòng.
T-T24-1 (tay): rê ghi chú 9 dòng ⇒ đọc đủ 9 dòng; T-T24-2: bật phím, ⌃⌥N từ Safari ⇒ editor mép mở; T-T24-3: thư mục sao lưu
có file hôm nay, Nhập JSON lại được.
