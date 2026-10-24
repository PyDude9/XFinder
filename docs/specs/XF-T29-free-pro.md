# XF-T29 — Free / Pro

> Chủ dự án 2026-10-24 (giữa XF-T28): "Free/Pro bao gồm cả limit số lượng Clipboard lưu trữ, ko lưu screenshot quá 20,
> không quá 50 nếu free nhé, hoặc những mục nào bạn thấy người dùng chuyên nghiệp mới xài pro thì gợi ý luôn".
> Đọc là: Free giữ tối đa **50 mục Clipboard** và **20 ảnh chụp**; cộng các tính năng người dùng chuyên nghiệp mới cần.
> Trả lời Q-T28-1: trình duyệt tệp cũng phân tầng.

> **Quyết định 2026-10-24** (chủ dự án): làm theo bảng §2 (Q-PRO-1 = như bảng); **dùng thử Pro 14 ngày bật mặc định**;
> "build ở đây thì cứ build full; sau khi final release mới free/pro" ⇒ cổng chỉ **thực thi trong bản không có `DEBUG`**
> (bản cài trên máy chủ dự án là Debug ⇒ luôn đủ); bản Debug có `pro.simulateTier` để tự thử free/trial/pro.
> Q-PRO-2 (vượt giới hạn) theo mặc định: **ẩn, không xoá**.

## 0. Câu việc

"Bản miễn phí đủ dùng hằng ngày; ai làm việc nặng (nhiều dữ liệu, tự động hoá, bảo mật, AI agent) trả một lần để mở
giới hạn — và không ai mất dữ liệu vì hết dùng thử hay hạ cấp."

## 1. Nguyên tắc

1. **Free phải tốt thật** — mọi tính năng hằng ngày chạy đầy đủ; Pro là **quy mô, tự động hoá, bảo mật, agent**.
2. **Không bao giờ xoá dữ liệu vì giới hạn mà không báo trước** (luật 9): vượt giới hạn ⇒ phần cũ hơn bị **ẩn / chỉ đọc**,
   không xoá; muốn tỉa thì người dùng bấm (Thùng rác, có xuất trước).
3. Hạ cấp (hết dùng thử) không phá cái đang có: bố cục 16 ngăn đã mở vẫn dùng được, chỉ không thêm ngăn thứ 3 mới
   (cơ chế FileOctopus, đo từ tài liệu của họ).
4. Một nơi quyết định: `Entitlement` thuần (bảng giới hạn, `allows(_:)`), mọi cổng gọi nó — không `if isPro` rải rác.
5. Không mạng khi kiểm giấy phép (khoá ký Ed25519 kiểm offline bằng khoá công khai nhúng trong app — CryptoKit
   `Curve25519.Signing`); dùng thử 14 ngày.

## 2. Đề xuất phân tầng (chủ dự án duyệt từng dòng — Q-PRO-1)

| Khu vực | Free | Pro | Lý do |
|:--|:--|:--|:--|
| Lịch sử Clipboard | **50 mục** (ghim/snippet không tính) | không giới hạn (tới `clipboard.maxHistory`) | yêu cầu chủ dự án |
| Lịch sử Chụp màn hình | **20 ảnh** | không giới hạn | yêu cầu chủ dự án |
| Bảng khoá Clipboard (Secure Enclave + HPKE) | — | ✓ | bảo mật — người dùng chuyên nghiệp |
| Máy chủ MCP Clipboard (`--mcp`, cho AI agent) | — | ✓ | tự động hoá |
| Paste Stack, gộp/tách mục | ✓ | ✓ | hằng ngày |
| Chụp cuộn | — | ✓ | công cụ chuyên nghiệp, tốn tài nguyên |
| Chú thích ảnh chụp, chụp vùng/cửa sổ/màn hình | ✓ | ✓ | hằng ngày |
| OCR (Sao chép chữ trên màn hình) | ✓ | ✓ | hằng ngày |
| Trình duyệt tệp: số ngăn | **2** | **16** | FileOctopus làm đúng vậy |
| Trình duyệt tệp: Shelf, Workspaces có tên, hàng đợi nhiều việc, tác vụ đám mây hàng loạt | — | ✓ | FileOctopus làm đúng vậy |
| Trình duyệt tệp: duyệt, 4 kiểu xem, tìm câu thường, đổi tên hàng loạt, ZIP, tự khôi phục phiên | ✓ | ✓ | |
| Agent AI: crew (Lead Architect), phiên không cửa sổ, handoff | — | ✓ | người dùng chuyên nghiệp |
| Agent AI: theo dõi phiên, hook, statusLine trên notch | ✓ | ✓ | |
| Khoá thư mục (vault mã hoá) | — | ✓ | bảo mật |
| Đồng bộ thư mục tự động, Kết nối từ xa | — | ✓ | tự động hoá |
| Nhớ bố cục cửa sổ (SNAPMEM) | — | ✓ | quy mô (nhiều màn hình) |
| Vùng bắt dính, Dock preview, ⌘-Tab, cuộn mượt, notch, lịch, ghi chú mép, dịch, chọn thông minh, chống ngủ, lau phím, giám sát hệ thống | ✓ | ✓ | hằng ngày |
| Nhập giọng nói | ✓ | ✓ (chế độ tinh chỉnh AI) | |
| Chia sẻ nhanh | ✓ (1 liên kết cùng lúc) | không giới hạn | |

## 3. Kiến trúc

- `Core/Pro/Entitlement.swift` (thuần, symlink): `Tier {free, trial(until), pro}`, `Feature` enum các cổng, `Limits`
  (clipboardItems 50, captures 20, browserPanes 2…), `allows(_ feature, tier) -> Bool`, `limit(_ , tier) -> Int?`,
  luật hạ cấp (bố cục đã có giữ nguyên).
- `Core/Pro/LicenseKey.swift` (thuần): định dạng khoá (base32: payload JSON {email-hash, edition, issued} + chữ ký
  Ed25519), kiểm chữ ký bằng khoá công khai nhúng; không mạng.
- `Core/Pro/LicenseManager.swift` (@MainActor @Observable): ONE reader `pro.licenseKey` (lưu trong Keychain của app —
  **không** UserDefaults), `pro.trialStart`, `tier`; trang "XFinder Pro" (nhập khoá, trạng thái, so sánh Free/Pro).
- Cổng: Clipboard `historyCap` = min(cài đặt, limit); Capture giữ 20 mới nhất hiển thị, phần cũ ẩn + nút "Dọn ảnh cũ
  vào Thùng rác"; trình duyệt `PaneTree.maxPanes` theo tier (canSplit); MCP/crew/vault/sync… hiện "Cần XFinder Pro"
  + nút xem Pro thay vì công tắc chết (luật 7: bề mặt phải nói nó đang tắt và vì sao).
- Khoá ký: chủ dự án giữ khoá riêng, script `scripts/make-license.py` (chạy trên máy chủ dự án) ký khoá cho người mua.
  Claude **không** tạo hay đọc khoá riêng (luật: không đụng credential).

## 3b. Hợp đồng (bắt buộc)

```swift
// Core/Pro/Entitlement.swift — thuần, symlink
enum ProTier: Equatable, Sendable { case free; case trial(daysLeft: Int); case pro }
enum ProFeature: String, CaseIterable, Sendable {
    case unlimitedClipboard, unlimitedCaptures, lockedBoard, clipboardMCP, scrollingCapture
    case browserPanes, browserShelf, browserWorkspaces, browserQueue, browserBatchCloud
    case agentCrews, windowlessAgents, agentHandoff, folderLock, folderSync, remoteConnect, snapMemory
    case unlimitedQuickShare, voiceAIRefine
    var titleKey: String { get }                       // khoá L10n, vd "Bảng khoá Clipboard"
}
enum ProLimit: String, CaseIterable, Sendable { case clipboardItems, captures, browserPanes, quickShareLinks }
enum Entitlement {
    static let trialDays = 14
    static let freeLimits: [ProLimit: Int]             // clipboardItems 50, captures 20, browserPanes 2, quickShareLinks 1
    /// !enforced ⇒ .pro. licenseValid ⇒ .pro. trialStart nil ⇒ .trial(daysLeft: 14) (người gọi ghi trialStart = now).
    /// Đồng hồ: effectiveNow = max(now, maxSeen); daysLeft = ⌈(14 ngày − đã qua) / 1 ngày⌉ (ngày đầu = 14), hết 14 ngày ⇒ .free.
    static func tier(enforced: Bool, licenseValid: Bool, trialStart: Date?, now: Date, maxSeen: Date?) -> ProTier
    static func allows(_ feature: ProFeature, tier: ProTier) -> Bool   // pro/trial: true; free: false
    static func limit(_ limit: ProLimit, tier: ProTier) -> Int?          // nil = không giới hạn (pro/trial)
    /// Ẩn phần vượt giới hạn: `pinned` mục luôn hiện và không tính vào giới hạn; còn lại hiện `limit` mục mới nhất.
    static func visibleCount(total: Int, pinned: Int, limit: Int?) -> (visible: Int, hidden: Int)
}
// Core/Pro/LicenseKey.swift — thuần, symlink (CryptoKit Curve25519.Signing)
struct LicensePayload: Codable, Equatable, Sendable { let id: String; let licensee: String; let edition: String; let issued: Date }
enum LicenseKey {
    /// "XF1-" + base64url(payload JSON) + "." + base64url(chữ ký 64 byte); bỏ qua khoảng trắng/xuống dòng.
    static func verify(_ text: String, publicKey: Data) -> LicensePayload?
    static func make(payload: LicensePayload, privateKey: Data) -> String?   // dùng bởi test và scripts/make-license.swift
    /// Khoá công khai của chủ dự án (Q-PRO-5); nil ⇒ mọi khoá không hợp lệ (dùng thử vẫn chạy).
    static let publicKeyRaw: Data?
}
// Core/Pro/LicenseManager.swift — @MainActor @Observable
@MainActor @Observable final class LicenseManager {
    static let shared: LicenseManager
    private(set) var tier: ProTier
    var isEnforced: Bool { get }                       // #if DEBUG false (trừ khi pro.simulateTier được đặt), ngược lại true
    func allows(_ feature: ProFeature) -> Bool
    func limit(_ limit: ProLimit) -> Int?
    @discardableResult func activate(_ key: String) -> Bool   // kiểm chữ ký, lưu vào Keychain của app
    func deactivate()
    func refresh()                                     // launch + didBecomeActive: bắt đầu dùng thử lần đầu, cập nhật maxSeen
}
// Views/Components/ProBadge.swift
struct ProBadge: View { }                              // nhãn "PRO"
extension View { func proGated(_ feature: ProFeature) -> some View }   // tắt control + nhãn + tooltip "Cần XFinder Pro" khi !allows
```
Khoá (ONE reader trong LicenseManager): `pro.trialStart` (Double, 0), `pro.maxSeenDate` (Double, 0), `pro.simulateTier`
(String, "" — chỉ đọc trong DEBUG: "free" | "trial" | "pro"). Khoá giấy phép: Keychain (generic password, service
`com.xfinder.app.license`) — dữ liệu của chính app.

## 4. Ca hỏng

| Ca | Trả lời |
|:--|:--|
| Đang Pro, hết hạn dùng thử, 900 mục Clipboard | 50 mới nhất hiện; còn lại ẩn với dòng "850 mục cũ hơn — mở bằng Pro hoặc xuất"; không xoá |
| Free chép mục thứ 51 | mục cũ nhất không ghim bị **ẩn** (vẫn trong DB) cho tới khi người dùng dọn; DB có trần cứng = `clipboard.maxHistory` |
| Free có 35 ảnh chụp từ trước | 20 mới nhất hiện; nút "Dọn 15 ảnh cũ vào Thùng rác" |
| Bố cục 6 ngăn từ lúc dùng thử | mở được, dùng được; nút chia bị tắt với nhãn Pro |
| Khoá sai / bị sửa một ký tự | "Khoá không hợp lệ" — chữ ký không khớp; không gọi mạng |
| Đồng hồ máy bị chỉnh lùi để kéo dài dùng thử | lưu thời điểm lớn nhất từng thấy; lùi ⇒ coi như hết hạn |
| MCP đang chạy cho một agent khi hạ cấp | dừng sau phiên hiện tại, báo trong trang |

## 5. Q / T

- **Q-PRO-1** duyệt bảng §2 (mặc định: như bảng).
- **Q-PRO-2** vượt giới hạn: **ẩn, không xoá** (mặc định) hay tự tỉa vào Thùng rác như `clipboard.maxHistory` đang làm?
- **Q-PRO-3** bán ở đâu (Lemon Squeezy / Paddle / Gumroad / tự bán) và giá — chỉ ảnh hưởng nơi phát khoá; app kiểm offline.
- **Q-PRO-4** dùng thử 14 ngày (mặc định) và bản 1.3.0 hiện có không phân tầng — người đã cài 1.3.0 có được giữ Pro không?
- **Q-PRO-5** chủ dự án tạo cặp khoá Ed25519 trên máy mình (`scripts/make-license.py --init`), dán khoá công khai vào app.
- T-PRO-1 Free: chép 60 mục ⇒ 50 hiện + dòng "10 mục cũ hơn"; nhập khoá Pro ⇒ hiện đủ 60.
- T-PRO-2 Free: chụp 25 ảnh ⇒ 20 hiện + nút dọn; Pro ⇒ 25.
- T-PRO-3 Free: trình duyệt chia ngăn thứ 3 ⇒ bị chặn kèm nhãn Pro.
