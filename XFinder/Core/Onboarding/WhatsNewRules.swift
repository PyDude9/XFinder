import Foundation

/// N7 (2026-10-13) — the per-version "Có gì mới" sheet (OneNotch keys its What's New page on
/// `lastSeenWhatsNewVersion`). XFinder already had a first-run SETUP window (`Onboarding`, commit c436b80: choose a
/// preset, ask only for the permissions it needs) — that is the tour, and it stays. This file adds only what was
/// missing: notes per version and the rule for when to show them. Pure, symlinked, tested.
///
/// Rules: the sheet appears once per app version, to EXISTING users only (someone who completed setup or already
/// has a clipboard database); a fresh install is on setup and gets the current version recorded as seen.
enum WhatsNewRules {
    static let key = "whatsNew.lastSeenVersion"

    static func shouldShow(lastSeen: String?, current: String, isExistingUser: Bool) -> Bool {
        isExistingUser && lastSeen != current && !notes(for: current).isEmpty
    }

    /// One line: the feature, one sentence, and the page that holds it. `destinationRaw` is a
    /// `SidebarDestination.rawValue` kept as a String so this file stays free of the SwiftUI-side model.
    struct Note: Equatable, Identifiable {
        var id: String
        var symbol: String
        var titleKey: String
        var bodyKey: String
        var destinationRaw: String?
    }

    /// Notes per version, matched on the first two components so a patch release carries its minor's story.
    static func notes(for version: String) -> [Note] {
        switch minor(version) {
        case "1.2": return notes12
        default: return []
        }
    }

    static func minor(_ v: String) -> String {
        let parts = v.trimmingCharacters(in: .whitespaces).split(separator: ".").map(String.init)
        return parts.prefix(2).joined(separator: ".")
    }

    static let notes12: [Note] = [
        Note(id: "panel", symbol: "rectangle.topthird.inset.filled", titleKey: "Notch mượt hơn",
             bodyKey: "Một cửa sổ cố định cho mọi trạng thái — hub mở ra từ notch, không còn giật khi đổi trang.", destinationRaw: "dropTray"),
        Note(id: "hover", symbol: "cursorarrow.motionlines", titleKey: "Rê chuột vào notch mở gì là tuỳ bạn",
             bodyKey: "Chỉ xem nhanh, theo hoạt động, hay một trang cố định — một picker trong Notch & Khay thả.", destinationRaw: "dropTray"),
        Note(id: "agents", symbol: "terminal", titleKey: "Phiên Claude Code trên notch",
             bodyKey: "Trạng thái từng phiên và nút Cho phép / Từ chối cho yêu cầu quyền, qua hook công khai của Claude Code.", destinationRaw: "dropTray"),
        Note(id: "calendar", symbol: "calendar", titleKey: "Trang Lịch",
             bodyKey: "Hôm nay có gì, việc kế tiếp, lịch âm theo giờ Việt Nam, nút Tham gia cho link họp.", destinationRaw: "dropTray"),
        Note(id: "files", symbol: "doc.richtext", titleKey: "Thêm việc cho tệp đang giữ",
             bodyKey: "Sang PDF, OCR, Thu nhỏ ảnh với preset khi giữ chuột — bên cạnh ZIP, Gộp PDF, Tách nền, AirDrop.", destinationRaw: "dropTray"),
        Note(id: "player", symbol: "music.note", titleKey: "Tua, xáo trộn, lặp lại",
             bodyKey: "Kéo thanh tiến trình để tua; xáo trộn và lặp lại trong menu của trang Đang phát.", destinationRaw: "dropTray"),
        Note(id: "library", symbol: "books.vertical", titleKey: "Thư viện Clipboard và bảng khoá",
             bodyKey: "Mọi clip từng copy, lọc theo loại / app / bảng / thời gian; bảng khoá mã hoá bằng Secure Enclave, mở từng thẻ bằng Touch ID.", destinationRaw: "clipboard"),
    ]
}
