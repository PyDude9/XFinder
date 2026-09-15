# Mindmap thiết kế XFinder

Tài liệu này trả lời câu bạn hỏi: **"làm sao để thiết kế app mà không phải đi copy ý tưởng người khác."**

Vấn đề không nằm ở chuyện bạn nhìn app khác — kỹ sư nào cũng nhìn. Vấn đề là **copy ở tầng sai**: copy *bố cục màn hình* thay vì copy *cách hiểu vấn đề*. Mindmap dưới đây ép bạn làm việc từ tầng đúng.

---

## 1. Năm tầng — luôn đi từ trên xuống

Đây là xương sống. Mỗi tầng chỉ được phép suy ra từ tầng ngay trên nó.

```
       ┌──────────────────────────────────┐
  L1   │  NGƯỜI DÙNG LÀ AI                │   Ai? Làm nghề gì? Một ngày chạm máy thế nào?
       └───────────────┬──────────────────┘
                       │
       ┌───────────────▼──────────────────┐
  L2   │  CÔNG VIỆC (JOBS)                │   Họ đang cố LÀM GÌ? (động từ, không phải tính năng)
       └───────────────┬──────────────────┘
                       │
       ┌───────────────▼──────────────────┐
  L3   │  NỖI ĐAU                         │   Vì sao việc đó đang khó/chậm/bực?
       └───────────────┬──────────────────┘
                       │
       ┌───────────────▼──────────────────┐
  L4   │  GIẢI PHÁP                       │   XFinder làm gì để bớt đau? (mới sinh ra tính năng)
       └───────────────┬──────────────────┘
                       │
       ┌───────────────▼──────────────────┐
  L5   │  GIAO DIỆN                       │   Bày ra màn hình thế nào? (cuối cùng mới tới đây)
       └──────────────────────────────────┘
```

**Quy tắc vàng:** khi nhìn app khác (MFinder, Tinycast, Raycast…), bạn chỉ được lấy thông tin ở **L2 và L3** — họ hiểu người dùng đang làm gì, đang đau gì. **L4 và L5 bạn phải tự nghĩ.** Copy L5 (bố cục) chính là cái đang làm bạn thấy "khá kém", vì bạn có giao diện của họ nhưng không có lý do đằng sau.

---

## 2. Ví dụ thật, từ chính đợt sửa này

### Ví dụ A — trang "Hệ thống"

| Tầng | Nội dung |
|:--|:--|
| L2 — Công việc | "Tôi muốn biết máy đang khỏe hay yếu." |
| L3 — Nỗi đau | Mở Activity Monitor thì quá nhiều số, rối. |
| L4 — Giải pháp | Vài chỉ số lớn, đọc trong 2 giây. |
| L5 — Giao diện | CPU / RAM / uptime dạng phẳng. |

Áp câu hỏi **"người dùng đến đây để làm gì?"** vào danh sách top-10 app ăn CPU → **trượt**. Nó trả lời câu *"app nào đang phá máy"*, mà câu đó Activity Monitor trả lời tốt hơn nhiều (sắp xếp được, kill được). Nên nó bị gỡ — đúng như bạn yêu cầu, và lý do khớp với nguyên tắc chứ không phải theo cảm tính.

### Ví dụ B — "Biểu tượng thanh menu"

| Tầng | Nội dung |
|:--|:--|
| L2 | "Thanh menu đầy quá, tôi muốn gọn." |
| L3 | macOS trước đây không cho ẩn icon. |
| L4 (cũ) | Dùng mẹo vạch ngăn 10.000 pt để đẩy icon ra ngoài. |
| L4 (nay) | **Mẹo đó chết trên macOS 27** → chỉ giải thích + mở đúng trang Cài đặt. |

Nếu chỉ copy giao diện MFinder, bạn sẽ vẽ lại cái công tắc đẹp đẽ — và nó **không làm gì cả**. Đi từ L3 thì thấy ngay: nỗi đau giờ đã được chính macOS giải quyết, nên việc của XFinder chuyển từ *làm thay* sang *chỉ đường*.

---

## 3. Bản đồ XFinder hiện tại (dùng làm gốc để sửa)

```
XFinder — "giữ máy Mac gọn gàng và trong tầm tay"
│
├── THEO DÕI MÁY ......... "máy đang khỏe không?"
│   ├── Tổng quan ........ trạng thái + quyền hạn
│   ├── Điều khiển nhanh . chỉnh nhanh: âm lượng, sáng, giao diện
│   ├── Hệ thống / Mạng / Ổ đĩa / Pin
│   └── Chống ngủ
│
├── CỬA SỔ ............... "sắp xếp chỗ làm việc"
│   ├── Xem trước cửa sổ
│   ├── Vùng bắt dính
│   └── Biểu tượng thanh menu  ← nay là trang giải thích
│
├── FINDER & TÌM KIẾM .... "tìm và xử lý file"
│   ├── Tìm kiếm / Tìm kiếm AI
│   ├── Bàn phím Finder / Thao tác Finder
│   └── Đổi tên hàng loạt + Lịch sử thao tác   ← chuyển lên đây
│
├── CÔNG CỤ .............. "xử lý nội dung"
│   ├── Clipboard + Ghi chú
│   ├── Khay thả
│   └── Nén / PDF / Khóa thư mục
│
├── KẾT NỐI .............. "đưa file đi nơi khác"
└── TIỆN ÍCH ............. "gắn XFinder vào Finder"
```

Vì sao **Đổi tên hàng loạt** nằm ở FINDER chứ không ở CÔNG CỤ? Vì người dùng tới đó **từ một lựa chọn trong Finder**. Nhóm theo *ý định của người dùng*, không theo *file code nào cài đặt nó*.

---

## 4. Quy trình mỗi khi muốn thêm/sửa tính năng

```
   Ý tưởng
      │
      ▼
 ① Viết 1 câu: "Người dùng tới đây để ______."
      │            (không viết được → bỏ ý tưởng)
      ▼
 ② Đã có trang nào trả lời câu đó chưa?
      │  rồi → sửa trang cũ, ĐỪNG thêm trang mới
      ▼ chưa
 ③ macOS có API công khai không?
      │  không → trang giải thích + link, KHÔNG làm công tắc giả
      ▼ có
 ④ Viết probe đo thử cơ chế → chạy thật
      │  không chạy được → quay lại ③
      ▼
 ⑤ Grep khóa UserDefaults: đã có control nào chưa?
      │  có rồi → dùng lại, không tạo cái thứ hai
      ▼
 ⑥ Làm — rồi kiểm chứng bằng log/test, không phải bằng "build xanh"
      │
      ▼
 ⑦ Ghi lại phát hiện vào CLAUDE.md
```

Bước ④ là bước bạn hay thiếu nhất, và cũng là bước cứu bạn nhiều nhất. Lần này chính probe đã chứng minh mẹo thanh menu đã chết — nếu chỉ đọc code thì sẽ kết luận sai (probe đầu tiên cho thấy OS cắt bề rộng, suýt dẫn tới "fix" nhầm; probe thứ hai mới lộ ra sự thật là icon hàng xóm **không hề bị đẩy đi**).

---

## 5. Công cụ để vẽ

| Cách | Khi nào dùng |
|:--|:--|
| **Markdown như file này** | Tốt nhất cho bạn lúc này — nằm trong git, diff được, sửa bằng bàn phím |
| **Excalidraw / tldraw** | Khi cần vẽ tay nhanh lúc đang nghĩ |
| **Obsidian Canvas** | Bạn đã có Obsidian; hợp để nối ý tưởng dài hạn |
| **Figma** | Chỉ khi tới L5 (giao diện chi tiết), không dùng cho L1–L4 |

Khuyên thật: **đừng mua công cụ mới.** Giữ file này trong repo, mỗi lần sửa app thì sửa luôn nó. Mindmap có giá trị vì nó *được cập nhật*, không phải vì nó đẹp.

---

## 6. Ba câu hỏi tự kiểm trước khi code

1. **"Người dùng tới trang này để làm gì?"** — không trả lời được trong một câu ⇒ chưa nên code.
2. **"Nếu macOS đã làm việc này rồi thì sao?"** — nếu rồi, việc của XFinder là *chỉ đường*, không phải *làm lại*.
3. **"Cái nút này có thật sự làm được điều nó ghi không?"** — không chắc ⇒ viết probe đo, hoặc đổi thành dòng giải thích.

Ba câu này chính là thứ ngăn bạn copy. Copy giao diện thì trả lời được câu nào đâu — mà app của bạn thì phải trả lời được cả ba.
