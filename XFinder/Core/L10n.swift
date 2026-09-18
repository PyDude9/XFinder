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
    ///
    /// Stable-key shim: nếu `vi` là key trong `L10nDB.viToKey`, dịch qua table
    /// thay vì `enDict`. Nhờ đó code cũ `L10n.t("chuỗi Việt")` vẫn chạy trong khi
    /// code mới dùng `L10n.t(key: "domain.key")` — không cần flag day.
    nonisolated static func t(_ vi: String) -> String {
        if let stableKey = L10nDB.viToKey[vi],
           let pair = L10nDB.table[stableKey],
           LanguageIsEnglish,
           let en = pair[.english] { return en }
        if LanguageIsEnglish, let en = enDict[vi] { return en }
        if LanguageIsEnglish, let en = moreDict[vi] { return en }
        if LanguageIsEnglish, let en = fragDict[vi] { return en }
        return vi
    }

    nonisolated static func t(key: String) -> String {
        guard let pair = L10nDB.table[key] else { return key }
        if LanguageIsEnglish, let en = pair[.english] { return en }
        return pair[.vietnamese] ?? key
    }

    nonisolated private static var LanguageIsEnglish: Bool {
        UserDefaults.standard.string(forKey: "AppLanguage") == AppLanguage.english.rawValue
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
        "Ẩn biểu tượng trên Desktop": "Hide desktop icons",
        "Icon màn hình nền biến mất cho tới khi bật lại (Finder tự khởi động lại).":
            "Desktop icons disappear until turned back on (Finder relaunches).",
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
        // Điều khiển nhanh
        "Điều khiển nhanh máy Mac và các cửa sổ.": "Quick controls for your Mac and its windows.",
        "Áp dụng cho toàn máy, không chỉ XFinder.": "Applies to the whole Mac, not just XFinder.",
        "Cửa sổ": "Windows",
        "Âm lượng": "Volume",
        "Tắt tiếng": "Mute",
        "Độ sáng màn hình": "Display brightness",
        "Không đọc được độ sáng — máy này có thể chỉ dùng màn hình ngoài.": "Can't read brightness — this Mac may be using only an external display.",
        "Chế độ giao diện": "Appearance",
        "Tự động ẩn Dock": "Auto-hide Dock",
        "Xem trước Dock": "Dock preview",
        "Chuyển đổi ứng dụng (⌘-Tab)": "App switcher (⌘-Tab)",
        // WindowPreview / Snap zones
        "Xem trước và chuyển cửa sổ ứng dụng ngay từ Dock.": "Preview and switch app windows right from the Dock.",
        "Cách hoạt động": "How it works",
        "Di chuột qua ứng dụng trên Dock để xem trước các cửa sổ.": "Hover an app on the Dock to preview its windows.",
        "Hiện bản xem trước cửa sổ khi di chuột qua ứng dụng trên Dock": "Show window previews when hovering an app on the Dock",
        "Xem trước cửa sổ bằng Command-Tab": "Window previews with Command-Tab",
        "Chuyển trực tiếp giữa các cửa sổ bằng hình xem trước trực tiếp.": "Switch directly between windows with live previews.",
        "Hiện bản xem trước cửa sổ bằng Command-Tab": "Show window previews with Command-Tab",
        "Hiện cả cửa sổ ẩn trong App Switcher": "Also show hidden windows in the switcher",
        "Quyền cần thiết": "Required permissions",
        "Trợ năng": "Accessibility",
        "Ghi màn hình": "Screen Recording",
        "Bắt dính cửa sổ bằng cách kéo chúng đến cạnh và góc màn hình.": "Snap windows by dragging them to screen edges and corners.",
        "Khôi phục kích thước cửa sổ khi gỡ bắt dính": "Restore window size when unsnapped",
        "Tạo hiệu ứng cho vùng xem trước": "Animate the preview zone",
        "Phản hồi rung": "Haptic feedback",
        "Kéo tới mép màn hình": "Drag to screen edge",
        "Bật bắt dính khi kéo tới mép": "Snap when dragging to an edge",
        "Phím tắt toàn hệ thống": "System-wide shortcuts",
        "Bật phím tắt bắt dính": "Enable snap shortcuts",
        "Hướng dẫn chia cửa sổ": "Window-split guide",
        "Kéo đến cạnh hoặc góc màn hình, rồi thả.": "Drag to an edge or corner, then drop.",
        "Bắt dính ngay": "Snap now",
        "Bấm một vùng để áp dụng cho cửa sổ vừa dùng.": "Click a zone to snap the focused window.",
        // Ghi chú
        "Lưu ghi chú, danh sách công việc và ý tưởng ngay mép màn hình.": "Keep notes, to-dos and ideas at the screen edge.",
        "Ghi chú ở mép màn hình — di chuột tới mép để xem và sửa.": "Edge notes — move the pointer to the edge to view and edit.",
                "Hiện ghi chú ở mép màn hình": "Show notes at the screen edge",
        "Cạnh màn hình": "Screen edge",
        "Hiện trên ứng dụng toàn màn hình": "Show over full-screen apps",
        "Ẩn khi con trỏ rời khỏi": "Hide when pointer leaves",
        "Giao diện ghi chú": "Note appearance",
        "Phím tắt": "Shortcuts",
        "Nhập / Xuất ghi chú": "Import / Export",
        // Nén & Giải nén
        "Nén và giải nén file từ Finder.": "Compress and extract files from Finder.",
        "Giải nén vào": "Extract to",
        "Khi tên đã tồn tại": "If name already exists",
        "Mặc định giải nén": "Default extraction",
        "Bộ máy nén và giải nén": "Compression engine",
        "Tách tác vụ nén và giải nén hoạt động": "Background compress & extract",
        // Thao tác Finder
        "Chạy thao tác của XFinder trên các tệp đang chọn trong Finder.": "Run XFinder actions on the files selected in Finder.",
        "Chọn các mục xuất hiện trong menu ngữ cảnh MFinder.": "Choose which items appear in Finder's context menu.",
        "Cấu hình menu": "Menu configuration",
        "Bố cục menu": "Menu layout",
        "Gọn": "Compact",
        "Đầy đủ": "Full",
        "Terminal mặc định": "Default terminal",
        "Các nhóm hiển thị": "Visible groups",
        "Mở trong": "Open in",
        "Tạo file mới": "New file",
        "Sao chép": "Copy",
        "Hiển thị Finder": "Show in Finder",
        "Dọn file rác": "Clean up",
        "Công cụ ảnh": "Image tools",
        "Nén & Sắp xếp": "Compress & Sort",
        "Sắp xếp": "Sort",
        "OCR": "OCR",
        "Chống ghi": "Write-protect",
                "Tệp đang chọn trong Finder": "Files selected in Finder",
        "Thao tác nhanh": "Quick actions",
        "Menu chuột phải trong Finder": "Finder context menu",
        // Drop tray
        "Giữ file tạm để xử lý hàng loạt.": "Stage files for batch actions.",
        "Trong khay": "In tray",
        "Xem chi tiết": "Details",
        "Thu gọn": "Collapse",
        "Thao tác cho cả khay": "Actions for the whole tray",
        // Misc
        "Bản xem trước": "Preview",
    ]
}
