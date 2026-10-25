# XF-T30 W6 — contract (thao tác tệp: gộp thư mục, danh sách Sự cố, tốc độ/ETA, hoàn tác bền, cắt ⌘X, thư mục mới chứa mục chọn)

Spec tổng §2 hàng W6. Hành vi: `scratchpad/claude/t30/spec-file-operations.md` (R1–R75, nhất là R21–R32 gộp, R33–R44 bảng
tiến trình, R45–R51 Sự cố, R52–R58 hoàn tác), bảng thiếu `gap-file-operations.md`. Stub thêm SAU khi W1 gộp.

## 1. Thuần (builder F6 — `FolderMerge.swift` (mới), `ProblemsList.swift` (mới), `UndoJournal.swift` (mới), `CutBoard.swift` (mới), `FileOperationRules.swift`, test)

- **Gộp thư mục** `FolderMerge.plan(source: Tree, destination: Tree, policy) -> MergePlan`: chính sách Giữ cả hai (mặc định)
  · Bỏ qua · Giữ bản mới hơn (ngưỡng 1 s, 2 s cho FAT); loại trừ gói, symlink, khác kiểu (tệp ↔ thư mục), thư mục đám mây; từ
  chối nguồn/đích lồng nhau; bảng đếm xem trước (sẽ chép / sẽ thay / bỏ qua / đổi tên); thư mục nguồn rỗng sau khi chuyển ⇒
  vào Thùng rác; bản bị thay ⇒ Thùng rác (không xoá hẳn), Thùng rác lỗi ⇒ dừng; khác ổ ⇒ chép + SHA-256 rồi mới bỏ nguồn;
  báo cáo cuối; hoàn tác bất đối xứng (đưa mục đã chuyển về, lấy lại bản đã thay từ Thùng rác).
- **Sự cố** `ProblemsList`: mỗi thao tác hỏng một hàng (thao tác + giờ) với từng mục hỏng (tên + lý do theo bộ từ vựng: không
  có quyền, đầy ổ, tệp đang dùng, ổ/máy chủ mất kết nối, lỗi đọc/ghi, hết giờ, ổ chỉ đọc, tên quá dài, mục không còn — còn lại
  ⇒ chuỗi lỗi hệ thống); `canRetry` chỉ lỗi trước khi ghi và có thể tạm thời; Bỏ qua / Xoá hết / Ẩn chỉ đụng danh sách; chỉ trong
  phiên (không ghi đĩa).
- **Hoàn tác bền** `UndoJournal`: 20 bước / 24 giờ, lưu metadata (đường dẫn, inode, cỡ, mtime, checksum khi có) — không nội dung;
  `canUndo(step, exists:, identity:)` kiểm lại trước khi chạy (đã bị thay, đổi tên kiểu Giữ cả hai, đụng từ ngoài app, thiếu
  một mục ⇒ từ chối cả bước, không hoàn tác một phần); ổ chưa gắn ⇒ "Không hoàn tác được…" xám tới khi ổ quay lại; nhãn "Hoàn
  tác Chuyển 3 mục"; Làm lại ⇒ cùng luật. Thay `ActionHistoryStore` **chỉ trong trình duyệt** (trang Lịch sử thao tác cũ giữ
  nguyên, không gộp).
- **Cắt ⌘X** `CutBoard`: tập mục đang chờ cắt (chỉ khi `fileBrowser.cutWithCmdX`), ⌘V ở thư mục khác ⇒ chuyển, Esc / ⌘C mới /
  chép thứ khác ⇒ huỷ (Delete, điều hướng không huỷ), dán sang app khác ⇒ thành chép (pasteboard chỉ có URL).
- `FileOperationRules`: tên ZIP (`tên.zip` / `Archive N.zip`), nén tạo ở chỗ tạm rồi kiểm rồi mới đặt vào (không bao giờ để ZIP
  hỏng lộ ra), Nén xám khi chọn một tệp .zip hoặc có mục đám mây chưa tải; mục trong Thùng rác: Chia sẻ / Nhân bản / Nén / Tạo bí
  danh xám; `newFolderWithSelection` (tên "Thư mục mới chứa mục" theo Finder "New Folder With Items").

## 2. AppKit (builder Q6 — `FileOperationQueue.swift`, `FolderMergeController.swift` (mới); P6 — `OperationsPanelView.swift`, `ConflictSheet.swift`, `MergePreviewSheet.swift` (mới))

- Hàng đợi: lô **tiếp tục khi một mục hỏng** (ghi vào Sự cố, cảnh báo ngay một lần); tốc độ/ETA = byte qua cửa sổ trượt 5 s, ẩn
  khi Đang tạm dừng / Đang kiểm / Đang hoàn tất / đứng yên > 3 s / thao tác 0 byte; bảy nhãn giai đoạn (Đang chờ, Đang chuẩn bị,
  Đang chép, Đang tạm dừng, Đang kiểm, Đang hoàn tất, Xong / Lỗi / Đã dừng); không cho tạm dừng ở bước Kiểm/Hoàn tất của mục cuối
  (tooltip lý do); kéo sắp xếp + "Chạy tiếp theo / Lên / Xuống"; Tạm dừng tất cả / Tiếp tục tất cả khi ≥ 2 việc; Hoàn tác khi việc
  nguồn còn chạy ⇒ xếp hàng chạy sau. Gộp thư mục chạy qua cùng hàng đợi (SHA-256 khi khác ổ).
- Bảng: phần Sự cố trong cùng popover (chuột phải: Hiện trong XFinder (chọn tại chỗ hoặc thư mục cha gần nhất còn lại) · Hiện
  trong Finder · Thử lại · Bỏ qua), Xoá hết; ConflictSheet: thư mục ↔ thư mục có nút **Gộp…** mở `MergePreviewSheet` (bảng đếm,
  chọn chính sách, "Áp dụng cho tất cả").

## 3. Lệnh (stub sau W1)

`newFolderWithSelection` ⌃⌘N · `cut` ⌘X (chỉ khi bật) · `redo` ⇧⌘Z · `clearOperationHistory` · `merge` (từ ConflictSheet).

## 4. Nghiệm thu W6

Test thuần (kế hoạch gộp với cây cố định: mỗi chính sách, ngưỡng FAT, loại trừ, lồng nhau; Sự cố + canRetry; UndoJournal kiểm
lại + 20/24 h + ổ vắng; CutBoard luật huỷ), harness thêm mutant. T-T30-25…30: gộp hai thư mục trùng tên, chép 1 000 tệp có 1 tệp
khoá ⇒ 999 xong + một hàng Sự cố + Thử lại, tốc độ/ETA hiện khi chép tệp lớn, thoát app rồi ⌘Z hoàn tác chuyển, ⌘X kiểu Windows,
⌃⌘N.
