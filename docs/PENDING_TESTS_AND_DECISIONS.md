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

### P3 · Vỏ cài đặt theo OneNotch (đã dựng 2026-10-13)

Brief v3 nói "sidebar 220 pt có ô màu, thẻ nhóm #F7F7F7 r10, header 52 + 6 trang mới". Những chỗ brief không nói, tôi chọn:

| Mã | Câu hỏi | Lựa chọn | Mặc định đang làm |
|:--|:--|:--|:--|
| Q-P3-1 | 6 trang mới nằm ở đâu trong sidebar? | (a) nhóm mới **NOTCH** ngay dưới CHUNG (Giao diện notch · Khay thả · Đang phát · Agent AI · Lịch & lời nhắc · Hoạt động trực tiếp), Phím tắt vào CHUNG, các nhóm khác giữ nguyên · (b) xếp lại cả sidebar theo nhóm của OneNotch (Tính năng / Trải nghiệm) | **(a)** — ở XFinder notch là MỘT bề mặt trong nhiều tính năng; gom theo việc "cài notch" khớp Part 0 §3, và không xáo trộn 34 hàng bạn đã quen |
| Q-P3-2 | Màu của vỏ (thẻ #F7F7F7, viền #E5E5E5, tiêu đề #4D4D4D) | (a) suy từ màu hệ thống: ra đúng số đo ở chế độ sáng, tự đổi ở chế độ tối · (b) chép đúng mã hex của OneNotch + tự chọn một bảng tối riêng | **(a)** — `XFinderTokens` vốn là "chỉ màu hệ thống"; (b) phải tự duy trì hai bảng màu |
| Q-P3-3 | Hàng đang chọn ở sidebar | (a) vùng chọn gốc của macOS (bo góc, màu nhấn) · (b) viên thuốc tự vẽ như OneNotch | **(a)** — tự vẽ phải bỏ `List(selection:)`, mất phím ↑↓ và VoiceOver của sidebar |
| Q-P3-4 | Header 52 pt | (a) `PageHeader` vẽ kiểu mới cho cả 37 trang (thanh 52 pt, tiêu đề 20 pt, đường kẻ), cuộn cùng trang · (b) thanh cố định ở trên, nội dung cuộn dưới | **(a)** — đổi một component là mọi trang đổi theo; (b) phải sửa cả 37 trang (để P4) |
| Q-P3-5 | Các trang cũ có chuyển sang thẻ nhóm luôn không? | (a) chỉ 6 trang mới + trang bị tách dùng thẻ; trang cũ giữ hàng phẳng tới P4 · (b) chuyển hết ngay | **(a)** — đúng tách P3/P4 của brief |
| Q-P3-6 | Công tắc tổng của notch (`dropTray.notchEnabled`) | (a) chuyển sang **Giao diện notch** + đổi nhãn ở hub thành "Notch" (nó tắt CẢ notch, không chỉ khay) · (b) giữ ở Khay thả | **(a)** — nhãn cũ "Khay thả file" hứa tắt một công cụ trong khi thực ra tắt cả Clipboard/Đang phát/Agent/Lịch ở notch |
| Q-P3-7 | Bộ ghi phím tắt (6 phím Chụp + ⌘K) | (a) chuyển hẳn sang trang **Phím tắt**; trang Chụp / Tìm kiếm chỉ hiện phím + link · (b) giữ ở trang tính năng, Phím tắt chỉ liệt kê | **(a)** — một khoá một control (Part 0 §4); và chỉ ở một chỗ mới so được trùng phím giữa các tính năng |
| Q-P3-8 | ⇧⌘G (Dịch vùng chọn) đè phím "Find Next" của mọi app khi bật | (a) ghi rõ cảnh báo, phím vẫn cố định · (b) cho đổi phím (thêm bộ ghi + khoá mới) | **(a)** cho P3; (b) là thêm cơ chế mới — nói tôi nếu muốn |
| Q-P3-9 | Trang Ghi chú ghi ⌥⌘A và "⌘T/⌘F/⌘P/Esc trong ghi chú" nhưng không phím nào được nối | (a) gỡ các dòng sai, ghi đúng ⌥⌘N/L/P chỉ chạy khi XFinder ở phía trước · (b) nối thêm các phím đó | **(a)** — sửa lời hứa sai trước; nối phím là tính năng mới |

### Khác

~~Q-P2-SL~~ — đã trả lời 2026-10-13: tài khoản Pro/Max. Vậy % đến ở phiên `claude` trong terminal sau câu trả lời đầu (xem T-P2-SL).

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
| T-P1a | (P1, bản đã cài lúc XFinder đang tắt — mở app trước) Có tệp trong khay / đang phát nhạc / phiên Claude Code chạy: nhìn notch khi thu gọn, bấm từng cánh | Hai cánh bên camera, **cao đúng bằng notch**, không có gì thòng xuống; cánh trái: icon Claude (cam khi đang chờ bạn) + số tệp; cánh phải: sóng nhạc hoặc ảnh bìa + giờ đếm ngược; bấm cánh mở đúng trang |
| T-P1b | Mở hub (⌘⇧V hoặc bấm cánh), bấm từng chấm trên dải trên cùng, vuốt hai ngón trên dải | Chấm sáng là trang hiện tại; rê lên chấm hiện tên trang; đổi trang thì nội dung mờ chéo, khung co giãn giữa hai cỡ; mở có nảy nhẹ, đóng nhanh không nảy |
| T-P1c | Trang Clipboard: gõ ngay sau ⌘⇧V; bấm vòng tròn kính lúp; bắt đầu Paste Stack (⌘⇧C) | Gõ được ngay (ô tìm tự mở); viên trạng thái cuối hàng chip hiện "Paste Stack · n" + Dán tiếp; thẻ có màu theo app nguồn |
| T-P1d | Trang Đang phát: kéo thanh tiến trình; bấm icon app ở góc ảnh bìa; khi không phát gì | Thả tay thì nhảy tới đúng chỗ; mở đúng player; không phát gì thì khung giữ nguyên, nút mờ |
| T-P2-SL | Trang **Agent AI** (nhóm NOTCH) ▸ **Cài statusLine**; mở `claude` trong terminal, gửi một câu, đợi trả lời; mở notch ▸ Hạn mức AI | Hai vòng 5 giờ / 7 ngày có % và "lúc HH:mm"; dòng trạng thái của Claude Code trông y như trước (vẫn chạy lệnh của Notch Crew → OneNotch). **Gỡ statusLine** trả lại đúng cài đặt cũ |
| T-P2-TIMER | Mở hub ▸ icon Hẹn giờ trên toolbar: − / + rồi ▶; đang chạy bấm ⏸, −5, +5, ✕ | Số phút nhảy bậc 5 (5…120); chạy thì cánh phải notch hiện ⏱ mm:ss; tạm dừng thì số đứng yên và cánh hiện biểu tượng pause; hết giờ kêu "Glass" + "Hết giờ" |
| T-P2-AI | Hub ▸ icon Hạn mức AI: tab Hạn mức / Token | Chưa cài statusLine: không có vòng %, có nút "Bật trong Cài đặt"; tab Token: "Hôm nay" khác "7 ngày" và cả hai là token RA; Codex hiện % hoặc "đã qua giờ reset" |
| T-P2-AGENTS | Mở một phiên `claude` trong terminal; mở hub ▸ chấm Agent AI | Dòng "n phiên"; hàng phiên có chấm trạng thái + tuổi; khi Claude xin quyền: thẻ có đồng hồ giây chạy + Cho phép / Từ chối hoạt động |
| T-P2-CAL | Hub ▸ icon Lịch | Thứ in đậm, ngày/tháng + năm + âm lịch bên phải; dải 9 ngày với hôm nay trong ô tối; danh sách hôm nay cuộn được |

### P3 · Vỏ cài đặt (dựng 2026-10-13, chưa ai bấm thử)

| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-P3-SIDEBAR | Mở cửa sổ XFinder, cuộn sidebar, dùng ↑↓, gõ vào ô "Tìm trang" | Sidebar rộng 220 pt, mỗi hàng có ô màu + icon trắng; nhóm **NOTCH** ngay dưới CHUNG; ↑↓ vẫn chuyển trang; tìm theo tên Việt/Anh vẫn ra; bấm hàng dài không làm cửa sổ nhảy rộng |
| T-P3-HEADER | Mở 4–5 trang cũ (Hệ thống, Mạng, Chụp & chú thích, Cài đặt Clipboard, Tổng quan) | Đầu trang là thanh 52 pt: tiêu đề 20 pt bên trái, công tắc (nếu có) bên phải, đường kẻ mảnh bên dưới, câu mô tả dưới đường kẻ; không trang nào bị chữ đè hay cụt |
| T-P3-NOTCH | Trang **Giao diện notch**: tắt công tắc ở đầu trang, rồi bật lại | Tắt: notch biến mất hẳn (không badge, không hub), ⌘⇧V rơi về khay nổi; trang Khay thả hiện dòng "Notch đang tắt" có link về đây. Bật lại: notch quay lại |
| T-P3-HOVER | Giao diện notch ▸ tắt "Rê chuột vào notch"; rê vào notch; rồi kéo một tệp vào notch | Rê không mở gì; kéo tệp vẫn mở khay; picker "mở gì" và độ nhạy bị mờ khi tắt |
| T-P3-PAGES | Giao diện notch ▸ ẩn một trang, đổi thứ tự, bấm **Khôi phục mặc định** | Hub đổi theo ngay; Khôi phục đưa về đủ 7 trang đúng thứ tự gốc |
| T-P3-SPLIT | Mở lần lượt Đang phát · Agent AI · Lịch & lời nhắc · Hoạt động trực tiếp; bật/tắt vài công tắc | Mỗi công tắc làm đúng việc như ở trang "Notch & Khay thả" cũ; Lịch: nút "Cấp quyền" mới hỏi quyền, công tắc không bao giờ bật hộp thoại |
| T-P3-SHORTCUTS | Trang **Phím tắt**: gán một phím Chụp (ví dụ ⌃⌥D); đổi ⌘K sang một tổ hợp đã dùng | ⌃⌥D báo trùng với "Bắt dính một phần ba trái" khi phím bắt dính đang bật; ⌘K trùng cũng báo; bấm Huỷ ghi / rời trang giữa chừng thì phím cũ vẫn chạy |
| T-P3-LINKS | Trang Chụp & chú thích và Tìm kiếm: bấm "Đổi phím tắt trong Phím tắt"; trang Chọn văn bản: đọc dòng ⇧⌘G | Link mở trang Phím tắt; không còn nút ghi phím ở hai trang kia; dòng ⇧⌘G nói rõ nó thay Find Next khi bật |
| T-P3-DARK | Bật chế độ tối của macOS, mở Giao diện notch và Phím tắt | Thẻ nhóm vẫn thấy được (sáng hơn nền một chút), chữ đọc rõ, đường kẻ không biến mất |

### P4 · Mọi trang cài đặt còn lại sang thẻ nhóm (2026-10-14, chưa ai bấm thử)

| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-P4-PAGES | Lướt qua từng trang trong sidebar, nhất là Cài đặt Clipboard, Nhập bằng giọng nói, Chuột & cử chỉ, Nén & Giải nén, Tổng quan | Mỗi nhóm cài đặt là một thẻ bo góc có tiêu đề ở trên; không chữ nào dính mép, không hai đường kẻ liền nhau, không thẻ rỗng; trang không bị kéo rộng |
| T-P4-METRICS | Mở Hệ thống, Mạng, Ổ đĩa, Pin để vài giây rồi chuyển trang khác | Số liệu chạy khi trang mở, đứng khi rời trang (CPU XFinder lúc rảnh vẫn ~0 %) |
| T-P4-DARK | Bật chế độ tối, mở 3–4 trang | Thẻ vẫn thấy được, chữ phụ đọc rõ |

### P5 · Agent ngoài Claude Code (dựng 2026-10-14)

Trang: NOTCH ▸ **Agent AI**. Bật "Hiện phiên agent ở notch" trước.

| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-P5-CODEX | Agent AI ▸ Codex ▸ **Cài hook vào ~/.codex/hooks.json**; mở `codex` trong terminal, gõ `/hooks`, tin cậy các hook "Managed by XFinder"; gõ một yêu cầu | Phiên Codex hiện trên notch (nhãn "Codex"); dòng "Sự kiện gần nhất" trên trang có thời gian. **Trước khi tin cậy: không có sự kiện nào** (Codex bỏ qua hook chưa duyệt — đúng như tài liệu) |
| T-P5-CODEX-PERM | Trong phiên đó, để Codex xin quyền chạy một lệnh | Thẻ duyệt hiện trên notch; Cho phép / Từ chối có tác dụng trong Codex |
| T-P5-MULTI | Có cả hook duyệt quyền của OneNotch / Notch Crew trong `~/.claude/settings.json` (máy này đang có cả hai), cài hook Claude của XFinder, để Claude Code xin quyền, bấm Cho phép trên notch của XFinder | **Chưa biết** — tài liệu Claude Code không nói nhiều hook PermissionRequest kết hợp thế nào. Ghi lại: lệnh chạy ngay, hay chờ app kia trả lời / hết giờ? Trang Agent AI đã cảnh báo số hook của công cụ khác |
| T-P5-PID | Trong một phiên Codex, thoát `codex` bằng ⌃C | Phiên chuyển "Đã kết thúc" trong ≤ 20 s (hook tìm đúng tiến trình `codex` cha — đã đo bằng tiến trình giả tên `codex`, chưa đo với Codex thật) |
| T-P5-OPENCODE | Agent AI ▸ OpenCode ▸ bật "Theo dõi phiên OpenCode"; mở `opencode` trong terminal, nhờ nó chạy một lệnh shell | Phiên hiện trên notch với tiêu đề của OpenCode; khi OpenCode hỏi quyền, thẻ duyệt hiện trong ~2,5 s; Cho phép chạy lệnh đúng một lần (không tạo luật "always"); trả lời ở terminal thì thẻ biến mất |
| T-P5-NOTIFY | Bật thông báo (mặc định bật cả hai) ; để một phiên xin quyền khi notch đang thu gọn, rồi để một phiên trả lời xong | Notch hiện "Cần bạn duyệt" (agent · tên · công cụ, nút Xem mở trang Agents) và "Tới lượt bạn"; mở XFinder khi đã có phiên đang chờ thì **không** báo lại; đang mở trang Agents thì không báo |
| T-P5-RECENT | Agent AI ▸ Phiên gần đây; trên notch, trang Agents khi không có phiên nào đang chạy | Chỉ phiên terminal (không có phiên của app Claude/Codex để bàn); "Sao chép lệnh" dán vào terminal mở lại đúng phiên trong đúng thư mục; tên thư mục dài bị cắt giữa, nút vẫn thấy |
| T-P5-UI | Đọc trang Agent AI ở cả hai ngôn ngữ (chưa đo qua AX: màn hình khoá suốt lượt cài 2026-10-14) | Mục: Phiên agent trên notch · Claude Code · Codex · OpenCode · Cursor (giải thích) · Thông báo · Phiên gần đây · Hạn mức Claude; không lẫn tiếng Việt ở bản English |

### P6 · Nhắn phiên từ notch (dựng 2026-10-14)

Trên notch, trang Agents: nút **Nhắn** (bong bóng chữ) cạnh mỗi phiên. Không cần cài lại hook: lần mở XFinder đầu
tiên sau bản này tự chép script hook mới (nó ghi thêm `KITTY_WINDOW_ID` / `KITTY_LISTEN_ON` / `$TMUX`). Phiên đã chạy
từ trước đó chỉ có kitty/tmux sau sự kiện hook kế tiếp của nó (một câu trả lời là đủ).

| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-P6-KITTY | `kitty.conf`: `allow_remote_control yes` + `listen_on unix:/tmp/kitty`; mở lại kitty, chạy `claude`, chờ nó trả lời xong; trên notch bấm Nhắn, gõ một câu có dấu tiếng Việt, ↩ | Câu hiện trong ô nhập của Claude **đúng dấu** và được gửi (Enter riêng 0,1 s sau). Chuyển sang một tab kitty khác trước khi gửi: vẫn vào đúng cửa sổ của phiên |
| T-P6-TMUX | Trong tmux (bất kỳ terminal nào), chạy `claude`, làm như trên | Như trên. Đóng ô đó, mở ô mới cùng số `%N`, gửi lại ⇒ **không gõ gì**, dòng báo "Ô tmux của phiên không còn" |
| T-P6-OPENCODE | Phiên `opencode` đang trả lời (đang chạy); gửi một tin từ notch | Dòng "OpenCode đã xếp tin vào hàng đợi của phiên"; tin chạy sau khi lượt hiện tại xong (không cắt ngang) |
| T-P6-QUEUE | Phiên Claude trong kitty/tmux đang chạy một lệnh dài; gửi một tin, rồi gửi tin thứ hai trước khi nó xong | Tin đầu bị thay ("Đã thay tin đang chờ…"); khi phiên rảnh chỉ tin thứ hai được gõ. Bấm Huỷ trên dòng "Tin đang chờ" ⇒ không gì được gõ |
| T-P6-BLOCK | (a) Claude đang hỏi quyền (thẻ Cho phép/Từ chối) · (b) Claude đang hỏi một câu có lựa chọn, hoặc có hộp thoại trên terminal | (a) Nhắn không gõ gì, báo dùng Cho phép / Từ chối. (b) Nút đổi thành **Chép và mở terminal**: tin vào clipboard, terminal lên trước, **không phím nào được gõ**; trả lời hộp thoại rồi dán. Thử thêm: bấm Esc thoát hộp thoại ở terminal rồi nhắn — vẫn ra "Chép" (XFinder không biết hộp thoại đã đóng; đó là cố ý, vì Enter vào hộp thoại quyền là "Yes") |
| T-P6-COPY | Phiên trong Terminal.app / iTerm2 / Ghostty | Nút ghi "Chép và mở terminal"; tin vào clipboard, terminal lên trước; dán ⌘V là đúng câu |
| T-P6-KEEP | Đang gõ dở trong ô Nhắn, đưa con trỏ ra khỏi notch | Notch **không** thu lại (chữ đang gõ còn nguyên); Esc hoặc ✕ đóng ô |

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| Q-P6-TERMINAL | Gõ tự động vào Terminal.app bằng AppleScript `do script` — cần bạn bấm cho phép Automation một lần để đo (chưa đo; chưa ship) | Chép + mở terminal |
| Q-P6-CODEX | `codex queue --thread … --message …` có thể gửi tin vào phiên Codex mà không gõ phím — chưa đo trên phiên thật (đo sẽ chạy một lượt model) | Chép + mở terminal |

### P7a · Phiên không cửa sổ (dựng 2026-10-14)

Notch ▸ trang Agents ▸ nút **+**, hoặc Agent AI ▸ **Phiên không cửa sổ**. XFinder chạy `claude -p` (chế độ luồng) trong
thư mục bạn chọn, không mở terminal. **Mỗi tin là một lượt dùng gói Claude của bạn** — chưa có lượt model nào được chạy để
kiểm (mọi kiểm tra đều dùng một `claude` giả).

| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-P7a-START | Agent AI ▸ Phiên không cửa sổ ▸ Chọn thư mục ▸ gõ "liệt kê các tệp ở đây" ▸ Bắt đầu phiên | Hàng mới trên trang Agents (biểu tượng khung đứt), trạng thái "Đang làm" rồi "Tới lượt bạn"; notch báo "Tới lượt bạn"; Xem hội thoại hiện câu trả lời |
| T-P7a-REPLY | Trong hội thoại đó bấm Nhắn, gửi một câu tiếp; thử gửi trong lúc nó còn đang làm | Câu đi vào phiên (không cần terminal); gửi lúc đang làm ⇒ "Tin đang chờ — gửi khi phiên rảnh", tự gửi khi lượt xong |
| T-P7a-PERM | Nhờ phiên chạy một lệnh shell cần duyệt (đã cài hook Claude Code của XFinder) | Thẻ Cho phép/Từ chối hiện ở hàng VÀ trong màn hội thoại; bấm Cho phép thì lệnh chạy |
| T-P7a-NOHOOK | Như trên nhưng CHƯA cài hook | Trang cài đặt báo lệnh cần duyệt không hỏi được qua notch. Ghi lại Claude Code làm gì với lệnh đó (chưa đo) |
| T-P7a-STOP | Trong hội thoại: Ngắt lượt khi đang làm; rồi Dừng phiên | Ngắt ⇒ lượt dừng, phiên vẫn còn; Dừng ⇒ "Đã dừng", tiến trình `claude` biến mất (`pgrep -fl "claude -p"`) |
| T-P7a-QUIT | Có một phiên không cửa sổ đang chạy ⇒ thoát XFinder | Tiến trình `claude` của phiên đó kết thúc; mở lại XFinder ⇒ phiên nằm ở Phiên gần đây |
| T-P7a-REOPEN | Phiên gần đây ▸ "Mở lại không cửa sổ" trên phiên vừa dừng | Phiên chạy lại với hội thoại cũ. Nếu cùng phiên đó đang mở trong terminal ⇒ báo "đang mở ở nơi khác", không mở lần hai |
| T-P7a-PATH | Trong phiên không cửa sổ, nhờ nó chạy một lệnh Homebrew (vd. `which tmux`) | Lệnh tìm thấy công cụ như trong terminal của bạn (XFinder dùng môi trường đăng nhập của shell) |

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| Q-P7a-MODEL | XFinder không tự chạy lượt model nào để kiểm phiên không cửa sổ với `claude` thật. Bạn có muốn tôi chạy một lượt ngắn (tốn một lượt của gói) để đo đường đi thật? | Không chạy — chờ bạn |
| Q-P7a-CODEX | Phiên không cửa sổ cho Codex cần giao thức `codex app-server` (JSON-RPC, ~160 lệnh, đã sinh schema tại chỗ). Dựng ở lượt sau? | Chưa dựng — trang giải thích |
| Q-P7a-QUIT | Thoát XFinder ⇒ phiên không cửa sổ dừng theo. Claude Code có "background session" (`claude --bg`) sống qua khi XFinder thoát, nhưng không có cách công khai nào gửi tin vào nó mà không mở terminal | Dừng theo XFinder |

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
