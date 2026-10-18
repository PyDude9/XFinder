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
