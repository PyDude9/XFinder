# XF-T41 — Gộp Shelf của trình duyệt vào Khay thả của notch (2026-11-09)

**Câu việc:** "Người dùng gom tệp từ nhiều nơi vào MỘT chỗ giữ tạm — Khay thả trên notch — rồi chép/chuyển cả chồng vào
ngăn trình duyệt đang mở, đổi tên hàng loạt, nén, mở hay bỏ vào Rác."

Lệnh chủ dự án (2026-11-09, sau khi hỏi "Add to Shelf thì không thấy file ở Shelf nào" và được chỉ ra Shelf ≠ Khay thả):
"bỏ cái shelf cũ này đi. Chuyển tính năng này vào Notch Shelf vì XFinder nó có cái này còn FileOctopus không có nên thành
ra tính năng hơi bị lặp". Danh sách gỡ/thêm dưới đây đã được anh duyệt (AskUserQuestion, lựa chọn 1).

## Gỡ (trình duyệt tệp)

| Mục | Ghi chú |
|:--|:--|
| Thanh Shelf ở đáy cửa sổ (`ShelfBarView`), model `ShelfModel` | không lưu bền (chỉ sống trong cửa sổ) ⇒ không có gì phải di cư |
| Lệnh `addToShelf` (⌃⌘S) và `toggleShelf` (⌥⌘B) | phím ⌃⌘S, ⌥⌘B được giải phóng |
| Nút Shelf trên thanh công cụ (`ID.shelf`) | cấu hình thanh công cụ đã lưu có id này: `NSToolbar` bỏ qua id không còn |
| Menu View ▸ Shelf ▸ · chuột phải "Thêm vào Shelf" · menu Tệp "Thêm vào Shelf" | thay bằng **Thêm vào Khay thả** (chuột phải, menu Tệp, bảng lệnh) |
| Quyền Pro `browserShelf` ("Shelf trong trình duyệt tệp") | bỏ khỏi `ProFeature` |
| `WindowSnapshot.shelfVisible` | **giữ trường** để tệp phiên/workspace cũ đọc được; luôn ghi `false`, không đọc |
| Harness: `ShelfModel.swift` khỏi FILES, 11 mutant `ShelfModel-*`, `ShelfModelTests` | test gói: `ShelfModel.swift` (symlink) + `ShelfModelTests.swift` xoá |

## Khay thả nhận thêm (`DropTrayBrowserBridge`)

| Việc | Ở đâu | Luật |
|:--|:--|:--|
| Chép vào ngăn: *tên* / Chuyển vào ngăn: *tên* | trang Khay thả ▸ "Thao tác cho cả khay" (cả khay); notch ▸ chuột phải một tệp (tệp đó) | chỉ hiện khi có cửa sổ trình duyệt và ngăn đang chọn là thư mục thật (không phải kết quả tìm / Gần đây / thẻ); đi qua **hàng đợi của trình duyệt** (hộp trùng tên, tiến trình, ⌘Z); chuyển xong ⇒ rời khay, chép ⇒ ở lại |
| Đổi tên hàng loạt | trang Khay thả | mở sheet đổi tên của trình duyệt với các tệp trong khay (mở cửa sổ trình duyệt nếu chưa có) |

"Ngăn đang chọn" = ngăn đang chọn của cửa sổ trình duyệt **key**, không có thì cửa sổ mở gần nhất (`BrowserWindowController.frontmostModel`).
Khay thả đã có sẵn: giữ tệp, kéo cả chồng ra, Sao chép…/Di chuyển… vào thư mục chọn, Nén ZIP, Mở tất cả, Bỏ vào Rác, Dọn khay, báo tệp không còn.

## Ca hỏng

| Ca | Phải |
|:--|:--|
| Không có cửa sổ trình duyệt | hai nút Chép/Chuyển vào ngăn không hiện; Đổi tên hàng loạt mở cửa sổ trình duyệt mới |
| Ngăn đang tìm / ở Gần đây | hai nút không hiện |
| Chuyển vào ngăn chính thư mục chứa tệp | hàng đợi báo trùng tên như một lần kéo thả bình thường |
| Phiên/workspace cũ có `shelfVisible: true` | mở bình thường, không có thanh Shelf |
| Thanh công cụ đã tuỳ biến có nút Shelf | nút biến mất, các nút khác giữ nguyên |

## Nghiệm thu

Build; test (menu/lệnh/hợp đồng tính năng không còn Shelf); gate L10n; harness DRY (271 mutant, 0 anchor hỏng); chạy thật
trong Atlas: chuột phải ▸ Thêm vào Khay thả ⇒ khay có tệp; trang Khay thả ▸ "Chép vào ngăn: Sub" ⇒ tệp xuất hiện trong `Sub`.
Test tay T-T41-1…2.
