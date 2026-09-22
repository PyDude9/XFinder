import Foundation
import Observation
import SwiftUI

/// Ngôn ngữ giao diện XFinder.
enum AppLanguage: String, CaseIterable, Identifiable {
    case vietnamese
    case english
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .vietnamese: return "Tiếng Việt"
        case .english: return "English"
        }
    }
}

/// Bộ dịch của XFinder.
///
/// **Khoá là chính chuỗi tiếng Việt đang dùng ở call site.** Nhờ vậy một call
/// site đọc như tiếng Việt tự nhiên (`L10n.t("Mở khóa “")`) mà vẫn tra được bản
/// tiếng Anh, và không cần đổi hàng trăm chỗ sang key.
///
/// Toàn bộ bản dịch nằm trong **một** file dữ liệu duy nhất —
/// `Resources/L10n.strings.json` — chứ không rải trong ba dictionary Swift như
/// trước. Lý do là lỗi ngôn ngữ đã được báo **bốn lần**: với ba dictionary, không
/// ai biết một chuỗi mới phải nằm ở đâu, nên nó thường nằm ở "không đâu cả". Và
/// vì `t()` rơi về tiếng Việt khi trượt, giao diện tiếng Anh lặng lẽ hiện tiếng
/// Việt mà build không hề báo.
///
/// Cấu trúc mỗi entry:
///
///     "Kéo LÊN": { "en": "Drag UP", "scope": "sentence" }
///     " mục":    { "en": " items",  "scope": "fragment" }
///
/// `scope` thay cho việc "chuỗi này nằm ở dict nào" trước đây. `fragment` là
/// một *mảnh* được ghép chuỗi, luôn giữ khoảng trắng hai đầu — chính khoảng
/// trắng đó làm câu ghép đọc đúng ở cả hai ngôn ngữ. `sentence` là câu hoàn
/// chỉnh, không có khoảng trắng thừa.
@MainActor
@Observable
final class L10n {
    static let shared = L10n()

    var language: AppLanguage = {
        let raw = UserDefaults.standard.string(forKey: "AppLanguage") ?? ""
        return AppLanguage(rawValue: raw) ?? .vietnamese
    }() {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "AppLanguage") }
    }

    func set(_ lang: AppLanguage) { language = lang }

    /// Nonisolated — đọc thẳng UserDefaults nên gọi được từ enum `titleVI`
    /// (không ở MainActor). Re-render toàn cửa sổ do `.id(language)` của
    /// RootView đảm nhiệm khi đổi ngôn ngữ.
    nonisolated static func t(_ vi: String) -> String {
        guard LanguageIsEnglish else { return vi }
        // `fragment` được tra trước `sentence`: một mảnh giữ khoảng trắng hai
        // đầu nên không thể trùng khoá với câu hoàn chỉnh, nhưng thứ tự này
        // khiến ý định rõ ràng khi đọc code.
        if let entry = L10nStore.fragments[vi] { return entry }
        if let entry = L10nStore.sentences[vi] { return entry }
        return vi
    }

    /// Dạng `LocalizedStringKey` cho chuỗi có markdown (`**bold**`).
    nonisolated static func md(_ vi: String) -> LocalizedStringKey {
        LocalizedStringKey(t(vi))
    }

    nonisolated private static var LanguageIsEnglish: Bool {
        UserDefaults.standard.string(forKey: "AppLanguage") == AppLanguage.english.rawValue
    }
}
