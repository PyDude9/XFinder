# Dynamic Island — Stocks và Doanh thu bán app

Hai trang độc lập trong menu Thêm của XFinder. Mỗi trang có cấu hình, quyền truy cập, cache và trạng thái lỗi riêng. Dùng shell Ref29, giao diện Việt–Anh và cơ chế focus hiện có. Mở trang mới khởi tạo công việc mạng. Đóng trang hủy công việc có thể hủy và bỏ qua kết quả trễ. Dữ liệu mẫu dùng cho QA.

## Phạm vi MVP đã chốt

- Doanh thu kết nối cả Stripe và Shopify. Mỗi nguồn có số liệu và trạng thái đồng bộ riêng. Chỉ gộp khi xác định được hai nguồn đại diện cho các khoản thu riêng hoặc có khóa đối soát chung. Khi chưa rõ hai nguồn có trùng giao dịch, hiển thị từng nguồn.
- Stocks bắt đầu với thị trường Mỹ. Watchlist mặc định khi chưa có cấu hình gồm chỉ số S&P 500, Apple (AAPL), Nvidia (NVDA), Crocs (CROX) và Bitcoin (BTC/USD). Settings cho phép tìm, thêm, xóa và đổi thứ tự cả khi chưa cấu hình nguồn giá. Giữ danh sách người dùng đã lưu, kể cả danh sách trống. Bitcoin dùng nguồn và thời điểm tham chiếu riêng cho thị trường 24/7. S&P 500 được định danh là chỉ số, với mã cụ thể do nguồn giá cung cấp. ETF theo dõi chỉ số là một tài sản riêng.
- Tài liệu WidgetKit mô tả cách widget do app sở hữu lấy dữ liệu, còn hướng dẫn Stocks của Apple mô tả cách người dùng xem widget. Chưa tìm thấy API Apple công khai để ứng dụng khác đọc giá trong widget Stocks. Widget dùng làm tham chiếu hiển thị. Adapter giá nhận dữ liệu từ API được phép hiển thị trong XFinder khi đã chốt nguồn.

## Hợp đồng cho hai connector doanh thu

| Nguồn | Dữ liệu và phạm vi đọc | Quy tắc đối soát |
| --- | --- | --- |
| Stripe | Balance Transactions để lấy amount, fee, net, currency, reporting_category và source. Lấy thêm loại đối tượng nguồn khi cần liên kết khoản thu/hoàn tiền. Dùng quyền đọc tối thiểu của tài khoản. | Payout nằm riêng. Giữ loại tiền và số liệu đúng như Stripe báo cáo. Chỉ phân loại giao dịch chưa rõ khi có dữ liệu nguồn phù hợp. |
| Shopify | GraphQL Admin API và read_orders cho đơn/hoàn tiền. read_shopify_payments_payouts chỉ khi có Shopify Payments và cần phí, net hoặc payout. | Giữ doanh thu đơn hàng và dòng tiền settlement ở các trường riêng. Đánh dấu phạm vi lịch sử bị giới hạn theo quyền. Với khoản thu đã liên kết được sang Stripe, dùng một bản ghi tiền thu và giữ cả hai ID để truy vết. |

Tài liệu nguồn: [Apple Stocks](https://support.apple.com/en-euro/guide/stocks/st96acfa8842/mac), [WidgetKit](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget), [Stripe Balance Transactions](https://docs.stripe.com/api/balance_transactions/object), [Shopify API scopes](https://shopify.dev/docs/api/usage/access-scopes), [Shopify Payments Account](https://shopify.dev/docs/api/admin-graphql/latest/queries/ShopifyPaymentsAccount).

## Đối chiếu bộ 29 ảnh

| Ảnh | Phần tham chiếu | Áp dụng |
| --- | --- | --- |
| 1, 20 | Shelf trống và đang kéo | Giữ Khay và vị trí các hành động theo ngữ cảnh. |
| 2 | Bảng tính năng và giá | Nhận diện Stocks và doanh thu là hai chức năng riêng. |
| 3, 8 | AI Usage, trạng thái từng nguồn | Hiện trạng thái kết nối và tuổi dữ liệu theo nguồn. |
| 4, 9 | Tổng quan và tác vụ đang chạy | Giữ nhạc và lịch trong luồng hiện có. |
| 5 | Tìm kiếm Clipboard | Tìm mã trên dòng có đủ chỗ, hỗ trợ focus và Esc. |
| 6, 14 | Reminders và Calendar | Dùng danh sách ngắn, hiển thị thời gian theo ngữ cảnh. |
| 7, 12, 18, 25 | Mirror và Teleprompter | Các cửa sổ và quyền riêng của module này nằm trong roadmap riêng. |
| 10, 17 | Island thu gọn, timer và thông báo bán hàng | Giữ một tín hiệu tại một thời điểm. Thông báo doanh thu là tùy chọn sau MVP vì số tiền có thể nhạy cảm. |
| 11, 27 | Lưu lượng truy cập và referrer | Analytics truy cập là module riêng. |
| 13, 21, 29 | Doanh thu theo giờ/ngày, bộ chọn kỳ, tổng và trạng thái làm mới | Làm cơ sở cho trang Doanh thu. Hiển thị nguồn, kỳ, đơn vị tiền và lần cập nhật trên cùng màn. |
| 15, 19, 23, 26 | Cấu hình, vị trí tab và nút bật/tắt | Dùng menu Thêm và trang Settings cho kết nối. Ảnh Stocks xác nhận điểm vào, bố cục chi tiết dưới đây là đề xuất cho XFinder. |
| 16 | Timers và thao tác chính | Giữ điểm vào, nút chính rõ ràng trong shell. |
| 22, 28 | Chat và trạng thái rỗng | Dùng mẫu hướng dẫn ngắn ở màn chưa kết nối. Chat nằm ngoài hai module. |
| 24 | Bộ thẻ tổng quan | Giữ mỗi trang một nhiệm vụ chính và trạng thái nguồn nhìn được ngay. |

## Doanh thu bán app

- **Bố cục.** Tiêu đề và Làm mới ở đầu. Hôm nay / 7 ngày / 30 ngày, tổng theo tiền tệ và số giao dịch ở trái, biểu đồ theo giờ hoặc ngày ở phải. Khổ hẹp xếp dọc trong thân có cuộn. Một dòng nguồn và lần đồng bộ. Settings mở luồng kết nối portal và chọn tài khoản. Các kỳ dùng múi giờ báo cáo của tài khoản và hiển thị rõ ranh giới.
- **Mô hình.** Lưu loại sự kiện, khóa định danh theo portal/tài khoản, giờ tuyệt đối, số tiền nguyên theo đơn vị nhỏ nhất và mã ISO tiền tệ. Phân biệt khoản thu, hoàn tiền, phí và payout. Hiển thị từng tiền tệ nếu có nhiều loại tiền. Tổng tiền thực nhận chỉ xuất hiện khi dữ liệu đủ để đối soát. Giá trị thiếu giữ trạng thái chưa có dữ liệu.
- **Đồng bộ.** Hai connector chỉ đọc ở MVP. Phân trang, upsert theo ID, xử lý cập nhật hoàn tiền muộn, ghi cursor sau khi lưu thành công. Lưu token trong Keychain theo tài khoản. Làm mới gộp các yêu cầu trùng. Khi ngắt kết nối, hủy yêu cầu, xóa token và dữ liệu cục bộ thuộc tài khoản. Cache cũ có nhãn khi offline/lỗi. Đối soát số tiền và số đơn với từng dashboard.
- **Nghiệm thu.** Dữ liệu mẫu gồm giao dịch trùng, nhiều tiền tệ, hoàn một phần, payout, phân trang bị ngắt và đổi ngày/DST. Kiểm tra tài khoản thật bằng quyền chỉ đọc sau khi người dùng chốt portal. Chưa cần gửi khóa trong chat.

## Stocks

- **Bố cục.** Watchlist có tìm mã, thêm/xóa và đổi thứ tự. Hàng hiển thị mã, sàn, giá, biến động và thời điểm cập nhật. Chi tiết mã có biểu đồ của kỳ được nguồn dữ liệu hỗ trợ. Khổ hẹp ưu tiên hàng đang chọn và thông tin giá. Khi thị trường đóng, hiện giá cuối phiên kèm thời điểm. Lỗi một mã giữ các mã còn lại dùng được.
- **Mô hình.** Định danh theo mã, sàn và mã nguồn. Giữ tiền tệ, giá, giá tham chiếu phiên trước từ provider, timestamp và trạng thái phiên. Tách trạng thái giá trễ theo nguồn, thị trường đóng và dữ liệu quá cũ. Chỉ tính phần trăm thay đổi khi giá tham chiếu hợp lệ.
- **Đồng bộ.** Chọn nguồn theo loại tài sản; dùng adapter riêng cho Bitcoin nếu nguồn giá Mỹ không cung cấp BTC/USD. Xác nhận quyền hiển thị dữ liệu trong app trước khi chọn provider. Lưu watchlist cục bộ. Chỉ gọi mạng khi mở trang hoặc làm mới, gộp yêu cầu theo khả năng của provider, bỏ kết quả của watchlist đã đổi. Giữ giá cache với tuổi dữ liệu.
- **Nguồn đang dùng.** Hỗ trợ **Twelve Data** và **Massive** (cả hai trả nến ngày đã hoàn tất, mỗi hàng có giá đóng cửa kèm `quotedAt`/`fetchedAt`, biến động so với lần đóng cửa trước và biểu đồ thu gọn 7 ngày; chi tiết có kỳ 7 và 30 ngày). Bản Debug dùng khóa demo công khai của Twelve Data cho `AAPL` và `BTC/USD` khi chưa lưu khóa riêng; các mã khác như `NVDA`, `CROX`, `S&P 500` ở chế độ demo không có dữ liệu và phải hiển thị rõ lý do demo (không chỉ báo chung chung "Cần quyền truy cập nguồn giá") kèm đường dẫn mở thẳng ô nhập khóa API trong Settings. Settings lưu khóa riêng cho từng nguồn trong Keychain (`com.xfinder.app.stocks`). Không bịa giá và không scrape nguồn không phép. Dữ liệu của các mã khác phụ thuộc quyền tài khoản. SPX chỉ nhận dữ liệu nguồn xác nhận là chỉ số (`I:SPX` với Massive).
- **Ca hỏng cần xử lý.** Thiếu khóa API ở Debug (demo chỉ hỗ trợ `AAPL` & `BTC/USD`, hiện hướng dẫn demo + nút mở Settings cho các mã bị chặn) · thiếu khóa ở Release (mở màn hình chưa cấu hình, giữ watchlist) · khóa sai/hết hạn 401/403 (báo lỗi quyền truy cập, không bịa giá) · vượt giới hạn 429 (báo hết lượt, cho phép thử lại) · offline có/không có cache (giữ cache có nhãn tuổi dữ liệu hoặc báo mất mạng) · đổi nguồn hoặc xóa/lưu khóa trong Settings (hủy yêu cầu cũ và tải lại sạch) · đổi watchlist khi phản hồi cũ đang bay (bỏ kết quả cũ) · SPX không được gói Basic hỗ trợ (cô lập lỗi từng mã).
- **Nghiệm thu.** Dữ liệu mẫu gồm mã trùng ở hai sàn, mở/đóng phiên, giá trễ, giá thiếu, quota, offline, và đổi mã khi phản hồi cũ đang chờ. Kiểm tra dữ liệu một phiên mở và một phiên đóng theo múi giờ của sàn.

## Thứ tự triển khai

1. Hai portal và thị trường đã chốt. Xác nhận kiểu thanh toán Shopify để kiểm thử đối soát chéo, chọn API giá theo phạm vi Mỹ và điều khoản hiển thị lại dữ liệu.
2. Dựng hai bản QA cô lập với fixture, dùng menu Thêm, action làm mới, trạng thái chưa kết nối, đang tải, rỗng, lỗi, offline và dữ liệu cũ. Tái sử dụng NotchExtraModule, NotchGalleryRules và hành vi mở/đóng của shell. Mỗi module có ViewModel và adapter riêng. Giữ menu đáy và vùng phím Esc ổn định. Xác minh layout VI/EN, khổ rộng/hẹp, VoiceOver và Esc trên Atlas.
3. Thêm connector chỉ đọc cho portal và adapter giá trong hai nhánh công việc riêng. Kiểm tra test hợp đồng với HTTP giả lập và dữ liệu mẫu. Sau đó đối soát dữ liệu thật qua luồng cấu hình an toàn của app.
4. Build arm64 và chạy các kiểm tra giao diện trên Atlas. Kiểm tra hồi quy Khay, Clipboard, Weather và điều hướng. Kiểm tra Stocks mở được ở trạng thái chưa có nguồn giá và chỉ tải giá khi có adapter.

## Luồng QA độc lập với nhà cung cấp

| Trạng thái | Doanh thu | Stocks |
| --- | --- | --- |
| Chưa cấu hình | Nút Kết nối mở Settings | Hiện watchlist đã lưu và nút mở phần quản lý trong Settings. Có thể mở Apple Stocks nếu app được cài trên máy. |
| Rỗng | Kỳ đã đồng bộ và có 0 giao dịch | Watchlist chưa có mã |
| Đang tải lần đầu | Giữ bộ chọn kỳ, vô hiệu hóa Làm mới | Giữ watchlist, hiển thị đang tải ở hàng thiếu giá |
| Làm mới với cache | Giữ tổng, biểu đồ và tuổi dữ liệu | Giữ giá từng hàng và tuổi dữ liệu |
| Lỗi có cache | Giữ kỳ và số liệu, ghi lỗi bên cạnh lần cập nhật | Chỉ đánh dấu hàng bị lỗi, giữ các hàng còn lại |
| Lỗi thiếu cache | Hiện lỗi và Thử lại | Hiện lỗi tại hàng hoặc khu vực tìm kiếm, theo thao tác gây lỗi |

Ở khổ hẹp, mỗi hàng ưu tiên ký hiệu, giá và biến động. Mở chi tiết để xem nguồn, độ trễ và mốc so sánh. Danh sách cuộn khi vượt chiều cao Island. Nghiệm thu với 0, 1, 5 và nhiều hơn 5 tài sản, tên dài, mất giá một mã và BTC/USD cuối tuần.
