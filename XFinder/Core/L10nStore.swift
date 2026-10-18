import Foundation

/// Cửa vào duy nhất của kho bản dịch.
///
/// Dữ liệu nằm ở `Resources/L10n.strings.json` (được nhúng vào bundle) — không
/// phải một dictionary Swift. Đổi lại một chút thời gian nạp lúc khởi động, ta
/// được ba thứ mà ba dictionary Swift cũ không có:
///
/// 1. **Không còn "đặt sai file".** Trước đây `enDict` / `moreDict` / `fragDict`
///    không có quy tắc nào phân biệt; chuỗi mới rất dễ rơi vào "không dict nào".
/// 2. **`scope` là dữ liệu, không phải vị trí.** `fragment` (mảnh ghép chuỗi, giữ
///    khoảng trắng hai đầu) tách hẳn khỏi `sentence`, nên một mảnh không thể che
///    bản dịch đầy đủ của cùng cụm từ.
/// 3. **Lint đọc được.** `scripts/check-l10n-coverage.py` duyệt chính file này và
///    fail build khi có entry thiếu bản Anh, hoặc khi `en` giống hệt `vi` mà
///    chuỗi có chữ.
///
/// `vi` giữ nguyên tiếng Việt khi thiếu bản dịch: hỏng theo hướng dễ thấy, không
/// crash và không hiện key thô. Nhưng thiếu bản dịch giờ là **lỗi build**, không
/// còn là chuyện âm thầm.
enum L10nStore {

    /// Câu hoàn chỉnh. Khoá = chính chuỗi tiếng Việt ở call site.
    static let sentences: [String: String] = {
        entries(scope: "sentence")
    }()

    /// Mảnh câu dùng trong ghép chuỗi / interpolation. Giữ khoảng trắng hai đầu
    /// **có chủ đích** — đó là thứ làm `"\(t("Đã nén "))\(n)\(t(" mục"))"` đọc
    /// đúng ở cả hai ngôn ngữ.
    static let fragments: [String: String] = {
        entries(scope: "fragment")
    }()

    /// Tổng số entry đã nạp, để lint và test khẳng định kho không rỗng.
    static var count: Int { sentences.count + fragments.count }

    /// Decoded ONCE; `sentences` and `fragments` are two slices of it. The old code decoded the 410 KB file twice
    /// (once per scope) on first access — audit 2026-10-18, P-3.
    private static let root: Root? = {
        guard let url = Bundle.main.url(forResource: "L10n.strings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(Root.self, from: data) else {
            // Không có kho thì app vẫn chạy, chỉ là tiếng Việt. Ghi log để lần
            // sau không phải đoán vì sao giao diện không đổi ngôn ngữ.
            NSLog("[XFinder] L10n.strings.json missing or unreadable — UI stays Vietnamese")
            return nil
        }
        return root
    }()

    private static func entries(scope: String) -> [String: String] {
        guard let root else { return [:] }
        var out: [String: String] = [:]
        out.reserveCapacity(root.entries.count)
        for (vi, entry) in root.entries where entry.scope == scope {
            if entry.swap == true {
                // Deposition: the Vietnamese form *opens* a clause and an English
                // sentence usually cannot open the same clause, because it tends to
                // carry its verb first ("Mở khóa “" + name — "Unlock “" + name is
                // fine, but "Đã chuyển " + n — "moved " + n is not). Rather than
                // ship a second dictionary of whole sentences, the entry records
                // that the call site's English version needs the value *before* it,
                // and `swap` tells `t()` to return nothing so the call site's own
                // wording is used.
                out[vi] = ""
                continue
            }
            // Bản rỗng = chưa dịch, KHÔNG phải "dịch thành chuỗi rỗng". Bỏ qua để
            // `t()` rơi về tiếng Việt, và để lint bắt được ở dạng dễ đọc.
            if !entry.en.isEmpty { out[vi] = entry.en }
        }
        return out
    }

    /// Khoá mà call site phải xử lý riêng khi sang tiếng Anh (xem `swap` ở trên).
    /// `L10n.t` trả về chuỗi rỗng cho chúng, và đó là *kết quả đúng*, không phải
    /// thiếu bản dịch — lint phân biệt hai thứ này bằng chính cờ `swap`.
    static let swapped: Set<String> = {
        guard let url = Bundle.main.url(forResource: "L10n.strings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(Root.self, from: data) else { return [] }
        return Set(root.entries.filter { $0.value.swap == true }.keys)
    }()

    private struct Root: Decodable {
        var entries: [String: Entry]
    }

    private struct Entry: Decodable {
        var en: String
        var scope: String
        var swap: Bool?
    }
}
