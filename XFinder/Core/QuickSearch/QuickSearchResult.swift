import Foundation
import AppKit

/// Một kết quả của "Tìm nhanh" trong trang Tìm kiếm — kiểu TinyCast: gộp
/// ứng dụng, liên kết nhanh, phép tính và tập tin trong cùng một danh sách.
/// `@unchecked Sendable`: kết quả được tạo ở background task rồi đưa về main —
/// action closure chỉ chạy trên main, còn icon/title là dữ liệu đọc-ghi vô hại.
struct QuickSearchResult: Identifiable, @unchecked Sendable {
    let id = UUID()
    let type: ResultType
    let title: String
    let subtitle: String
    let icon: NSImage?
    let action: () -> Void

    /// Thứ tự case = thứ tự ưu tiên hiển thị trong trang Tìm kiếm.
    enum ResultType: Int {
        case quicklink
        case snippet
        case settingsPage
        case app
        case calculator
        case file

        /// Nhãn nhóm hiển thị trên trang Tìm kiếm.
        var titleVI: String {
            switch self {
            case .quicklink: return L10n.t("Liên kết nhanh")
            case .snippet: return L10n.t("Đoạn văn bản nhanh")
            case .settingsPage: return L10n.t("Cài đặt XFinder")
            case .app: return L10n.t("Ứng dụng")
            case .calculator: return L10n.t("Tính toán")
            case .file: return L10n.t("Tập tin")
            }
        }

        /// Icon dự phòng khi engine không trả về NSImage.
        var symbolName: String {
            switch self {
            case .quicklink: return "link.circle.fill"
            case .snippet: return "text.badge.plus"
            case .settingsPage: return "gearshape.fill"
            case .app: return "app.fill"
            case .calculator: return "equal.circle.fill"
            case .file: return "doc.fill"
            }
        }
    }
}

/// Score cho fuzzy matching (càng nhỏ càng khớp)
struct SearchScore {
    let score: Int
    let result: QuickSearchResult
}
