# Việc chờ bạn: lựa chọn + test tay

Một chỗ duy nhất cho mọi thứ còn phân vân. Mỗi mục có **mã** (ví dụ `Q-F4-2`, `T-B6`) để bạn nói lại cho nhanh
("Q-F4-2 chọn b", "T-B6 hỏng: …"). Khi một mục xong, xoá nó khỏi file này trong cùng commit.

Cập nhật: 2026-10-21.

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


### P12 · Làm tiếp việc dở khi một agent hết hạn mức (đề xuất: `docs/P12_PROPOSAL_2026-10-14.md`)

| Mã | Câu hỏi | Lựa chọn | Mặc định đang làm |
|:--|:--|:--|:--|
| Q-P12-1 | Phạm vi | (a) P12.1–5 · (b) thêm P12.6–7 (worktree + crew Boss/thợ/người kiểm khác model) | **Bạn chọn (a), đã làm.** (b) chờ bạn sau khi dùng thử |
| Q-P12-7 | Thông báo "dừng vì chạm giới hạn" khi bạn đang nhìn phiên đó | (a) vẫn báo (bỏ qua "Im lặng khi terminal ở phía trước") · (b) im lặng như các thông báo khác | **(a)** — terminal / app Claude hiện lỗi, nhưng không có lối ra; thông báo mang nút chuyển phiên |
| Q-P12-2 | `rateLimitExceeded` của Codex | (a) chỉ ghi vào hội thoại · (b) báo như `usageLimitExceeded` | **(a)** — schema tách hai mã; 429 có thể chỉ tạm thời |
| Q-P12-3 | Lệnh đang chờ duyệt trong bản ghi chuyển giao | (a) nguyên văn, cắt 300 ký tự · (b) chỉ tên công cụ | **(a)** — bạn đọc bản xem trước rồi mới Gửi |
| Q-P12-4 | Công tắc thông báo | (a) khoá riêng `agents.notify.quotaBlocked`, mặc định bật · (b) dùng chung `agents.notify.finished` | **(a)** |
| Q-P12-5 | Cảnh báo "sắp hết" (90 %) | (a) chưa làm · (b) làm luôn | **(a)** — % Claude trên máy này đang không rõ (statusLine XFinder chưa cài) |
| Q-P12-6 | Bộ `agent-mail-kit` tải về | (a) để nguyên · (b) tôi sửa thành bản dùng được ngoài XFinder | **(a)** — chưa có lệnh; danh sách lỗi + cách sửa ở mục 3 của đề xuất |

### Q-OC · Đối chiếu OneNotch (2026-10-14) — chọn mã muốn làm

Bảng đầy đủ: `docs/ONENOTCH_COMPARE_2026-10-14.md` (OC-1 … OC-77, mỗi dòng có trạng thái, công, đề xuất). Phần gộp
trùng lặp đã làm (Tìm kiếm, Quick Look, dòng quyền ở Tổng quan, đổi tên trang ẩn biểu tượng, bỏ đoạn lặp ở Tiện ích Finder).
**Mặc định đang áp:** chưa dựng mục OC nào. Trả lời theo mã ("làm OC-4, OC-18, OC-65") hoặc theo nhóm ("làm hết các mục
nhỏ"). Riêng **OC-52**: OneNotch mở khay nổi bằng ⇧⌘C, nhưng ⌘⇧C ở XFinder đang là Paste Stack — muốn đổi thì phải chọn
phím mới cho một trong hai.

### Q-DIAG · Chẩn đoán và phân tích ẩn danh (2026-10-14)

Bạn đã chốt: **phân tích ẩn danh bật sẵn, một công tắc "Từ chối gửi phân tích ẩn danh" (mặc định tắt)**, giải thích rõ đây là
thống kê trải nghiệm để nâng cấp app. Đã dựng (`AnalyticsRules`, `AnalyticsCenter`, khối ở Giới thiệu ▸ Hỗ trợ & báo lỗi):
không mã định danh (mỗi lần gửi một bản rời), không nội dung, tối đa 1 bản/ngày, thông báo một lần + chờ 24 giờ trước lần gửi
đầu, xem trước đúng JSON. Nhật ký lỗi cục bộ vẫn bật sẵn (Q-DIAG-3 giữ mặc định).

Luật (tra 2026-10-14, chưa có án lệ vì luật mới ~2 tuần): luật 91/2025 điều 2 — dữ liệu đã khử nhận dạng không còn là dữ liệu cá
nhân; Nghị định 356/2025 không xếp thống kê kỹ thuật vào dữ liệu nhạy cảm. EU: GDPR không áp cho dữ liệu ẩn danh (Recital 26),
nhưng ePrivacy 5(3) vẫn áp cho việc đọc thông tin thiết bị; thiết kế này bám các điều kiện miễn đồng ý của CNIL (mục đích hẹp,
thống kê ẩn danh, không đối chiếu, báo trước + từ chối dễ). Thêm mã định danh hay nội dung vào bản thống kê là phá điều kiện đó —
`AnalyticsRulesTests` chặn cả hai.

| Mã | Còn cần bạn làm | Mặc định |
|:--|:--|:--|
| ~~Q-DIAG-4~~ | **Xong 2026-10-15:** bạn đưa App ID `EDD21AF7-…F36B62` + namespace `com.xfinder`, đã điền vào Info.plist (giá trị công khai, nằm trong mọi bản build). Lưu ý đo được: endpoint của TelemetryDeck trả **HTTP 200 "OK" cho cả một namespace bịa**, nên 200 không chứng minh namespace đúng — chỉ dashboard xác nhận được (T-ANALYTICS-5) | — |
| Q-DIAG-5 | TelemetryDeck ghi trong FAQ rằng sự kiện lưu trữ lạnh có thể giữ 7–10 năm. Có muốn ghi câu này lên trang Giới thiệu không? | Chưa ghi |

### Q-MG · Thiết kế lại trang Chuột & cử chỉ (2026-10-15)

Ảnh tham chiếu bạn gửi (app khác) có ba thứ mà engine cử chỉ của XFinder **chưa có**. Wireframe không vẽ control cho chúng
(luật Trung thực: control nào cũng phải làm được đúng điều nó ghi).

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| Q-MG-1 | Cử chỉ theo phím bổ trợ (giữ Control/Option + kéo = một bộ hành động khác, như "Snap Window" / "Window Hub" trong ảnh)? Cần sửa engine | Chưa làm |
| Q-MG-2 | Mỗi nút một vòng 4 hướng riêng (hiện XFinder chỉ có MỘT nút giữ × 4 hướng)? Cần sửa engine + cấu hình | Chưa làm |
| Q-MG-3 | Tuỳ biến cuộn chuột (đổi hướng cuộn, làm mượt, tốc độ, chế độ gia tốc/đều)? Là một tính năng mới, cần tap cuộn riêng | Chưa làm |
| ~~Q-MG-4~~ | **Bạn chốt 2026-10-15: preset Dev & AI kéo lên = Mission Control** (đọc từ phím tắt máy bạn đã gán, như bảng Mặc định toàn cục). Kéo xuống vẫn Chưa gán; trái/phải ⌘[ / ⌘] | Đã làm |

### Q-PROC · Cách agent khác làm việc khi Claude hết quota (2026-10-15)

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| ~~Q-PROC-1~~ | Cho DeepSeek **commit trên nhánh riêng** `agent/<công-cụ>-<mã việc>`? | **Bạn chốt 2026-10-15: cho.** Mỗi việc / mỗi bước một commit trên nhánh `agent/…`; không commit lên `main`, không push, không merge. Việc nhiều bước dùng một nhánh. Quy trình ở `docs/AGENT_TASKS.md` §3 |
| Q-PROC-2 | Cho chạy **nhiều việc cỡ S trong một phiên** (như lần này)? | **Cho**, với điều kiện mỗi việc một dòng worklog có danh sách file + kết quả `gate-all.sh`. Việc cỡ M/L vẫn một việc một phiên |

### Q-NOTION · Routine nhiều agent qua Notion (2026-10-15, `docs/AGENT_NOTION.md`)

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| Q-NOTION-1 | Notion giữ hàng đợi / trạng thái / Run; Git giữ đặc tả. Có bỏ hẳn `docs/AGENT_WORKLOG.md` không? | **Giữ làm đường dự phòng** cho agent chưa nối được Notion; Claude chép mục worklog thành Run khi về |
| Q-NOTION-2 | Gói Notion hiện tại chạm hạn mức truy vấn SQL của MCP sau **5 lệnh một phiên** (đo 2026-10-15). Nâng gói, hay chỉ dùng view + `fetch`? | **Chỉ view + `fetch`** (chế độ view không có hạn mức riêng). Nâng gói chỉ khi view không đủ |
| Q-NOTION-3 | Cho một tiến trình đọc view *Review — Awaiting Claude* theo lịch (Notion Agent, hoặc Claude Code lên lịch) để review không cần bạn mở phiên? | **Chưa làm**; mọi phiên do bạn mở. Routine hiện chỉ nối các vai qua State |
| Q-NOTION-4 | Đăng nhập Notion MCP cho OpenCode / Antigravity / Zed / Codex — OAuth một lần mỗi công cụ, **bạn làm tay** (Claude không đụng cấu hình công cụ khác). Cấu hình mẫu ở `AGENT_NOTION.md` §9 | **Chờ bạn**; tới lúc đó Builder đi đường dự phòng §7 |
| Q-NOTION-5 | Trang "Nguồn & lịch sử — 24 tài liệu" trên hub XFinder là **bản chép** `.md` từ repo lúc nhập: không agent nào đọc, đã lệch `main`, và mỗi dự án sau sẽ thêm 20–30 bản chép nữa. Xoá (Thùng rác, phục hồi 30 ngày) và thay bằng 24 link GitHub? | **Đề nghị xoá**; Claude chỉ xoá khi bạn gật |
| Q-NOTION-6 | 6 linked-view **không tên** của trợ lý trước trên hub XFinder (filter không đọc được qua API; tool đòi `allow_deleting_content` để gỡ). Xoá chúng? Chúng chỉ là tham chiếu, không chứa dữ liệu | **Đề nghị xoá** — bạn xoá trong UI (⋯ → Xoá) hoặc gật để Claude xoá |
| Q-NOTION-7 | Việc **mới** đặt `Task ID` có tiền tố dự án (`XF-T20`) để mọi danh sách phẳng tự nói nó của ai; 163 ID cũ giữ nguyên | **Áp dụng** từ việc kế tiếp sau T14 |

### Q-SNAPMEM · Nhớ bố cục cửa sổ (2026-10-18, `docs/specs/SNAPMEM-window-layout-memory.md`)

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| Q-SNAPMEM-1 | Nhớ theo **Space** thường (ví dụ "Space 2 trên màn trong"): macOS không có API công khai; SkyLight private (`SLSCopyManagedDisplaySpaces`, `SLSGetActiveSpace`) đo được trên macOS 27 (màn trong 2 Space, màn ngoài 1). Dùng private API để gắn luật theo thứ tự Space? | **Chưa** — v1 nhớ theo bộ màn hình + toàn màn hình (một Space riêng, qua `AXFullScreen` công khai). Private API chỉ khi bạn gật, và sẽ ghi rõ trên trang |
| Q-SNAPMEM-2 | Mặc định **tắt** (tính năng đặt observer lên app khác và tự di chuyển cửa sổ lúc app mở). Có đưa vào preset "Hằng ngày" không? | **Không** — người dùng bật ở Vùng bắt dính ▸ Nhớ bố cục |
| Q-SNAPMEM-3 | Khi app có nhiều cửa sổ (Chrome 3 cửa sổ) chỉ cửa sổ **chính** được áp. Muốn áp mọi cửa sổ, hay nhớ từng cửa sổ theo tiêu đề? | **Chỉ cửa sổ chính** — nhớ theo tiêu đề là đoán (tiêu đề đổi theo tab) |

### Q-ORCA · Orca làm IDE multi-agent (2026-10-18, `docs/ORCA_PLAN_2026-10-18.md`)

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| Q-ORCA-1 | Bật "Agent status hooks" của Orca (nó ghi hook vào `~/.claude` và `~/.codex`, cạnh hook của XFinder/OneNotch/Notch Crew)? Trust hook của Codex tính theo vị trí trong mảng — hook chèn trước có thể làm hook XFinder mất trust | **Giữ nguyên settings.json** cho tới khi T-ORCA-4 đo xong |
| Q-ORCA-2 | Cho Claude dùng `orca worktree create --prompt` để tạo việc cho Builder ngay khi set `Ready` trong Notion (thay vì bạn dán prompt)? | **Có, từ giai đoạn 1** sau khi T-ORCA-2 đo được rằng `--name` thành tên nhánh `agent/<tool>-<ID>` |

### Q-PRUNE · Kiểm toán tính năng 2026-10-18 (`docs/APP_AUDIT_2026-10-18.md`) — chủ dự án "pump it all" ⇒ mặc định ĐÃ ÁP

| Mã | Đã làm (2026-10-18 chiều) | Còn gì cho bạn |
|:--|:--|:--|
| Q-PRUNE-1 | **Bỏ** Dải Dock Liquid Glass (`DockLayerController` + công tắc). Khoá cũ `windowPreview.customDockEnabled` không đọc nữa | — |
| Q-PRUNE-2 | **Đo**: 12/12 icon thanh menu đều on-screen, kể cả 3 icon bên trái mũi tên XFinder; engine 12 h không bao giờ tới `activate`. Viết spec **XF-T22** (về explainer + "Ẩn icon XFinder", migration giữ trạng thái bạn đang bật) cho Builder | gật XF-T22 Ready, hoặc nói nếu bạn thấy nó ẩn được icon app khác ở đâu đó |
| Q-PRUNE-3 | **Bỏ** khối "Cấu hình menu" 13 công tắc + picker Terminal/Bố cục (không gì đọc); subtitle + ghi chú nói đúng: extension có 2 mục | — |
| Q-PRUNE-4 | **Gọn** `PermissionManager` còn Trợ năng + banner; bỏ CoreBluetooth/ScreenCaptureKit, 5 thành viên chết | — |
| Q-PRUNE-5 | `voice.enabled` **mặc định tắt** (reader + catalog). Máy bạn chưa từng ghi khoá ⇒ Nhập giọng nói đang **tắt** sau cập nhật; bật lại ở trang Nhập bằng giọng nói nếu dùng | T-VOICE vẫn treo |
| Q-PRUNE-6 | Spec **XF-T21** (hàng catalog + reader cho Chia sẻ nhanh / Kết nối từ xa) cho Builder | **đã áp 2026-10-18** — Claude làm luôn (T-T21-1/2) |

### Q-CREW · Crew v2 — Lead Architect (2026-10-18, `docs/specs/XF-T23-crew-v2.md`, bằng chứng `docs/NOTCHCREW_EVIDENCE_2026-10-18.md`)

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| Q-CREW-1 | v2a (luật thuần) và **v2b** (worktree/nhánh mỗi builder, CLI ký v2, relay qua Gate, guard PreToolUse, bảng checklist, dừng không mất việc) **Claude đã dựng, 2026-10-18**, có e2e 33/33 trên git thật + `claude` giả. **v2c** (From a Goal: lead đề xuất seat → bạn Mở) giao Builder hay Claude? | Giao Builder sau khi bạn chạy thử v2b với model thật (T-CREW-1) |
| Q-CREW-2 | Lệnh phải **luôn hỏi** kể cả khi bạn có allow rule: danh sách trong `CrewV2.StateChanging` (git commit/push/merge/rebase, reset --hard, checkout --, npm/pnpm/yarn/bun/pip/brew install|add|publish, deploy*, rm, sudo, launchctl, defaults write, xcodebuild, make…). Thêm/bớt gì? | giữ danh sách; nói rõ trên trang "lưới an toàn, không phải ranh giới" |
| Q-CREW-3 | Nút "Cho phép và không hỏi lại `npm test` trong crew này" (bộ nhớ phía XFinder theo crew). **Chưa làm trong v2b** (cần sửa thẻ duyệt trên notch + lưu prefix theo crew); chuyển sang v2c. Có muốn không? | **Có**, ở v2c |
| Q-CREW-4 | Seat ngoài Claude/Codex (Gemini, Pi, Hermes, Cursor như Notch Crew) | **Chưa** — chỉ Claude + Codex windowless đã có |
| Q-CREW-5 | v2b lệch spec ở 5 chỗ, mỗi chỗ có lý do (xem `docs/specs/XF-T23-crew-v2.md` §7): (1) dừng crew **không** `worktree remove --force` — worktree còn file chưa commit được **chuyển sang** `Agents/crew-kept/` thay vì xoá; (2) guard là `XFinder --crew-guard` đặt trong `--settings` của từng thành viên, không phải sửa hook toàn cục; (3) khi builder báo `done`, XFinder **tự** nhờ security và reviewer duyệt (spec để lead nhờ); (4) trần chặng tin của Lead Architect là **60** (v1 vẫn 20) vì một vòng 2 builder đã tốn 20; (5) trạng thái `merged` được ghi lúc lead **xin** merge, không phải lúc `git merge` thật xong. Đồng ý? | **Đồng ý** cả 5; (5) là giới hạn đã biết, không làm yếu rào |
| Q-CREW-6 | Judge chạy `git merge --no-ff <nhánh>` trong worktree tích hợp (để chạy test) — lệnh đó cũng hiện thẻ trên notch (luôn hỏi). Với 2 builder là 2 thẻ mỗi vòng. Có muốn một ngoại lệ "merge vào nhánh `crew/*-integration` không hỏi"? | **Không** — giữ hỏi; đây là chỗ rẻ nhất để bạn thấy mã trước khi gộp |
| Q-CREW-7 | v2c "From a Goal" (spec `docs/specs/XF-T23c-crew-from-goal.md`, Notion XF-T23c Draft): mặc định của template Lead Architect là **Lead đề xuất seat trước, bạn bấm Mở** (chỉ lead spawn; worktree/nhánh chỉ tạo lúc Mở) hay **Mở đủ 5 vai ngay** (= v2b)? | **Lead đề xuất trước** (khoá `crew.fromGoal` default true) |
| Q-CREW-8 | "Không hỏi lại `npm test` trong crew này": nhớ trong RAM theo crew (mất khi crew dừng) hay persist theo repo (`updatedPermissions` `destination: localSettings` của repo thử — Claude Code có cơ chế này thật, đã đọc tài liệu 2026-10-18)? | **RAM theo crew** — hiện trên bảng, không ghi vào settings của repo |

### Q-REF · Đối chiếu một app cùng loại trên máy (2026-10-19, 17 ảnh cài đặt chủ dự án gửi) — việc nhỏ đã làm, việc vừa/lớn chờ bạn

Đã làm luôn (nhỏ, không chi phí nghỉ, API công khai): QR + trang chỉ mục cho Chia sẻ nhanh · Đếm ngược và Bóng đổ cửa sổ khi chụp ·
Độ trễ Dock preview · Làm mới bộ nhớ đệm Quick Look · dòng trống Kết nối từ xa nói nút Tải lên ở đâu. Bỏ không bàn: công tắc menu
ngữ cảnh Finder + Terminal mặc định (XFinder đã gỡ 2026-10-18 vì không gì đọc), bản quyền/mua hàng (XFinder không bán), chia sẻ qua cloud
của hãng (trái thiết kế LAN-only). Đo trên binary app đó (`strings`/`otool`, không đọc source): nó link `MenuBarClientCore` private +
`com.apple.MenuBarAgent` — **đúng cơ chế XFinder đã đo trả lỗi 4097 khi ký ad-hoc/tự ký**; app đó ký Developer ID (có `team-identifier`).

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| Q-REF-1 | **Cuộn chuột**: đảo hướng riêng cho bánh xe (trackpad giữ nguyên, phân biệt bằng `scrollWheelEventIsContinuous`), cuộn mượt (engine nội suy theo frame clock — app kia có `SmoothScrollEngine`), tốc độ, per-app. Cần event tap scrollWheel luôn bật ⇒ hàng catalog `listensToMouse`. Làm không? | **Viết spec XF-T25 cho Builder** khi bạn gật; chưa code |
| Q-REF-2 | **Kết nối từ xa** thêm SMB/SFTP/FTP + chính sách file trùng (giữ cả hai / bỏ qua / ghi đè) + mật khẩu trong Keychain. SMB mount được bằng `NetFSMountURLSync` (công khai); scp không có chính sách trùng ⇒ phải đổi sang sftp batch/rsync. Vừa–lớn | **Chưa**; nói mã nếu muốn |
| Q-REF-3 | **Chia sẻ nhanh** lên bucket S3/R2 **của bạn** (SigV4 bằng CryptoKit, không máy chủ trung gian của XFinder) — cho link ngoài LAN | **Chưa** — LAN + QR đủ cho "điện thoại cùng Wi-Fi"; nếu bạn hay gửi ra ngoài thì gật |
| Q-REF-4 | **Ẩn icon menu bar app khác**: app kia dùng đúng cơ chế XFinder đo (MenuBarAgent) nhưng ký Developer ID. Bạn có chứng chỉ Developer ID không? Có ⇒ đo lại XF-T22 với bản ký thật | **Giữ explainer XF-T22**; T-REF-1 bên dưới xác nhận app kia có ẩn thật không |
| Q-REF-5 | **Ghi chú mép**: ẩn khi đang dùng app đã chọn · chọn màn hình hiển thị · 6 vị trí (trên/giữa/dưới × trái/phải) · độ trễ rê chuột trước khi peek | **Chưa**; cái rẻ nhất là độ trễ peek (một khoá) |
| Q-REF-6 | **Quay màn hình** (phím tắt quay/dừng, tạm dừng, webcam, fps) và **chụp cuộn** | **Không** — hai tính năng lớn, macOS có ⇧⌘5 |

| Mã | Thao tác | Kỳ vọng |
|:--|:--|:--|
| T-REF-1 | Trong app kia: Biểu tượng thanh menu ▸ bật ẩn cho **1Password** (hoặc Claude) ▸ thu gọn | Icon 1Password **biến mất** khỏi thanh menu thật? Có ⇒ cơ chế sống với chữ ký Developer ID, XF-T22 cần đo lại; không ⇒ explainer đúng |

### Q-SS / Q-SC · Cuộn chuột mượt và Chụp cuộn (2026-10-22, `docs/specs/XF-T25-smooth-scrolling.md`, `XF-T26-scrolling-capture.md`)

| Mã | Câu hỏi | Lựa chọn | Mặc định đang làm |
|:--|:--|:--|:--|
| Q-SS-4 | Quy tắc riêng theo app (tắt cuộn mượt trong game, tốc độ riêng cho Xcode…)? | (a) để v2 · (b) làm ngay | **(a)** — v1: bật/tắt + tốc độ + độ mượt + đảo chiều cho mọi app |
| Q-SS-5 | Cuộn mượt mặc định bật hay tắt? | Bật · Tắt | **Tắt** — tính năng nuốt mọi sự kiện bánh xe, người dùng phải tự chọn |
| Q-SS-6 | Mos (hoặc công cụ làm mượt khác) đang chạy thì sao? | (a) XFinder tạm dừng + nói rõ · (b) chạy song song | **(a)** — hai lớp làm mượt chồng nhau là cảm giác "trôi kép" |
| Q-SC-1 | Chụp cuộn: cuộn tay hay tự cuộn? | (a) cuộn tay mặc định, nút Tự cuộn trong phiên · (b) chỉ một cách | **(a)** |
| Q-SC-2 | Biết "hết trang" bằng gì? | (a) 3 lần tự cuộn không đổi · (b) đọc thanh cuộn qua Trợ năng | **(a)** — (b) cần đọc AX từng app, để v2 |
| Q-SC-3 | Trần chiều cao ảnh dài | số px | **20 000 px** — đo lại ở T-T26-5 |
| Q-SC-4 | Ghép cả khi cuộn ngược lên? | (a) chỉ cuộn xuống ở v1 · (b) hai chiều | **(a)** — cuộn lên ⇒ báo "cuộn ngược lên một chút" |

## Phần 2 — Cần test tay (T)

Những thứ code + test tự động đã qua nhưng **chưa ai làm bằng tay thật**. Ghi kết quả: ✅ / ❌ + mô tả.

### Routine Notion (2026-10-15, chưa agent nào đi qua)

| Mã | Thao tác | Kỳ vọng |
|:--|:--|:--|
| T-NOTION-1 | Một Builder thật (OpenCode/DeepSeek hoặc Antigravity, đã OAuth Notion MCP) dán prompt Builder ở `AGENT_NOTION.md` §10 | Nó đọc view *Queue — Ready*, ghi `Claimed By` + `Doing` + tạo Run, đọc lại sau ~10 s, rẽ nhánh đúng SHA, làm T14d, dán gate stdout vào Run, đặt `Awaiting Claude`. Không chạm vùng Spec |
| T-NOTION-2 | Hai Builder mở cùng lúc trên cùng view | Đúng một bên giữ `Claimed By`; bên kia không ghi gì và bỏ qua |
| T-NOTION-3 | Reviewer (công cụ khác) dán prompt Reviewer | Chỉ ghi vùng Review + `Pre-reviewed`, không đổi State, không sửa file |

### Crew v2 (2026-10-18)

| Mã | Thao tác | Kỳ vọng |
|:--|:--|:--|
| T-CREW-1 | mở crew **Lead Architect** trên một repo thử (không phải XFinder), goal nhỏ, **một** lượt model mỗi thành viên (Q-P7b-MODEL còn treo). e2e `scripts/e2e-crew-v2.sh` đã chứng minh 33/33 với `claude` giả; chỉ còn cái người/model thật mới kiểm được | (a) mỗi builder có `wt/<role>` và nhánh `crew/<slug>-<role>` và `git worktree list` đúng; (b) lead nhắn đúng mẫu `[TIME] [FROM] -> [TO] / TASK | CRITERIA | BRANCH`; (c) **Claude thật** bị guard chặn khi sửa file ngoài worktree và hiện thẻ khi chạy `git commit`/`git -C . push` (hook `--crew-guard` qua `--settings`); (d) merge trước 2 Approved bị từ chối; sau 2 Approved lead chạy `git merge` và **thẻ hiện trên notch**; (e) dừng crew: nhánh còn, worktree sạch mất, worktree có file chưa commit nằm trong `crew-kept/` |

### Hiệu năng sau commit `3fe1b66` (2026-10-18)

| Mã | Thao tác | Kỳ vọng |
|:--|:--|:--|
| T-PERF-1 | Khởi động XFinder, không mở trang Pin trong 60 s; `ps -o time= -p $(pgrep -x XFinder)` ở 0 s và 60 s; `log show --last 2m --predicate 'process == "XFinder" AND subsystem == "com.apple.bluetooth"'` | CPU ≈ 0,00–0,05 s/60 s; **không** dòng `CBCentralManager`/`scanForPeripherals` nào trước khi trang Pin mở (Claude đo 2026-10-18 11:04 trên bản cài: 0 dòng; 24 dòng IOBluetooth/CoreBluetooth còn lại là đăng ký thông báo kết nối của **Hoạt động trực tiếp ▸ Bluetooth** — có hàng catalog, tắt được ở trang đó); mở trang Pin ⇒ thiết bị Bluetooth hiện sau vài giây (GATT scan bắt đầu lúc đó) |

### Nhớ bố cục cửa sổ (2026-10-18, chưa ai thử bằng tay)

| Mã | Thao tác | Kỳ vọng |
|:--|:--|:--|
| T-SNAPMEM-1 | Vùng bắt dính ▸ bật "Nhớ bố cục theo bộ màn hình". Kéo Chrome vào mép phải (hoặc ⌃⌥→). Thoát Chrome, mở lại | Hàng luật "Chrome · Phải nửa màn hình · <tên màn>" xuất hiện ngay sau khi bắt dính; Chrome mở lại nằm đúng nửa phải trong ~0,5–2 s; hàng luật ghi "Đã áp" **Đo 2026-10-18 16:53 (e2e, app thử): cửa sổ ĐÃ về leftHalf của engine — x=48 w=840 vì `snapzones.stageInset`=48 + Stage Manager bật; hai lần FAIL trước là harness đo quá sớm (0,3 s, trước replay 0,5 s) rồi đo thiếu inset. Phase b (không luật ⇒ không di chuyển) PASS. Còn lại cho tay người: màn hình ngoài, fullscreen, app thật.** |
| T-T24-1 | Ghi chú mép: rê chuột lên viên của một ghi chú 9 dòng (như ảnh 7 things before every trade) | thẻ hiện **đủ 9 dòng**, rộng hơn (248 pt), chữ 11 pt; ghi chú rất dài: cắt "…" + dòng "còn N dòng nữa — bấm để mở"; với 1–2 ghi chú thẻ **không** bị cắt đáy; rê dọc dải vẫn chuyển từ ghi chú này sang ghi chú kế mà không nhảy **Lần 1 (20:4x) HỎNG: 8/9 dòng — đo chữ 13 pt/dòng thay vì 14 của SwiftUI; sửa `1560eb6`, đã cài. Lần 2: **PASS** (chủ dự án, đủ 9 dòng).** |
| T-T24-2 | Ghi chú ▸ Ghi chú ở mép màn hình ▸ bật "Phím tắt ⌃⌥N…"; vào Safari, bấm ⌃⌥N; bấm lại | editor mép mở trên ghi chú đầu dải, gõ được ngay; bấm lại thì đóng; không có ghi chú ⇒ tạo mới **PASS 2026-10-18 (chủ dự án) sau khi bật công tắc; lần đầu "không mở" vì công tắc chưa bật — khoá vắng trong defaults.** |
| T-T24-3 | Sửa một ghi chú bất kỳ; Ghi chú ▸ Nhập / Xuất ▸ "Mở thư mục sao lưu" | có `notes-<hôm nay>.json` + `.md`; "Nhập… ▸ JSON" từ file đó khôi phục đủ danh sách; "Bản gần nhất: <ngày>" hiện trên trang **PASS 2026-10-18 (chủ dự án): file có từ 20:36, nhập JSON khôi phục đủ (nhập = thay toàn bộ, không nhân đôi).** |
| T-T21-1 | Chia sẻ nhanh ▸ chia sẻ một file, chép link, mở trên điện thoại cùng Wi-Fi (hoặc `curl -O <link>`); rồi Tính năng & Quyền ▸ **Tắt tất cả** (hoặc tắt "Cho phép Chia sẻ nhanh" đầu trang) | **PASS 2026-10-19 (chủ dự án: "đã làm việc"). Câu hỏi kèm theo "điện thoại lấy link kiểu gì" ⇒ QR (T-T21-3/4).**  tải được trước khi tắt; sau khi tắt: danh sách liên kết rỗng, nhãn đầu trang "Đang tắt", link cũ **không** tải được (kết nối bị từ chối), nút "Chọn file…" xám. File tên tiếng Việt tải về **giữ đúng tên** (trước đây header thô) |
| T-T21-2 | Kết nối từ xa ▸ **Thêm kết nối…** một máy chủ bất kỳ (tên + host là đủ, không cần đúng) rồi tắt "Cho phép Kết nối từ xa" | Nút "Tải lên…" nằm **trên hàng của từng kết nối** — chưa có kết nối thì không có nút (2026-10-19 chủ dự án "không thấy nút": đúng, trang rỗng; giờ dòng trống nói rõ điều đó). Sau khi tắt: "Tải lên…", "Kiểm tra kết nối" (menu ⋯) và "Kiểm tra" trong hộp thêm/sửa đều xám; danh sách vẫn còn; bật lại ⇒ dùng như cũ **PASS 2026-10-19 (chủ dự án): tắt thì các nút xám hết.** |
| T-T21-3 | Chia sẻ nhanh ▸ chia sẻ một file ▸ bấm nút **QR** trên hàng ▸ mở Camera iPhone/Android cùng Wi-Fi, quét | Safari/Chrome của điện thoại mở `http://<ip>:<cổng>/<mã>` và tải file đúng tên; không cần cài gì **PASS 2026-10-19 (chủ dự án) sau `0b0a9a2` — lần đầu "không thấy QR": nút chỉ là icon và chỉ hiện khi đã có file, bản cài vừa relaunch app làm mất danh sách; giờ QR tự bật sau khi chọn file.** |
| T-T21-4 | Chia sẻ 2–3 file ▸ **QR cho tất cả** ▸ quét | Trang web liệt kê đủ các file, chạm một file thì tải; tên file có `<` `"` hiện nguyên văn (không thành thẻ HTML); sau "Thu hồi tất cả" quét lại ⇒ không mở được **PASS 2026-10-19 (chủ dự án): quét QR chung thấy đủ file. Chưa xác nhận: tên có `<`/`"`, quét lại sau Thu hồi (cả hai có test tự động + mutation C10/C11).** |
| T-POL-1 | Chụp màn hình ▸ Đếm ngược = 3 giây ▸ bấm "Chụp" ở hàng **Toàn màn hình** | chụp sau ~3 s; kiểu Vùng chọn/Chú thích/Chữ/Màu không đếm (vì có bước chọn) **PASS 2026-10-19 (chủ dự án): đếm 3 giây rồi chụp. Chưa xác nhận tay: các kiểu có bước chọn không đếm (test tự động + mutation K11 canh).** |
| T-POL-2 | Chụp màn hình ▸ tắt "Bóng đổ cửa sổ" ▸ chụp **Cửa sổ đang mở** | ảnh không có viền bóng macOS; bật lại ⇒ có bóng **PASS 2026-10-19 (chủ dự án).** |
| T-POL-3 | Xem trước cửa sổ ▸ kéo "Độ trễ trước khi hiện" lên 600 ms ▸ lướt chuột qua Dock | lướt nhanh không mở bảng; dừng ≥ 0,6 s mới mở; kéo về 80 ms thì gần như tức thì **2026-10-19 chủ dự án: ảnh xem trước bị CHÉO** — đo: app nằm ở dải Stage Manager bị macOS xoay 3D, cache ảnh không hết hạn giữ ảnh nghiêng; đang sửa + brief thiết kế lại chờ `ok`. |
| T-POL-4 | Quick Look ▸ Bảo trì ▸ "Làm mới bộ nhớ đệm Quick Look" | dòng "Đã xoá bộ nhớ đệm…" hiện sau ~1 s; Finder vẽ lại ảnh thu nhỏ khi mở lại thư mục **PASS 2026-10-19 (chủ dự án).** |
| T-HUD-3 | Bấm âm lượng / độ sáng (notch đang thu gọn) | Notch **nở ngang** cùng chiều cao, cùng góc bo với cánh thu gọn: loa/mặt trời ở cánh trái, thanh mức mảnh ở cánh phải; không còn tấm đen thả xuống dưới. Màn ngoài không notch: viên thuốc ở mép trên **PASS 2026-10-19 (chủ dự án).** |
| T-HUD-2 | Đang phát nhạc, bấm tăng/giảm âm lượng và độ sáng: (a) không đụng notch; (b) rê lên notch cho dải nhạc hiện rồi bấm; (c) mở trang Đang phát trên notch rồi bấm | (a) và (b): ô Âm lượng/Độ sáng hiện ngay ở notch, kể cả khi đang có thông báo agent (thông báo agent quay lại sau); (c): hộp vuông của macOS hiện (trong hub XFinder nhường phím cho macOS) **PASS 2026-10-19 (chủ dự án) — kèm nhận xét giao diện HUD không đồng nhất ⇒ T-HUD-3.** |
| T-DOCK-1 | Stage Manager bật. Bấm sang một app (để nó lên giữa), chờ 1 s, bấm app khác (app đầu vào dải trái). Rê chuột lên icon Dock của app đầu | Ảnh **thẳng, nét**, là cửa sổ lúc nó còn ở giữa; nhãn nhỏ "Trong Stage Manager" ở góc. Không còn ảnh nghiêng **PASS 2026-10-20 (chủ dự án): ảnh thẳng.** |
| T-DOCK-2 | Rê lên icon một app có 2–4 cửa sổ (Finder mở vài cửa sổ) | Panel có tiêu đề (icon + tên app + "N cửa sổ"), mỗi cửa sổ một thẻ, ảnh **không bị cắt** (cả cửa sổ nằm gọn trong khung 16:10), tên cửa sổ dưới ảnh; bấm thẻ nào thì đúng cửa sổ đó lên trước **Lần 1 (2026-10-20) HỎNG: Finder "5 windows" + ô trống, Claude 3 / TradingView 6, panel TradingView tràn mép, mất dòng tên — CG đếm tab và cửa sổ phụ (AX: Finder 2, Claude 1, TradingView 1); sửa `753dd9d`. Lần 2: đếm đúng (Finder 2), nhưng kích thước thẻ nhảy theo số cửa sổ + nhãn Stage Manager rối + Switcher ⌘-Tab thẻ trống ⇒ `5a55c26`: thẻ cố định 304×160 như thẻ Chrome, bỏ nhãn, Switcher lấy cửa sổ thật qua AX. Lần 3: **PASS (thẻ cố định)**; Switcher: Safari ở Space khác thẻ trống ⇒ sửa (chọn cửa sổ có tên + lớn nhất; Space khác chụp qua đường legacy). Switcher PASS (Safari có ảnh). Thẻ "to quá" ⇒ DockCard 208×130 (panel một thẻ 224×182, trước 320×220), chung cho cửa sổ và tab trình duyệt. 2026-10-21: chủ dự án muốn "như Switcher" ⇒ `0691fab` thẻ 200 pt, ảnh 184×86 lấp khung, chỉ icon + tên app; Switcher thỉnh thoảng ảnh nghiêng (chụp lúc cửa sổ bay vào dải) ⇒ kiểm nghiêng theo pixel. Rồi viền mỏng kiểu MacBook (`ae3d56d`, lề 6, góc đồng tâm 14) + thẻ tab trình duyệt cùng kiểu (`c742777`): **PASS 2026-10-21 (chủ dự án: "thẻ tab ok rồi")**.** |
| T-DOCK-3 | Nhìn nền panel (macOS 26+) | Vật liệu Liquid Glass của hệ thống (khúc xạ nền phía sau), góc bo như cũ |
| T-MEM-1 | (2026-10-21) Chụp 3 ảnh vào clipboard liên tiếp (⌃⇧⌘4), chờ 10 s, chạy `footprint $(pgrep -x XFinder) \| grep Footprint` | Footprint **gần như không đổi** (≈ 30–45 MB). Trước bản này: 43 → 125 MB, đỉnh 170 MB — Vision OCR của clipboard giữ lại +21 MB (fast) / +54 MB (accurate) mãi trong app; giờ OCR chạy trong tiến trình con `XFinder --ocr`, thoát là trả bộ nhớ. Tìm chữ có trong ảnh ở Thư viện clipboard vẫn ra ảnh đó (OCR vẫn chạy) **PASS 2026-10-21 (chủ dự án): footprint giữ ~40 MB.** |
| T-MEM-2 | Chụp màn hình ▸ một ảnh trong Lịch sử ▸ "Sao chép chữ"; và notch ▸ Khay ▸ một ảnh ▸ OCR | Chữ vào clipboard như trước (tiếng Việt giữ dấu). Lần **đầu tiên** sau khi cài có thể chờ vài giây (daemon Neural Engine — đo một lần > 15 s, các lần sau 0,2 s) |
| T-MEM-3 | Notch ▸ Khay ▸ thả một ảnh có chủ thể ▸ **Tách nền**; và Thao tác Finder ▸ Tách nền | File `<tên>-cutout.png` nền trong suốt như trước; footprint app không tăng sau đó (tách nền cũng chạy trong `XFinder --vision cutout`; đo trong app cũ giữ lại +29 MB mỗi tiến trình). Ảnh không có chủ thể ⇒ thông báo "Không tìm thấy chủ thể…" như cũ (nút chỉ hiện sau khi chọn ảnh: Thao tác Finder ▸ "Đọc lựa chọn" ▸ nhóm Ảnh; hoặc khay notch đang giữ ảnh) |
| T-DOCK-4 | Stage Manager bật. ⌘-Tab qua lại liên tục giữa 3 app trong 1 phút, rồi rê lên icon Dock của một app đang nằm ở dải trái | Ảnh vẫn thẳng (chụp lúc app lên giữa, cũ nhất ~30 s). Bản này chỉ chụp sẵn tối đa 1 lần/app/30 s thay vì mỗi lần chuyển app |
| T-T25-1 | Chuột & cử chỉ ▸ Cuộn chuột mượt ▸ bật. Lăn bánh xe chuột (Razer) trong Safari, Finder, Xcode | Trôi mượt thay vì nhảy nấc; dòng trạng thái ghi "Lần cuộn vừa rồi: bánh xe chuột — đã làm mượt" |
| T-T25-2 | Cuộn bằng trackpad / Magic Mouse khi cuộn mượt đang bật | Như cũ (có quán tính của macOS); dòng trạng thái ghi "trackpad hoặc Magic Mouse — giữ nguyên" |
| T-T25-3 | Giữ ⌘ (hoặc ⌥) rồi lăn trong trình duyệt / Preview | Phóng to như cũ, không bị làm mượt |
| T-T25-4 | Mở Mos khi cuộn mượt đang bật; rồi thoát Mos | Trang ghi "Đang tạm dừng: Mos cũng làm mượt cuộn"; thoát Mos ⇒ chạy lại |
| T-T25-5 | Kéo Tốc độ lên 200 %, Độ mượt xuống 80 ms; bật Đảo chiều | Mỗi nấc đi xa gấp đôi, dừng nhanh; chiều bánh xe đảo, trackpad không đổi |
| T-T26-1 | Chụp màn hình ▸ Chụp cuộn ▸ kéo một vùng trên một trang web dài ▸ tự cuộn bằng tay xuống ▸ Enter | Một ảnh dài trong Lịch sử + thẻ Quick Access; không lặp, không hụt đoạn |
| T-T26-2 | Như trên nhưng bấm **Tự cuộn** | XFinder tự cuộn, tự dừng ở cuối trang ("Đã đến cuối trang") |
| T-T26-3 | Trang có header dính (GitHub, Notion) | Header xuất hiện một lần ở đầu ảnh |
| T-T26-4 | Cuộn tay thật nhanh một cú dài | Thanh báo "Không ghép được đoạn mới — cuộn ngược lên một chút"; cuộn ngược ⇒ ghép tiếp |
| T-T26-5 | Tự cuộn một trang rất dài | Dừng ở 20 000 px ("Đã đến giới hạn chiều cao"); footprint app không tăng (ảnh dài được dựng ở tiến trình con) |
| T-T27-1 | Hệ thống ▸ Chống ngủ 15 phút ▸ để yên máy quá thời gian tắt màn hình thường lệ; Terminal: `pmset -g assertions \| grep XFinder` | Màn hình **không** tắt; có 2 dòng XFinder (hệ thống + màn hình). Tắt "Giữ cả màn hình sáng" ⇒ còn 1 dòng |
| T-T27-2 | Bật Chống ngủ vô hạn, thoát XFinder, mở lại | Vẫn bật ("∞ Vô hạn") |
| T-T27-3 | Menu bar ▸ Lau bàn phím… | Lớp phủ trên mọi màn hình, gõ không ra chữ, phím âm lượng/độ sáng không đổi gì, chuột vẫn bấm được; Esc 5 lần ⇒ mở; để yên 2 phút ⇒ tự mở |
| T-CAP-RET | Chụp màn hình ▸ Gần đây ▸ Xoá ảnh chụp sau = 1 ngày | Ảnh cũ hơn 1 ngày biến khỏi lưới và nằm trong Thùng rác |
| T-MEM-4 | Mở Thư viện clipboard, cuộn qua nhiều ảnh, đóng lại; `footprint` trước/sau | Footprint quay về gần mức trước khi mở (đối chiếu: ứng dụng tham chiếu báo tới ~330 MB giữ lại sau khi đóng) |
| T-MEM-5 | Chụp cuộn một trang dài (≥ 10 lần cuộn), chép ảnh vào clipboard 3–4 lần; `footprint $(pgrep -x XFinder)` trước/sau | Tăng ≤ ~10 MB và không leo theo số lần chép (trước `edff2af`/`31e2b13`: 12 khung 10 MB + ~42 MB mỗi lần chép ⇒ 257–374 MB, đỉnh 821 MB) |
| T-CLIP-IMG | Chép cùng một ảnh hai lần trong 10 s; chép một file `.svg` trong Finder | Lần hai không thành dòng mới; SVG hiện là **ảnh** có thumbnail (`e05a67f`) |
| T-SEARCH-1 | Tìm kiếm AI: gõ "ảnh"; trang Tìm kiếm: để trống điều kiện rồi Tìm | Kết quả hiện gần như ngay (< 1 s cho "ảnh"), tiêu đề "100+ kết quả", dòng cuối "…và 50+ kết quả nữa"; không treo (trước: 2 s / 35 s, "100 kết quả") |
| T-PASTE-1 | Chụp màn hình → bấm Sao chép; dán vào Messages/Notes/Preview (Tệp ▸ Mới từ Clipboard); mở Thư viện clipboard, dán lại một ảnh cũ | Dán được ở cả ba app (Preview đọc TIFF lười — kiểm nó vẫn ra ảnh); `footprint` không tăng vài chục MB mỗi lần (trước: 92–94 MB/lần với ảnh chụp cuộn) |
| Q-T28-1 | Trình duyệt tệp: phân tầng Free/PRO như FileOctopus (2 ngăn miễn phí)? | **Mặc định: mọi thứ miễn phí, 16 ngăn** — XFinder không có hệ thống giấy phép |
| Q-T28-3 | ⌘F trong trình duyệt = lọc thư mục hiện tại, ⌥⌘F = tìm kiếm (FileOctopus: ⌘F = tìm)? | **Thay bởi Q-T30-2** (⌘F = Tìm như FileOctopus) |
| Q-T28-4 | Di chuyển khác ổ: bản gốc sau khi kiểm SHA-256 đi đâu? | **Mặc định: Thùng rác** (luật 9); FileOctopus xoá hẳn |
| Q-T28-6 | "Mở trong Google Drive" / "Sao chép liên kết Drive" | v2 — máy này không cài Drive/Dropbox, chưa đo được xattr của Drive |
| T-T28-1…10 | Trình duyệt tệp — xem `docs/specs/XF-T28-file-browser.md` §7 (bước + kỳ vọng từng mục) | chờ bản cài có giao diện thật |
| Q-T30-1 | Trình duyệt (XF-T30): nút Lùi/Tiến trên toolbar áp cho ngăn nào? | **Ngăn đang chọn** (như FileOctopus); nút chuột 4/5 + vuốt áp cho ngăn dưới con trỏ và chọn nó |
| Q-T30-2 | ⌘F trong trình duyệt | **= Tìm** như FileOctopus (thay Q-T28-3); "Lọc thư mục hiện tại" thành lệnh không phím |
| Q-T30-4 | Đóng tab cuối của một ngăn | **Đóng ngăn** nếu còn ngăn khác; ngăn cuối + tab cuối ⇒ lệnh xám |
| Q-T30-6 | "Đổi chỗ với ngăn kế" | **Đổi nội dung** (chồng tab + lịch sử), vị trí ngăn giữ nguyên |
| Q-T30-7 | Khôi phục Column view | **Hơn FileOctopus**: khôi phục cả đường cột (họ chỉ khôi phục thư mục cuối) |
| Q-T30-8 | Cửa sổ License / dải "14 days left · Upgrade" / bước trial trong Welcome | **Không làm** khi Pro còn ngủ (bạn: chưa bán) |
| Q-T30-9 | Bước "Usage Statistics" của Welcome | **Bỏ** — trình duyệt không gửi gì; Welcome 4 bước: Chào · Quyền thư mục · Full Disk Access (bỏ qua được) · Chọn bố cục |
| Q-T30-12 | Trang "Trình duyệt tệp" cũ trong XFinder | Giữ bật/tắt + phím toàn cục + nút **"Mở cài đặt trình duyệt…"**; mọi cài đặt khác của trình duyệt chỉ ở cửa sổ Cài đặt trình duyệt (một khoá một control). Trang khác của XFinder **không** gộp |
| Q-T30-13 | Menu bar khi cửa sổ trình duyệt ở trước | Thêm mục Tệp/Xem/Đi/Cửa sổ của trình duyệt nếu SwiftUI không ghi đè (chưa đo — T-T30-MENU) |
| T-T30-1…6 | Trình duyệt W1 (tab trong ngăn, tab cửa sổ, toolbar, các thanh, chọn ngăn theo hướng) — bước + kỳ vọng ở `docs/specs/XF-T30-w1-contract.md` §8 | chờ bản cài W1 |
| Q-T30-14 | Tìm "Máy này" khi chưa có thư mục đánh chỉ mục | **Spotlight toàn máy** (XFinder đã có); FileOctopus lùi về thư mục hiện tại |
| Q-T30-15 | Get Info ▸ Mở bằng: có nút "Thay đổi tất cả…" (đổi app mặc định hệ thống)? | **Không** — đổi cấu hình máy, chỉ làm khi bạn gật |
| T-T30-7…18 | Kiểu xem / sidebar / menu Đi (W2–W3): tam giác + ⌥→, Nhóm theo ngày, chuột phải tiêu đề cột, ⌘J, chấm thẻ, kéo giữ trên thư mục thì mở; Gần đây / AirDrop / Thẻ / Tất cả thẻ; cắm USB hiện ngay; ⌘E ổ hai phân vùng hỏi; ⇧⌘D / ⌥⌘L / ⇧⌘H; ⌘K | chờ bản cài |
| T-T30-19…24 | Cài đặt trình duyệt (⌘, khi trình duyệt ở trước, 7 tab), đổi phím + xung đột "Vẫn dùng", hồ sơ Total Commander (F5 chép sang ngăn kia), Xuất/Nhập, Welcome lần đầu + "Hiện cửa sổ Chào…", ⌘X kiểu Windows (tệp mờ, ⌘V nơi khác chuyển) | chờ bản cài |
| T-T30-25…30 | Gộp thư mục trùng tên, chép 1 000 tệp có 1 tệp khoá ⇒ 999 xong + Sự cố + Thử lại, tốc độ/ETA, thoát app rồi ⌘Z hoàn tác chuyển, ⇧⌘Z làm lại, ⌃⌘N | chờ bản cài |
| T-T30-31…36 | ⇧⌘P xem trước, ⌥⌘Y trình chiếu, ⌘I đủ mục, Thông tin ổ, Tải về ngay / Gỡ bản tải trong iCloud Drive, badge đám mây | chờ bản cài |
| T-T30-SEARCH | Cài đặt ▸ Tìm kiếm thêm một thư mục, bật Nội dung; tìm "bao cao" thấy "Báo cáo.pdf"; tìm "hop dong" thấy PDF có chữ "hợp đồng"; Lưu tìm kiếm vào sidebar | chờ bản cài |
| T-T30-CLOUD | Google Drive / Dropbox: chưa cài trên máy ⇒ "Mở trong Google Drive" / "Sao chép liên kết" / "Xem trên Dropbox.com" chưa làm (không đo được cơ chế) | cần máy có cài |
| T-T30-MENU | Menu bar khi cửa sổ trình duyệt ở trước có Tệp/Xem/Đi/Cửa sổ của trình duyệt không (SwiftUI có ghi đè không) | chờ bạn nhìn |
| T-T30-SESSION | Mở trình duyệt, chọn Side by Side, đóng cửa sổ cuối (⌘W) rồi mở lại từ menu bar / ⌘N; lần hai: thoát app (⌘Q), mở lại; lần ba: đóng hết rồi bấm một thư mục trong sidebar XFinder | Cả ba lần quay về Side by Side đúng thư mục; lần ba thư mục vừa bấm là tab mới ở ngăn đang chọn |
| T-PERF-LAUNCH | Thoát app, mở lại, đếm tới lúc notch/menu bar phản hồi | Không còn 4–5 s nặng máy; danh sách phiên agent hiện sau ~1 s, không có thông báo cũ bắn lại |
| T-T31-1 | Side by Side trên `~`, chọn một hàng, rồi từ Terminal `touch ~/x.txt` và `rm ~/x.txt` | hàng x.txt hiện/mất tại chỗ; hàng đang chọn và vị trí cuộn giữ nguyên; không có vòng xoay |
| T-T31-2 | Mở rộng một thư mục con trong List (tam giác), rồi tạo tệp ở `~` | thư mục con vẫn mở rộng sau khi tệp mới hiện |
| T-T31-3 | Đổi tên một tệp giữa danh sách sao cho vị trí sắp xếp đổi | danh sách sắp lại đúng (đường reload) |
| T-T31-4 | Side by Side, click một hàng ở ngăn KHÔNG đang chọn, rồi click một hàng ở ngăn đang chọn | cả hai lần hàng được chọn ngay; không cần click lần hai (trước 26/10 overlay nhận kéo tab nuốt mọi click vào nội dung ngăn) |
| T-T31-5 | Kéo một tab ngăn thả vào mép trái/phải/dưới của ngăn khác, và thả vào giữa | mép ⇒ chia ngăn + tab vào ngăn mới (tô sáng nửa ngăn khi rê); giữa ⇒ tab nối cuối (viền quanh ngăn); thả vào dải tab ⇒ chèn đúng vị trí |
| Q-T31-1 | Hai ngăn/tab cùng thư mục: dùng chung listing + watcher (DirectoryLoadCoordinator)? | mặc định: làm sau khi h2h có số |
| Q-T31-2 | Badge đám mây đọc theo lô 50 ở nền (CloudLookupBatch)? | mặc định: có, sau T-T31 |
| Q-T31-3 | MainThreadWatchdog bản Debug (log + sample khi main > 250 ms)? | mặc định: có |
| Q-T32-0…13 | Hướng Tilde cho trình duyệt (spec `docs/specs/XF-T32-tilde-direction.md`) | 2026-10-26 chủ dự án chọn: làm cả W0 → W1+W2+W3 → W4+W5 → W6, fan-out agent theo file; mặc định Q-T32-* giữ nguyên trừ khi trả lời bằng mã |
| T-T32-W0-1 | Mở một thư mục nhiều tệp, sang thư mục khác, quay lại | lần quay lại danh sách hiện ngay (từ cache), vài trăm ms sau tự vá nếu có tệp đổi; không chớp spinner |
| T-T32-W0-2 | Side by Side, hai ngăn cùng một thư mục; tạo một tệp mới trong Finder | cả hai ngăn cùng hiện tệp mới (một watcher chung), không ngăn nào mất cuộn/chọn |
| T-T32-W0-3 | Chọn một thư mục con, ⌘↑ | thư mục vừa rời được chọn sẵn ở thư mục cha (cả khi danh sách đến từ cache) |
| Q-T31-1 | (đã áp 26/10) Hai ngăn/tab cùng thư mục dùng chung listing + watcher | `DirectoryLoadCoordinator`, `60e8e71` |
| W6-MERGE-QUEUE | **Đã làm** (`.merge` job): gộp hiện trong bảng Thao tác, tạm dừng / huỷ được, bước lỗi vào Sự cố, ⌘Z đưa từng mục về chỗ cũ | thử: gộp hai thư mục trùng tên lớn, bấm Tạm dừng giữa chừng, rồi ⌘Z |
| Q-PRO-5 | Tạo cặp khoá ký giấy phép trên máy bạn: `swift scripts/make-license.swift init ~/Private/xfinder-license.key`, dán khoá công khai in ra vào `LicenseKey.publicKeyRaw` | chưa có ⇒ mọi khoá không hợp lệ; dùng thử + bản Debug vẫn đủ |
| Q-PRO-6 | Free: xuất toàn bộ lịch sử Clipboard (.xfinderclip) có bị giới hạn 50 mục không? | **Mặc định: không** — dữ liệu của chính người dùng (luật 9) |
| T-PRO-1 | Trang XFinder Pro ▸ Thử giới hạn = Miễn phí; chép 60 mục | 50 hiện + dòng "10 mục cũ hơn — mở bằng Pro"; chọn Pro ⇒ hiện đủ 60 |
| T-PRO-2 | Thử giới hạn = Miễn phí; chụp 25 ảnh | 20 hiện + nút "Dọn ảnh cũ vào Thùng rác"; Chụp cuộn hiện nhãn PRO |
| T-PRO-3 | Thử giới hạn = Miễn phí; trình duyệt chia ngăn thứ 3; Lưu Workspace; Đồng bộ ngay | bị chặn kèm nhãn PRO / banner; bố cục, cặp đồng bộ, vault đã có vẫn còn |
| T-HUD-7 | Đang phát nhạc: rê lên notch cho dải Đang phát hiện, giữ chuột ở đó, bấm phím âm lượng | Ô âm lượng hiện thay dải nhạc; ~1,5 s sau **dải nhạc quay lại** (trước: biến mất tới khi rê lại). Bấm xong rời chuột khỏi notch ⇒ dải đóng như thường |
| T-SNAPMEM-2 | Với luật trên, rút màn ngoài rồi cắm lại (hoặc ngược lại) | Luật ghi với bộ "màn trong + HC-L200A" chỉ áp khi đủ hai màn; khi chỉ còn màn trong, Chrome **không** bị kéo đi; cắm lại ⇒ áp trong ~1–3 s |
| T-SNAPMEM-3 | Đưa một app đã có luật vào toàn màn hình (nút xanh), thoát app, mở lại | Hàng luật đổi thành "Toàn màn hình (Space riêng)"; mở lại ⇒ app vào toàn màn hình trên đúng màn. App không cho đặt ⇒ hàng ghi "App không cho đặt toàn màn hình qua Trợ năng", không thử lại |
| T-SNAPMEM-4 | Mở hộp thoại Lưu (⌘S) hoặc ⌘N trong app đã có luật, đang chạy | Cửa sổ chính **không** bị kéo lại chỗ cũ (chỉ lần mở app mới áp) |
| T-SNAPMEM-5 | Bật "Nhớ cả vị trí tự kéo", kéo tay cửa sổ đã có luật sang chỗ khác, thả | Sau ~0,6 s hàng luật đổi thành "Vị trí tự kéo" (hoặc đúng ô nếu bạn thả vừa khít một ô); tắt công tắc này thì kéo tay không đổi luật |

### Orca (2026-10-18, chưa cài)

| Mã | Thao tác | Kỳ vọng |
|:--|:--|:--|
| T-ORCA-1 | `brew install --cask stablyai/orca/orca`, thêm repo, tạo một worktree; `.worktreeinclude` có `CLAUDE.md` | Worktree có `CLAUDE.md` (file bị gitignore, Orca copy) |
| T-ORCA-2 | `orca worktree create --name agent/opencode-XF-T20 --agent opencode --prompt "<Builder §10>" --json` | nhánh trong worktree đúng tên; agent nhận prompt |
| T-ORCA-3 | `XF_ROOT=<wt> XF_OUT=$TMPDIR/xf-<wt> sh scripts/gate-all.sh` trong worktree, song song với checkout chính | hai build không ghi đè nhau; `lsregister -dump` sạch sau khi xoá worktree |
| T-ORCA-4 | Bật Agent status hooks rồi diff cấu trúc `~/.claude/settings.json` (không in nội dung) và `/hooks` trong Codex | hook XFinder/OneNotch/Notch Crew còn nguyên; Codex không mất trust hook XFinder |
| T-ORCA-5 | Orca nhàn 60 s | `ps -o time=` và footprint — ghi số |
| T-ORCA-6 | Một Builder thật làm T14d trong Orca theo AGENT_NOTION §4 | = T-NOTION-1 nhưng trong worktree của Orca |

### Notch
| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-HUD-1 | Bấm phím âm lượng và độ sáng **thật** trên bàn phím (chế độ "Chỉ dùng notch cho độ sáng và âm lượng" giờ **mặc định bật**, cần quyền Trợ năng) | Chỉ notch hiện mức (âm lượng, độ sáng); **hộp vuông của macOS không hiện**; mức đổi từng nấc 1/16. Claude đã đo bằng phím giả lập gửi ở tầng HID trên app đã cài (2026-10-15): 0 cửa sổ hộp `MenuBarAgent`, notch đọc "Brightness 94%" — phím thật đi cùng đường đó nhưng chưa ai bấm |
| T-HUD-6 | Bấm liên tục / giữ phím âm lượng và độ sáng (bản 2026-10-15 chiều, `59d0380`) | Dải trên notch hiện gần như ngay lập tức, không nảy; thanh mức trượt theo từng nấc, không giật; chữ % không làm cả dòng xô sang trái phải. Đo trong app: dữ liệu tới notch < 1 ms, giao diện cập nhật 2–10 ms — còn khựng là phần cảm giác, chỉ tay bạn đánh giá được |
| T-HUD-2 | Giữ ⌥⇧ rồi bấm phím âm lượng | macOS tự xử lý (bước nhỏ ¼ nấc, hộp vuông của macOS hiện) — XFinder cố ý không nhận |
| T-HUD-3 | Đang ở mức 100 % (hoặc 0 %), bấm tiếp phím tăng (giảm) | Notch vẫn hiện thanh đầy (rỗng), phím không "chết" |
| T-HUD-4 | Chuyển loa ra HDMI / thiết bị không chỉnh được âm lượng, bấm phím âm lượng | macOS hiện hộp "không khả dụng" của nó; XFinder không nuốt phím |
| T-HUD-5 | Tắt "Chỉ dùng notch…" | Hộp vuông của macOS trở lại như cũ; công tắc "Độ sáng" mờ đi (độ sáng chỉ hiện trên notch khi XFinder nhận phím) |
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

### P8–P10 · Agent trên notch, chuyển phiên, danh sách (dựng 2026-10-14)

| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-P8-WING | Chạy 1 rồi 3 phiên agent | Cánh trái: một ô logo (agent khẩn nhất) + số phiên bên cạnh khi ≥ 2; cánh phải: lưới chấm chạy khi có phiên đang làm, cam khi có phiên chờ bạn |
| T-P8-QUIET | Một phiên trong kitty xong lượt khi kitty đang ở trước / ở sau | Ở trước: không thông báo, không âm thanh; ở sau: có |
| T-P9-HANDOFF | Notch ▸ Agents ▸ icon nhánh trên một phiên ▸ Claude Code ▸ đọc tin ▸ Gửi | Phiên Claude không cửa sổ mới trả lời 3 dòng mục tiêu / hiện trạng / bước tiếp theo rồi chờ |
| T-P9-OPENCODE | Như trên, đích OpenCode | Phiên OpenCode mới (tiêu đề "Handoff from …") trong đúng thư mục, nhận tin |
| T-P10-EDGE | Rê chuột dừng trên ô agent ở cánh trái notch | Trang Agents mở thẳng, dù "Rê chuột vào notch mở" chọn gì |
| T-P10-SORT | Đổi "Sắp xếp phiên" và tắt "Giữ phiên đã kết thúc" | Thứ tự đổi ngay; phiên đã kết thúc biến khỏi notch |
| T-P12-HOOK | Agent AI ▸ hook Claude Code: trạng thái báo thiếu `StopFailure` → bấm **Cài / Cập nhật hook** | Trạng thái về "Đã cài"; `~/.claude/settings.json` có thêm `StopFailure` (bản sao lưu có ngày nằm cạnh) |
| T-P12-LIMIT | Khi một phiên Claude Code thật chạm giới hạn ("API Error: Rate limit reached") | Hàng phiên đổi thành **"Chạm giới hạn"** (không còn "đang chạy" hay "Tới lượt bạn"); notch hiện **một** thông báo đỏ "Phiên dừng vì chạm giới hạn" với nút **"Chuyển sang Codex…"** (hoặc agent khác đang cài) — kể cả khi app Claude đang ở phía trước |
| T-P12-HANDOFF | Bấm nút đó | Mở bảng chuyển phiên đã chọn sẵn agent; bản ghi có dòng "Phiên đó dừng giữa chừng vì chạm giới hạn sử dụng", "Phiên đó vẫn mở…", và mục "Log đầy đủ" là một đường dẫn. **Chưa gửi gì** cho tới khi bạn bấm Gửi |
| T-P12-RESUME | Nếu Claude Code tự chạy tiếp khi hạn mức hồi lại | Hàng phiên quay về "đang chạy", nhãn "Chạm giới hạn" biến mất |
| T-P11-START | Notch ▸ Agents ▸ "+" ▸ chọn Codex ▸ thư mục ▸ "liệt kê tệp ở đây" ▸ Bắt đầu | Hàng Codex mới (ô logo Codex, khung đứt), chạy rồi "Tới lượt bạn"; hội thoại có câu trả lời. Tốn một lượt gói Codex |
| T-P11-APPROVE | Nhờ phiên Codex chạy một lệnh cần duyệt (ghi ngoài thư mục, mạng) | Thẻ Cho phép / Từ chối hiện ở hàng; bấm là Codex nhận (không cần cài hook Codex) |
| T-P11-HANDOFF | Chuyển một phiên Claude sang Codex | Mở phiên Codex không cửa sổ trong đúng thư mục, trả lời 3 dòng rồi chờ |

### 1.4.0 (đóng gói 2026-10-14, chưa đăng)

`dist/XFinder-1.4.0-arm64.zip` (7,1 MB, sha256 `02d314cc…a64a08`), ký XFinder Dev, giải nén ra vẫn `--verify --deep --strict`.
Bản 1.4.0 đã cài vào /Applications.

| Mã | Làm gì / câu hỏi | Mong đợi / mặc định |
|:--|:--|:--|
| T-1.4-WHATSNEW | Mở XFinder 1.4.0 lần đầu (đã từng dùng 1.3) | Cửa sổ "Có gì mới" hiện 7 mục của 1.4, mỗi mục mở đúng trang; lần mở sau không hiện nữa |
| Q-RELEASE-14 | Đăng 1.4.0 lên GitHub (tag `v1.4.0` + Release kèm zip và `.sha256`)? | Chưa đăng — chờ bạn |

### P7b · Nhóm agent (crew) (dựng 2026-10-14)

Agent AI ▸ **Nhóm agent (crew)**: chọn mẫu (Builder → người duyệt · Builder + hai người duyệt), thư mục, mục tiêu ▸ Bắt
đầu crew. Mỗi thành viên là một phiên không cửa sổ (P7a); họ nhắn nhau bằng `xfinder-crew send <vai> "<tin>"` và XFinder
chuyển tin + mang câu trả lời về. **Bắt đầu một crew là chạy 2–3 phiên Claude Code; người dẫn dùng một lượt ngay, mỗi tin
giữa họ là thêm một lượt** — chưa có lượt model nào được chạy để kiểm (mọi kiểm tra dùng `claude` giả: e2e 15/15).

| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-P7b-START | Bắt đầu crew "Builder → người duyệt" với một mục tiêu nhỏ | Notch ▸ Agents có một hàng crew; Builder chạy; người duyệt chờ, không tốn lượt nào |
| T-P7b-APPROVE | Khi builder muốn nhắn người duyệt | Thẻ duyệt hiện "→ reviewer: …" (không phải dòng lệnh thô); Cho phép ⇒ tin hiện trên bảng crew, người duyệt bắt đầu làm |
| T-P7b-REPLY | Người duyệt làm xong lượt đó | Câu trả lời tự quay về builder (bảng: "reviewer trả lời builder: …"); không có trả lời lặp qua lại |
| T-P7b-READONLY | Nhờ người duyệt sửa một tệp | Nó không có công cụ sửa tệp. Ghi lại: lệnh chỉ đọc (cat, grep, git diff) chạy không hỏi — đúng theo quy tắc của Claude Code |
| T-P7b-PAUSE | Tạm dừng crew rồi để builder nhắn | CLI báo "crew is paused"; không giao tin nào cho tới khi Chạy tiếp |
| T-P7b-CAP | Để crew chạy đủ 20 chặng tin | Crew tự tạm dừng, notch báo "Crew tạm dừng — chờ bạn"; Chạy tiếp cho thêm 20 |
| T-P7b-STOP | Dừng crew; thử thoát XFinder khi crew đang chạy | Mọi tiến trình `claude` của crew biến mất; thư mục crew trong Application Support bị xoá |
| T-P7b-COST | Xem dòng "≈ $" trên notch và trang cài đặt | Có tooltip "Ước tính của Claude Code, không phải hoá đơn" ở cả hai |

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| Q-P7b-APPROVE | Mỗi tin giữa các thành viên phải được bạn duyệt (chậm nhưng an toàn). Có muốn một chế độ không cần duyệt? Quy tắc prefix không nhìn thấy nội dung tin, nên chế độ đó sẽ cho mọi tin đi qua | Luôn duyệt, không có công tắc |
| Q-P7b-CAP | Tự tạm dừng sau 20 chặng tin (mỗi tin hoặc câu trả lời được giao là một chặng) | 20 |
| Q-P7b-BRANCH | Mọi thành viên làm chung một thư mục. Nhánh git / worktree riêng cho từng builder (như Notch Crew) chưa dựng | Chung thư mục |
| Q-P7b-ALLOW | Quy tắc cho phép sẵn trong `~/.claude/settings.json` hoặc của thư mục vẫn có hiệu lực với thành viên crew (trang cài đặt nói rõ). Muốn XFinder chạy thành viên với nguồn cài đặt hạn chế? Cách đó cũng bỏ luôn hook của XFinder ⇒ không duyệt được qua notch | Giữ cài đặt của bạn |

### P13 · Snap kéo cửa sổ, Theo dõi hệ thống, menu thanh trạng thái (dựng 2026-10-14)

| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-P13-1 | Kéo **thanh tiêu đề** một cửa sổ (Safari, Finder, Xcode, Claude…) chạm mép trái / phải / trên | Khung xem trước hiện; thả ra là bắt dính. Trước bản này chỉ phím tắt chạy |
| T-P13-2 | Kéo chọn chữ, hoặc kéo một file, sát mép màn hình | **Không** có khung bắt dính (cửa sổ không dịch chuyển ⇒ bị loại sau 40 pt) |
| T-P13-3 | Sidebar ▸ **Theo dõi hệ thống** ▸ bấm Hệ thống / Mạng / Ổ đĩa / Pin | Một hàng sidebar, 4 tab; số liệu chạy ở tab đang mở |
| T-P13-4 | Bấm biểu tượng XFinder trên thanh menu | Menu chữ native kiểu OneNotch (không còn popover nhiều tab); dòng phiên bản mờ; ⌘, và ⌘Q bên phải |
| T-P13-5 | Menu ▸ Chụp màn hình ▸ Chụp toàn màn hình | Menu **không** lọt vào ảnh |
| T-P13-6 | Menu ▸ Khởi động lại XFinder | App tắt rồi tự mở lại (đã đo bằng app thử: mở lại sau 0.84 s) |
| T-P13-7 | Bật ⇧⌘G (Chọn văn bản), bôi đen chữ trong Safari, rồi Menu ▸ Dịch vùng chọn | Bảng dịch hiện với đúng chữ đã bôi đen (gọi từ menu chưa đo) |
| T-P13-8 | Tổng quan ▸ **Số liệu trên thanh menu** ▸ bật, chọn CPU + RAM, đổi "Cập nhật mỗi" | Số hiện cạnh biểu tượng, đổi theo chu kỳ; tắt là mất số |
| T-P13-9 | Menu ▸ Tạm dừng ghi clipboard, copy một đoạn, rồi bỏ tạm dừng | Đoạn copy lúc tạm dừng không vào lịch sử; Cài đặt Clipboard hiện đúng trạng thái |
| T-P13-10 | Sidebar ▸ **Tìm kiếm** ▸ tab "Tìm kiếm AI"; rồi **Quick Look** ▸ tab "Hỗ trợ đa phương tiện" | Mỗi hàng có 2 tab; "Tìm kiếm AI" và "Tương thích media" không còn là hàng riêng; gõ "AI" hay "media" vào ô tìm sidebar vẫn ra hàng chứa nó |
| T-P13-11 | Tổng quan ▸ dòng "Trợ năng và Ghi màn hình" ▸ "Xem tab Quyền" | Mở Tính năng & Quyền **đúng tab Quyền** |
| T-P13-12 | Sidebar có "Ẩn biểu tượng thanh menu"; Tổng quan có "Biểu tượng XFinder trên thanh menu" | Hai tên khác nhau (trước đây cùng là "Biểu tượng thanh menu") |
| T-P13-13 | Kéo thanh tiêu đề một cửa sổ lên notch ▸ rê xuống ô **4 góc** (ô thứ 3) ▸ rê qua từng góc phần tư của ô rồi thả | Góc phần tư dưới con trỏ sáng màu nhấn, khung xem trước đổi theo; mỗi lần đổi góc trackpad rung một nhịp (nếu "Phản hồi rung" bật); thả là cửa sổ vào đúng góc đó |
| T-P13-14 | Mở Clipboard ở notch (hoặc khay nổi), lướt hai ngón ngang qua các thẻ | Mỗi thẻ lướt qua rung một nhịp nhẹ; tắt "Rung nhẹ khi lướt qua các thẻ" ở Cài đặt Clipboard thì hết rung. Lướt bằng chuột/phím: không có gì để cảm nhận (đúng) |

### Chẩn đoán & báo lỗi (dựng 2026-10-14)

| Mã | Làm gì | Mong đợi |
|:--|:--|:--|
| T-DIAG-1 | Menu thanh trạng thái ▸ Trợ giúp ▸ **Báo lỗi…** | Mở trang Giới thiệu, khung báo cáo hiện sẵn: phiên bản, macOS, máy, quyền, tính năng bật, crash gần đây, sự kiện gần đây |
| T-DIAG-2 | Đọc báo cáo | Không có tên người dùng, đường dẫn thư mục nhà (`~` thay thế), tên tệp, nội dung clipboard, tên cửa sổ |
| T-DIAG-3 | Bấm **Mở GitHub Issues** | Trình duyệt mở trang tạo issue chỉ có mẫu + phiên bản; báo cáo đã nằm trong clipboard để dán |
| T-DIAG-4 | Bấm **Lưu tệp…** | Hộp lưu mở, tên `XFinder-diagnostics-<phiên bản>.txt`; tệp lưu đúng nội dung đang hiện |
| T-DIAG-5 | Thoát XFinder bình thường rồi mở lại; sau đó Buộc thoát (⌥⌘⎋) rồi mở lại; mở báo cáo | Lần thoát thường: không có `app/uncleanExit`; sau Buộc thoát: có một dòng `app/uncleanExit` |
| T-DIAG-6 | Tắt "Ghi lỗi kỹ thuật…", bấm **Xoá nhật ký**, mở lại báo cáo | Phần sự kiện trống; tệp `~/Library/Application Support/XFinder/Diagnostics/events.jsonl` đã biến mất |
| T-DIAG-7 | Đợi MetricKit (giao gói chẩn đoán tối đa ~1 lần/ngày, chỉ khi có crash/treo) | Nếu có: dòng `metrickit/received` và mục `· metrickit` trong báo cáo. **Chưa đo được MetricKit có giao cho bản không qua App Store hay không** |
| T-ANALYTICS-1 | Giới thiệu ▸ Phân tích ẩn danh ▸ bấm **Xem dữ liệu sẽ gửi** | Mở khung xem trước JSON; định dạng đẹp, không chứa tên người dùng, đường dẫn `/Users/`, UUID, e-mail, hay nội dung clipboard |
| T-ANALYTICS-2 | Bật công tắc **Từ chối gửi phân tích ẩn danh** | Dòng trạng thái đổi thành "Đã từ chối — XFinder không gửi gì."; lần kích hoạt kế tiếp không gửi |
| T-ANALYTICS-3 | Khi Info.plist chưa điền AppID và Namespace (mặc định hôm nay) | Dòng trạng thái ghi "Bản này chưa có máy chủ nhận nên chưa gửi gì." và không có yêu cầu mạng nào được tạo |
| T-ANALYTICS-4 | Hộp thoại thông báo lần đầu (khi có máy chủ): chọn "Từ chối gửi" hoặc "Xem dữ liệu…" | "Từ chối" bật công tắc từ chối; "Xem dữ liệu…" chuyển tới trang Giới thiệu mở sẵn khung xem trước |
| T-ANALYTICS-5 | TelemetryDeck dashboard ▸ app XFinder ▸ bật **Test Mode** ▸ tìm tín hiệu `Setup.verify` (Claude gửi một cái lúc 00:2x ngày 15/10) | Thấy tín hiệu ⇒ App ID + namespace đúng. Không thấy ⇒ namespace sai: lấy đúng namespace trong dashboard rồi sửa `XFAnalyticsTelemetryDeckNamespace`. Bản trên máy bạn là bản **Debug** nên mọi báo cáo của nó vào Test Mode; bản Release (make-release.sh) mới vào số liệu thật |
| T-ANALYTICS-6 | Hộp "XFinder gửi thống kê ẩn danh" đang hiện sau khi cài (15/10) — bấm một nút | "Đã hiểu": 24 giờ sau mới có bản đầu. "Từ chối gửi": công tắc Từ chối bật, không bao giờ gửi. Trang Giới thiệu ghi đúng trạng thái |
| T-LIMIT-1 | Lần tới phiên Claude (app desktop) chạm giới hạn: nhìn notch / trang Agent | Trong ~20 giây hàng của phiên đổi sang "chạm giới hạn" (không còn "đang chạy"), có thông báo kèm nút chuyển phiên. Dán một đoạn văn có câu "hit your session limit" vào chat thì **không** được làm phiên báo dừng |
| T-LAYOUT-1 | Mở Thư viện Clipboard, rồi Theo dõi hệ thống (cả 4 tab); kéo nhỏ cửa sổ hết cỡ | Header, thanh tab và ô "Tìm cài đặt…" luôn ở mép trên; cửa sổ không nhỏ hơn 900×600 |
| T-SLEEP-1 | Tính năng & Quyền ▸ dòng Chống ngủ: chọn "15 phút" rồi bật | Dòng hiện "Còn 14:59…" đếm lùi màu cam; ô thời lượng mờ khi đang bật; tự tắt sau 15 phút. Tổng quan ▸ Chống ngủ ▸ "Mở…" dẫn tới trang này |

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
| T-T14a | Mở Chuột & cử chỉ (bản 2026-10-15 chiều). Bấm vào một mũi tên → "Ghi phím tắt…"; rồi bấm số nút giữ trên thân chuột để ghi nút giữ | Trang xếp thành các khối (trạng thái · chọn app · sơ đồ · nút hông · nút giữ & cuộn · nghiêng · chẩn đoán · chân trang); công tắc đầu trang là công tắc gạt. Khi ghi phím tắt, dòng trạng thái ghi **"Đang ghi phím tắt — bấm tổ hợp phím trên bàn phím (Esc để hủy)"**; khi ghi nút giữ, nó ghi **"…bấm nút trên chuột…"**; Esc huỷ cả hai. Danh sách app chưa phải dải chip (đó là T14b) |
| T-T14b | Chuột & cử chỉ ▸ dải chip app ở đầu trang. Chuyển sang một app KHÔNG có preset (Slack, Ghi chú…) rồi quay lại trang | Chip "Mặc định toàn cục" có chấm (nó đang điều khiển app đó); với app có preset (Safari, VS Code…) chấm nằm ở chip của app đó; chip đang chọn không có chấm. App chưa cài vẽ nét đứt. Trang không khựng khi đổi app |
| T-T14c | Chuột & cử chỉ ▸ khối sơ đồ: chưa chọn gì → cột phải tóm tắt 4 hướng; bấm một hàng hoặc mũi tên → bảng chi tiết hướng; bấm chip một nút → bảng của nút đó. Bấm chip chuột trái / chuột phải | Không bao giờ có cột phải trống. Chip chuột trái/phải **không** có nút "Dùng làm nút giữ"; nút hông thì có. Bấm mũi tên sau khi chọn chip thì chip hết sáng. UI tiếng Anh: hàng của hành động macOS chưa gán phím ghi tiếng Anh, màu cam |
| T-MG-BID | Mở Claude (hoặc VS Code, Cursor, Notion…), giữ nút cử chỉ rồi kéo lên / sang trái / sang phải | Claude, VS Code, Cursor, Antigravity, Zed: kéo lên mở Mission Control; trái/phải gửi ⌘[ / ⌘]; kéo xuống không gửi gì. Notion/Obsidian: trái/phải ⌘⌥← / ⌘⌥→. Trang Chuột & cử chỉ: các app này nằm trong nhóm đã cài ở đầu danh sách (đã đo bằng AX 2026-10-15) |
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
