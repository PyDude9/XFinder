# XF-T21 — Chia sẻ nhanh và Kết nối từ xa vào `FeatureCatalog` (một khoá, một reader, một hàng)

Nguồn: kiểm toán 2026-10-18 (`docs/APP_AUDIT_2026-10-18.md`, Q-PRUNE-6). Hai tính năng KẾT NỐI là **những tính năng duy
nhất có hành vi nền** (server HTTP trên LAN qua `NWListener` + `sweepTimer`; scp/sftp qua `Process`) mà **không có hàng
catalog**, nên "Tắt tất cả" trong Tính năng & Quyền không tắt được một server mạng, và `FeatureContractTests` không biết
tới chúng.

## 1. Câu việc

"Tôi bấm *Tắt tất cả* thì KHÔNG còn gì của XFinder chạy nền — kể cả server chia sẻ file tôi quên tắt."

## 2. Phạm vi — đúng tám thứ của một tính năng (CLAUDE.md §2)

Cho **mỗi** tính năng (`quickShare`, `remoteConnect`):

1. `FeatureCatalog`: `case quickShare`, `case remoteConnect` trong `FeatureID`; hai `FeatureDef` group `.connect` (thêm
   case `.connect` vào `FeatureGroup` nếu chưa có — kiểm `FeatureGroup` trước, đừng đoán), `enabledKey`
   `quickShare.enabled` / `remoteConnect.enabled`, `defaultOn: true` (đây là công tắc *cho phép*, không tự chạy gì),
   `permissions: []`, `idle`: QuickShare = `.timerWhileActive` (server + sweep chỉ khi đang chia sẻ), RemoteConnect =
   `.nothingAtRest`. Đọc `IdleCost` hiện có và `testNothingWithAPollingTimerIsLabelledNothingAtRest` trước khi chọn.
2. **ONE reader** trong Core, đúng dạng `UserDefaults.standard.object(forKey: "quickShare.enabled") as? Bool ?? true`,
   trong `QuickShareController` / `RemoteConnectController`. Tắt ⇒ `QuickShareController` **dừng server đang chạy** và
   không cho bắt đầu; `RemoteConnectController` từ chối gửi.
3. View: `@AppStorage("quickShare.enabled") … = true` làm công tắc đầu trang (`ToggleRow`, `.onChange` →
   `applySettings()`), các control còn lại `.disabled(!enabled)`; subtitle nói rõ "tắt thì server dừng ngay".
4. `FeatureKeyDefaultsTests`: hai hàng `Switch(key:views:reader:)`.
5. `FeatureContractTests`: `.quickShare: .pure([...])` — tách luật thuần nếu có (QuickShare: sinh mã chia sẻ, thời hạn,
   whitelist? đọc code rồi quyết) **hoặc** `.exempt("… Fix: …")` chỉ khi trần exemption (hiện 5, tối đa 6) còn chỗ.
   `.remoteConnect` tương tự.
6. `FeatureHub.applySettings` case cho cả hai + gọi `applySettings()` lúc khởi động trong `XFinderApp` (chỉ khi
   controller có việc lúc khởi động — RemoteConnect có thể không cần).
7. L10n: script add-only `scripts/add-connect-catalog-l10n-entries.py` cho title/subtitle của hai hàng và các chuỗi mới
   trên hai trang; khoá đã có mang nghĩa khác ⇒ khoá mới.
8. Mutation: thêm vào `scripts/mutation-check-settings.sh` (hoặc harness phù hợp) ít nhất một mutation "tắt công tắc mà
   server vẫn chạy" nếu luật thuần tách được; nếu không, ghi rõ trong worklog vì sao không mutate được.

## 3. Ca hỏng phải có câu trả lời

| Ca | Trả lời |
|:--|:--|
| Tắt công tắc khi server đang chia sẻ | dừng `NWListener`, huỷ `sweepTimer`, trang hiện "đã dừng" |
| "Tắt tất cả" ở hub | đi qua đúng reader ⇒ cùng hành vi như công tắc |
| Người dùng cũ chưa có khoá | `?? true` ⇒ không đổi hành vi |
| Preset onboarding | `quiet` được **suy ra** từ catalog (idle không chạy nền + không quyền) — RemoteConnect sẽ vào `quiet`, QuickShare thì không; kiểm `OnboardingTests` |
| `testQuietBundleSwitchesOffEverythingThatRunsInTheBackground` | QuickShare phải nằm trong danh sách bị tắt của gói Yên tĩnh |

## 4. Nghiệm thu

`sh scripts/gate-all.sh` xanh; `FeatureCatalogTests`/`FeatureContractTests`/`FeatureKeyDefaultsTests` xanh; e2e tay:
bật chia sẻ một file → bấm *Tắt tất cả* → server dừng (curl địa chỉ chia sẻ thất bại), trang Chia sẻ nhanh nói đã dừng.

## 5. Ngoài phạm vi

Không đổi giao thức chia sẻ, không thêm xác thực, không đụng `Core/Notch`.

## 6. Worklog (Claude, 2026-10-18 — làm luôn thay Builder, Q-PRUNE-6 "pump it all")

- Nhóm mới `FeatureGroup.connect` ("Kết nối"); hai hàng catalog đúng §2.1. Reader: `QuickShareController.isEnabled`,
  `RemoteConnectController.isEnabled`. `QuickShareController.applySettings()` tắt ⇒ `revokeAll()` (dừng `NWListener` +
  `sweepTimer`); `share(files:)` từ chối khi tắt; `receive` trả 404 khi tắt (phòng kết nối đang chờ). RemoteConnect: `test`
  / `upload` từ chối trước khi chạy process, nói rõ "đang tắt".
- Luật thuần `Core/ConnectRules.swift` (symlink): `QuickShareRules.token/link/contentDisposition`,
  `RemoteConnectRules.testArguments/uploadArguments/explanationKey`. **Lỗi tìm được khi tách**: tên file đi thẳng vào
  `Content-Disposition` ⇒ tên chứa `"`/CR/LF chèn được header; giờ fallback ASCII + `filename*=UTF-8''`. Thêm `--` trước
  đích ssh và trước danh sách file scp (host/tên file bắt đầu bằng `-` không thành option). Token chỉ nhận GET + hex.
- Contract: `.quickShare`/`.remoteConnect` = `.pure([ConnectRules])`; tiện trả luôn exemption `.edgeNotes` (XF-T24 đã tách
  hình học) ⇒ trần exemption 5 → **4**.
- Mutation `scripts/mutation-check-connect.sh` (C1–C9). "Tắt mà server vẫn chạy" nằm trong controller (cần app chạy) ⇒
  không mutate được trong package; nghiệm thu bằng T-T21-1.

## 7. Phụ lục 2026-10-19 — điện thoại lấy liên kết bằng QR

Câu hỏi của chủ dự án sau T-T21-1: "điện thoại lấy link kiểu gì, ngoài iPhone cùng Apple ID?" Trả lời: **mã QR**, không cần
app điện thoại. Camera của iOS và Android đều đọc QR chứa URL và mở thẳng trình duyệt; liên kết `http://<ip-LAN>:<cổng>/<mã>`
chỉ sống trong cùng Wi-Fi nên không cần đăng nhập.

- Nút **QR** trên từng hàng (popover: mã + liên kết + ghi chú) — `QRCodeView` (`CIQRCodeGenerator`, công khai, offline; vẽ
  nearest-neighbour; dựng trong `.task(id:)`, không trong `body`).
- **QR cho tất cả**: một `indexToken` mỗi lần server chạy; `GET /<indexToken>` trả trang HTML liệt kê mọi file đang chia sẻ
  (`QuickShareRules.indexPage`, thuần, có test): link **tương đối** `/<token>` nên đúng với bất kỳ địa chỉ nào điện thoại
  dùng; tên file và chi tiết qua `htmlEscape` (tên file là text người dùng — `<script>.txt` là một cái tên). Header
  `text/html; charset=utf-8`, `nosniff`, `no-store`. Ai có liên kết chỉ mục thấy cả danh sách — popover nói thẳng.
- Khi tắt công tắc: index cũng 404 (`isEnabled` kiểm trước), token xoá khi server dừng.
- Mutation C10 (không escape `<`), C11 (link theo tên thay vì token). T-T21-3/4.
- Không làm: mDNS/Bonjour tên `.local` (Android không phân giải trong trình duyệt), app điện thoại, relay ngoài LAN (Q-REF-3).
