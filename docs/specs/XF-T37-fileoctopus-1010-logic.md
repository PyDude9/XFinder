# XF-T37 — Trình duyệt tệp: luật logic theo FileOctopus 1.0.10 (2026-11-08)

**Câu việc:** "Người dùng đổi tên, đổi tên hàng loạt, tìm bằng bộ lọc và thoát app trong trình duyệt tệp mà không gặp
lỗi im lặng hay mất việc ngoài ý muốn — đúng luật FileOctopus 1.0.10."

Lệnh chủ dự án (2026-11-08): "Tôi gửi lại nội dung đặc tả để bạn cập nhật chức năng logic chuẩn hơn", kèm bản đặc tả
"Octopane" (dựng lại FileOctopus bằng Rust/egui) và bảng cơ chế. Phần Rust/egui **không** áp cho XFinder; chỉ lấy luật.

## 0. Kiểm bản đặc tả trên binary (FileOctopus 1.0.10 build 18, sha256 `940882b4…ed55`, đúng bản trong bảng)

Cách đo: chuỗi UTF-8 của binary (`scratchpad/fo10/u8.txt`, 91 504 dòng; positive control: bundle id có 24 lần),
`llvm-objdump` quanh chỗ dùng chuỗi, và probe trên APFS của máy này. Không đọc dữ liệu người dùng của app kia.

| Điều bảng ghi | Kết quả kiểm | XFinder hiện tại |
|:--|:--|:--|
| Tối đa **4** ngăn mỗi cửa sổ | **Sai.** Chuỗi "More panes, up to 16 per window" (bản Free: 2) | 16 — giữ |
| "Mới hơn" khi chênh ≥ 2 s | Đúng một phần: chỉ khi "One of the disks keeps file times only roughly" | 1 s, ổ thô 2 s (`FileOperationRules.isNewer`) — giữ |
| Tên tệp tối đa 255 **byte** | **Sai cho APFS.** Đo: giới hạn là **255 đơn vị UTF-16 sau khi tách dấu (NFD)** — `a×253+ả` (256 byte) tạo được, `a×254+ả` (255 ký tự) bị `ENAMETOOLONG`; `ệ×85` được, `ệ×86` không. Câu của FileOctopus nói "255 characters" — cũng không đúng | Không kiểm — **sửa (L1)** |
| Kích thước "1023.9 KB" ⇒ cơ số 1024 | Không chứng minh được: "Zero bytes / 999 bytes / 1023.9 KB / 1023.9 MB" nằm cạnh bảng kết quả tìm — là chuỗi mẫu đo bề rộng cột | `ByteCountFormatter(.file)` như Finder — giữ |
| Hộp trùng tên có "Keep the newer one" | Sai chỗ: đó là lựa chọn của **Gộp** (`bf.merge.policy.replaceOlder`); hộp trùng tên có Gộp/Thay thế/Dừng/Bỏ qua/Giữ cả hai/Áp dụng cho tất cả | Khớp — giữ |
| Thư mục/gói không bị Thay thế | Đúng ("Folders and packages can’t be replaced…") | Khớp — giữ |
| Return đổi tên, ⌘X không cắt, Tab chọn mục kế, nút chuột 4/5 Lùi/Tiến | Đúng (câu "Restore Defaults" của trang Bàn phím) | Khớp — giữ |
| Cú pháp ngày `<7d >2w <3m <1y today yesterday 2026-10-01 2026-10-01..2026-10-10` | Đúng (câu báo lỗi của parser) | Chỉ có từ khoá — **sửa (L4)** |
| Cú pháp cỡ `>5MB <=200KB =0` | Đúng | Không hiểu `=0` — **sửa (L4)** |
| Báo lỗi bộ lọc thân thiện | Đúng: 7 kiểu (`unknownOperator invalidValue inputTooLong tooManyTerms unterminatedQuote ambiguousDate emptyOperand`) | Một câu chung, và **không hiện ra đâu cả** — **sửa (L4)** |
| Giới hạn độ dài ô tìm (ước 512) | Có câu "The search is longer than N characters"; N nằm trong cấu hình truyền vào hàm (`0x100d29c20` đọc trường `[x0,#0x1c]`), chưa đọc được | **XFinder tự chọn** 512 ký tự / 32 từ (§2 L4) |
| Cảnh báo trước khi thoát (⌘Q) | Đúng: "When on, hold ⌘Q or press it twice to quit. Closing the last window never quits" | Không có; ⌘Q trong trình duyệt tắt **cả XFinder** — **thêm (L5)** |
| Đổi tên hàng loạt: Replace Text / Add Text / Format + Include extension | Đúng; Finder cũng có ba kiểu đó (`BulkRenameWindow.nib`: Format = Name and Index/Counter/Date, Where, Custom Format mặc định `"File "` có dấu cách cuối, Start numbers at) | Kiểu riêng (tiền tố/hậu tố/thay/đánh số/hoa/thường), xem trước chỉ báo "trùng" — **làm lại (L2)** |

## 1. Lỗi đo được trên XFinder (trước khi sửa)

1. **Chỉ đổi hoa/thường bị từ chối** ở cả ba chỗ: đổi tên tại chỗ (`commitRename` báo "Đã có mục khác tên này"), đổi tên
   hàng loạt trong trình duyệt và trang Đổi tên hàng loạt (chế độ "Chữ HOA"/"Chữ thường" đánh dấu mọi dòng là trùng ⇒ không
   đổi gì). Đo: `FileManager.fileExists("REPORT.txt")` = true khi chỉ có `report.txt` (đối chứng tên không có = false).
   Trong khi đó `moveItem`, `rename(2)` và `renamex_np(RENAME_EXCL)` đổi hoa/thường đều được; `RENAME_EXCL` vẫn từ chối
   đè lên một tệp **khác** (`other.txt` ← `OTHER.txt`: `EEXIST`).
2. **Hoàn tác** một lần chỉ đổi hoa/thường luôn báo "Không thể hoàn tác": `performUndo` bỏ qua mục khi `fileExists(to)`.
3. Đổi tên hàng loạt **đổi một phần lô** khi có dòng lỗi (chạy "những dòng chạy được"); không đổi được chuỗi `a→b, b→c`
   hay hoán đổi `a↔b`; mỗi phím gõ `stat` lại mọi tệp trong `body` (luật 14); hoàn tác qua Lịch sử thao tác, không qua ⌘Z
   của trình duyệt.
4. Ô tìm: `modified:<7d`, `modified:2026-10-01`, `size:=0`, `tags:x`, `kind:` (trống) đều thành **chữ thường để khớp tên**,
   không chip, không báo gì ⇒ "không có kết quả" mà không biết vì sao.

## 2. Phạm vi đợt này (L1–L5)

**L1 — Luật tên (`Core/Browser/RenameRules.swift`, thuần).** `nameProblem(_:)` trả khoá L10n hoặc nil: rỗng sau khi bỏ
khoảng trắng · chứa "/" hoặc ":" · "." / ".." · bắt đầu bằng `.xfinder-` (tên tạm của app) · ký tự điều khiển C0/DEL ·
quá 255 đơn vị UTF-16 NFD. `isSameName(a,b)` = khác nhau chỉ ở hoa/thường hoặc dạng Unicode (so `compare` không
`.literal`, `.caseInsensitive`). Ghi chú (không chặn): chỉ đổi hoa/thường · bắt đầu bằng "." (sẽ ẩn) · đổi/bỏ/thêm đuôi
(thư mục không tính đuôi). Dùng ở: đổi tên tại chỗ, đổi tên hàng loạt (cả hai), Thư mục mới.

**L2 — Đổi tên hàng loạt trong trình duyệt (`Core/Browser/BatchRenameRules.swift` thuần + sheet).** Ba kiểu như
Finder/FileOctopus:
- *Thay chữ*: Tìm → Thay bằng (mọi lần xuất hiện, phân biệt hoa/thường như bản cũ).
- *Thêm chữ*: chữ + Trước tên / Sau tên.
- *Định dạng*: Tên và chỉ số (số trần) / Tên và bộ đếm (5 chữ số, `00001`) / Tên và ngày (`yyyy-MM-dd 'at' HH.mm.ss` —
  mẫu của FileOctopus, theo **ngày sửa của từng mục**, Q-T37-3); Vị trí Sau tên / Trước tên; Tên tuỳ chỉnh (mặc định
  "Tệp " — dấu cách là của người dùng, như Finder); Bắt đầu từ (≥ 0).
- "Gồm cả đuôi" cho Thay chữ / Thêm chữ (tắt ⇒ chỉ đổi phần trước đuôi; thư mục luôn là cả tên). Định dạng luôn giữ đuôi.
- Mỗi dòng: Tên cũ → Tên mới → Trạng thái. **Lỗi** (chặn cả lô, nút Đổi tên tắt, dòng tóm tắt "N mục sẽ đổi tên. M mục
  không dùng được."): mọi lỗi L1 · trùng một mục khác trong lô · đã có mục khác cùng tên trong thư mục (trừ mục **của
  chính lô** sẽ được đổi đi) · nằm trong một mục khác cũng đang đổi tên · mục không còn · bị khoá · không có quyền ghi thư
  mục. **Ghi chú** (không chặn): ghi chú L1. Tên không đổi ⇒ bỏ qua (không đếm).
- Thực thi hai pha: mọi nguồn → tên tạm `.xfinder-rename-<uuid>-<i>` (`renamex_np RENAME_EXCL`), rồi tên tạm → tên
  mới; lỗi giữa chừng ⇒ đưa mọi mục đã đổi về tên cũ theo thứ tự ngược, báo số mục. Xong ⇒ **một bước ⌘Z** (kind
  `rename`, N mục) trong nhật ký hoàn tác của trình duyệt + Lịch sử thao tác.
- Đọc đĩa (tồn tại/khoá/quyền) **một lần** khi mở sheet và sau mỗi lần đổi, không trong `body`.

**L3 — Hoàn tác/làm lại** coi đích "đã tồn tại" là trống khi đó chính là mục đang đổi (cùng inode).

**L4 — Cú pháp tìm (`SearchQuery`).** Thêm `DateRange.within(n, unit)` (`<7d`: trong N ngày/tuần/tháng/năm qua tính
từ lúc này), `.olderThan(n, unit)` (`>2w`), `.day(y,m,d)` (`2026-10-01`), `.span(…)` (`A..B`, gồm cả ngày B; đảo
ngược thì đổi chỗ); `size:` nhận `=` (`=0`); `tags:` = `tag:`; nguồn `from:` có bảng tên → miền (gmail, github,
dropbox, drive, onedrive, outlook, notion, chatgpt — miền tệp đính kèm lấy từ binary FileOctopus). Cảnh báo thành cấu trúc
`SearchWarning(key, subject)` và **hiện dưới ô tìm**: bộ lọc lạ (giữ là chữ) · giá trị sai theo từng loại (ngày, cỡ,
loại, đuôi) · thiếu giá trị (`kind:` trống ⇒ bỏ) · thiếu dấu `"` đóng · dài quá 512 ký tự (phần sau bỏ) · quá 32 từ (chỉ
dùng 32 từ đầu).

**L5 — Cảnh báo trước khi thoát (⌘Q).** Khoá `fileBrowser.warnBeforeQuitting` (mặc định **bật**, Q-T37-1), một control
ở Cài đặt trình duyệt ▸ Chung. Khi bật và ⌘Q đến từ bàn phím lúc một cửa sổ trình duyệt đang là key: lần đầu không thoát,
hiện HUD "XFinder vẫn đang chạy. Bấm ⌘Q lần nữa hoặc giữ ⌘Q để thoát."; lần ⌘Q thứ hai trong 1,5 s (giữ phím = lặp phím)
thì thoát. Thoát từ menu bar của XFinder, Dock, hay khi cửa sổ khác của XFinder đang key ⇒ không hỏi.

**Ngoài phạm vi đợt này** (chưa có trong XFinder, mỗi cái một đợt sau, Q-T37-4): So sánh & đồng bộ thư mục, Tìm tệp
trùng, Máy chủ từ xa (SFTP/WebDAV/S3-R2/FTPS chỉ đọc — FileOctopus chạy SFTP qua `ssh` hệ thống, thấy các dòng
`KexAlgorithms=` / `HostKeyAlgorithms=` trong binary), trang Cài đặt ▸ Menu chuột phải, cửa sổ Clipboard, Thư mục gần đây
theo dõi ổ đã tháo/thư mục đã dời.

## 3. Ca hỏng

| Ca | Phải |
|:--|:--|
| `report.txt` → `Report.txt` (tại chỗ, hàng loạt, ⌘Z, ⇧⌘Z) | đổi được, hoàn tác được |
| Hai dòng ra cùng tên khác hoa/thường (`A.txt`, `a.txt`) | lỗi "trùng một mục khác trong lô" (ổ mặc định không phân biệt hoa/thường) |
| Hoán đổi `a.txt ↔ b.txt` trong một lô | đổi được nhờ tên tạm; ⌘Z trả lại đúng |
| Lỗi giữa pha 2 (mục bị xoá từ bên ngoài) | mục đã đổi về tên cũ, không còn tệp `.xfinder-rename-*` |
| Tên tiếng Việt 200 ký tự có dấu | báo "quá dài" trước khi gọi hệ thống (đo NFD) |
| Tên có xuống dòng / ký tự chuông | từ chối khi người dùng gõ (tên đã có trên đĩa vẫn hiện, không bị đụng) |
| `modified:<7d` / `created:>1y` / `modified:2026-02-30` | chip đúng / chip đúng / cảnh báo "không phải ngày" |
| `kind:` trống, `foo:bar`, `"abc` | cảnh báo "cần giá trị" / "không phải bộ lọc, tìm như chữ" / "thiếu dấu ngoặc kép" |
| Dán 10 000 ký tự vào ô tìm | chỉ dùng 512 ký tự đầu + cảnh báo, không treo |
| ⌘Q một lần trong trình duyệt | không thoát, HUD; ⌘Q lần hai trong 1,5 s ⇒ thoát; Thoát từ menu bar ⇒ thoát ngay |
| Đang có thao tác tệp chạy + ⌘Q hai lần | vẫn hỏi "Vẫn còn thao tác tệp đang chạy" như cũ |

## 4. Nghiệm thu

Build xanh; toàn bộ test 0 lỗi (bảng L1, L2, L4; test hai pha trên thư mục tạm thật; test mutation-sensitive cho
`isSameName`, NFD, `=0`, `<7d`); gate L10n/token 0; harness `mutation-check-browser.sh` thêm nhóm `T37-*` 100 % RED; cài
+ so hash dylib; runtime L10n 0; chạy thật trong Atlas: đổi tên hoa/thường + ⌘Z, đổi tên hàng loạt hoán đổi, gõ
`modified:<7d` thấy chip, `foo:bar` thấy cảnh báo, ⌘Q một lần không thoát. Test tay: T-T37-1…5.

## 5. Quyết định (mặc định đang theo)

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| Q-T37-1 | "Cảnh báo trước khi thoát (⌘Q)" mặc định bật hay tắt? | **Bật** — ⌘Q trong trình duyệt tắt cả notch, clipboard, agent… của XFinder, không chỉ cửa sổ |
| Q-T37-2 | Giới hạn ô tìm (FileOctopus có, chưa đọc được số) | 512 ký tự, 32 từ |
| Q-T37-3 | "Tên và ngày": ngày nào? | Ngày sửa của từng mục (ngày hiện tại cho mọi mục ⇒ trùng tên cả lô) |
| Q-T37-4 | Đợt sau: làm tính năng mới nào trước? | So sánh & đồng bộ thư mục → Tìm tệp trùng → Máy chủ từ xa → Menu chuột phải → Clipboard |
| Q-T37-5 | Trang "Đổi tên hàng loạt" cũ (sidebar) | Giữ kiểu cũ, chỉ sửa lỗi hoa/thường + luật tên L1 (gộp/đổi trang phải hỏi trước — memory) |
