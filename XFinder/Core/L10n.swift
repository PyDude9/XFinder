import Foundation
import Observation

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

/// Bộ dịch tối giản. Khóa = chính chuỗi tiếng Việt đang dùng, giá trị =
/// tiếng Anh — giúp quấn string hiện có mà không phải đổi sang key ở khắp
/// nơi. Nếu đổi một chuỗi Việt mà dict chưa có bản Anh thì rơi về Việt (an
/// toàn, không lỗi).
///
/// Hiện dịch: sidebar + trang Tổng quan. Các trang khác vẫn Việt — mở rộng
/// dần bằng cách thêm cặp vào `en` rồi quấn `L10n.shared.l("...")`.
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
        if UserDefaults.standard.string(forKey: "AppLanguage") == AppLanguage.english.rawValue,
           let en = enDict[vi] { return en }
        return vi
    }

    nonisolated private static let enDict: [String: String] = [
        // Sidebar
        "Tổng quan": "Overview",
        "Điều khiển nhanh": "Quick Controls",
        "Chống ngủ": "Anti-sleep",
        "Hệ thống": "System",
        "Mạng": "Network",
        "Ổ đĩa": "Storage",
        "Pin": "Battery",
        "Clipboard": "Clipboard",
        "Ghi chú": "Notes",
        "Xem trước cửa sổ": "Window Preview",
        "Vùng bắt dính": "Snap Zones",
        "Biểu tượng thanh menu": "Menu Bar Icons",
        "Bàn phím Finder": "Finder Keyboard",
        "Thao tác Finder": "Finder Actions",
        "Tìm kiếm": "Search",
        "Tìm kiếm AI": "AI Search",
        "Đổi tên hàng loạt": "Batch Rename",
        "Lịch sử thao tác": "Action History",
        "Khay thả": "Drop Tray",
        "Nén & Giải nén": "Compress & Extract",
        "Công cụ PDF": "PDF Tools",
        "Khóa thư mục": "Folder Lock",
        "Quick Look": "Quick Look",
        "Tương thích media": "Media Compatibility",
        "Tiện ích Finder": "Finder Utilities",
        "Đồng bộ": "Sync",
        "Kết nối từ xa": "Remote Connect",
        "Chia sẻ nhanh": "Quick Share",
        "Cài đặt Clipboard": "Clipboard Settings",
        "Giới thiệu": "About",
        // Tổng quan
        "Xem những gì đã sẵn sàng và hoàn tất thiết lập.": "See what's ready and finish setup.",
        "Ngôn ngữ ứng dụng": "App language",
        "Cấp quyền nhanh": "Quick permissions",
        "Nhắc Trợ năng + Ghi màn hình cùng lúc; mở Cài đặt nếu vẫn thiếu.":
            "Prompt Accessibility + Screen Recording at once; open Settings if still missing.",
        "Cấp mọi quyền…": "Grant all…",
        "Xem trước media": "Media preview",
        "Đã cài": "Installed",
        "Chưa cài — tải trong trang Quick Look": "Not installed — get it on the Quick Look page",
        "Apple Intelligence": "Apple Intelligence",
        "Chưa sẵn sàng": "Not ready",
        "Khởi động XFinder khi đăng nhập": "Launch XFinder at login",
        "Hiện biểu tượng trong Dock": "Show icon in Dock",
        "Tắt để dùng XFinder thuần menubar.": "Turn off to run XFinder menu-bar only.",
        "Trợ năng (cửa sổ, Dock, độ sáng)": "Accessibility (windows, Dock, brightness)",
        "Ghi màn hình (ảnh thu nhỏ cửa sổ)": "Screen Recording (window thumbnails)",
        "Tự động hóa (đổi giao diện Sáng/Tối)": "Automation (light/dark appearance)",
        "Xem trước cửa sổ từ Dock": "Dock window preview",
        "Thiếu quyền Ghi màn hình": "Missing Screen Recording",
        "Quick Look nâng cao": "Enhanced Quick Look",
        "Tác vụ nhanh trong Finder": "Finder Quick Actions",
        "Ghi chú ở mép màn hình": "Edge notes",
        "Bắt đầu": "Getting started",
        "Kiểm tra lại quyền": "Re-check permissions",
        "Điều khiển nhanh…": "Quick controls…",
        "Đã cấp": "Granted",
        "Chưa cấp": "Not granted",
        "Đã bật": "On",
        "Đang bật": "On",
        "Đang tắt": "Off",
        "Đã sẵn sàng": "Ready",
        "Chưa có": "Not available",
        "Chưa có mục": "No items",
        "Chưa xác định": "Not verified",
        "mục": "items",
        "Mở…": "Open…",
        "Mở khay Clipboard nổi ở bất kỳ đâu": "Open the floating Clipboard shelf anywhere",
        "Bắt đầu Paste Stack": "Start Paste Stack",
        "Bắt dính cửa sổ đang focus": "Snap the focused window",
        "Chuyển cửa sổ kèm ảnh xem trước": "Switch windows with live previews",
        "Di chuột lên icon app trên Dock để xem trước cửa sổ; lắc chuột khi kéo file hoặc trỏ vào tai thỏ để mở Khay thả.": "Hover an app's Dock icon to preview its windows; shake the cursor while dragging a file, or point at the notch, to open the Drop Tray.",
    ]
}
