import Foundation

/// The old Batch Rename page's picker vocabulary. Since XF-T37 (Q-T37-5, owner: "fix the bugs, update the features")
/// the names, the checks, the two-phase rename and its undo all live in `BatchRenameRules` — pure and tested directly,
/// shared with the file browser's batch rename — so this file only names the page's modes.
enum BatchRenameEngine {
    static func title(_ mode: BatchRenameRules.PageMode) -> String {
        switch mode {
        case .prefix: return L10n.t("Thêm tiền tố")
        case .suffix: return L10n.t("Thêm hậu tố")
        case .replace: return L10n.t("Thay thế chữ")
        case .sequence: return L10n.t("Đánh số thứ tự")
        case .lowercase: return L10n.t("Chữ thường")
        case .uppercase: return L10n.t("Chữ HOA")
        case .format: return L10n.t("Định dạng")
        }
    }
}
