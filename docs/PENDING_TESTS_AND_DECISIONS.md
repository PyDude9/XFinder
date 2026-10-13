# Việc chờ bạn: lựa chọn + test tay

Một chỗ duy nhất cho mọi thứ còn phân vân. Mỗi mục có **mã** (ví dụ `Q-F4-2`, `T-B6`) để bạn nói lại cho nhanh
("Q-F4-2 chọn b", "T-B6 hỏng: …"). Khi một mục xong, xoá nó khỏi file này trong cùng commit.

Cập nhật: 2026-10-13.

---

## Phần 1 — Cần bạn chọn (Q)

Mỗi câu ghi **mặc định tôi đang làm theo** — bạn không trả lời thì giữ mặc định.

### F4 · Chụp & chú thích ("làm y OneNotch trước")

Bạn đã duyệt brief F4 với 5 câu trả lời mặc định, sau đó nói "cứ làm y OneNotch". Mấy chỗ dưới đây là nơi hai điều đó
**mâu thuẫn**, nên tôi phải chọn một bên:

| Mã | Câu hỏi | Lựa chọn | Mặc định đang làm |
|:--|:--|:--|:--|
| Q-F4-1 | Quay màn hình / GIF? | (a) chỉ chụp ảnh, quay để sau · (b) làm luôn quay video + GIF như OneNotch | **(a)** — brief đã chốt "không quay"; quay là một khối việc riêng (ScreenCaptureKit stream, mic, encoder) |
| Q-F4-2 | Phím tắt mặc định? OneNotch trên máy này lưu: chụp vùng ⇧⌘4, toàn màn hình ⇧⌘3, cửa sổ ⇧⌘9, OCR ⇧⌘2, lấy màu ⇧⌘1, chụp cuộn ⇧⌘6 | (a) không gán sẵn, có nút "Dùng bộ phím giống OneNotch" · (b) gán sẵn ⇧⌘-số như OneNotch | **(a)** — ⇧⌘3 / ⇧⌘4 là của macOS; gán sẵn sẽ tranh phím với hệ thống cho mọi người dùng chưa tắt phím của macOS |
| Q-F4-3 | Chọn vùng bằng gì? | (a) công cụ chọn vùng của macOS (`screencapture -i`: vùng, Space = cửa sổ, Esc huỷ) · (b) lớp phủ tự vẽ như OneNotch (kính lúp, đo pixel, chụp cuộn, nhận phần tử thông minh) | **(a)** — chắc chắn chạy, không cần tự vẽ; (b) là việc lớn, làm sau nếu bạn muốn |
| Q-F4-4 | Thẻ xem trước nổi (Quick Access) bật lên ở cạnh nào? | Trái · Phải | **Trái dưới** — tránh chỗ ảnh thu nhỏ của chính macOS (phải dưới) |
| Q-F4-5 | Ảnh chụp lưu ở đâu? | (a) luôn giữ một bản trong thư mục của XFinder (để có Lịch sử như OneNotch `Captures/`) + Lưu thì ghi thêm ra Desktop · (b) chỉ ghi file khi bấm Lưu | **(a)** — giống OneNotch; bản giữ lại nằm trong `~/Library/Application Support/XFinder/Captures/`, có nút xoá lịch sử |
| Q-F4-6 | Bố cục trình chú thích | wireframe A (thanh công cụ trên cùng) · B (cột công cụ + bảng thuộc tính) · C (chú thích tại chỗ) | **A** — OneNotch dùng cửa sổ chú thích riêng, thanh công cụ ngang |

### Khác

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| Q-MULTIDISPLAY | §3b #39 — notch hiện trên mọi màn hình cùng lúc (nay: màn đang có con trỏ). Máy này một màn nên không đo được gì. Khi cắm màn ngoài, báo tôi để làm + đo | Chưa làm |
| Q-GESTURE | Nút giữ cử chỉ chuột đang là Nút 3 (bấm con lăn). Đổi sang nút hông? (trang Chuột & cử chỉ có nút "Ghi lại nút giữ") | Để nguyên |

~~Q-WAVE~~ — đã probe và làm 2026-10-13: bạn bấm Allow lúc 16:44; tap chạy, có tín hiệu nhạc thật (xem T-WAVE).

~~Q-GIT~~ / ~~Q-RELEASE~~ — đã xong 2026-10-13: push `main` tới `48546c5`, tag `v1.3.0`, [Release 1.3.0](https://github.com/PyDude9/XFinder/releases/tag/v1.3.0) với zip + .sha256 (tải lại từ GitHub: checksum OK, `codesign --verify --deep --strict` OK).

~~Q-CLIP-PAUSE~~ / ~~Q-NOTCH-SW~~ — đã tự giải quyết: `clipboard.paused` giờ là `0`, `dropTray.notchDropEnabled` /
`dropTray.hoverEnabled` giờ đều là `1` (đo lại 2026-10-13). Xoá khỏi danh sách.

---

## Phần 2 — Cần test tay (T)

Những thứ code + test tự động đã qua nhưng **chưa ai làm bằng tay thật**. Ghi kết quả: ✅ / ❌ + mô tả.

### Notch
| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-B1 | Kéo một tệp từ Finder lên notch (cần bật Q-NOTCH-SW) | Hub mở, thả vào thì tệp nằm trong khay |
| T-B1b | Kéo thanh tiêu đề một cửa sổ đi ngang qua notch | Notch **không** mở |
| T-B1c | Kéo tệp rồi lắc chuột | Khay mở ngay dưới con trỏ |
| T-B1d | Khi khay có tệp: rê lên notch → kéo icon trái ra Finder | Kéo ra được **tất cả** tệp |
| T-B2d | Hàng nút trên hub khi giữ tệp: ZIP, Gộp PDF, Sang JPEG/PNG, Tách nền, AirDrop | Mỗi nút tạo file cạnh tệp gốc; AirDrop mở bảng chọn thiết bị |
| T-N6 | Hub: Sang PDF, OCR, Thu nhỏ ảnh (giữ chuột lên nút Thu nhỏ để chọn cỡ) | PDF/txt/ảnh nhỏ nằm cạnh tệp gốc; OCR chép chữ vào clipboard |
| T-B3 | Kéo một cửa sổ lên vùng quanh notch | Hiện hàng 7 bố cục; thả lên một ô thì cửa sổ vào đúng ô |
| T-B4 | Rút sạc · tắt Wi-Fi · bấm Caps Lock · kết nối AirPods/chuột Bluetooth | Notch báo từng việc; **app không crash** khi thiết bị Bluetooth kết nối |
| T-B4b | Bấm phím âm lượng; Flyout ▸ Hẹn giờ trên notch 5 phút | Notch hiện thanh âm lượng; đếm ngược trên notch, hết giờ kêu "Glass" |
| T-B6 | Bật Đang phát, mở Music / Spotify / YouTube trong Safari | Notch hiện bài + ảnh bìa; ⏮ ⏯ ⏭ điều khiển đúng player |
| T-N8 | Trang Đang phát: kéo thanh tiến trình, chọn Trộn bài / Lặp lại | Player nhảy tới đúng chỗ; chế độ đổi trong player |
| T-B7 | Cắm màn hình ngoài (không có notch) | Có "notch ảo" giữa mép trên; hover/hub chạy như màn chính |
| T-N4 | Bật Lịch trên notch → cấp quyền Lịch + Lời nhắc | Trang Lịch hiện sự kiện hôm nay, ngày âm lịch; nút "Tham gia" mở link họp |
| T-N3 | Notch & Khay thả ▸ Cài hook Claude Code, rồi mở một phiên Claude Code | Notch hiện phiên; khi Claude xin quyền, bấm Cho phép/Từ chối trên notch thì terminal nhận |
| T-N33 | Bật Lịch trên notch (cấp quyền), tạo một sự kiện có link Zoom/Meet bắt đầu sau 6 phút | Sau ~1 phút: dòng "Sắp đến giờ · <tên> · còn 5 phút" dưới notch, có âm "Glass"; rê chuột tới **không** làm nó biến mất; "Tham gia" mở link; "Hoãn 5 phút" báo lại sau 5 phút; sự kiện cả ngày không bao giờ báo |
| T-USAGE | Bật phiên Claude Code trên notch, mở trang Agents | Dòng "Claude Code · 5 giờ: …K token ra · 7 ngày: …M token ra" (rê chuột hiện giải thích: không phải %). Dùng Codex một lần rồi mở lại: "Codex · 5 giờ N% · tuần M%"; nếu lần Codex gần nhất đã qua giờ reset thì nói thế, không hiện % cũ |
| T-D1g2 | Vuốt hai ngón ngang trên dải tab của hub; đổi màu nhấn | Đổi trang; màu nhấn đổi trên notch |

### Clipboard
| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-D0 | Bấm ⌘⇧V ở một app bất kỳ | Clipboard mở trên notch; ↩ dán ngược vào app đó |
| T-D0b | Cài đặt Clipboard ▸ khoá bằng Touch ID, mở lại ⌘⇧V | Hỏi Touch ID mỗi lần mở |
| T-B5 | ⌘⇧C bắt đầu Paste Stack, copy 3 thứ, rồi ⌘V ba lần | Dán lần lượt từng thứ |
| T-D1 | Trên thẻ clip: Phát âm · Sửa văn bản… · kéo thẻ lên chip Đã ghim / một bảng | Đọc to; sửa rồi Sao chép tạo clip mới; thẻ được ghim / vào bảng |
| T-D2 | Cài đặt Clipboard ▸ Xuất rồi Nhập `.xfinderclip`; copy một đoạn code | File tạo ra và nhập lại được; thẻ code có màu cú pháp |
| T-D2b | Bật Clipboard MCP, thêm `XFinder --mcp` vào Claude Code / Cursor | Client liệt kê 3 tool và đọc được clip |
| T-D3 | Thư viện Clipboard: bấm một thẻ, dùng ←→, "Dán vào app trước đó" | Bảng chi tiết mở; dán vào đúng app trước |
| T-D4 | Thư viện ▸ chuột phải một bảng ▸ Khoá bảng này… → bấm thẻ → Touch ID; **huỷ** Touch ID ở thẻ khác; rời trang rồi quay lại; Gỡ khoá | Thẻ hiện sau Touch ID; huỷ thì **không** báo lỗi; quay lại thì khoá lại; gỡ khoá một lần hỏi |
| T-D4b | Bật Xem trước link, copy một link | Thẻ hiện tiêu đề + ảnh của trang |

### Cửa sổ, chuột, bàn phím
| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-C1 | Bật ⌘-Tab của XFinder; khi đang mở: Q · H · Space · ` · , | Đóng cửa sổ · ẩn app · phóng to ảnh · chuyển app ↔ cửa sổ · tìm |
| T-GEST | Giữ nút cử chỉ rồi kéo lên / sang phải (profile Global) | Mission Control mở / chuyển Space |
| T-QUIT | Bật Giữ ⌘Q; nhấn nhanh ⌘Q rồi giữ ⌘Q ở một app | Nhấn nhanh không thoát; giữ ~1 s thì thoát |
| T-F3 | Thoát ứng dụng ▸ thêm Preview; đóng cửa sổ cuối của Preview; thu nhỏ cửa sổ (tắt Stage Manager) | Đóng hết thì Preview thoát; cửa sổ thu nhỏ thì **không** thoát |
| T-AUDIO | Cắm tai nghe / AirPods, chọn trong Điều khiển nhanh | Âm thanh chuyển sang thiết bị đó |

### Chọn văn bản, giọng nói, dịch
| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-E | Bôi đen trong Safari, Chrome, VS Code: một số tiền, một ngày, `5 km`, `9am EST` | Huy hiệu hiện; quy đổi đúng; "Thêm vào Lịch" tạo sự kiện thật |
| T-DICT | Bật Chọn văn bản thông minh; bôi đen một từ tiếng Anh ("ephemeral") rồi một từ tiếng Việt ("ngoại lệ") ở Safari | Bảng có dòng **Định nghĩa** với nghĩa ngắn (không có phiên âm); nút "Từ điển" mở đúng mục trong app Từ điển. Bôi đen "5 km" hay một câu dài: **không** có dòng Định nghĩa |
| T-N5a | Bật ⇧⌘G, bôi đen chữ ở app khác, nhấn ⇧⌘G | Bảng dịch mở (macOS 15+) |
| T-VOICE | Nhập bằng giọng nói: nói vào micro | Chữ được gõ ra đúng chỗ con trỏ |

### Dọn dẹp
| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-F1 | Dọn rác thư mục ▸ chọn một thư mục có `.DS_Store` ▸ Chuyển vào Thùng rác | Chỉ rác metadata vào Thùng rác |
| T-F2 | Gỡ ứng dụng ▸ kéo một app thử vào | Liệt kê app + phần sót lại; bỏ chọn được; mọi thứ vào Thùng rác |

### F4 · Chụp & chú thích (đã cài vào /Applications lúc 2026-10-13, chưa ai bấm thử)

Trang: CÔNG CỤ ▸ **Chụp & chú thích**. Cần quyền **Ghi màn hình** cho XFinder. Phím tắt mặc định **chưa gán** (Q-F4-2):
bấm "Dùng bộ phím giống OneNotch" hoặc "Gán phím" từng dòng — hoặc chụp bằng flyout (Chụp vùng / cửa sổ / toàn màn hình).

| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-F4-1 | Flyout ▸ Chụp vùng → kéo khoanh một vùng | Ảnh vào clipboard ngay; thẻ xem trước hiện ở **góc trái dưới**; tự đóng sau 10 s |
| T-F4-2 | Rê chuột lên thẻ rồi rời ra | Thanh đếm ngược **dừng** khi trỏ vào, chạy tiếp khi rời ra |
| T-F4-3 | Trên thẻ: Sao chép · Lưu · Ghim lên màn hình · ✕; chuột phải: Chép chữ, Hiện trong Finder, Xoá | Lưu tạo file trên Desktop (đuôi theo Định dạng); Ghim mở cửa sổ nổi kéo được, ⌘+/⌘− đổi cỡ |
| T-F4-4 | Kéo thẻ thả vào Finder / Slack | Thả ra một file PNG |
| T-F4-5 | Vuốt hai ngón ngang trên thẻ | Thẻ trượt ra và đóng |
| T-F4-6 | Bấm "Chú thích" trên thẻ: vẽ mũi tên, khung, chữ, số thứ tự, làm mờ địa chỉ email, tô sáng, cắt; ⌘Z / ⇧⌘Z; ↩ | Nét vẽ **đúng độ dày trên Retina** (không mảnh như sợi chỉ); vùng làm mờ thành khối; ↩ chép kết quả và đóng cửa sổ |
| T-F4-7 | Chụp cửa sổ đang mở (đứng ở Safari) | Chỉ cửa sổ Safari, có bóng như ⇧⌘4-Space của macOS; không bao giờ là cửa sổ của XFinder |
| T-F4-8 | Chụp toàn màn hình khi cắm 2 màn | Chỉ màn đang có con trỏ |
| T-F4-9 | Gán ⇧⌘4 khi macOS vẫn giữ ⇧⌘4 | Dòng cảnh báo "Trùng với macOS Chụp vùng — macOS có thể giành trước." |
| T-F4-10 | Thu hồi quyền Ghi màn hình rồi bấm phím chụp | Toast "Cần quyền Ghi màn hình để chụp ảnh." (không im lặng) |
| T-WAVE | Bật **Notch & Khay thả ▸ Sóng nhạc thời gian thực** (đang tắt — tôi trả khoá về như cũ sau khi đo), mở YouTube ở Chrome, rê vào notch / mở trang Đang phát | Cột sóng nhảy theo nhạc; tắt tiếng thông báo không làm cột nhảy; tạm dừng thì cột lặng; Safari cũng chạy (chưa đo) |
| T-F4-11 | Tắt "Giữ lịch sử ảnh chụp", chụp, đóng thẻ | Ảnh không ở lại trong `~/Library/Application Support/XFinder/Captures/` sau lần chụp kế tiếp |
