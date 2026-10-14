# Đối chiếu XFinder với OneNotch 2.0.5 — 2026-10-14

Nguồn: 17 ảnh chụp OneNotch chủ dự án gửi (menu thanh trạng thái, Floating Clipboard, General, Interface, Clipboard,
Screenshot, AI, Utilities, Live Activities, Calendar, Shortcuts, Pro, Support, About). Mỗi dòng của OneNotch được một
agent đối chiếu với **mã XFinder** (file:dòng, khoá UserDefaults), rồi một agent khác tìm cách bác từng kết luận "thiếu" /
"khác". Chi tiết bằng chứng (tiếng Anh) nằm trong phụ lục do workflow sinh ra: `scratchpad/p13/compare1.txt`,
`compare2.txt` (không đưa vào repo vì dài và chứa đường dẫn tạm).

Trạng thái: **Có** = tương đương · **Khác** = cùng việc, cách khác · **Thiếu** = không có · **Không làm** = không làm được
hoặc cố ý không làm (kèm lý do đã đo). Công: nhỏ (≤ nửa ngày), vừa (1–2 ngày), lớn (nhiều ngày / đổi thiết kế).

Trang thu tiền "OneNotch Pro" và mọi nhãn PRO: bỏ qua — XFinder không có paywall; tính năng sau nhãn PRO được đối chiếu
như mọi tính năng khác.

## Đã làm trong lượt này (gộp trùng lặp — chủ dự án: "gộp cái nào duplicates")

| Thay đổi | Lý do | Kiểm chéo |
|:--|:--|:--|
| **Tìm kiếm + Tìm kiếm AI** → một hàng "Tìm kiếm", 2 tab | cùng việc "tìm một tệp", cùng `FileSearchEngine`, cùng danh sách kết quả; chỉ khác cách nhập | không bị bác |
| **Quick Look + Tương thích media** → một hàng "Quick Look", tab "Xem trước file" / "Hỗ trợ đa phương tiện" | cùng việc "tệp này mở được không"; MFinder cũng gộp đúng hai tab này | agent kiểm chéo trả rác — tôi tự soát: trang Quick Look là ScrollView, trình xem nằm trong sheet nên vào tab không sao |
| Tổng quan: 2 dòng Trợ năng / Ghi màn hình → **1 dòng** mở thẳng tab **Quyền** | bản mỏng hơn của tab Quyền (tab Quyền còn nói tính năng nào dùng quyền đó, cảnh báo quyền thừa) | không bị bác |
| Tiện ích Finder: bỏ mục "XFinder thêm gì vào Finder" | lặp lại bằng văn xuôi điều các trang Thao tác/Bàn phím Finder/Đổi tên tự nói | không bị bác |
| Đổi tên trang **"Ẩn biểu tượng thanh menu"** và dòng Tổng quan **"Biểu tượng XFinder trên thanh menu"** | hai thứ khác nhau cùng mang chữ "Biểu tượng thanh menu" / "Menu Bar Icons" | không bị bác |
| Cơ chế tab chung (`SidebarDestination.tabGroups`, `TabbedPage`, `AppState.openTab`) | gộp cặp nào chỉ cần thêm một dòng; deep link tới tab con vẫn mở đúng tab | test ép 2–4 tab/hàng, mỗi trang ở tối đa 1 nhóm |

**Giữ nguyên (đã soát, không trùng):** Thư viện + Cài đặt Clipboard (thư viện là trình duyệt toàn khung: rail 180 pt + lưới +
inspector 320 pt, không có control cài đặt — nhét vào tab là hỏng) · Tổng quan / Tính năng & Quyền / Giới thiệu (ngoài phần
quyền đã gộp, ba việc khác nhau) · Cảnh báo (cài ngưỡng để được báo ≠ xem số liệu) · Chống ngủ · 6 trang NOTCH · các trang
CỬA SỔ, CÔNG CỤ, KẾT NỐI. Quét máy: **không khoá nào có hai control ghi** (chỉ `capture.annotate.color/width`: trang cài
đặt đặt mặc định, cửa sổ chú thích nhớ lựa chọn cuối — cả hai đọc giá trị sống).

## Bảng đối chiếu — chọn theo mã (OC-…)

### Menu thanh trạng thái
| Mã | OneNotch | XFinder | Công | Đề xuất |
|:--|:--|:--|:--|:--|
| — | Clipboard Library, Pause Clipboard, Screenshot ▸, Settings ⌘,, Check for Updates…, phiên bản, Restart, Quit ⌘Q | **Có** (menu native mới) | — | — |
| OC-1 | Help ▸ | **Thiếu** | nhỏ | Trợ giúp ▸ GitHub / Báo lỗi / Sao chép thông tin hệ thống (gộp với OC-71) |
| — | Open Floating Clipboard ⇧⌘C | **Khác**: 1 dòng theo bề mặt ⌘⇧V đang mở; khay nổi là ⌘⌥C (tắt sẵn) | — | xem OC-52 |

### Floating Clipboard (khay nổi)
| Mã | OneNotch | XFinder | Công | Đề xuất |
|:--|:--|:--|:--|:--|
| OC-2 | Đầu khay "· 20 Copies" + nút ✕ | **Thiếu** số đếm và ✕ (chỉ Esc / bấm ra ngoài / Ghim) | nhỏ | thêm |
| OC-3 | Ô tìm rộng, tự focus khi mở | **Khác**: ô 155 pt, chỉ focus khi ⌘F | nhỏ | mở rộng + tự focus |
| OC-4 | Nút xoá lịch sử (giữ mục đã ghim) | **Thiếu** ở mọi nơi (khay, thư viện, cài đặt) | nhỏ | `clearHistory(keepPinned:)` + hỏi xác nhận |
| OC-5 | Danh sách dọc 68 pt | **Khác**: dãy thẻ ngang 215×230 (thiết kế đã chọn) | lớn | giữ; thêm nút ••• trên thẻ |
| OC-6 | ⌘/⇧-click chọn nhiều → ⌘V dán theo thứ tự | **Khác**: chọn nhiều chỉ gộp/xoá; Paste Stack là lối ⌘⇧C riêng | vừa | nối chọn nhiều vào Paste Stack |
| OC-7 | Kéo giãn được | **Khác**: thanh cố định đáy màn | lớn | giữ |
| OC-8 | Chủ đề Sáng/Tối riêng | **Thiếu** (theo hệ thống) | nhỏ | thêm nếu cần |
| OC-9 | Xem trước tự động khi rê / đi phím | **Thiếu** (Space mới mở Quick Look) | vừa | tuỳ chọn, mặc định tắt |

### Clipboard (cài đặt)
| Mã | OneNotch | XFinder | Công | Đề xuất |
|:--|:--|:--|:--|:--|
| — | iCloud Sync, giới hạn & thời hạn lịch sử, âm khi chép, bỏ qua nội dung nhạy cảm, xem trước liên kết, MCP, xuất/nhập, bảng ghim | **Có** (không paywall; MCP còn có sẵn cấu hình dán được) | — | — |
| OC-10 | Công tắc "Bật Clipboard" ở đầu trang | **Khác**: "Tạm dừng ghi" nằm ở mục Riêng tư | nhỏ | đưa lên đầu (cùng khoá) |
| OC-11 | Nhấp thẻ: Copy / Paste / Paste & close | **Khác**: một công tắc tự dán | nhỏ | đổi thành 3 lựa chọn |
| OC-12 | Toast "Đã sao chép" dưới notch | **Thiếu** | vừa | dùng hàng đợi Live Activity |
| OC-13 | Chọn âm khi dán | **Thiếu** (cố định "Tink") | nhỏ | thêm `clipboard.pasteSound` |
| OC-14 | Nhận màu không có # (FF0000) | **Thiếu** | nhỏ | tuỳ chọn, mặc định tắt |
| OC-15 | Bỏ qua app: chọn app | **Khác**: gõ bundle id | nhỏ | thêm bộ chọn app |
| OC-16 | Dung lượng lưu trữ clipboard | **Thiếu** | nhỏ | thêm |
| OC-17 | Nhập từ Paste / PastePal / Maccy… | **Thiếu** | lớn | để sau |
| — | Mật mã cho bảng khoá | **Khác**: khoá từng bảng bằng Secure Enclave + Touch ID (mạnh hơn) | — | giữ |

### Chụp màn hình
| Mã | OneNotch | XFinder | Công | Đề xuất |
|:--|:--|:--|:--|:--|
| — | Bật chụp, định dạng ảnh, âm thanh, cạnh màn hình & tự đóng thẻ, dừng đếm khi rê, vuốt đóng | **Có** | — | — |
| OC-18 | Hiện con trỏ trong ảnh | **Thiếu** | nhỏ | `screencapture -C` |
| OC-19 | Gợn sóng khi chụp | **Thiếu** | vừa | overlay ngắn |
| OC-20 | Giữ bóng cửa sổ | **Thiếu** (luôn có bóng) | nhỏ | `-o` khi tắt |
| OC-21 | Nút "Dùng mặc định" cho thư mục lưu | **Thiếu** | nhỏ | thêm |
| OC-22 | Dung lượng thư mục ảnh + Mở thư mục | **Thiếu** | nhỏ | thêm |
| OC-23 | Sau khi chụp: 4 công tắc độc lập (Quick Access / Copy / Save / Annotate) | **Khác**: 1 lựa chọn 3 kiểu, không tự lưu | vừa | thêm "tự lưu" |
| OC-24 | Công cụ chú thích mặc định + nhớ công cụ cuối | **Thiếu** (chỉ nhớ màu, độ dày) | nhỏ | luôn nhớ công cụ cuối |
| OC-25 | Tuỳ biến nút trên thẻ xem trước | **Thiếu** | lớn | để sau |

### AI
| Mã | OneNotch | XFinder | Công | Đề xuất |
|:--|:--|:--|:--|:--|
| — | Theo dõi agent, sắp xếp phiên, im lặng / kèm âm | **Có / Khác** (XFinder thêm nhắn phiên, phiên không cửa sổ, crew, chuyển phiên) | — | — |
| OC-26 | % đã dùng / còn lại | **Thiếu** (luôn "đã dùng") | nhỏ | thêm |
| OC-27 | Sắp xếp thủ công | **Thiếu** (P10 cố ý chưa làm) | vừa | để sau |
| OC-28 | Kiểu chỉ báo đang chạy (Pixel grid…) | **Khác**: một kiểu cố định | vừa | để sau |
| OC-29 | Báo khi hạn mức được reset | **Thiếu** (chỉ báo khi chạm giới hạn) | vừa | thêm |
| OC-30 | Chọn âm báo | **Thiếu** (Pop/Glass cố định) | nhỏ | thêm |
| OC-31 | Bật/tắt từng agent | **Thiếu** (chỉ công tắc chung + cài hook từng agent) | nhỏ | thêm |
| OC-32 | Báo Codex đã đăng xuất | **Thiếu** | nhỏ | `codex login status` |
| OC-33 | Hiện đường dẫn hook + nút Cài lại | **Khác** | nhỏ | thêm |

### Tiện ích (Smart Select, Snap Zones, Pomodoro)
| Mã | OneNotch | XFinder | Công | Đề xuất |
|:--|:--|:--|:--|:--|
| — | Bỏ qua vùng chọn ngắn, tiền tệ, múi giờ, ngày → Lịch, bỏ qua app, hàng bố cục ở notch | **Có / Khác** (XFinder thêm tra từ điển, ⇧⌘G) | — | — |
| OC-34 | Icon nút đổi theo việc sẽ làm | **Khác**: luôn đũa phép | nhỏ | đổi theo loại |
| OC-35 | Công tắc riêng từng loại (Dịch, Đơn vị…) | **Khác**: chỉ tiền tệ có công tắc | nhỏ | thêm |
| OC-36 | Tính "200 + 10%" | **Thiếu** | vừa | thêm (cẩn thận văn xuôi có %) |
| OC-37 | Nhận màu trong vùng chọn | **Thiếu** (parser đã có) | nhỏ | nối `ColorFormat.parse` |
| OC-38 | Nhận dấu thời gian Unix / ISO | **Thiếu** | vừa | thêm |
| OC-39 | Làm sạch link trong vùng chọn | **Thiếu** (`URLCleaner` đã có) | nhỏ | nối |
| OC-40 | Giữ một chút mới mở hàng bố cục | **Khác**: mở ngay | nhỏ | dùng độ trễ rê chung |
| OC-41 | Chọn / sắp xếp bố cục, thêm Quarters, Sixths, Top & Bottom, Wide Center | **Thiếu** (7 ô cố định) | lớn | để sau |
| OC-42 | Thanh trượt độ trễ rê chuột | **Khác**: 3 mức | nhỏ | giữ |
| OC-43 | Pomodoro (làm/nghỉ) + kiểu toàn màn hình | **Thiếu** (chỉ hẹn giờ) | lớn | để sau |
| OC-44 | Chọn âm hết giờ | **Thiếu** ("Glass" cố định) | nhỏ | thêm |

### Live Activities
| Mã | OneNotch | XFinder | Công | Đề xuất |
|:--|:--|:--|:--|:--|
| — | Caps Lock | **Có** (XFinder thêm sạc/pin, mạng, Bluetooth, cảnh báo, hẹn giờ) | — | — |
| OC-45 | Thay HUD âm lượng/độ sáng của macOS | **Không làm**: HUD hệ thống là tiến trình riêng (private), độ sáng không đọc được trên Apple Silicon (đã đo) | — | giữ HUD song song |
| OC-46 | Hiệu ứng phát sáng | **Thiếu** | nhỏ | thêm |
| OC-47 | Thanh tiến trình theo màu nhấn | **Khác — và là lỗi nhỏ**: thanh âm lượng vẽ cứng màu trắng, phớt lờ `notch.accent` | nhỏ | sửa |
| OC-48 | Kiểu HUD: dưới notch / trong notch | **Thiếu** | vừa | thêm |
| OC-49 | Bật/tắt hiện % | **Khác**: luôn hiện | nhỏ | thêm |
| OC-50 | Nút ▶ xem thử từng hiệu ứng | **Thiếu** (toàn app) | vừa | thêm cho Live Activities, âm thanh, nhắc họp |

### Phím tắt
| Mã | OneNotch | XFinder | Công | Đề xuất |
|:--|:--|:--|:--|:--|
| — | Bật phím chụp toàn cục, Lấy màu ⇧⌘1 ghi lại được | **Có** | — | — |
| OC-51 | Ghi lại / xoá ⌘⇧V, khay nổi, ⇧⌘G | **Khác**: cố định, chỉ bật/tắt | vừa | thêm bộ ghi |
| OC-52 | Khay nổi ⇧⌘C | **Khác**: ⌘⌥C (⌘⇧C đang là Paste Stack) | — | chọn ở Q-OC |
| OC-53 | Nhấn đúp phím bổ trợ → Paste Stack (toàn cục) | **Thiếu** (⌘⇧C chỉ khi XFinder ở trước) | vừa | thêm |
| OC-54 | Khôi phục phím tắt mặc định | **Khác**: chỉ có "Dùng bộ phím giống OneNotch" | nhỏ | thêm |
| OC-55 | Lấy màu: Tab đổi HEX / RGB / HSL / HSB | **Thiếu** | vừa | thêm |

### Lịch & lời nhắc
| Mã | OneNotch | XFinder | Công | Đề xuất |
|:--|:--|:--|:--|:--|
| — | Ẩn sự kiện cả ngày, báo trước 5 phút, âm báo, ẩn lời nhắc đã xong | **Có** | — | — |
| OC-56 | Lịch phụ (tắt được) | **Khác**: âm lịch luôn hiện | nhỏ | thêm tắt âm lịch |
| OC-57 | Xem thử nhắc họp | **Thiếu** | nhỏ | thêm |
| OC-58 | Chọn thời gian hoãn | **Thiếu** (5 phút cố định) | vừa | thêm |
| OC-59 | Công tắc nhắc cho Lời nhắc có giờ | **Khác**: luôn nhắc | nhỏ | thêm |
| OC-60 | Chọn lịch nào hiện | **Thiếu** | vừa | thêm |

### Giao diện (Interface)
| Mã | OneNotch | XFinder | Công | Đề xuất |
|:--|:--|:--|:--|:--|
| — | Bật/tắt, thứ tự trang, khôi phục mặc định | **Có** (XFinder thêm rê chuột mở gì, độ nhạy, viên thuốc, ẩn khỏi ảnh chụp, màu nhấn) | — | — |
| OC-61 | Hình kích thước notch của màn hình đang dùng | **Thiếu** | nhỏ | thêm |
| OC-62 | Xem trước dải notch khi sắp xếp | **Thiếu** | vừa | thêm |
| OC-63 | Kéo thả để sắp xếp / ẩn trang | **Khác**: nút ▲▼ + công tắc | vừa | thêm kéo thả, giữ nút |
| OC-64 | Trang Pin / Dịch ở notch | **Thiếu** | lớn | để sau |

### Chung (General)
| Mã | OneNotch | XFinder | Công | Đề xuất |
|:--|:--|:--|:--|:--|
| — | Mở khi đăng nhập, phím tắt | **Có** | — | — |
| OC-65 | Ẩn biểu tượng thanh menu của chính app | **Thiếu** (XFinder ẩn được Dock nhưng không ẩn được biểu tượng menu) | nhỏ | `NSStatusItem.isVisible` |
| OC-66 | Hiện trên mọi màn hình | **Thiếu** | lớn | để sau (chưa có màn thứ hai để đo) |
| OC-67 | Chọn màn hình mặc định / tự chuyển màn | **Khác**: luôn theo con trỏ | vừa | để sau |
| OC-68 | Ẩn notch khi app toàn màn hình | **Thiếu** (luôn hiện trên app toàn màn hình) | vừa | thêm |

### Giới thiệu & Hỗ trợ
| Mã | OneNotch | XFinder | Công | Đề xuất |
|:--|:--|:--|:--|:--|
| — | Phiên bản, kiểm tra cập nhật, ghi chú phát hành, liên hệ | **Có** | — | — |
| OC-69 | Số build | **Thiếu** | nhỏ | thêm |
| OC-70 | Tự kiểm tra / tự tải cập nhật | **Không làm mặc định**: cam kết không chạy mạng nền | nhỏ | có thể thêm tuỳ chọn, mặc định tắt |
| OC-71 | Sao chép thông tin hệ thống (không chứa clipboard) | **Thiếu** | nhỏ | thêm |
| OC-72 | Gom trợ giúp một chỗ | **Khác**: "Có gì mới" ở Tổng quan, "Chạy lại thiết lập" ở Tính năng | nhỏ | gom về Giới thiệu |

### Khung trang cài đặt
| Mã | OneNotch | XFinder | Công | Đề xuất |
|:--|:--|:--|:--|:--|
| — | Ô màu ở sidebar, thẻ nhóm, chân thẻ, công tắc, menu bật lên, dòng › | **Có** | — | — |
| OC-73 | Icon đầu mỗi dòng | **Thiếu** | vừa | thêm tham số `icon` cho các row dùng chung |
| OC-74 | Nút dạng viên thuốc (tím / đỏ) | **Khác**: nút bordered của hệ thống | nhỏ | giữ màu nhấn của XFinder, chỉ đổi dáng |
| OC-75 | Thẻ chọn bằng hình (2 lựa chọn cạnh nhau) | **Thiếu** | lớn | chỉ khi có tính năng cần (OC-43, OC-48) |
| OC-76 | Hình minh hoạ đầu mục | **Thiếu** | lớn | để sau |
| OC-77 | Nhóm sidebar Features / Experiences / Other | **Khác**: nhóm theo việc người dùng làm | nhỏ | giữ |
