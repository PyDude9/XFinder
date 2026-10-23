# XF-T26 — Chụp cuộn: chụp một vùng dài hơn màn hình bằng cách cuộn và ghép

## 0. Câu việc

"Chụp **cả** một trang web, cuộc trò chuyện hay danh sách dài thành **một** ảnh, không phải chụp mười tấm rồi tự ghép."

## 1. Đo trước khi viết (2026-10-22, brief `scratchpad/feat/brief.md`)

| | XFinder (`6952224`) | Ứng dụng tham chiếu (đo binary, không đọc source) |
|:--|:--|:--|
| Cơ chế chụp | mọi chế độ chạy `/usr/sbin/screencapture` (không có cờ cuộn/ghép) | ScreenCaptureKit (`SCScreenshotManager`, `SCStream`, `SCContentFilter`) |
| Chụp cuộn | không có | có: `ScrollCaptureSession/Stitcher/TwoWayStitcher`, vùng tối thiểu **48 × 48 pt**, cuộn tay **và** tự cuộn (cần Trợ năng), dừng khi "đến cuối trang", lỗi "Không ghép được đoạn mới — hãy cuộn ngược lại một chút", trần chiều cao (`heightLimit`), tạm dừng cuộn mượt khi đang chụp |
| SCK | chỉ Dock preview, ảnh thumbnail | — |

Header SDK: `SCScreenshotManager.captureImage(contentFilter:configuration:)` có từ macOS 14.0 (đúng sàn của app); chỉ chụp
**cái đang hiện trên màn hình** ⇒ bắt buộc chu trình chụp → cuộn → chụp → ghép phần chồng.

## 2. Thiết kế

**2.1 Vào.** Chế độ mới `CaptureMode.scrolling` ("Chụp cuộn") — tự hiện trên trang Chụp màn hình, có phím tắt riêng
(`capture.shortcut.scrolling`), chạy được từ nút "Chụp" như mọi chế độ.

**2.2 Chọn vùng.** Một lớp phủ tối mờ trên màn hình có con trỏ (`ScrollCaptureSelector`): kéo để vẽ vùng, Esc huỷ. Vùng nhỏ
hơn 48 × 48 pt ⇒ báo "Chọn vùng ít nhất 48 × 48 điểm" và cho kéo lại.

**2.3 Phiên chụp.** Khi đã có vùng: một viền mảnh quanh vùng (nằm NGOÀI vùng, và bị loại khỏi ảnh chụp) + một thanh điều
khiển nhỏ dưới vùng: chiều cao đã ghép · **Tự cuộn** · **Xong** · **Huỷ**. Hai cách cuộn, dùng chung một bộ ghép:
- **Cuộn tay** (mặc định): người dùng tự cuộn bằng chuột/trackpad; app chụp vùng ~8 lần/giây, ghép mỗi khi khung đổi.
- **Tự cuộn**: app gửi sự kiện cuộn pixel (gắn tag riêng) vào giữa vùng, mỗi bước ~60 % chiều cao vùng, chờ khung đứng yên
  (hai lần chụp giống nhau hoặc 600 ms) rồi chụp; dừng khi ba lần cuộn liên tiếp không đổi gì ("Đã đến cuối trang").
Enter = Xong, Esc = Huỷ. Trong phiên chụp, Cuộn chuột mượt (XF-T25) tạm dừng.

**2.4 Ghép (thuần, `Core/Capture/ScrollStitch.swift`, symlink test).** Mỗi khung → chữ ký từng hàng (64 mẫu độ sáng, lượng
tử 6 bit). Giữa khung trước và khung mới:
1. Dải cố định trên/dưới (header/footer dính) = số hàng giống hệt ở cùng vị trí ⇒ loại khỏi phần so khớp.
2. Độ dịch `d` = vị trí làm khớp tốt nhất phần thân, chỉ tính các hàng **có thông tin** (không phải hàng trơn một màu); bỏ
   phiếu theo băm hàng, rồi xác minh bằng so sánh có dung sai. Cần ≥ 95 % hàng có thông tin khớp và ≥ 8 hàng như thế.
3. `d == 0` ⇒ không có gì mới. Không tìm được `d` ⇒ "mất dấu": giữ phần đã ghép, báo cuộn ngược lại một chút.
4. Nối `d` hàng mới (ngay trên dải dưới) vào ảnh; dải dưới lấy từ khung mới nhất, gắn vào cuối khi xong.
Chỉ hướng xuống ở bản này (cuộn lên ⇒ "mất dấu" — v2 làm hai chiều).

**2.5 Bộ nhớ.** Khung chụp chỉ giữ chữ ký hàng (vài KB) + dải hàng mới được ghi ra một thư mục tạm dạng PNG; ảnh cuối do
tiến trình con `XFinder --vision stitch` dựng và ghi ra file (cùng cơ chế với OCR/tách nền: bộ nhớ đỉnh nằm ở tiến trình con).
Trần chiều cao **20 000 px** (đo lại ở T-T26-5) ⇒ dừng, báo "Đã đến giới hạn chiều cao".

**2.6 Ra.** Ảnh ghép đi qua đúng `finishCapture` hiện có (tên file, Lịch sử, chép clipboard, thẻ Quick Access, mở chú thích),
định dạng PNG.

## 3. Ca hỏng

| Ca | Trả lời |
|:--|:--|
| Chưa có quyền Ghi màn hình | xin quyền + note như các chế độ khác; không mở lớp phủ |
| Không có quyền Trợ năng | Cuộn tay vẫn chạy; nút Tự cuộn mờ + "Cần quyền Trợ năng để tự cuộn" |
| Vùng < 48 × 48 pt | báo, cho kéo lại |
| Vùng trùm nhiều màn hình | cắt theo màn có điểm bắt đầu kéo |
| Header/footer dính | dải cố định loại khỏi so khớp, xuất hiện một lần |
| Nội dung động (con trỏ nhấp nháy, video, ảnh động) | hàng khác ít không làm hỏng (ngưỡng 95 %); khung không ổn định quá 600 ms ⇒ vẫn chụp |
| Cuộn quá nhanh (không còn phần chồng) | "mất dấu", giữ phần đã ghép, chờ người dùng cuộn ngược |
| Cuộn lên | không ghép (v1), báo |
| Trang tải thêm khi cuộn | phần mới chỉ là các hàng mới — ghép bình thường |
| Hết trang (tự cuộn) | 3 lần không đổi ⇒ tự Xong |
| Trần 20 000 px | dừng, giữ ảnh, báo |
| Người dùng chuyển app / cửa sổ che vùng | ảnh chụp là cái đang hiện — có thể mất dấu ⇒ báo như trên |
| Huỷ | xoá thư mục tạm (Thùng rác không cần cho file tạm của app), không thêm Lịch sử |
| Chỉ có 1 khung (không cuộn) | Xong ⇒ lưu khung đó như chụp vùng |
| Cuộn mượt đang bật | tạm dừng trong phiên, bật lại khi xong/huỷ |
| Tiến trình con không chạy được | dựng ảnh ngay trong app (đường lùi), vẫn ra file |

## 4. Nghiệm thu

Thuần (`ScrollStitchTests`): khung tổng hợp từ một ảnh dài có header/footer dính, dịch đều/không đều, hàng trơn, nhiễu nhỏ ⇒
ảnh ghép trùng từng hàng với ảnh gốc; mất dấu; d = 0; trần chiều cao. Mutation vào `mutation-check-capture.sh` (FILES +
FILTER). e2e: chạy phiên tự cuộn trên một cửa sổ thử của chính harness (văn bản dài đánh số dòng) ⇒ OCR ảnh ghép thấy đủ dòng
đầu–cuối, không lặp dòng.

## 5. Q / T

- Q-SC-1 cuộn tay mặc định, Tự cuộn là nút trong phiên (đã chọn: cả hai).
- Q-SC-2 hết trang = 3 lần cuộn không đổi (không đọc thanh cuộn qua AX ở v1).
- Q-SC-3 trần 20 000 px (đo lại).
- Q-SC-4 một chiều (xuống) ở v1.
- T-T26-1 cuộn tay một trang web dài ⇒ một ảnh, không lặp/hụt đoạn.
- T-T26-2 Tự cuộn trên Finder/Messages ⇒ tự dừng ở cuối.
- T-T26-3 trang có header dính (GitHub, Notion) ⇒ header xuất hiện một lần.
- T-T26-4 cuộn quá nhanh ⇒ thấy báo "mất dấu", cuộn ngược ⇒ ghép tiếp.
- T-T26-5 trang rất dài ⇒ dừng ở trần, footprint app không phình (đỉnh nằm ở tiến trình con).
