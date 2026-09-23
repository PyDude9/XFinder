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

// MARK: - Mouse-gesture semantic keys
//
// The gesture *model* never returns display text (that is how Vietnamese leaked
// into an English UI: three call sites wrapped `L10n.t` around a value the model
// had already rendered, and two did not). Instead the model exposes semantic
// cases — `ButtonKey`, `GestureDirection.motionKey` — and these overloads are the
// **only** place they become words. `LanguageNeutralKeys` lists what is a symbol
// rather than a sentence, so a test can assert every *word* key is translated
// while the symbols legitimately pass through.
extension L10n {
    enum LanguageNeutralKeys {
        /// Keys that are symbols, not words, so they are identical in every language.
        /// Kept explicit so "this resolves to itself" is a declared fact rather than
        /// an untranslated string hiding among the rest.
        ///
        /// Only symbols belong here. This list previously held three **Vietnamese
        /// sentences** — `"Nút 3 (bấm con lăn xuống)"` and friends — declared as
        /// "language-neutral" and therefore returned verbatim by `t(_:)`. That is the
        /// exact mechanism behind the user's report of Vietnamese leaking into the
        /// English page: not a missing translation, but a line of code asserting the
        /// string must never be translated.
        ///
        /// It was also factually wrong. macOS numbers mouse buttons from **0**: 0 =
        /// left, 1 = right, 2 = middle (the wheel), 3 = first side button. The old
        /// label called the wheel "Nút 3", so it misnamed the very button this feature
        /// now defaults to as its hold trigger.
        ///
        /// Button labels are now ordinary translatable sentences; what stays neutral
        /// is the bare modifier symbols, which are language-independent glyphs.
        static let all: Set<String> = [
            "⌘", "⌥", "⌃", "⇧",
        ]
    }

    /// Resolve a semantic button reference to its label.
    ///
    /// `Nút N` is numbered the way the user counts (macOS numbers from 0), and the
    /// three numbers every mouse shares carry a short factual note. A modifier
    /// trigger prints its own symbols, which are language-neutral.
    ///
    /// The **structure** — which key to use, and the `+ 1` offset — comes from
    /// `ButtonLabelStructure`, which imports nothing but Foundation and is symlinked
    /// into the test package. Putting it there is what let the mutation harness
    /// catch a broken numbering again; living in this SwiftUI-importing file it was
    /// unreachable and three mutations stayed green.
    nonisolated static func t(_ key: ButtonKey) -> String {
        switch key {
        case .index(let n):
            if let named = ButtonLabelStructure.namedKey(forButtonNumber: n) { return t(named) }
            let number = t(ButtonLabelStructure.numberedPrefixKey)
                + "\(ButtonLabelStructure.displayNumber(forButtonNumber: n))"
            // A side button carries a positional hint, because "Button 4" alone does
            // not tell the user where to put their thumb. The hint is a separate
            // translatable sentence, so it says "usually" in both languages rather
            // than inventing a position no API can confirm.
            guard let hint = ButtonLabelStructure.hintKey(forButtonNumber: n) else { return number }
            return number + " — " + t(hint)
        case .modifier(let flags):
            return GestureShortcut(key: 0, flags: flags).modifierLabel
        }
    }

    /// The heading for one direction, naming the held button. Composed here (not in
    /// the model) so both halves are translated and the joined sentence reads
    /// correctly in each language.
    ///
    /// The *shape* of the join lives in `ButtonLabelStructure.HeadingStructure`, so
    /// the "does the heading name the held button?" property is testable. This
    /// function only supplies the words.
    nonisolated static func t(_ direction: GestureDirection, trigger: TriggerSource) -> String {
        let parts = ButtonLabelStructure.HeadingStructure.parts(for: direction, trigger: trigger)
        guard let buttonKey = parts.buttonKey else { return t(parts.motionKey) }
        // The interpolated case joins a *fragment* to a runtime value: the key keeps
        // its trailing space and the number is appended, because a key containing a
        // runtime value can never be looked up.
        let button = parts.appendNumber.map { t(buttonKey) + "\($0)" } ?? t(buttonKey)
        return button + ButtonLabelStructure.HeadingStructure.separator + t(parts.motionKey)
    }
}
