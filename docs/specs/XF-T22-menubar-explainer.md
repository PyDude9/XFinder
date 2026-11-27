# XF-T22 — Biểu tượng thanh menu: về trang explainer, giữ đúng một việc làm được

Nguồn: kiểm toán 2026-10-18 (Q-PRUNE-2) + **phép đo cùng ngày** trên máy chủ dự án (macOS 27.0.1, 2 màn hình):

```
AX trusted: true | screens maxX: 3648
x= 1177 notion.id          ON      ← bên TRÁI mũi tên của XFinder (x 1279/1305) = vùng "ẩn" theo thiết kế
x= 1209 com.1password      ON
x= 1249 one.ayugram        ON
x= 1279 com.xfinder.app#1  ON      ← mũi tên ẩn/hiện
x= 1305 com.xfinder.app#0  ON      ← icon XFinder
x= 1337 … 1708 Claude · TextInput · Chrome · 4 × MenuBarAgent   ON
total 12 · onscreen 12
hider defaults: menubar.hiderEnabled=1 defaultCollapsed=1 autoHideEnabled=1
log 12 h: chỉ "NativeVisibility: assertion callback error=(null)" ×3 — KHÔNG có "activation SUCCEEDED", KHÔNG có "arrow at x="
```

Kết luận đo được: với mọi công tắc bật, **không icon app thứ ba nào bị ẩn**, và engine chưa bao giờ tới bước
`activate` (không resolve được ranh giới mũi tên). Trùng với spike 2026-09: `MBAssessmentModeAssertion` chỉ ẩn module
hệ thống, không ẩn `NSStatusItem` của app khác; separator trick chết vì macOS 27 gộp cả bar thành một window. Trang hiện
tại **hứa một việc không xảy ra** (Part 0 §6).

## 1. Câu việc còn lại

"Tôi muốn thanh menu gọn: ít nhất là **giấu icon của XFinder** khi tôi không cần, và biết đường tắt/mở icon hệ thống ở
đâu." Chỉ phần đó là làm được bằng API công khai.

## 2. Việc

1. **Trang `menuIcons`** thành explainer + một công tắc: "Ẩn biểu tượng XFinder trên thanh menu" (`menubar.hideOwnIcon`,
   mặc định `false`, ONE reader trong `MenubarController` → `statusItem.isVisible`), link Control Centre ▸ Menu Bar, và
   bảng ngắn "vì sao không ẩn được icon app khác" lấy nguyên văn từ phép đo trên (ngày, số đo).
1b. **Thứ tự tạo và giữ vị trí bên phải notch (`MenubarController`):** tạo `statusItem` chính (`xfinder.menubar.main`, `squareLength`, icon thương hiệu XFinder) **trước** `readoutItem` (`xfinder.menubar.readouts`, `variableLength`) để icon chính luôn nằm bên phải số liệu (xa notch hơn). Khi khởi động, đổi cấu hình màn hình (`didChangeScreenParametersNotification`), hoặc bấm "Hiện lại biểu tượng", kiểm tra vị trí trên màn hình có notch (`screen.auxiliaryTopRightArea`): nếu `statusItem` bị đẩy tràn sang trái notch (`frame.minX < rightArea.minX`) thì xóa `NSStatusItem Preferred Position` cũ và đặt lại hiển thị (không thêm timer nền). Giữ nguyên click trái mở `MenubarPanelView` popover và click phải mở `NSMenu`.
2. **Xoá** `MenuBarHiderController`, `Core/MenuBar/{MenuBarEngine, MenuBarEngineFactory, NativeVisibilityEngine,
   LegacyLengthEngine}.swift`, `Core/MenuBar/Native/*` (shim ObjC + bridge), `Core/MenuBar/Layout/*` — mỗi file đủ **4
   dòng pbxproj** (shim `.m` có thêm bridging header/`-fobjc-arc`? kiểm `project.pbxproj` và `XFinder-Bridging-Header.h`
   trước khi xoá), cờ compile `XFinder_NATIVE_VISIBILITY` trong build settings, các khoá `menubar.hiderEnabled`,
   `menubar.autoHideEnabled`, `menubar.autoHideSeconds`, `menubar.defaultCollapsed` (gỡ reader + view; khoá cũ trên máy
   người dùng không đọc nữa — vô hại).
3. `FeatureCatalog`: nếu có hàng cho hider (kiểm `grep hiderEnabled`), chuyển thành hàng của `menubar.hideOwnIcon`
   (`idle: .nothingAtRest`, không quyền) hoặc bỏ hàng; `FeatureKeyDefaultsTests` theo đó.
4. **Migration một dòng**: nếu `menubar.hiderEnabled == true` trên máy người dùng (chủ dự án đang bật), icon XFinder đang bị
   ẩn bởi engine cũ — sau khi gỡ, icon sẽ hiện lại; đặt `menubar.hideOwnIcon = true` một lần khi thấy khoá cũ `true` để giữ
   trạng thái người dùng chọn (ẩn icon XFinder), rồi không đọc khoá cũ nữa.
5. L10n add-only cho chuỗi mới; xoá entry chỉ engine dùng là tuỳ chọn (không bắt buộc).
6. Mutation: không có luật thuần mới ⇒ ghi rõ trong worklog; gate thường (`gate-all.sh`) đủ.

## 3. Ca hỏng

| Ca | Trả lời |
|:--|:--|
| Người dùng đang ẩn icon XFinder bằng engine cũ | migration mục 4 — đặt `menubar.hideOwnIcon = true` một lần duy nhất khi `menubar.hideOwnIcon` chưa từng lưu và `menubar.hiderEnabled == true`; khi người dùng bật hiện lại sau đó không migration lại |
| Icon XFinder ẩn ⇒ không còn cửa vào menu | trang Tổng quan ("Hiện lại biểu tượng") + ⌘, vẫn mở app; trang này ghi câu đó cạnh công tắc |
| `statusItem.isVisible = false` còn giữ `NSStatusItem` | đúng ý: bật lại là hiện ngay, không tạo lại item; khi đang ẩn thì `applyIcon()` không tự ép `isVisible = true` |
| Thanh menu chật (nhiều app thứ ba) hoặc bật `menubar.readoutsEnabled` chuỗi dài | tạo `statusItem` trước `readoutItem` để icon chính đứng bên phải số liệu; nếu vẫn tràn vào vùng notch thì xóa `Preferred Position` cũ và khôi phục vị trí (nếu hệ thống vẫn quá chật, không hứa ép ẩn app thứ ba) |
| Nhiều màn hình / chuyển giữa màn hình có notch và màn hình ngoài | lắng nghe `didChangeScreenParametersNotification` để kiểm tra lại `auxiliaryTopRightArea` của màn hình chứa `statusItem`, không dùng polling timer |
| Nhiều tiến trình XFinder chạy song song trong quá trình QA | nhân đôi `NSStatusItem` gây tràn notch — nghiệm thu live yêu cầu đúng 1 tiến trình `XFinder.app` |

## 4. Nghiệm thu

`gate-all.sh` xanh; `grep -rn "MBAssessment\|NativeVisibility\|LegacyLength" XFinder` = 0; trang menuIcons render (AX)
hai ngôn ngữ không chuỗi Việt lọt; bật công tắc ⇒ icon XFinder biến mất (`AXExtrasMenuBar` của XFinder không còn item
đó), tắt ⇒ hiện lại; trên màn hình có notch với 1 tiến trình XFinder, `xfinder.menubar.main` có `isVisible == true`, `frame.width > 0`, `frame.minX >= screen.auxiliaryTopRightArea.minX`.
