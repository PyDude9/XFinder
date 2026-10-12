import Foundation

/// N5a (2026-10-13) — "Dịch vùng chọn": ⇧⌘G reads the focused app's selected text through Accessibility and shows
/// Apple's on-device translation for it. OneNotch's Smart Selection (a badge that appears on every selection) is the
/// reference; XFinder starts with the hotkey half — a badge on every selection needs per-app AX observers and is a
/// later step. Pure rules here; the hotkey, the AX read and the panel live in `TranslateSelectionController`.
///
/// Measured first (`scratchpad/n5/translate-probe`): `LanguageAvailability.status(en→vi)` answers `installed` after
/// 8.5 s from an ad-hoc AND an XFinder Dev-signed process (47 languages), so availability is not gated by signature;
/// the translation itself only exists inside SwiftUI's `.translationPresentation` (macOS 15+).
enum TranslateSelectionRules {
    static let enabledKey = "translate.hotkeyEnabled"
    /// ⇧⌘G, like OneNotch; recorded so the Voice page can say what the key is without a second source.
    static let hotkeyLabel = "⇧⌘G"
    static let keyCodeG: UInt32 = 5
    /// Apple's popover handles long text, but a selection of a whole file is never what the person meant.
    static let maxCharacters = 5_000

    enum Verdict: Equatable { case translate(String), tooShort, tooLong, nothingSelected }

    /// What to do with what Accessibility returned.
    static func verdict(for selection: String?) -> Verdict {
        guard let s = selection?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return .nothingSelected }
        if s.count < 2 { return .tooShort }
        if s.count > maxCharacters { return .tooLong }
        return .translate(s)
    }

    /// Store keys for the panel's one-line states (the view wraps them in `L10n.t`).
    static func messageKey(for v: Verdict) -> String? {
        switch v {
        case .translate: return nil
        case .tooShort: return "Chọn ít nhất hai ký tự để dịch."
        case .tooLong: return "Vùng chọn quá dài để dịch tại chỗ (tối đa 5 000 ký tự)."
        case .nothingSelected: return "Không đọc được vùng chọn: app này không cho Trợ năng đọc, hoặc chưa cấp quyền Trợ năng."
        }
    }
}
