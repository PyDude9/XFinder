# Nhập bằng giọng nói (Voice to Typing)

Nói và chữ tự vào đúng ô đang gõ — kèm một lượt AI tút lại văn bản nếu bạn muốn.
100% chạy trên máy hoặc qua nhà cung cấp bạn tự chọn; XFinder không gửi gì tới máy chủ của mình.

> Trang trong app: sidebar **CÔNG CỤ → Nhập bằng giọng nói**.

---

## 1. Bắt đầu nhanh

1. Mở **Nhập bằng giọng nói**, bật công tắc **Bật nhập bằng giọng nói**.
2. Cấp **ba** quyền (mỗi dòng có nút yêu cầu ngay tại chỗ):
   - **Trợ năng (Accessibility)** — để XFinder nghe được phím tắt toàn hệ thống.
   - **Micro (Microphone)** — để thu giọng nói.
   - **Nhận dạng giọng nói (Speech Recognition)** — để Apple Speech chuyển thành chữ.
3. Đặt con trỏ vào ô văn bản bất kỳ, **giữ Option Phải (⌥)**, nói, rồi **thả ra**.

Văn bản được chèn vào đúng ô đang gõ. Không cần cấu hình gì thêm — chế độ mặc định
**Tút lại & xóa từ thừa** chỉ cần một trong bốn nhà cung cấp ở mục 4; nếu chưa cấu hình,
XFinder vẫn chèn **bản gốc** và báo lý do, chứ không làm mất lời bạn vừa nói.

### Phím trong phiên nói

| Phím | Việc |
|:--|:--|
| Giữ phím kích hoạt | Bắt đầu nói (chế độ *Giữ để nói*) |
| Thả phím kích hoạt | Kết thúc và xử lý |
| `Space` (khi đang tút) | **Chèn ngay bản gốc**, không đợi AI |
| `Esc` (bất cứ lúc nào) | **Hủy** — không chèn gì, clipboard được khôi phục |
| `Return` (khi bảng so sánh hiện) | Chèn bản đã tút |
| `Esc` (khi bảng so sánh hiện) | Bỏ, không chèn |

---

## 2. Sáu nhóm cài đặt trên trang

| Nhóm | Gồm |
|:--|:--|
| **Kích hoạt & phím tắt** | Bật/tắt · cách kích hoạt (giữ / bấm bật-tắt) · phím kích hoạt · ngôn ngữ nhận dạng · trạng thái Event Tap |
| **Chế độ gõ** | Chọn chế độ · bỏ từ đệm · tự động thêm dấu câu · câu lệnh riêng + thư viện câu lệnh |
| **Mô hình AI tút văn bản** | Bốn tầng nhà cung cấp + nút **Kiểm tra kết nối** |
| **Thanh trạng thái nổi** | Vị trí HUD · sóng âm · âm báo · xem lại trước khi chèn · khôi phục clipboard |
| **Ngữ cảnh màn hình** | Gửi tên ứng dụng + tiêu đề cửa sổ · gửi đoạn bôi đen |
| **Quyền & thử nghiệm** | Ba dòng quyền + **Thử micro** ngay trên trang |

### Phím kích hoạt

`Option Phải (61)` *(mặc định)* · `Option Trái (58)` · `Command Phải (54)` · `Fn / Globe (63)`.

`Fn/Globe` được ghi rõ là **có thể không hoạt động**: một số bàn phím không gửi phím này
dưới dạng mã phím thường. Trang nói trước điều đó thay vì để bạn ngồi đoán.

> Người dùng bản cũ đã chọn `Option Trái` được **giữ nguyên** — giá trị cũ chỉ được đọc
> một lần khi chưa có phím mới, nên việc migrate không ghi đè lựa chọn thật.

---

## 3. Sáu chế độ gõ

| Chế độ | Làm gì | Cần AI? |
|:--|:--|:--|
| **Chép nguyên văn** | Chèn đúng những gì bạn nói | **Không** |
| **Tút lại & xóa từ thừa** *(mặc định)* | Bỏ từ đệm, sửa nói lắp, thêm dấu câu, viết hoa | Có |
| **Soạn email** | Dựng thành email có chào hỏi, thân bài, kết | Có |
| **Văn phong chuyên nghiệp** | Câu từ gãy gọn, lịch sự | Có |
| **Gạch đầu dòng** | Tóm ý thành danh sách | Có |
| **Tùy biến** | Câu lệnh riêng bạn viết (dịch, chú thích mã, báo cáo cuối ngày…) | Có |

**Chép nguyên văn** là đường chạy không cần nhà cung cấp nào — đó là lý do nó vẫn hoạt động
trên máy vừa cài và chưa cấu hình gì.

Thư viện câu lệnh lưu các câu lệnh bạn hay dùng để chọn lại bằng một cú bấm (JSON trong
`UserDefaults`, không phải Keychain vì đây không phải bí mật).

---

## 4. Bốn tầng mô hình

| Tầng | Trạng thái | Ghi chú |
|:--|:--|:--|
| **Apple Intelligence (trên máy)** | Có | Cần macOS 26+ và Apple Intelligence đang bật. Miễn phí, offline. Trang nói rõ **vì sao** chưa dùng được nếu thiếu. |
| **Ollama (chạy trên máy)** | Có | `http://localhost:11434`. Nút **Tải danh sách** đọc các model bạn đã pull. |
| **API riêng (dùng khoá của bạn)** | Có | OpenAI · Groq · Anthropic (Claude) · Google Gemini · OpenRouter · DeepSeek · địa chỉ riêng. |
| **Tài khoản ChatGPT / Claude** | **Không ship** | Xem mục dưới. |

### Vì sao không có "đăng nhập ChatGPT Plus / Claude Pro"

Không có OAuth công khai nào cấp quyền **dùng API** cho hai gói thuê bao đó. Cách duy nhất
để "đăng nhập hộ" là **dùng lại cookie phiên trình duyệt của bạn để gọi các endpoint nội bộ
của web app** — vi phạm điều khoản của cả hai nhà cung cấp, hỏng mỗi lần họ đổi giao diện, và
là đúng loại bề mặt riêng tư không tài liệu mà XFinder từ chối dựng lên.

Trang chọn cách trung thực: hiện **giải thích + nút "Dùng khoá API thay thế"**, và bộ chọn
nhà cung cấp ở tầng API đã có sẵn hai hãng đó.

### Khoá API

- Lưu trong **Keychain của macOS** (`com.xfinder.app.voice`), **không** trong `UserDefaults`,
  tệp cấu hình hay log.
- Giao diện chỉ hiện 4 ký tự cuối (`••••••••a1b2`).
- Dán vào một URL hay một dòng `export` sẽ bị từ chối trước khi ghi.
- **Kiểm tra kết nối** gửi một câu thật ngắn và hiện **nguyên văn** câu trả lời/lỗi của nhà
  cung cấp — đó là thứ nói cho bạn biết khoá sai hay mạng sai, khác hẳn một nút "OK" vô nghĩa.

---

## 5. Thanh trạng thái nổi (HUD)

- **Vị trí**: *Cạnh con trỏ* (nổi ngay cạnh chỗ đang gõ) hoặc *Mép trên màn hình*.
- **Sóng âm**: dải 34 cột vẽ bằng `Canvas`, nhích theo **từng buffer âm thanh thật** —
  không có timer, nên khi không nói thì không tốn CPU.
- **Chữ chạy thời gian thực**: kết quả nhận dạng tạm thời hiện ngay khi bạn đang nói.
- **Trạng thái "Đang tút lại văn bản…"** kèm tên chế độ.
- **Space** để chèn ngay bản gốc, **Esc** để hủy.
- **Âm báo** bắt đầu/kết thúc (mặc định tắt).
- Panel `ignoresMouseEvents = true`: HUD không bao giờ nuốt cú click dành cho tài liệu bên dưới.

---

## 6. Xem lại trước khi chèn (Diff Review)

Bật **Xem lại trước khi chèn** để so sánh chữ gốc và chữ đã tút trước khi nó vào tài liệu:

- từ **bị bỏ** gạch ngang màu đỏ, từ **được thêm** gạch chân màu xanh;
- `Return` = chèn, `Esc` = bỏ;
- thuần bàn phím (panel không nhận chuột), nên nó không cướp click của bạn;
- là diff theo **từ** (LCS), không phải theo ký tự — người đọc muốn biết *từ nào* đổi.
- bản viết lại **giống hệt** bản gốc thì bảng không hiện, để một lượt tút vô ích không làm gián đoạn.

---

## 7. Ngữ cảnh màn hình

Khi bật, XFinder gửi kèm cho AI:

- **tên ứng dụng + tiêu đề cửa sổ** — để câu chữ hợp ngữ cảnh (đang trả lời trong Mail thì
  biết đó là email);
- **đoạn bạn đang bôi đen** — chỉ khi bạn đã bôi đen.

Cả hai đọc qua Accessibility. **Không có ảnh chụp màn hình nào được gửi** — XFinder không
chụp màn hình cho việc này, và trang nói rõ như vậy.

---

## 8. Quyền

| Quyền | Để làm gì | Nếu thiếu |
|:--|:--|:--|
| **Trợ năng** | Event tap toàn hệ thống (nghe giữ/thả phím kích hoạt, `Esc`, `Space`, `Return`) | Công tắc bật nhưng dòng **Bộ nghe phím toàn hệ thống** báo *Chưa chạy* + nút **Cấp quyền** |
| **Micro** | Thu giọng nói | Báo khi bắt đầu nói; dòng quyền + nút **Yêu cầu** |
| **Nhận dạng giọng nói** | Apple Speech chuyển thành chữ | Như trên |

> **Lưu ý cho bản dev**: TCC gắn quyền với *danh tính chữ ký*. Bản ký ad-hoc có danh tính là
> cdhash, đổi mỗi lần build — nên mỗi lần build lại phải cấp quyền lại. Dùng
> `scripts/install-mouse-rebuild.sh` (ký bằng chứng chỉ **XFinder Dev**) để quyền sống qua các
> lần build.

---

## 9. Đã kiểm chứng tới đâu

Bốn kết quả **tách rời** — đừng gộp chúng:

| Phát biểu | Kết quả |
|:--|:--|
| Build | `BUILD SUCCEEDED`, 0 lỗi, 15 file mới **có tên trong compile log**, `lipo -archs` = arm64 |
| Test tự động | **289 test, 0 fail** (26 test mới cho Voice) |
| Cổng ngôn ngữ | coverage `TOTAL 0`/1553 · duplicates 0 · literal sweep 0 · `verify-l10n-runtime.py` trên **bundle đã cài**: **0 leak** |
| Trang render thật (đo bằng cây AX) | **English**: 94 node, **0 chuỗi tiếng Việt**. **Tiếng Việt**: 94/97 node có dấu; 3 node còn lại là `Pin`, `Quick Look` (tên riêng) và dòng thống kê |
| Event Tap | **đang chạy** (`Running`), 3 quyền đã cấp |
| **Nói thật và nghe kết quả** | ❌ **chưa kiểm chứng** — cần người nói vào micro |

**Không** được báo là đã chạy: độ chính xác của phần nhận dạng và chất lượng của bản viết lại
phụ thuộc micro, giọng và nhà cung cấp — chỉ người dùng xác nhận được.
