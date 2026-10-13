import Foundation

/// The pure half of the Features hub: what the switchable features ARE, which permissions each
/// needs, what it costs while idle, what a bundle turns on/off, and what the Permissions tab
/// reports. No UserDefaults, no AppKit — so every rule is pinned by a test, and a test also pins
/// that this catalogue agrees with the engines (key + default) it claims to switch.
///
/// The job (Part 0): *"choose what XFinder runs, and see what it is allowed to do."*
enum AppPermission: String, CaseIterable, Equatable {
    case accessibility, screenRecording, microphone, speechRecognition, notifications, calendars, reminders

    /// L10n store keys (Vietnamese literals, translated at the view).
    var titleKey: String {
        switch self {
        case .accessibility:     return "Trợ năng"
        case .screenRecording:   return "Ghi màn hình"
        case .microphone:        return "Micro"
        case .speechRecognition: return "Nhận dạng giọng nói"
        case .notifications:     return "Thông báo"
        case .calendars:         return "Lịch"
        case .reminders:         return "Lời nhắc"
        }
    }
    var purposeKey: String {
        switch self {
        case .accessibility:     return "Cho phép tính năng phản ứng với phím, chuột và di chuyển cửa sổ."
        case .screenRecording:   return "Cho phép hiện ảnh thu nhỏ cửa sổ."
        case .microphone:        return "Cho phép nghe giọng bạn khi nhập bằng giọng nói."
        case .speechRecognition: return "Cho phép chuyển giọng nói thành chữ."
        case .notifications:     return "Cho Cảnh báo hiện thêm trong Trung tâm thông báo. Không bắt buộc: cảnh báo luôn hiện bằng biểu ngữ của XFinder. Bản ký bằng chứng chỉ tự tạo bị macOS từ chối quyền này."
        case .calendars:         return "Cho trang Lịch trên notch đọc sự kiện của bạn. Chỉ đọc, không ghi, không mạng."
        case .reminders:         return "Cho trang Lịch trên notch hiện lời nhắc có giờ. Chỉ đọc."
        }
    }
    var symbol: String {
        switch self {
        case .accessibility:     return "accessibility"
        case .screenRecording:   return "rectangle.dashed.badge.record"
        case .microphone:        return "mic.fill"
        case .speechRecognition: return "waveform"
        case .notifications:     return "bell.badge"
        case .calendars:         return "calendar"
        case .reminders:         return "checklist"
        }
    }
    /// Deep link to the pane. macOS opens a PANE, never a row inside it (CLAUDE.md Part 3c).
    var settingsURL: String {
        switch self {
        case .accessibility:     return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording:   return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .microphone:        return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition: return "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        case .notifications:     return "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        case .calendars:         return "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        case .reminders:         return "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
        }
    }
}

/// What a feature costs while it is on and idle. Shown as a badge, so it must be TRUE: a feature
/// with a polling timer is not "nothing at rest".
enum IdleCost: String, Equatable {
    case nothingAtRest, listensToKeyboard, listensToMouse, timerWhileActive
    /// A child process stays alive while the feature is on (B6: the Now Playing helper in /usr/bin/perl).
    case helperProcess
    /// F3: an AX observer on the windows of the apps the user listed — nothing runs between window events.
    case watchesWindows

    var badgeKey: String {
        switch self {
        case .nothingAtRest:     return "Không chạy nền"
        case .listensToKeyboard: return "Lắng nghe bàn phím"
        case .listensToMouse:    return "Lắng nghe chuột"
        case .timerWhileActive:  return "Có bộ hẹn giờ"
        case .helperProcess:     return "Một tiến trình phụ"
        case .watchesWindows:    return "Theo dõi cửa sổ app đã chọn"
        }
    }
    /// Whether it keeps something running that the "quiet" bundle should switch off.
    var isBackgroundActive: Bool { self != .nothingAtRest }
}

enum FeatureGroup: String, CaseIterable {
    case windows, clipboard, tools, voice
    var titleKey: String {
        switch self {
        case .windows:   return "Cửa sổ và Dock"
        case .clipboard: return "Clipboard"
        case .tools:     return "Công cụ"
        case .voice:     return "Giọng nói"
        }
    }
}

enum FeatureID: String, CaseIterable {
    case dockPreview, commandTab, snapZones, quitProtection, quitOnClose
    case clipboardShelf, cleanURLs, suggestions, linkPreviews
    case quickSearch, edgeNotes, dropTray, nowPlaying, folderSync, agents, calendar
    case voice
    case translateSelection
    case smartSelect
    case alerts
    case menuBarReadouts
}

struct FeatureDef: Equatable {
    var id: FeatureID
    var titleKey: String
    var subtitleKey: String
    var symbol: String
    var group: FeatureGroup
    /// The ONE UserDefaults key that switches it. The engine reads it with
    /// `object(forKey:) as? Bool ?? defaultOn`; `FeatureCatalogTests` verifies that in source.
    var enabledKey: String
    var defaultOn: Bool
    var permissions: [AppPermission]
    var idle: IdleCost
}

struct FeatureBundle: Equatable {
    var id: String
    var titleKey: String
    var descriptionKey: String
    var symbol: String
    var turnOn: [FeatureID]
    var turnOff: [FeatureID]
}

enum FeatureCatalog {

    static let all: [FeatureDef] = [
        FeatureDef(id: .dockPreview, titleKey: "Xem trước Dock",
                   subtitleKey: "Rê chuột lên icon trên Dock để xem các cửa sổ.",
                   symbol: "macwindow.on.rectangle", group: .windows, enabledKey: "windowPreview.hoverEnabled",
                   defaultOn: true, permissions: [.accessibility, .screenRecording], idle: .listensToMouse),
        FeatureDef(id: .commandTab, titleKey: "Chuyển đổi ứng dụng (⌘-Tab)",
                   subtitleKey: "Thay trình chuyển ứng dụng của macOS bằng bản có ảnh thu nhỏ.",
                   symbol: "command", group: .windows, enabledKey: "windowPreview.commandTabEnabled",
                   defaultOn: false, permissions: [.accessibility, .screenRecording], idle: .listensToKeyboard),
        FeatureDef(id: .snapZones, titleKey: "Vùng bắt dính",
                   subtitleKey: "Kéo cửa sổ tới mép màn hình để chia khung.",
                   symbol: "rectangle.split.3x1", group: .windows, enabledKey: "snapzones.enabled",
                   defaultOn: true, permissions: [.accessibility], idle: .listensToMouse),
        FeatureDef(id: .quitProtection, titleKey: "Giữ ⌘Q để thoát ứng dụng",
                   subtitleKey: "Nhấn nhanh ⌘Q không thoát nhầm; phải giữ khoảng 1 giây.",
                   symbol: "xmark.square", group: .windows, enabledKey: "quitProtection.enabled",
                   defaultOn: false, permissions: [.accessibility], idle: .listensToKeyboard),
        // F3. Only the apps the user lists; off by default.
        FeatureDef(id: .quitOnClose, titleKey: "Thoát app khi đóng cửa sổ cuối",
                   subtitleKey: "Chỉ với những app bạn chọn; Finder không bao giờ.",
                   symbol: "power", group: .windows, enabledKey: "quitOnClose.enabled",
                   defaultOn: false, permissions: [.accessibility], idle: .watchesWindows),

        FeatureDef(id: .clipboardShelf, titleKey: "Khay Clipboard ⌘⇧V",
                   subtitleKey: "Mở lịch sử clipboard ở mọi ứng dụng bằng phím tắt.",
                   symbol: "doc.on.clipboard", group: .clipboard, enabledKey: "clipboard.globalHotkey",
                   defaultOn: true, permissions: [.accessibility], idle: .listensToKeyboard),
        // D4b. The one place a copy may cause a network request — off by default, says so on its row.
        FeatureDef(id: .linkPreviews, titleKey: "Xem trước liên kết (mạng)",
                   subtitleKey: "Tiêu đề và ảnh cho link đã copy, tải từ chính trang đó; mặc định tắt.",
                   symbol: "link.badge.plus", group: .clipboard, enabledKey: "clipboard.linkPreviews",
                   defaultOn: false, permissions: [], idle: .nothingAtRest),
        FeatureDef(id: .cleanURLs, titleKey: "Làm sạch liên kết khi sao chép",
                   subtitleKey: "Xóa tham số theo dõi khỏi liên kết bạn sao chép.",
                   symbol: "link", group: .clipboard, enabledKey: "clipboard.cleanURLs",
                   defaultOn: false, permissions: [], idle: .nothingAtRest),
        FeatureDef(id: .suggestions, titleKey: "Tab Gợi ý trong khay ⌘⇧V",
                   subtitleKey: "Xếp hạng lịch sử theo ứng dụng sắp dán vào.",
                   symbol: "sparkles", group: .clipboard, enabledKey: "clipboard.intelligentSuggestions",
                   defaultOn: true, permissions: [], idle: .nothingAtRest),

        FeatureDef(id: .quickSearch, titleKey: "Bảng lệnh ⌘K",
                   subtitleKey: "Tìm ứng dụng, tệp và tính toán từ một ô nhập.",
                   symbol: "magnifyingglass", group: .tools, enabledKey: "quickSearch.enabled",
                   defaultOn: true, permissions: [], idle: .nothingAtRest),
        FeatureDef(id: .edgeNotes, titleKey: "Ghi chú ở mép màn hình",
                   subtitleKey: "Dải ghi chú ẩn ở mép màn hình, rê chuột để mở.",
                   symbol: "note.text", group: .tools, enabledKey: "notes.edgeEnabled",
                   defaultOn: false, permissions: [], idle: .listensToMouse),
        FeatureDef(id: .dropTray, titleKey: "Khay thả file",
                   subtitleKey: "Giữ tệp tạm ở notch: kéo vào để giữ, kéo ra để dùng.",
                   symbol: "tray.and.arrow.down", group: .tools, enabledKey: "dropTray.notchEnabled",
                   defaultOn: true, permissions: [], idle: .listensToMouse),
        // B6. Its own row so "Tắt tất cả" and the Yên tĩnh bundle really end the helper process —
        // it used to be reachable only as a sub-switch of dropTray (review 2026-10-11).
        FeatureDef(id: .nowPlaying, titleKey: "Đang phát trên notch",
                   subtitleKey: "Bài đang phát, ảnh bìa và nút điều khiển ở notch; đọc qua một tiến trình trợ giúp nhỏ.",
                   symbol: "music.note", group: .tools, enabledKey: "notch.nowPlaying",
                   defaultOn: false, permissions: [], idle: .helperProcess),
        // N3. Files written by a hook script; a 20 s liveness timer only while a session is listed as alive.
        FeatureDef(id: .agents, titleKey: "Agent AI trên notch",
                   subtitleKey: "Phiên Claude Code đang chạy trong terminal: trạng thái và duyệt quyền tại notch; đọc nhật ký hook cục bộ.",
                   symbol: "terminal", group: .tools, enabledKey: "agents.enabled",
                   defaultOn: false, permissions: [], idle: .timerWhileActive),
        // N4. EventKit; a 60 s refetch only while the page is on screen, EKEventStoreChanged otherwise.
        FeatureDef(id: .calendar, titleKey: "Lịch trên notch",
                   subtitleKey: "Hôm nay có gì, việc kế tiếp và link họp — đọc từ Lịch của macOS, không mạng.",
                   symbol: "calendar", group: .tools, enabledKey: "notch.calendar",
                   defaultOn: false, permissions: [.calendars, .reminders], idle: .timerWhileActive),
        FeatureDef(id: .folderSync, titleKey: "Đồng bộ thư mục tự động",
                   subtitleKey: "Sao chép một chiều theo lịch hoặc khi có thay đổi.",
                   symbol: "arrow.triangle.2.circlepath", group: .tools, enabledKey: "sync.autoEnabled",
                   defaultOn: false, permissions: [], idle: .timerWhileActive),

        FeatureDef(id: .alerts, titleKey: "Cảnh báo hệ thống",
                   subtitleKey: "Thông báo khi CPU, bộ nhớ, ổ đĩa, nhiệt độ hay pin có vấn đề kéo dài.",
                   symbol: "bell.badge", group: .tools, enabledKey: "alerts.enabled",
                   defaultOn: false, permissions: [], idle: .timerWhileActive),

        FeatureDef(id: .menuBarReadouts, titleKey: "Số liệu trên thanh menu",
                   subtitleKey: "CPU, bộ nhớ, nhiệt độ… hiện cạnh biểu tượng XFinder; chọn số liệu trong popover (biểu tượng con mắt).",
                   symbol: "gauge.with.dots.needle.33percent", group: .tools, enabledKey: "menubar.readoutsEnabled",
                   defaultOn: false, permissions: [], idle: .timerWhileActive),

        // N5a. A Carbon hotkey (no idle cost beyond the registration) + an AX read on press.
        FeatureDef(id: .translateSelection, titleKey: "Dịch vùng chọn (⇧⌘G)",
                   subtitleKey: "Bôi đen chữ ở app bất kỳ, bấm ⇧⌘G: bản dịch của Apple ngay trên máy, không mạng.",
                   symbol: "character.bubble", group: .tools, enabledKey: "translate.hotkeyEnabled",
                   defaultOn: false, permissions: [.accessibility], idle: .listensToKeyboard),
        // E4/E5. One AXObserver on the frontmost app + a left-mouse-up monitor pair; nothing polls.
        FeatureDef(id: .smartSelect, titleKey: "Chọn văn bản thông minh",
                   subtitleKey: "Bôi đen chữ ở app khác: nút nhỏ đổi đơn vị, đổi múi giờ, tính, thêm vào Lịch, dịch.",
                   symbol: "wand.and.stars", group: .tools, enabledKey: "smartSelect.enabled",
                   defaultOn: false, permissions: [.accessibility], idle: .listensToMouse),
        FeatureDef(id: .voice, titleKey: "Nhập bằng giọng nói",
                   subtitleKey: "Giữ phím, nói, thả ra là chữ vào ô đang gõ.",
                   symbol: "mic.fill", group: .voice, enabledKey: "voice.enabled",
                   defaultOn: true, permissions: [.accessibility, .microphone, .speechRecognition],
                   idle: .listensToKeyboard),
    ]

    static func def(_ id: FeatureID) -> FeatureDef { all.first { $0.id == id }! }

    static func features(in group: FeatureGroup) -> [FeatureDef] { all.filter { $0.group == group } }

    // MARK: Bundles

    static let bundles: [FeatureBundle] = [
        FeatureBundle(id: "windows", titleKey: "Cửa sổ",
                      descriptionKey: "Xem trước Dock, ⌘-Tab, vùng bắt dính và giữ ⌘Q để thoát.",
                      symbol: "macwindow",
                      turnOn: [.dockPreview, .commandTab, .snapZones, .quitProtection], turnOff: []),
        FeatureBundle(id: "clipboard", titleKey: "Clipboard và tìm kiếm",
                      descriptionKey: "Khay ⌘⇧V, làm sạch liên kết, gợi ý và bảng lệnh ⌘K.",
                      symbol: "doc.on.clipboard",
                      turnOn: [.clipboardShelf, .cleanURLs, .suggestions, .quickSearch], turnOff: []),
        // "Quiet" is DERIVED from the catalogue, not hand-listed, so a feature added later that
        // listens to input is switched off by it without anyone remembering to edit this list.
        FeatureBundle(id: "quiet", titleKey: "Yên tĩnh",
                      descriptionKey: "Tắt mọi thứ lắng nghe bàn phím, chuột hay chạy hẹn giờ. Chỉ giữ những gì không chạy nền.",
                      symbol: "moon.zzz",
                      turnOn: [], turnOff: all.filter { $0.idle.isBackgroundActive }.map(\.id)),
    ]

    /// The states after applying a bundle. Features the bundle does not mention are untouched.
    static func apply(_ bundle: FeatureBundle, to states: [FeatureID: Bool]) -> [FeatureID: Bool] {
        var out = states
        for id in bundle.turnOn { out[id] = true }
        for id in bundle.turnOff { out[id] = false }
        return out
    }

    // MARK: Permissions tab

    struct PermissionRow: Equatable {
        var permission: AppPermission
        var granted: Bool
        /// Titles of EVERY feature that can use it.
        var usedBy: [String]
        /// How many of those are switched on right now.
        var activeUsers: Int
        /// Granted, yet nothing that is on needs it — the user can revoke it.
        var isUnneeded: Bool { granted && activeUsers == 0 }
        /// Something is on that needs it, and it is not granted — that feature cannot work.
        var isMissingForActive: Bool { !granted && activeUsers > 0 }
    }

    static func permissionRows(enabled: Set<FeatureID>, granted: [AppPermission: Bool]) -> [PermissionRow] {
        AppPermission.allCases.map { p in
            let users = all.filter { $0.permissions.contains(p) }
            return PermissionRow(permission: p, granted: granted[p] ?? false,
                                 usedBy: users.map(\.titleKey),
                                 activeUsers: users.filter { enabled.contains($0.id) }.count)
        }
    }

    /// Features that are switched on but lack a permission they need, with which one.
    static func blocked(enabled: Set<FeatureID>, granted: [AppPermission: Bool]) -> [(FeatureID, [AppPermission])] {
        all.compactMap { f in
            guard enabled.contains(f.id) else { return nil }
            let missing = f.permissions.filter { !(granted[$0] ?? false) }
            return missing.isEmpty ? nil : (f.id, missing)
        }
    }
}
