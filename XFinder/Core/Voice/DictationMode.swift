import Foundation

/// How a finished transcription is turned into the text that actually gets inserted.
///
/// This is the "persona" layer: the same spoken words produce different text depending on
/// the mode. `raw` skips the language model entirely, which is what makes it the fastest
/// path and the one that works with no provider configured at all.
///
/// The model deliberately exposes **keys**, not display strings. Every user-facing word is
/// resolved by `L10n.t` at the call site — a model that returns a rendered sentence is the
/// exact mechanism that leaked Vietnamese into the English UI four times (see CLAUDE.md).
public enum DictationMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case raw
    case cleanUp
    case email
    case professional
    case bulletPoints
    case custom

    public var id: String { rawValue }

    /// Vietnamese literal used as the L10n key. Not a display string.
    public var labelKey: String {
        switch self {
        case .raw: return "Chép nguyên văn"
        case .cleanUp: return "Tút lại & xóa từ thừa"
        case .email: return "Soạn email"
        case .professional: return "Văn phong chuyên nghiệp"
        case .bulletPoints: return "Gạch đầu dòng"
        case .custom: return "Tùy biến"
        }
    }

    /// One-line explanation shown under the mode name. Vietnamese literal = L10n key.
    public var detailKey: String {
        switch self {
        case .raw: return "Chèn đúng những gì bạn nói, không qua AI — nhanh nhất."
        case .cleanUp: return "Bỏ từ đệm, sửa nói lắp, thêm dấu câu và viết hoa."
        case .email: return "Dựng lời nói thành email có chào hỏi, thân bài và kết."
        case .professional: return "Câu từ gãy gọn, lịch sự, dùng cho công việc."
        case .bulletPoints: return "Tóm ý thành danh sách gạch đầu dòng."
        case .custom: return "Dùng câu lệnh riêng bạn tự viết."
        }
    }

    public var icon: String {
        switch self {
        case .raw: return "text.alignleft"
        case .cleanUp: return "wand.and.sparkles"
        case .email: return "envelope"
        case .professional: return "briefcase"
        case .bulletPoints: return "list.bullet"
        case .custom: return "slider.horizontal.3"
        }
    }

    /// `raw` is the only mode that never calls a language model — which is why it must
    /// still work when no provider is configured. Everything else needs one.
    public var usesLanguageModel: Bool { self != .raw }

    /// The built-in modes offered in the picker, in the order they are shown.
    public static var builtIn: [DictationMode] { [.raw, .cleanUp, .email, .professional, .bulletPoints, .custom] }

    /// A user-authored mode. Stored as JSON in `UserDefaults` under `voice.customModes`.
    public struct Custom: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var instruction: String
        public init(id: String = UUID().uuidString, name: String, instruction: String) {
            self.id = id
            self.name = name
            self.instruction = instruction
        }
    }
}
