# Dynamic Island — kế hoạch hoàn thiện

Kế hoạch này đối chiếu bộ 29 ảnh cũ và bộ 22 ảnh bổ sung với một lộ trình cho Dynamic Island của XFinder. Dùng shell Ref29 và nhận diện XFinder. Bản phát hành giữ CTA, phím tắt và quyền truy cập nhất quán giữa các module.

Mục tiêu là tương đương về chức năng và luồng thao tác nhìn thấy trong ảnh. Phạm vi triển khai là hợp của danh sách tham chiếu và chức năng XFinder đang có. Khi chức năng trùng nhau, mở rộng điểm đến hiện có và bảo toàn dữ liệu, quyền, phím tắt, thiết lập, thứ tự tab và đường mở. Khi chức năng chỉ có trong XFinder, giữ điểm đến và đưa vào cùng danh sách quản lý tab. Khi ảnh chỉ xác nhận tên một mục, ghi rõ hành vi cần xác nhận trước khi triển khai.

## Bản đồ chức năng

Số trong bảng này thuộc bộ 29 ảnh cũ. Bộ 22 ảnh mới có bảng đối chiếu riêng bên dưới.

| Module | Ảnh | Phần có sẵn và việc cần hoàn thiện |
| --- | --- | --- |
| Shell, thiết lập và tùy biến | 2, 7, 10, 15, 17, 19, 23, 26 | Dùng thanh icon cuộn ngang và nút Settings cố định ở cuối. Cửa sổ Settings và Settings trong notch dùng cùng danh sách bật/tắt, sắp xếp tab và thiết lập kích thước màn hình. Cửa sổ Settings có nút đi thẳng đến Các tab và Chứng khoán trong trang Giao diện notch. |
| Tổng quan | 4, 9, 24 | Tạo trang tùy chọn đọc trạng thái từ module hiện có. Hiện nhạc, lịch sắp tới và tác vụ đang chạy nếu người dùng đã bật tương ứng. |
| Khay, AirDrop và trình duyệt tệp | 1, 20 | Kiểm chọn nhiều và kéo vào/ra trên máy thật, AirDrop, chuyển vào ngăn, tệp lỗi, Quick Look và hàng đợi. |
| Clipboard | 5, 7 | Giữ lịch sử, tìm kiếm, lọc, ghim và loại trừ dữ liệu nhạy cảm. Kiểm bộ lọc và bàn phím ở hai khổ. |
| Đang phát, Hệ thống, Âm thanh | 2, 4, 9, 24 | System gom CPU, RAM, ổ đĩa, mạng và pin thành các hàng căn cột. Caffeine nằm dưới các chỉ số, dùng chung phiên chống ngủ với menu bar và Full Settings. Tùy chọn đóng nắp gửi yêu cầu chống ngủ khi cắm nguồn. Cần xác minh bằng thao tác đóng nắp trên MacBook thật. |
| Lịch và Nhắc việc | 6, 14 | Giữ Lịch. Thêm Nhắc việc qua EventKit với quyền xin khi dùng, tạo/hoàn thành và trạng thái từ chối quyền. |
| Đồng hồ và tập trung | 10, 16 | Timer, Stopwatch và Pomodoro dùng chung trang. Nhắc uống nước mặc định tắt. Khi bật, giới hạn 1–8 lần mỗi ngày, mặc định 6, trong khung 08:00–20:00 giờ địa phương. |
| Thời tiết | 2, 10, 23 | Debug dùng Open-Meteo Free. Release tích hợp WeatherKit khi có App ID, quyền và ký số. Kiểm lại tìm thành phố, cache, nguồn, ngoại tuyến và vị trí tùy chọn. |
| Stocks | 2, 19, 23 | Giữ watchlist S&P 500, AAPL, NVDA, CROX và BTC/USD. Settings cho chọn Twelve Data hoặc Massive và lưu khóa riêng trong Keychain. Massive Basic lấy giá đóng cửa ngày cho mục đích cá nhân. Quyền SPX và BTC/USD phụ thuộc sản phẩm dữ liệu bật trên tài khoản. |
| Doanh thu bán app | 13, 17, 21, 24, 29 | Stripe và Shopify. Kỳ Hôm nay/7/30, biểu đồ, số tiền/số đơn, tuổi dữ liệu và đối soát từng nguồn. |
| Analytics website | 11, 24, 27 | Nguồn riêng về truy cập và referrer. Ưu tiên bộ chọn kỳ, lượng truy cập, xu hướng và các trang chính. Chọn connector khi bắt đầu phase đó. |
| Agent AI và Hạn mức AI | 3, 8, 24 | Giữ module hiện có, kiểm dữ liệu local và phân biệt số đo, ước tính và thời điểm reset. |
| Chat local | 22, 28 | Module riêng với trạng thái thiết bị không hỗ trợ, yêu cầu tối thiểu và quản lý phiên hội thoại. |
| Mirror, Teleprompter | 7, 12, 18, 19, 25, 26 | Mirror xin quyền camera khi mở. Teleprompter có chế độ trong Island và cửa sổ đọc, có tốc độ, cỡ chữ và phím thoát. |
| Capture, Screen Time, Notes, Links, Files, Shortcuts, Emoji, Feedback | 7, 15, 19, 23, 26 | Rà các công cụ XFinder đã có và ưu tiên nối lại bằng đường vào chung. Mục cần dữ liệu/quyền riêng có đặc tả và kiểm thử của module đó. Đối chiếu thêm Scratchpad, To-Dos, Sounds, Message và Units trước khi phân công. |

## Yêu cầu ưu tiên: Settings mở trong notch

**Phạm vi ảnh mới 14 và 19–22.** Chế độ Settings trong notch đã được nối với nút răng cưa và có deep link để kiểm tra. Còn nghiệm thu thao tác kéo, công tắc, bàn phím và đổi màn hình trên máy thật.

### Luồng và bố cục

1. Nút răng cưa ở cuối thanh ngang mở Settings trong chính panel notch hiện tại. Dùng bố cục XFinder với điều hướng gồm **Chung**, **Màn hình**, **Các tab**, **Giao diện** và **Giới thiệu**. Mở ở Các tab từ nút răng cưa. Cột điều hướng có thể thu gọn ở khổ hẹp để giữ chỗ cho nội dung.
2. Settings là chế độ của shell và nằm ngoài danh mục tab có thể ẩn. Giữ panel trên màn hình đang dùng. Có nút Quay lại trang trước và nút Đóng. Escape thoát chế độ sửa hoặc kéo trước, sau đó quay về trang trước. Nếu trang trước đã bị tắt hoặc không còn khả dụng, chọn mục bật gần nhất theo catalog. Khi không còn mục nào, màn phục hồi vẫn mở được Settings.
3. Ở Các tab, hàng có tay nắm, icon, tên và công tắc. Tách nhóm đang bật và nhóm công cụ đang tắt. Kéo bằng tay nắm để đổi thứ tự hoặc dùng Lên/Xuống bằng bàn phím và VoiceOver. Công tắc và thứ tự phản ánh ngay trên thanh ngang. Hủy kéo không lưu. Khi bật lại một mục đã ẩn, giữ vị trí đã lưu của nó.
4. Chung dùng lại công tắc chính và tùy chọn mở bằng click, hover và phím tắt hiện có. Màn hình có sơ đồ và ba cỡ Nhỏ / Chuẩn / Lớn theo màn hình. Giữ mặc định cũ khi chưa có cấu hình riêng và áp dụng kích cỡ qua cùng đường layout/hit test. Giao diện có màu nhấn, kiểu thu gọn và quyền riêng tư hiện có. Giới thiệu dùng thông tin XFinder và điểm mở hỗ trợ của app.
5. Cửa sổ Settings đầy đủ vẫn truy cập được qua menu app, deep link và khi Island bị tắt. Tắt công tắc chính từ notch đóng panel và giữ đường bật lại trong cửa sổ Settings. Những thiết lập chung và cấu hình nguồn chi tiết có thể mở trang tương ứng bằng một hành động ghi rõ đích đến.

### Thiết kế kỹ thuật và nghiệm thu

- Dùng một API đọc/ghi cho catalog và thiết lập dùng chung. Giữ ID, thứ tự và dữ liệu hiện có, kể cả cấu hình đã di trú từ `notch.pages`. Rà `NotchTabCatalogState.moved(fromOffsets:toOffset:)` trước khi thêm logic kéo thả. Tách intent mở Settings trong notch khỏi intent mở cửa sổ Settings.
- Dùng một trạng thái trình bày Settings trong `NotchSurfaceMachine` hoặc một trường tường minh cùng vòng đời. Khi vào Settings, dừng tài nguyên chỉ chạy khi trang đang hiện. Việc kéo sắp xếp chỉ đi vào vùng nhận kiểu dữ liệu tab và không kích hoạt nhập tệp từ Finder.
- Tách trạng thái bật khỏi khả năng sử dụng. Hiện mô tả và đường cấu hình khi một tab thiếu nguồn hoặc khi tính năng liên quan đang tắt. Tắt tab không xóa lịch sử, danh sách hay thông tin kết nối. Nút Settings luôn ở cuối dải, kể cả khi cuộn và khi tất cả tab bị tắt.
- Test logic cho mở/quay lại/đóng, tất cả tab tắt, tắt trang đang chọn, thứ tự của mục ẩn, kéo đầu/cuối và khôi phục mặc định. Atlas kiểm ảnh giao diện và vị trí focus. Kiểm thao tác thật trên notch và màn hình ngoài gồm click đầu, kéo tab, click xuyên ngoài hình, rút màn hình, VI/EN, bàn phím và Reduce Motion. Nếu chỉ kiểm được deep link hoặc ảnh tĩnh thì ghi riêng.

## Đối chiếu 22 ảnh bổ sung

| Ảnh mới | Đã có hoặc đã xác nhận | Việc làm và tiêu chí nghiệm thu |
| --- | --- | --- |
| 1–2 · AI Usage | Một dải thẻ cuộn ngang theo thứ tự Claude Code, Codex, Antigravity, Gemini CLI. Hạn mức và Token áp dụng cho cả dải. Có nút làm mới. Gemini CLI và Antigravity hiển thị token từ log cục bộ và chỉ dẫn xem quota trong CLI. | Nghiệm thu dải thẻ ở khổ hẹp và khổ rộng. Tổng Hôm nay/30 ngày chỉ hiện khi có dữ liệu và giá hợp lệ, ghi rõ phần ước tính và độ bao phủ. Số liệu quota phải lấy từ nguồn báo quota trực tiếp. |
| 3 · Calendar | Có trang Lịch và nguồn EventKit. | Lịch tháng và agenda theo ngày, chọn ngày để đổi agenda, đánh dấu ngày có sự kiện, mở chi tiết từ hàng. Kiểm sự kiện cả ngày, ngày trống, múi giờ và quyền bị từ chối. |
| 4 · Stats | Có trang Hệ thống và các bộ lấy số liệu. | Cho CPU, RAM, ổ đĩa, mạng và pin mỗi loại một hàng dễ đọc. Mạng tách lên/xuống, đơn vị và lịch sử. Hiện sức khỏe pin khi thiết bị trả dữ liệu. Dừng cập nhật khi trang ẩn. |
| 5 · Weather | Đã có trang và phương án Open-Meteo cho bản test. | Kiểm chọn vị trí hiện tại/thành phố, Hàng giờ/7 ngày và đơn vị. Kiểm bố cục thiếu quyền vị trí, cache cũ và offline. Giữ khâu phát hành WeatherKit riêng. |
| 6 · Clipboard | Có lịch sử, tìm kiếm, ghim và nhiều kiểu nội dung. | Đối chiếu sáu lọc Tất cả/Ghim/Text/Links/Ảnh/Tệp, hàng thẻ và phím tắt. Kiểm nội dung dài, nguồn nhạy cảm, khổ hẹp và trạng thái rỗng. |
| 7 · Notes | Có tab Ghi chú. | Đối chiếu cột tìm/chọn ghi chú và vùng đọc/sửa. Rà autosave với kho hiện có, sửa nhanh trong panel, đọc lại sau khi chuyển tab hoặc khởi động lại, lỗi lưu và xác nhận xóa. |
| 8 · Stocks | Có watchlist mặc định và chỉnh sửa tại Settings. | Soi tìm mã, thêm/xóa nhanh và hàng có sparkline/giá/% thay đổi trên nguồn được phép phân phối. Khi thiếu giá hoặc quá hạn, hiện rõ trạng thái. Kiểm phiên Mỹ và BTC với dữ liệu thử. |
| 9 · Shortcuts | Có tab nối Apple Shortcuts. | Tìm, làm mới và chạy từ danh sách/lưới theo chiều rộng. Kiểm chưa có shortcut, thiếu quyền, chạy lỗi, tab đóng giữa lúc tải và shortcut do người dùng chọn. |
| 10 · Units | Có đổi đơn vị offline. | Kiểm hai trường giá trị, đổi chiều, chọn nhóm và đổi ngay khi nhập. Tỷ giá là adapter riêng có mốc cập nhật và trạng thái offline. |
| 11 · Chat local | Có chat qua FoundationModels khi máy hỗ trợ. | Kiểm trạng thái chào, gợi ý và gửi/dừng, nhập từ bàn phím và fallback phiên bản hay thiết bị không hỗ trợ. Kiểm hủy khi ẩn tab. |
| 12 · Teleprompter | Có trình sửa và cửa sổ đọc. | Kiểm sửa kịch bản trong notch, đếm từ, ước lượng thời lượng, mở cửa sổ dưới camera, đổi màn hình và thoát. Kiểm nội dung rỗng, tắt tab và cửa sổ không còn. |
| 13 · Feedback | Có tab gửi qua quy trình GitHub của XFinder. | Phân biệt Báo lỗi/Đề xuất, xem trước nội dung, mở bản nháp qua kênh XFinder đã xác nhận. Ảnh minh họa mail nháp, nên nếu bổ sung mail thì xác nhận địa chỉ nhận trước. Không tự gửi. |
| 14, 19–22 · Shell và Settings | Dải tab cuộn ngang, chỉ báo 2 pt, nút Settings cố định, lưu thứ tự và bật/tắt. | Ưu tiên Settings trong notch theo đặc tả trên. Kiểm từ shortcut/hover/click, ghim, click xuyên và kích cỡ riêng theo màn hình. |
| 15 · Shelf | Có Khay thả, AirDrop và xử lý mục mất liên kết. | Kiểm kéo vào/ra nhiều tệp, AirDrop, xem nhanh, tệp mất quyền và nhãn lỗi dài. Nếu bổ sung hạn giữ, chỉ dọn mục hoặc bản sao thuộc XFinder và giữ an toàn tệp gốc. |
| 16–17 · Trạng thái thu gọn | Có tín hiệu hẹn giờ, nhạc, Agent và tệp. | Kiểm số đếm ngược hai đầu notch và ưu tiên khi nhiều tín hiệu cùng lúc. Thông báo đơn mới phụ thuộc connector Doanh thu thật, cần chống báo trùng và tôn trọng công tắc. |
| 18 · Revenue | Có phạm vi kết nối Stripe và Shopify. | Rà kỳ Hôm nay/7/30, tổng, số đơn, tiền tệ, biểu đồ và nguồn. Chỉ cộng sau khi đã có quy tắc tỷ giá và đối soát tránh đếm trùng. Các cổng khác trong ảnh là mở rộng riêng. |

## Danh sách điểm đến để triển khai và nghiệm thu

Danh sách này là phạm vi chức năng cần đối chiếu. Các mục chức năng có công tắc riêng trong Settings, kể cả khi cùng dùng một adapter hoặc cùng nhóm điều hướng. Giữ bố cục và hệ nhận diện XFinder, dùng ảnh tham chiếu cho thao tác và thứ bậc nội dung.

| Nhóm | Điểm đến | Điều kiện để gọi là hoàn thành |
| --- | --- | --- |
| Tổng quan | Home, Đang phát | Home mở được nội dung từ các tab đã bật. Đang phát có phát/tạm dừng, qua bài và tiến độ nếu nguồn hỗ trợ. |
| Văn bản và tệp | Scratchpad, Notes, Clipboard, Khay, Files, Links | Scratchpad sửa nhanh và lưu tự động. Notes có danh sách và tìm. Clipboard có bộ lọc. Khay nhận/kéo tệp và AirDrop. Files và Links mở được đối tượng đã chọn. |
| Công việc | To-Dos, Reminders, Calendar | To-Dos quản lý danh sách riêng. Reminders đồng bộ với hệ thống khi được cấp quyền. Calendar có tháng và agenda. |
| Công cụ cá nhân | Timers, Units, Emoji, Shortcuts | Đồng hồ có Timer/Stopwatch/Pomodoro và tùy chọn nhắc uống nước. Units đổi đơn vị. Emoji tìm và sao chép. Shortcuts chọn và chạy phím tắt do người dùng sở hữu. |
| macOS và trình bày | Hệ thống, Audio, Capture, Screen Time, Mirror, Teleprompter, Sounds, Message | Hệ thống và Audio dùng điều khiển đã có. Capture tạo ảnh chụp. Screen Time cần nguồn dữ liệu chính thức và phạm vi dữ liệu được chốt. Mirror cấp quyền theo yêu cầu. Teleprompter sửa nội dung, chạy/tạm dừng và mở chế độ cửa sổ đọc. Sounds và Message cần xác định hành vi vì ảnh chỉ cho thấy tên tab. |
| Dữ liệu | Weather, Stocks, Doanh thu, Analytics | Weather lấy dự báo theo nguồn. Stocks là watchlist giá Mỹ. Doanh thu kết nối Stripe và Shopify. Analytics có kỳ, nguồn, KPI và referrer. |
| AI | Agent AI, AI Usage, Chat local | Agent AI có hoạt động phiên. AI Usage phân biệt quota với ước tính và nguồn. Chat local có kiểm khả năng thiết bị, phiên hội thoại và trạng thái lỗi. Mục Claude trong ảnh cấu hình được đối chiếu với Agent AI trước khi quyết định cần tab riêng. |
| Cấu hình | Feedback, Settings | Feedback mở luồng phản hồi đã xác định. Settings mở danh sách công tắc, thứ tự, display và appearance. Settings luôn có đường mở để khôi phục tab khi người dùng tắt hết. |

Hồ sơ PeakPad 2.0 build 8 bổ sung bằng chứng về Screen Time, Sounds, Message và Analytics. Xem bảng đối chiếu bên dưới trước khi chốt đặc tả từng module.

## Thứ tự thực hiện

| Đợt | Đầu ra | Điều kiện nghiệm thu |
| --- | --- | --- |
| 1. Settings trong notch và shell | Tích hợp mode Settings, nhóm Các tab, kéo đổi thứ tự và quản lý màn hình theo đặc tả trên | Luồng răng cưa/quay lại/đóng chạy đúng, tab cập nhật ngay và giữ dữ liệu cũ. Kiểm rộng/hẹp, EN/VI, focus, VoiceOver, Reduce Motion và màn ngoài. |
| 2. Stocks và Doanh thu | Hai module riêng, fixture trước rồi connector thật. [Kế hoạch chi tiết](XF-ISLAND-STOCKS-REVENUE-plan.md) | API giá có quyền hiển thị trong app. Stripe và Shopify đối soát từng nguồn. Khi quan hệ nguồn chưa rõ, hiện riêng. Giữ cache có tuổi dữ liệu, kết nối chỉ đọc, Keychain và test mất mạng/quota. |
| 3. Nâng cấp các module đã có | Khay, Clipboard, Lịch, Đang phát, Hẹn giờ, Agent, Hệ thống, Âm thanh, Weather | Kiểm hồi quy dữ liệu và hành vi cũ. Test trên Atlas và xác minh vật lý cho notch, màn ngoài, kéo tệp và AirDrop khi môi trường có thiết bị. |
| 4. Mở rộng năng suất và ứng dụng hệ thống | Tổng quan, Nhắc việc, Mirror, Teleprompter và điểm vào tiện ích có sẵn | Chỉ xin quyền khi thao tác đòi hỏi. Nếu tắt tab hoặc chuyển trang, giải phóng camera và cửa sổ nổi, kiểm quyền bị thu hồi. |
| 5. Mở rộng dữ liệu và AI | Analytics, Chat local và các công cụ còn lại sau audit khả năng nền tảng | Mỗi nguồn có giới hạn, tuổi dữ liệu và quyền rõ ràng. Kiểm hỗ trợ phiên bản macOS và fallback trước khi nối tab. |
| 6. Bản thương mại | Cấu hình phát hành, dữ liệu đủ quyền, WeatherKit, kiểm thử và ký | Chạy gate arm64 và smoke test. Xác minh signing, capability, attribution, quyền dữ liệu và hành vi khi không cấu hình. |

## Quy tắc triển khai và bàn giao

- Cấu hình mạng bắt đầu từ thao tác mở module hoặc làm mới. Khi đóng, hủy yêu cầu có thể hủy và bỏ qua kết quả trễ. Dùng fixture cho QA, tách adapter, cache, ViewModel và giao diện theo ranh giới hiện có.
- Mọi tính năng có trạng thái chưa cấu hình, đang tải, rỗng, lỗi, cache cũ và quyền bị từ chối khi áp dụng. Dùng L10n và khả năng truy cập của XFinder. Dịch cả nhãn trợ năng.
- Mỗi đợt kiểm kê các điểm đến và thử hồi quy theo cấu hình người dùng hiện có. Kiểm từng chức năng tham chiếu theo thao tác thật và từng chức năng XFinder theo đường mở cũ, trạng thái dữ liệu và quyền. Một điểm đến hiển thị trong Settings chưa được tính là đã triển khai.
- Một build và một gate Atlas mỗi lượt. Báo mã nguồn, trạng thái patch, test, bằng chứng UI và giới hạn kiểm tra. Release dùng nguồn dữ liệu phù hợp với quyền phân phối. Khoản phí Apple Developer và ký WeatherKit thuộc bước phát hành.

## Tiến độ và điều kiện bàn giao

| Phạm vi | Trạng thái đã ghi nhận | Điều kiện còn thiếu |
| --- | --- | --- |
| Shell và Settings | Đã có Settings trong notch, năm nhóm điều hướng, công tắc và kéo đổi thứ tự cùng catalog với cửa sổ Settings, sơ đồ và lựa chọn chiều rộng theo màn hình. Atlas xác nhận trang Các tab mở ngay trong Island qua deep link. | Nghiệm thu thao tác nút răng cưa, kéo thả, công tắc, bàn phím, VoiceOver, click xuyên và thay đổi kích cỡ trên màn hình ngoài. |
| Khay và Clipboard | Đã tích hợp luồng XF-T41 và bố cục Ref29. Người dùng xác nhận kéo tệp vào. | Kiểm kéo nhiều tệp ra, AirDrop, Quick Look, thư mục đích mất quyền, lỗi chuyển và bộ lọc Clipboard. Kiểm notch thật và màn ngoài. |
| Home, Lịch, Nhắc việc | Đã tích hợp. Atlas đã kiểm mở trang, bố cục hẹp và xin quyền theo thao tác. | Kiểm tạo/hoàn thành nhắc việc với tài khoản thử, thu hồi quyền và mở lại. |
| Đồng hồ, Đang phát, Hệ thống, Âm thanh, Agent AI, Hạn mức AI | Đã có điểm đến. Atlas đã kiểm hai đầu dải vòng tiến độ Pomodoro. | Kiểm ngủ/thức, chuyển thiết bị âm thanh, dữ liệu media và quota, trạng thái trống. |
| Stocks Mỹ | Đã tích hợp danh sách mặc định S&P 500, AAPL, NVDA, CROX và BTC/USD. Atlas đã kiểm thêm, xóa, sắp xếp và lưu danh sách. | Chỉ bật giá thật khi xác minh nguồn và quyền hiển thị. Kiểm tuổi dữ liệu, phiên, lỗi từng mã và BTC 24/7. |
| Weather, Doanh thu | Có phần triển khai. Phạm vi này nằm ngoài đợt bàn giao hiện tại. | Quản lý các đầu việc còn lại trong đợt riêng. |
| Mirror và Teleprompter | Đã tích hợp vào danh mục và Settings. Build arm64 và gate trên Atlas xanh với 3.363 test, 1 bỏ qua, 0 lỗi. Ảnh Atlas xác nhận mở trang bằng deep link và hai trạng thái ban đầu. | Kiểm thao tác nhập kịch bản, cửa sổ đọc, công tắc, xin quyền và vòng đời camera bằng thao tác GUI. Camera thật cần máy có thiết bị truy cập được. |
| Tiện ích cục bộ | Đã tích hợp [Ghi chú](XF-ISLAND-NOTES.md), [Chụp màn hình](XF-ISLAND-CAPTURE.md), [Đổi đơn vị](XF-ISLAND-UNITS.md), [Bản nháp](XF-ISLAND-SCRATCHPAD.md), [Emoji](XF-ISLAND-EMOJI.md), [Tệp](XF-ISLAND-FILES.md) và [Liên kết](XF-ISLAND-LINKS.md). Gate đến Bản nháp và Emoji đạt 3.412 test, 1 bỏ qua, 0 lỗi. Tệp và Liên kết build arm64 và mở được trên Atlas. Đã tích hợp [Việc cần làm](XF-ISLAND-TODOS.md) và [Phím tắt Apple](XF-ISLAND-SHORTCUTS.md). Atlas xác nhận build arm64, 418 test tập trung (1 bỏ qua, 0 lỗi) và mở được hai trang. | Gate mới hết 600 giây trong nhóm WeatherRulesTests, chưa có kết quả đầy đủ. Kiểm ghi công việc và chạy phím tắt do người dùng chọn. Kiểm thao tác nhập, sao chép, mở tệp, sửa ghi chú, công tắc và chụp thật. Chốt hành vi Sounds, Message và Feedback theo bằng chứng hiện có. |
| Thời lượng ứng dụng | Đã tích hợp bộ đếm cục bộ với opt-in riêng. Atlas đã thấy trạng thái tắt mặc định và xác nhận chưa tạo file lịch sử khi mở trang. | Kiểm trên phiên thử đã bật, gồm chuyển ứng dụng, tạm dừng, khóa, ngủ, xóa và mở lại. |
| Analytics website, Chat local, Feedback | Đã tích hợp [Website Analytics](XF-ISLAND-ANALYTICS.md): DataFast chỉ đọc và GA4 qua OAuth loopback/PKCE; hai nguồn tách biệt, không có dữ liệu mẫu. Đã nối vào catalog, gallery, Settings toggle, Dynamic Island page và hủy tác vụ khi rời tab/tắt tab/thoát app. Build arm64 và 20 test Analytics/OAuth, 13 test catalog đạt. Chat local trên FoundationModels; Atlas thấy trang khả dụng và xác nhận liên kết yếu. Đã tích hợp [Tin nhắn cục bộ](XF-ISLAND-MESSAGE.md) và [Phản hồi](XF-ISLAND-FEEDBACK.md); Feedback bật/tắt độc lập trong Settings, chỉ sao chép khi bấm và mở trang GitHub đích đến. | Chưa xác thực OAuth hoặc tài khoản DataFast/GA4 thật. Atlas đã mở đúng build bằng deep link và xác nhận trạng thái chưa kết nối, bộ chọn nguồn và nút cấu hình. Chưa kiểm form và công tắc Settings vì Atlas không định vị được panel để gửi thao tác khi hộp thoại Device Control đang mở. Kiểm fallback Chat trên hệ điều hành cũ, trạng thái Apple Intelligence và đường mở Feedback. |

Gate của checkout trước đợt Mirror/Teleprompter đạt build arm64, 3.329 test, 1 bỏ qua, 0 lỗi. App build mới nhất trước đợt này chưa được nghiệm thu qua GUI.

## Thứ tự triển khai

1. Chạy song song [Mirror](XF-ISLAND-MIRROR.md), [Teleprompter](XF-ISLAND-TELEPROMPTER.md), [Đổi đơn vị](XF-ISLAND-UNITS.md) và kiểm kê tiện ích. Mỗi worker giữ phạm vi file riêng. Người tích hợp ghép một lượt các thay đổi chung ở danh mục, router, Settings, Xcode project và L10n.
2. Theo kết quả kiểm kê, chia nhóm tiện ích thành các patch độc lập. Ưu tiên đường mở Capture, Notes, Files và Shortcuts nếu engine hiện có đủ hành vi. Giao Scratchpad, To-Dos, Links, Emoji và Sounds theo nhóm dữ liệu và vòng đời. Xác nhận hành vi Message và nơi nhận Feedback trước khi nối thao tác gửi.
3. Chốt nguồn dữ liệu và luồng cấu hình cho Stocks, Analytics và Screen Time. Kiểm điều kiện hệ điều hành và thiết bị cho Chat local. Tách các công việc nghiên cứu khỏi tích hợp để các tiện ích offline đi tiếp.
4. Chạy một gate trên snapshot tích hợp và một lượt QA GUI trong profile Atlas. Đối chiếu bản build arm64, trạng thái tab trong Settings, sự cố quyền, dữ liệu trống và đường mở từ giao diện. Ghi rõ những ca cần phần cứng hoặc tài khoản thật. Bàn giao đường dẫn app để người dùng tự mở thử khi các tính năng trong đợt đạt tiêu chí.

## Đối chiếu với hồ sơ PeakPad 2.0 build 8

Nguồn nằm tại `/Users/wolong/.gemini/antigravity/prompt/peakpad_analysis/`. Dùng `00` làm mục lục. Đối chiếu tính năng với symbol/types (`07`, `12–14`), tài nguyên và quyền (`01–05`, `10–11`), reflection và key (`16–17`, `19–20`). Dùng `18` theo vùng hàm khi cần xác minh lời gọi cụ thể. Tên type, URL và khóa cấu hình chỉ cho thấy dấu vết trong build; xác minh điều kiện chạy, hành vi và quyền bằng nguồn phù hợp. Các phần mô tả lại từ metadata không phải mã nguồn gốc. XFinder triển khai luồng tương đương với nhận diện, dữ liệu và kiến trúc của mình.

| Nhóm | Bằng chứng bổ sung | Thay đổi trong kế hoạch XFinder và cách nghiệm thu |
| --- | --- | --- |
| Island, màn hình, Settings | `OverlayManager` có đường xử lý đổi màn hình, chuẩn bị khi chuột đến gần và trợ giúp nhận click đầu. `PanelScale` và metadata Settings cho thấy cấu hình kích cỡ, màn hình, chủ đề và tab. | Giữ `NotchSurfaceMachine` dẫn trạng thái, catalog dẫn điểm đến. Rà click đầu, click xuyên ngoài hình, màn không notch, fullscreen, chuyển display, kích cỡ theo màn, Reduce Motion, cold/warm open và khôi phục mọi tab tắt. Đối chiếu cái XFinder đã có trước khi bổ sung. |
| Khay và Clipboard | `ShelfStore` có hạn giữ, dọn và thời gian còn lại. `FileStagingView` có nút AirDrop và vùng thả. Clipboard có dấu vết lọc, ghim, loại nguồn nhạy cảm và nhận dạng màu. | Thêm vào kiểm kê Khay thời hạn và tuổi mục. Nếu triển khai hạn giữ, chỉ dọn tham chiếu hoặc bản sao do XFinder sở hữu, giữ nguyên tệp nguồn. Kiểm AirDrop, kéo nhiều tệp ra, Quick Look, tệp mất quyền, và Clipboard từ trình quản lý mật khẩu. Kiểm lọc các kiểu nội dung, nhận màu và nút sao chép. |
| Đang phát và đồng hồ | Có dấu vết tiến độ, seek, lời bài hát đồng bộ, bấm giờ chia vòng, Pomodoro preset và liên kết âm nền. | Rà khả năng từng nguồn phát, lap và các chế độ đã có. Lời bài hát, nếu làm, xin xác nhận nguồn và điều khoản; hiện nguồn, lỗi và trạng thái bài không có lời. Âm Pomodoro dùng engine Sounds khi sẵn sàng. |
| Gương, Máy nhắc chữ và Capture | Gương dùng preview camera. Prompter có key độ trong nền và chiều cao cửa sổ. `CaptureService` có trạng thái ghi và bộ đếm giây. | Rà preview sạch khi rời tab, LED, thiết bị bị rút, thoát/chuyển màn hình trong reader, đo chênh lệch cỡ chữ/độ trong và chiều cao. XFinder đã có chụp ảnh và công cụ bổ sung. Mở việc riêng cho quay màn hình nếu engine hiện tại chưa có, gồm quyền, báo đang quay, dừng và lưu file. |
| Tệp, Liên kết, Việc cần làm và Phím tắt | Liên kết có dấu vết điều hướng web nhỏ. Todo nội bộ có ưu tiên; phím tắt hệ thống và ghi chú là các công cụ riêng. | Giữ Tệp riêng với Khay và Links dùng Quicklinks. Kiểm mở mục, lỗi URL, workspace mất quyền và phím tắt do người dùng chọn. Rà thêm ưu tiên Todo và điều hướng web thành các phần nâng cấp riêng, không đọc Clipboard để tạo dữ liệu. |
| Đổi đơn vị, Emoji và chuyển ảnh | Hồ sơ cho thấy tỷ giá có nguồn riêng so với đổi đơn vị, Emoji là công cụ riêng, và `ImageConverter` nhận nhiều URL, chất lượng, kích thước. | Giữ đổi đơn vị offline hiện có. Tách tỷ giá thành gói có nguồn, thời điểm và cache. Đối chiếu engine chuyển ảnh XFinder rồi tách trang với giới hạn batch, chất lượng, không ghi đè nguồn và lỗi từng tệp. |
| Âm nền, Message và Feedback | Tám tài nguyên loop và `SoundEngine` có tập track đang phát, volume, timer. Có `NotificationView`, `MessageView` và `FeedbackView.send`; những dấu vết này chưa xác định đủ đích gửi. | Đặc tả Sounds riêng khỏi Audio hệ thống, có trộn, volume, hẹn giờ fade-out, dừng và âm thanh XFinder được phép phân phối. Rà Message như thông báo cục bộ với văn bản và thời hạn. Feedback cần chốt kênh của XFinder, nội dung xem trước, thao tác gửi chủ động và lỗi gửi. |
| Thời lượng dùng ứng dụng | Vùng `ScreenTimeService.tick` trong `18` gọi `CGEventSourceSecondsSinceLastEventType` và `NSWorkspace.frontmostApplication`. Types có thống kê ngày, tuần và theo ứng dụng. | Đặc tả bộ đếm XFinder rõ nguồn đo, mặc định chưa theo dõi, lưu tối thiểu cục bộ, dừng lúc idle/lock/sleep và có xóa lịch sử. Ưu tiên sự kiện chuyển ứng dụng, không giả lập lịch sử Screen Time của macOS. Kiểm ngày đổi, múi giờ, sleep, tắt và khởi động lại. |
| AI, Analytics và Stocks | Dấu vết: chat dùng FoundationModels liên kết yếu; AI Usage có Claude/Codex local, OpenRouter và bảng giá; Analytics có DataFast và GA4; Stocks có đường lấy chart Yahoo. | Tách quota thật, chi phí ước tính và dữ liệu local. Chat kiểm thiết bị/OS tại runtime, thao tác mới chat và lỗi. Analytics cần đối chiếu tài liệu hiện hành, quyền đọc và luồng credential, giữ số liệu tách theo nguồn. Stocks giữ danh sách Mỹ đã chốt, chỉ nối nguồn sau khi có quyền hiển thị và kiểm độ trễ, biểu đồ, phiên. Không coi URL trong binary là hợp đồng hiện hành. |
| Phát hành | Bundle và entitlements mô tả cách PeakPad build, cập nhật và cấp phép. | Giữ ID, updater, dữ liệu và quyền sở hữu XFinder. Tách điều kiện ký thương mại khỏi đợt dùng thử miễn phí. Weather và Doanh thu vẫn ở đợt riêng đã chốt. |

### Rà giao diện sau khi bỏ dropdown

| Khu vực | Đã có trong XFinder | Còn cần đối chiếu hoặc hoàn thiện |
| --- | --- | --- |
| Thanh công cụ và Khay | Dải icon cuộn ngang theo thứ tự Settings, nút Settings riêng, vùng AirDrop và khay file. Vạch cuộn 2 pt dưới icon chỉ hiện khi quá chiều rộng. | Kiểm cuộn bằng chuột và trackpad, chọn tab ở hai đầu trên màn hình hẹp. Ảnh người dùng cho thấy trạng thái tệp lỗi bị cắt chữ khi nhiều thẻ cùng hiện. |
| Settings | Trong notch có điều hướng theo nhóm, công tắc, kéo đổi thứ tự, nút Lên/Xuống và ba độ rộng theo màn hình. Cửa sổ Settings đầy đủ vẫn mở được riêng. | Kiểm thao tác thật, đặc biệt là kéo qua phần cuộn, khôi phục khi tất cả tab tắt và đổi màn hình đang hiển thị. |
| Công cụ HTML/data và hệ thống | Nhật ký triển khai bên trên ghi mức độ tích hợp của nhóm dữ liệu, tiện ích, media, lịch và hệ thống. | Cần xác nhận các luồng có tài khoản, quyền hoặc thiết bị thật. Các khoảng cách đã ghi nhận như lời bài hát, quay màn hình, tỷ giá và nguồn giá Stocks vẫn là hạng mục riêng. |

### Gói giao cho Gemini và tích hợp

1. Gemini đã bàn giao review các tab đã ghép. Ưu tiên bảo toàn Bản nháp, dừng camera khi panel ẩn, vòng đời cửa sổ Máy nhắc chữ và bàn giao lệnh Chụp màn hình. Đã ghép patch bảo toàn Bản nháp và chuyển lệnh Capture ra khỏi view. Theo dõi nghiệm thu trong [đặc tả sửa lỗi](XF-ISLAND-REVIEW-FIXES.md), sau đó xử lý sắp xếp tab và những chênh lệch giao diện còn lại.
2. Đã ghép Việc cần làm và Phím tắt Apple, build và kiểm trạng thái mở trên Atlas.
3. Gemini đã đối chiếu lõi XFinder và hồ sơ cho bảy nhóm còn lại. Đã tích hợp [Chuyển ảnh](XF-ISLAND-IMAGE.md) dùng ImageEngine và ImageRunner, cùng [Âm nền](XF-ISLAND-SOUNDS.md) dùng âm tổng hợp cục bộ. Atlas đã mở cả hai trang và chạy 379 test tập trung, 1 bỏ qua, 0 lỗi. Còn kiểm chuyển ảnh qua thao tác thật, phát âm và công tắc. Đã tích hợp [Thời lượng dùng ứng dụng](XF-ISLAND-APP-USAGE.md), build arm64 và 444 test tập trung với 1 bỏ qua, 0 lỗi. Đã tích hợp [Chat trên máy](XF-ISLAND-LOCAL-CHAT.md), build arm64 và 453 test tập trung (1 bỏ qua, 0 lỗi). Đã tích hợp Tin nhắn cục bộ và chạy 484 test tập trung với 1 bỏ qua, 0 lỗi. Đã tích hợp [Phản hồi](XF-ISLAND-FEEDBACK.md), build arm64 và 65 test tập trung đạt; Atlas đã mở app nhưng chưa chuyển đến Feedback. Analytics, Stocks, tỷ giá và lời bài hát cần xác minh nguồn. Gói shell và quyền thật cần QA riêng.
