# XF-WEATHER-01 — Contract: Dynamic Island Weather (Đợt 2)

Tài liệu đặc tả kỹ thuật theo quy trình `AGENT_TASKS.md` §3c cho tính năng **Thời tiết trong Dynamic Island (Đợt 2)**.

---

## 1. Mục tiêu và phạm vi

- **Mục tiêu**: Người dùng mở trang Thời tiết từ menu "Thêm" của Dynamic Island, tự chọn thành phố (tra cứu có debounce, phân biệt trùng tên), xem dự báo thời tiết 12 giờ tới và biết rõ dữ liệu được lấy bao lâu trước (tuổi dữ liệu / nhãn fresh/stale/offline). Thao tác lấy vị trí hiện tại là chủ động (opt-in), không tự động gọi định vị ngầm.
- **Ranh giới và độc lập**:
  - Tách rời hoàn toàn tầng dữ liệu, mô hình, cache, điều phối async và quy tắc hiển thị khỏi framework mạng hoặc hệ thống quyền.
  - Tách giao diện nhà cung cấp (`WeatherProvider`) thành giao thức độc lập, hỗ trợ MockProvider (cho unit tests với 0 network/disk I/O) và các nhà cung cấp thực tế.
  - Giữ Island, Khay thả và Atlas hoạt động bình thường, phản hồi ngay lập tức kể cả khi mạng chậm, offline hoặc người dùng chuyển đổi thành phố liên tục.
  - Doanh thu và Cổ phiếu (Stocks) KHÔNG thuộc phạm vi đợt này.

---

## 2. Tình huống hỏng (QUICKSTART Luật 11)

Bảng các tình huống hỏng bắt buộc phải được xử lý và kiểm chứng bằng unit test:

| Tình huống | Hành vi mong đợi của hệ thống |
|:---|:---|
| **1. Thiếu quyền định vị / Người dùng từ chối cấp quyền** | Không lặp lại hộp thoại xin quyền; quay lại màn hình chọn thành phố thủ công; hiển thị giải thích rõ ràng "Định vị bị từ chối/không khả dụng". Không tự động gọi định vị ngầm khi khởi động hoặc mở app. |
| **2. Ngoại tuyến (Offline) / Mất mạng** | Nếu có cache hợp lệ (< 6 giờ), hiển thị dự báo cùng tuổi dữ liệu ("Cập nhật X phút trước" / "Ngoại tuyến"). Nếu không có cache, hiển thị trạng thái ngoại tuyến rõ ràng kèm nút "Thử lại". Không làm đơ UI hoặc treo Dynamic Island. |
| **3. Lỗi mạng / Quota 429 / Server lỗi 5xx** | Báo lỗi rõ ràng, cho phép thử lại chủ động. Giới hạn timeout hữu hạn (10s), không auto-retry vô hạn trong vòng lặp. Click refresh liên tiếp được coalesce (gộp thành 1 request đang bay). |
| **4. Đổi thành phố liên tục (A → B → A) & phản hồi ngược thứ tự** | Dùng generation token và ID thành phố. Khi chọn thành phố mới, lập tức xóa dự báo cũ khỏi UI. Phản hồi chậm của thành phố cũ đến sau bị hủy/bỏ qua, không bao giờ ghi đè lên thành phố đang chọn. |
| **5. Cache cũ / Hết hạn (Expired) / Sai nhà cung cấp / Dữ liệu hỏng** | Dưới 15 phút: Fresh (không fetch lại trừ khi nhấn Làm mới). Từ 15 phút đến 6 giờ: Stale (dùng tạm khi ngoại tuyến, tự động làm mới khi mở trang). Quá 6 giờ hoặc sai provider hoặc dữ liệu không giải mã được: coi như Cache Miss. |
| **6. Giờ trong quá khứ** | Bỏ toàn bộ các mốc giờ trước thời điểm hiện tại (`date < now`); lấy tối đa 12 mốc giờ kế tiếp. Nếu không còn mốc giờ nào trong tương lai, ẩn card hoặc kích hoạt làm mới. |
| **7. Thành phố trùng tên (ví dụ: Paris, Texas vs Paris, Pháp)** | `WeatherLocation` có ID ổn định, hiển thị kèm vùng (`admin1`/tiểu bang/tỉnh) và quốc gia để phân biệt rõ ràng. |
| **8. Khác múi giờ & DST (Daylight Saving Time)** | Mốc giờ dự báo dùng `Date` tuyệt đối. Nhãn giờ địa phương được định dạng theo `TimeZone` của chính địa điểm đó, không phụ thuộc vào múi giờ của máy Mac. |
| **9. Trường dữ liệu thiếu (ví dụ: không có xác suất mưa)** | Không tự bịa số (không tạo số 0% nếu provider không trả về); trường nào thiếu thì ẩn nhãn tương ứng. |
| **10. Khởi động app / Mở trang khác / Đóng trang** | Không fetch dữ liệu lúc app launch; không fetch khi hover các trang khác; không dùng polling timer định kỳ. Khi đóng trang, hủy toàn bộ task tải chỉ phục vụ UI. |

---

## 3. Khảo sát Provider và điều kiện phân phối

### 3.1. Apple WeatherKit
- **Yêu cầu phân phối & Ký số**:
  - Yêu cầu tài khoản Apple Developer Program trả phí ($99/năm).
  - App ID phải được bật dịch vụ WeatherKit trên Apple Developer Portal.
  - Phải có file `embedded.provisionprofile` do Apple cấp chứa entitlement `com.apple.developer.weatherkit`.
  - Khảo sát mã ký của bản cài `/Applications/XFinder.app`:
    - `Identifier=com.xfinder.app`
    - `Authority=XFinder Dev` (chứng chỉ tự ký nội bộ để giữ quyền TCC).
    - `TeamIdentifier=not set`
    - `embedded.provisionprofile`: không có.
    - `entitlements`: không có.
  - Kết luận: Khi gọi `WeatherService.shared.weather(for:)` trong môi trường chưa có chứng chỉ và profile của Apple Developer Program, hệ thống sẽ từ chối và ném lỗi xác thực/entitlement không hợp lệ (`WeatherServiceError`).
- **Điều khoản & Lưu trữ (Apple WeatherKit)**:
  - Cache: Chỉ được lưu trữ tạm thời phục vụ hiển thị phiên người dùng; không lưu vĩnh viễn hoặc phân phối lại.
  - Attribution: Bắt buộc hiển thị logo Apple Weather và liên kết pháp lý (`WeatherService.attribution.legalPageURL` hoặc `https://weather-data.apple.com/legal-attribution.html`), kể cả khi đang xem dữ liệu cache.
  - Quota: 500.000 cuộc gọi/tháng cho tài khoản Apple Developer.

### 3.2. Phương án thay thế: Open-Meteo
- **Sự phù hợp**: Phù hợp tối đa với mô hình phân phối trực tiếp / nguồn mở của XFinder mà không đòi hỏi tài khoản Apple Developer, signing profile hay secret API key.
- **Quyết định của chủ dự án (2026-11-25)**: Chủ dự án phê duyệt sử dụng bản miễn phí Open-Meteo cho giai đoạn hiện tại ("tiếp tục dùng bản free. Khi nào tôi mua developer program sẽ cung cấp cho bạn sau").
- **Điều khoản & Giấy phép**: Miễn phí cho mục đích phi thương mại / cá nhân lên tới 10.000 request/ngày. Bản quyền dữ liệu theo CC-BY 4.0.
- **Attribution**: "Dữ liệu thời tiết bởi Open-Meteo.com" kèm link `https://open-meteo.com/`. Hiển thị đầy đủ cả khi xem cache.
- **Geocoding & Tìm kiếm**: Endpoint `https://geocoding-api.open-meteo.com/v1/search?name={query}&count=5&language=vi,en` trả về danh sách thành phố có tên, tỉnh/bang (`admin1`), quốc gia, tọa độ và múi giờ IANA.
- **Dữ liệu gửi đi & Quyền riêng tư**: Chỉ gửi tên thành phố khi người dùng tìm kiếm; không gửi telemetry, không gửi ID thiết bị, không lưu tọa độ GPS chính xác vào ổ đĩa.

---

### 3.3. Chọn nguồn dữ liệu theo bản dựng

- Debug dùng Open-Meteo Free cho thử nghiệm cá nhân, qua `configureWeather(provider:)`. Tham số `--disable-weather` tắt mục Thời tiết trong phiên thử nghiệm.
- Release có điểm cấu hình tại cùng lối khởi chạy trong `XFinderApp.swift`. Khi có App ID, signing và capability WeatherKit, nối một adapter `WeatherProvider` của Apple tại đây. Adapter cần cung cấp attribution Apple và dùng chính sách cache phù hợp với WeatherKit. Trước khi nối nguồn phát hành, Release để Thời tiết ở trạng thái chưa cấu hình.

## 4. Kiến trúc và các thành phần mã nguồn

### 4.1. `WeatherModels.swift` (Thuần Foundation)
- `WeatherLocation`: `id: String`, `name: String`, `region: String`, `country: String`, `latitude: Double`, `longitude: Double`, `timeZoneIdentifier: String`, `isCurrentLocation: Bool`.
- `WeatherCondition`: Phân loại điều kiện thời tiết (nắng, nhiều mây, mưa, dông, tuyết, sương mù...) ánh xạ sang SF Symbols và khóa L10n.
- `HourlyForecast`: `date: Date`, `temperatureCelsius: Double`, `precipitationProbability: Double?`, `condition: WeatherCondition`. Hàm format giờ theo múi giờ địa phương và kiểm tra DST.
- `WeatherAttribution`: `providerId: String`, `serviceName: String`, `legalURL: URL?`, `markSymbol: String?`.
- `WeatherSnapshot`: `location: WeatherLocation`, `fetchedAt: Date`, `attribution: WeatherAttribution`, `hourly: [HourlyForecast]`. Hàm `upcoming12Hours(from: Date, timeZone: TimeZone) -> [HourlyForecast]`.
- `WeatherFreshness`: `enum Freshness { case fresh, stale(age: TimeInterval), expired }`.

### 4.2. `WeatherCache.swift` (Thuần Foundation)
- Quản lý bộ nhớ đệm theo cặp `(providerId, locationId)`.
- TTL: 15 phút fresh, 6 giờ stale. Sau 6 giờ coi như hết hạn.
- Xử lý cache hỏng, cache sai phiên bản hoặc sai provider như cache miss an toàn.
- Giới hạn số lượng mục lưu trữ (tối đa 10 địa điểm), dọn dẹp các mục cũ.

### 4.3. `WeatherProvider.swift` (Protocol & Error Types)
- Giao thức `WeatherProvider: Sendable` định nghĩa:
  - `var id: String { get }`
  - `var attribution: WeatherAttribution { get }`
  - `func fetchForecast(for location: WeatherLocation) async throws -> WeatherSnapshot`
  - `func searchLocations(query: String) async throws -> [WeatherLocation]`
- `WeatherError: Error, Equatable`: `.offline`, `.rateLimited`, `.timeout`, `.invalidData`, `.locationDenied`, `.serverError(statusCode: Int)`.
- `MockWeatherProvider`: Dành cho kiểm thử không mạng, hỗ trợ mô phỏng độ trễ, lỗi timeout, 429, trả về dữ liệu mẫu có kiểm soát.

### 4.4. `WeatherCoordinator.swift` (Điều phối Async & Trạng thái UI)
- Giữ `WeatherUIState`:
  - `.unselected`
  - `.loadingInitial(WeatherLocation)`
  - `.loaded(WeatherSnapshot, freshness: WeatherFreshness)`
  - `.refreshing(WeatherSnapshot)`
  - `.offlineWithStale(WeatherSnapshot, age: TimeInterval)`
  - `.offlineNoData(WeatherLocation)`
  - `.failed(WeatherLocation, WeatherError, canRetry: Bool)`
  - `.locationDenied`
- Generation Tracking: Tránh race condition khi chuyển đổi địa điểm hoặc phản hồi đến trễ.
- Coalescing: Gộp các yêu cầu làm mới trùng lặp khi đang tải.
- Không có polling timer ngầm; I/O mạng chạy ngoài main actor; cập nhật UI trên MainActor.

### 4.5. `WeatherLocationService.swift` (Lưu trữ & Dịch vụ vị trí)
- `WeatherLocationStore`: Giao thức lưu trữ lựa chọn thành phố thủ công của người dùng (`loadSavedLocation()`, `saveLocation()`, `clearSavedLocation()`).
- `UserDefaultsWeatherLocationStore`: Triển khai qua `UserDefaults.standard` với khóa `weather.savedLocation`. Tuân thủ nghiêm ngặt nguyên tắc bảo vệ quyền riêng tư: **từ chối lưu tọa độ thiết bị** khi `isCurrentLocation == true`.
- `WeatherLocationService`: Giao thức xin vị trí thiết bị chủ động theo yêu cầu của người dùng (`requestCurrentLocation() async throws -> WeatherLocation`).
- `DefaultWeatherLocationService`: Trả về `WeatherError.locationDenied` một cách an toàn do app chưa khai báo `NSLocationWhenInUseUsageDescription` trong Info.plist (Builder không được phép sửa Info.plist), đưa người dùng quay lại giao diện chọn thành phố mà không crash hoặc rò rỉ dữ liệu.

---

## 5. Kế hoạch tích hợp và điểm dừng (Stop Condition)

1. **Giai đoạn hiện tại (Độc lập & Được phép)**:
   - Xây dựng tầng mô hình thuần `WeatherModels.swift`, `WeatherCache.swift`, `WeatherProvider.swift`, `WeatherCoordinator.swift`.
   - Viết bộ kiểm thử toàn diện `WeatherRulesTests.swift` phủ 100% ma trận nghiệm thu logic thuần.
   - Tạo symlinks trong `Tests/XFinderLogicTests/` để `swift test` chạy tự động và xanh.
   - Thẩm định `sh scripts/gate-all.sh` giữ trạng thái GATE: green.
2. **Giai đoạn tích hợp UI (Chờ baseline Phase 1 & Phê duyệt)**:
   - Dừng trước khi sửa `NotchSurfaceMachine.swift`, `NotchSurfaceController.swift`, `NotchIslandRules.swift`, `NotchGalleryRules.swift` hoặc `project.pbxproj` của app chính vì:
     - Nhánh `agent/antigravity-vorssaint-phase1` tại repo gốc `/Users/wolong/github/XFinder` chưa được commit hoặc gộp vào `main`.
     - Quy trình yêu cầu có baseline sạch được phê duyệt trước khi tích hợp vào giao diện Dynamic Island.
     - Cần quyết định của chủ dự án về việc lựa chọn nhà cung cấp chính thức (Open-Meteo vs WeatherKit khi có signing).

---

## 6. Bổ sung: Adapter Open-Meteo, SwiftUI View & Danh sách tích hợp Phase 1

### 6.1. Adapter Open-Meteo (`OpenMeteoAdapter.swift`)
- **Injectable HTTP Transport**: `HTTPTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)`. Cho phép kiểm thử 100% bằng dữ liệu mẫu (fixtures) trong bộ nhớ, không phụ thuộc kết nối mạng thực tế.
- **Xử lý Unicode & Locale**: Tìm kiếm thành phố hỗ trợ tiếng Việt có dấu ("Đà Nẵng", "TP. Hồ Chí Minh", "Hà Nội"), các bảng mã quốc tế, ánh xạ đúng múi giờ IANA.
- **Unix Timestamps & DST**: Sử dụng tham số `timeformat=unixtime` để nhận thời gian dạng Unix epoch tuyệt đối, triệt tiêu lỗi phân tích múi giờ chuỗi và phản ánh chính xác quy tắc Daylight Saving Time.
- **An toàn mảng & Mã thời tiết WMO**: Kiểm tra kích thước mảng lệch, giá trị null; ánh xạ mã thời tiết WMO (0..99) sang `WeatherCondition`.
- **Điều khoản thương mại & XFinder Pro**: Điều khoản Open-Meteo Free API (https://open-meteo.com/en/terms) giới hạn sử dụng phi thương mại. Do XFinder có gói Pro thương mại, adapter được thiết kế độc lập và **chưa bật làm mặc định** cho bản phân phối chính thức khi chưa có thỏa thuận cấp phép thương mại hoặc quyết định của chủ dự án.

### 6.2. SwiftUI View độc lập (`NotchWeatherPage.swift`)
- View độc lập hỗ trợ preview trong Dynamic Island canvas (chiều rộng 480pt/612pt).
- Dải dự báo 12 giờ tới dạng cuộn ngang (`ScrollView(.horizontal)`), nhãn giờ địa phương theo múi giờ thành phố, nhiệt độ, biểu tượng điều kiện thời tiết và xác suất mưa.
- Nhãn tuổi dữ liệu ("Vừa xong", "Cập nhật X phút trước", "Ngoại tuyến") tự động cập nhật theo trạng thái cache.
- Tìm kiếm thành phố có debounce 300ms, danh sách kết quả, điều hướng phím (Esc hủy/đóng, Enter chọn) và nút đóng/mở tìm kiếm.
- Xử lý lỗi đầy đủ kèm nút "Thử lại": mất mạng, lỗi máy chủ, từ chối định vị.
- Hỗ trợ VoiceOver đầy đủ (`accessibilityLabel`) và tôn trọng tùy chọn `accessibilityReduceMotion` (tắt hiệu ứng xoay khi tải).
- Tích hợp đầy đủ chuỗi L10n qua `L10n.t(...)` trong `L10n.strings.json`.

### 6.3. Thiết kế & Patch Tích Hợp Phase 1 (Đã kiểm chứng trên bản sao chọn lọc tại `/tmp/xf-weather-island-patch/`)

Qua đối chiếu trực tiếp mã nguồn Phase 1 (chế độ chỉ đọc trên `/Users/wolong/github/XFinder`), cơ chế chuẩn của Dynamic Island cho các module mở từ menu **"Thêm"** là `NotchExtraModule` (cùng nhóm với `.system` và `.audio`), cho phép tích hợp phẫu thuật mà **không sửa bất kỳ dòng nào của `NotchSurfaceMachine.swift`, `NotchPages.swift`, `NotchHoverOpen.swift` hay `NotchSurfaceLayout.swift`**:

1. **Cổng kích hoạt Production nghiêm ngặt (`configureWeather(provider:)`)**:
   - Mặc định trong `NotchSurfaceController`, `weatherCoordinator = nil` và `weatherViewModel = nil` (`isWeatherAvailable == false`).
   - Khi chưa được truyền một `WeatherProvider` phát hành hợp lệ: mục **Thời tiết** hoàn toàn **không xuất hiện** trong menu **"Thêm"**, không xuất hiện trong `Tất cả mục` (`⌘G`), phím tắt `W`/`0` không kích hoạt, và phát sinh **0 request mạng**. Không bao giờ tự gắn `Fixture` hay `OpenMeteoAdapter()` miễn phí làm mặc định trong production.
   - Khi chủ dự án chốt nguồn dữ liệu phát hành và gọi `NotchSurfaceController.shared.configureWeather(provider: ...)`, `model.weatherAvailable` bật `true` và đăng ký đầy đủ menu Thêm + Gallery + phím tắt.
2. **Danh sách 10 tệp Phase 1 áp dụng patch** (`/tmp/xf-weather-island-patch/XF-WEATHER-01-phase1-notch-integration.patch`, `257 insertions, 17 deletions`):
   - `XFinder/Core/Notch/NotchGalleryRules.swift`: Thêm `case weather` vào `NotchExtraModule`, `weatherItem` (`id: "weather"`, `titleKey: "Thời tiết"`, `symbol: "cloud.sun.fill"`, `shortcutKey: "W"`, `digitKey: "0"`), hàm `items(weatherAvailable:)` và `destination(forKeyCharacter:weatherAvailable:)`.
   - `XFinder/Core/Notch/NotchIslandRules.swift`: Thêm tham số `weatherAvailable: Bool = false` vào `NotchNavLayout.plan(...)`; khi `true`, trả về `overflowExtras = [.weather, .system, .audio]`. Không chạm tới `NotchCollapsedSignal` hay `NotchMotionPolicy`.
   - `XFinder/Views/NotchSectionsView.swift`: Đọc `NotchGalleryRules.items(weatherAvailable: model.weatherAvailable)` và tự co chiều cao ô (`31pt`, spacing `5pt` khi có 10 mục -> `4×31 + 3×5 = 139pt <= 140pt` khung wide body).
   - `XFinder/Views/NotchSurfaceView.swift`: Bổ sung `weatherAvailable`, `weatherViewModel`, `isSearchingWeatherCity` trên `NotchSurfaceModel`; render `NotchWeatherPage(viewModel: vm, embedsInIsland: true)` cho `case .weather`; truyền `weatherAvailable` vào `NotchNavLayout.plan`. Khi `embedsInIsland == true`, `NotchWeatherPage` nhường hoàn toàn quyền gọi `onAppear()` / `close()` cho `NotchSurfaceController.syncWeatherLifecycle()` (một chủ sở hữu vòng đời duy nhất).
   - `XFinder/Core/Notch/NotchSurfaceController.swift`: Bổ sung `configureWeather(provider:cache:locationStore:locationService:)`, `syncWeatherLifecycle()` (gọi `onAppear()` → `coordinator.reopen()` đánh giá lại TTL 15 phút / 6 giờ theo `clock()` và giữ nguyên dự báo cũ ở trạng thái `.refreshing` khi tải mới; gọi `close()` tăng `activeGeneration` để triệt tiêu kết quả GPS đến trễ và huỷ tìm kiếm đang bay ngay khi đóng module / đổi trang / thu gọn tai thỏ / `stop()`), giữ `composing = true` và `ensurePanelKeyForKeyboard()` + `@FocusState` khi ô tìm kiếm thành phố đang mở, và ưu tiên phím `Esc` đóng ô tìm kiếm thành phố cả khi `NSTextView` đang giữ focus.
   - `XFinder.xcodeproj/project.pbxproj`: Bổ sung đủ 4 mục (`PBXBuildFile`, `PBXFileReference`, group child, `Sources` phase) cho 8 tệp Weather với dải ID riêng `7F1A0E00`..`7F1A0E0F` (không đụng dải `7F1A0D24`..`7F1A0D51` của Phase 1).
   - `scripts/build-and-check.sh`: Thêm tên 8 tệp Weather + `NotchGalleryRules.swift`, `NotchIslandRules.swift` vào danh sách kiểm tra `XFinder.SwiftFileList`.
   - `XFinder/Resources/L10n.strings.json`: Nối 14 khóa L10n của Weather vào sau mục cuối của Phase 1 (0 trùng khóa).
   - `Tests/XFinderLogicTests/NotchGalleryRulesTests.swift` & `Tests/XFinderLogicTests/NotchIslandRulesTests.swift`: Bổ sung unit test xác minh cổng `weatherAvailable == false` vs `true`.
3. **Phân tích xung đột khi Rebase/Merge & Quy trình áp dụng khi có Baseline Phase 1**:
   - **Tệp mới không xung đột (18 đường dẫn)**: 8 tệp nguồn Swift (`XFinder/Core/Weather/*.swift`, `XFinder/Views/NotchWeatherPage.swift`), 3 tệp test (`WeatherRulesTests.swift`, `OpenMeteoAdapterTests.swift`, `WeatherViewModelTests.swift`) và 7 test symlinks hoàn toàn tách biệt với 97 đường dẫn đang thay đổi của Phase 1.
   - **Xung đột dự kiến nếu `git rebase` nhánh `agent/antigravity-weather` trực tiếp lên Phase 1**:
     1. `XFinder/Resources/L10n.strings.json`: Cả Phase 1 và nhánh Weather đều nối thêm khóa ngay sau `"Không tạo được tệp mới"` của `a03b647` (nhưng **0 trùng tên khóa** — 14 khóa Weather nối tiếp sau `"Không thể gửi sang ngăn trình duyệt hiện tại."` như đã giải quyết sẵn trong patch).
     2. `docs/AGENT_WORKLOG.md`: Cả hai nhánh cùng chèn mục mới lên đầu tệp (giữ cả hai theo thứ tự thời gian).
   - **Hai cách tích hợp sạch khi Phase 1 được commit lên `main`**:
     - *Cách A (Áp thẳng bundle patch lên Phase 1)*: `git apply --check /tmp/xf-weather-island-patch/XF-WEATHER-01-full-bundle.patch && git apply /tmp/xf-weather-island-patch/XF-WEATHER-01-full-bundle.patch`
     - *Cách B (Rebase nhánh `agent/antigravity-weather` lên `main` đã có Phase 1, rồi áp patch phần Notch)*: Giải quyết 2 hunk nối tiếp ở `L10n.strings.json` + `AGENT_WORKLOG.md`, sau đó áp các tệp Notch/pbxproj từ `/tmp/xf-weather-island-patch/XF-WEATHER-01-phase1-notch-integration.patch`.
   - **Lệnh kiểm chứng sau khi tích hợp lên baseline sạch**:
     ```bash
     plutil -lint XFinder.xcodeproj/project.pbxproj
     XF_OUT=/tmp/xf-weather-int-build sh scripts/build-and-check.sh
     XF_OUT=/tmp/xf-weather-int-build sh scripts/gate-all.sh
     ```

### 6.4. Harness Preview Độc Lập Cho Chủ Dự Án Thử Nghiệm (`scripts/preview-weather/`)
- **Tách biệt hoàn toàn**: Ứng dụng preview độc lập chạy trên kiến trúc arm64 macOS 14+, được build vào thư mục `/tmp/xf-weather-preview/XFinderWeatherPreview.app`, không đụng chạm đến bản cài `/Applications/XFinder.app` của máy chủ.
- **Không gọi mạng mặc định & Tách biệt Cache theo Provider**: `WeatherCoordinator` và `WeatherViewModel` bắt buộc tiêm provider tường minh. `WeatherCacheStore` lưu theo `provider.id` của coordinator nhưng vẫn giữ nguyên `snapshot.attribution` gốc, đảm bảo không bao giờ trộn cache giữa hai provider (`fixture` vs `open-meteo`). Preview khởi chạy mặc định ở nguồn `Fixture (Mẫu tĩnh · 0 mạng)`.
- **Hộp điều khiển mô phỏng tương tác (tách Nguồn dữ liệu và Tình trạng mạng)**:
  - **Nguồn dữ liệu (Provider)**: `Fixture (Mẫu tĩnh · 0 mạng)` (`id: "fixture"`) hoặc `Open-Meteo (Trực tiếp)` (`id: "open-meteo"` qua `SimulatableHTTPTransport`).
  - **Mô phỏng mạng**: `Trực tuyến (Bình thường)`, `Mạng chậm (1.5s delay)`, `Ngoại tuyến (Lỗi mạng)` (giữ nguyên dự báo 12h, tuổi dữ liệu và attribution thật khi Refresh; báo `Không có dữ liệu thời tiết` nếu cache trống/hết hạn), hoặc `Lỗi 429 (Hết hạn mức)`.
  - **Giả lập quyền vị trí**: Từ chối (Denied) / Cho phép (Allowed).
  - **Thu gọn / Mở rộng tai thỏ & Reset Cache**: Kiểm tra vòng đời `viewModel.close()`, `viewModel.onAppear()`, và `coordinator.reset()`.
  - **Cụm nút QA nhanh (plain `AXButton`)**: `Nạp TP.HCM mẫu`, `Ngoại tuyến + Làm mới`, `Trực tuyến + Làm mới`, `Chọn Đà Nẵng` — kích hoạt trực tiếp luồng `selectLocation` và `refresh()` thật trên ViewModel/Provider để hỗ trợ kiểm thử GUI tự động mà không phụ thuộc `NSPopUpButton` hay gán chuỗi AX trực tiếp.
  - **Chuyển đổi ngôn ngữ**: Tiếng Việt / English.
- **Lệnh build**: `sh scripts/build-weather-preview.sh`.
- **Lệnh mở preview**: `open /tmp/xf-weather-preview/XFinderWeatherPreview.app`.
