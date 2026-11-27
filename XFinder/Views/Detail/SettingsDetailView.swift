import SwiftUI
import AppKit

/// Sidebar-hosted settings. The four CÀI ĐẶT destinations share one page
/// scaffold; each renders its pane as bodies using the same flat
/// PageHeader/SectionHeader/row components the system pages use. Preferences
/// persist via `@AppStorage` (UserDefaults); the two that touch the running
/// app — theme and Dock visibility — apply live through AppKit.
struct SettingsDetailView: View {
    let destination: SidebarDestination

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: destination.titleVI)

                Group {
                    switch destination {
                    case .settingsClipboard:  ClipboardSettingsBody()
                    default:                  EmptyView()
                    }
                }
            }
            .padding(.bottom, 24)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
    }
}

// `GeneralSettingsBody` was deleted along with the `settingsGeneral`
// destination. Its two controls were duplicates: the theme picker is on
// Điều khiển nhanh (which applies it system-wide, not just to XFinder) and the
// Dock-icon toggle is on Tổng quan. `AppearanceController`/`DockController`
// below are still used — by launch-time restore and by those pages.

// MARK: - Clipboard

private struct ClipboardSettingsBody: View {
    @AppStorage("clipboard.captureImages") private var captureImages = true
    @AppStorage("clipboard.captureLinks") private var captureLinks = true
    @AppStorage("clipboard.cleanURLs") private var cleanURLs = false
    @AppStorage("clipboard.linkPreviews") private var linkPreviews = false   // D4b
    @AppStorage("clipboard.autoClearSeconds") private var autoClearSeconds = 0
    @AppStorage("clipboard.enableOCR") private var enableOCR = true
    @AppStorage("clipboard.maxHistory") private var maxHistory = 1000
    @AppStorage("clipboard.autoDeleteDays") private var autoDeleteDays = 30
    @AppStorage("clipboard.sounds") private var sounds = true
    /// D1 #16 — which system sound plays on copy; one reader: `ClipboardSounds.copySoundName`.
    @AppStorage("clipboard.copySound") private var copySound = "Pop"
    /// One reader: `ClipboardSounds.cardHapticOn`.
    @AppStorage("clipboard.cardHaptic") private var cardHaptic = true
    /// D1 #14 — pause recording; one reader: `ClipboardManager.isPaused`.
    @AppStorage("clipboard.paused") private var paused = false
    /// D1 #6 — ⌘⌥C opens the old floating shelf; OFF by default (user). One reader: `ClipboardShelfController.shelfHotkeyEnabled`.
    @AppStorage("clipboard.shelfHotkey") private var shelfHotkey = false
    /// D — the Clipboard MCP server (`XFinder --mcp`); OFF by default. One reader: `MCPServer.isEnabled`.
    @AppStorage("clipboard.mcpEnabled") private var mcpEnabled = false
    @State private var mcpSnippetCopied = false
    /// D — `.xfinderclip` export/import; outcome worded below, nothing stored.
    @State private var transferBusy = false
    @State private var transferOutcome: ClipTransfer.Outcome?
    /// Privacy lives here, not on its own page: excluding password managers is
    /// a property of *what the clipboard records*, not a separate feature.
    @AppStorage("privacy.excludePasswordManagers") private var excludePW = true
    @AppStorage("sync.icloudClipboard") private var icloudSync = false
    /// ⌘⇧V global shelf hotkey — read by `ClipboardShelfController.applySettings`.
    @AppStorage("clipboard.globalHotkey") private var globalHotkey = true
    /// D0: where ⌘⇧V lands — the notch's clipboard page, or the old floating shelf. One reader:
    /// `ClipboardShelfController.hotkeySurface`.
    @AppStorage("clipboard.hotkeySurface") private var hotkeySurface = "notch"
    @AppStorage("clipboard.autoPasteAfterSelection") private var autoPaste = true
    @AppStorage("clipboard.excludeCreditCards") private var excludeCreditCards = true
    @AppStorage("clipboard.customExcludedApps") private var customExcludedApps = ""
    @AppStorage("clipboard.textSize") private var textSize: Double = 13.5
    @AppStorage("clipboard.touchIDLock") private var touchIDLock = false
    @AppStorage("clipboard.intelligentSuggestions") private var intelligentSuggestions = true

    @State private var cloud = CloudSyncController.shared
    @State private var clipboard = ClipboardManager.shared
    @State private var editingBoard: Pinboard? = nil
    @State private var showRenameBoard = false

    /// Picker label for an auto-clear choice. Each literal is wrapped where it is written, so the
    /// literal lint sees it; a value outside `ClipboardAutoClear.choices` (hand-edited
    /// `defaults write`) falls back to a bare number of seconds rather than a blank row.
    private func autoClearLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0:   return L10n.t("Tắt")
        case 30:  return L10n.t("30 giây")
        case 60:  return L10n.t("1 phút")
        case 300: return L10n.t("5 phút")
        case 900: return L10n.t("15 phút")
        default:  return "\(seconds)s"
        }
    }

    /// One line for the last export/import. Counts are joined from fragments so both languages read
    /// in their own word order.
    private var transferLine: String? {
        guard let outcome = transferOutcome else { return nil }
        switch outcome {
        case .cancelled:
            return nil
        case .exported(let records, let files, let missing, let skipped):
            var s = "\(L10n.t("Đã xuất "))\(records)\(L10n.t(" mục"))"
            if files > 0 { s += ", \(files)\(L10n.t(" tệp đính kèm"))" }
            if missing > 0 { s += ", \(missing)\(L10n.t(" tệp không còn trên đĩa"))" }
            if skipped > 0 { s += ", \(L10n.t("bỏ qua "))\(skipped)\(L10n.t(" mục từ trình quản lý mật khẩu"))" }
            return s + "."
        case .imported(let records, let duplicates, let boards, let rejected):
            var s = "\(L10n.t("Đã nhập "))\(records)\(L10n.t(" mục"))"
            if duplicates > 0 { s += ", \(L10n.t("bỏ qua "))\(duplicates)\(L10n.t(" mục trùng"))" }
            if boards > 0 { s += ", \(boards)\(L10n.t(" bảng mới"))" }
            if rejected > 0 { s += ", \(rejected)\(L10n.t(" mục ảnh thiếu tệp"))" }
            return s + "."
        case .failed(.notAManifest):
            return L10n.t("Tệp này không phải tệp .xfinderclip hợp lệ.")
        case .failed(.unsupportedVersion):
            return L10n.t("Tệp được xuất từ bản XFinder mới hơn. Hãy cập nhật XFinder.")
        case .failed(.detail(let d)):
            return "\(L10n.t("Không thực hiện được: "))\(d)"
        }
    }

    /// The MCP client configuration for THIS install (the binary's real path).
    static var mcpConfigSnippet: String {
        let exe = Bundle.main.executablePath ?? "/Applications/XFinder.app/Contents/MacOS/XFinder"
        return """
        {
          "mcpServers": {
            "xfinder-clipboard": {
              "command": "\(exe)",
              "args": ["--mcp"]
            }
          }
        }
        """
    }

    private static func time(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
            // Nội dung clipboard hiển thị ở khay ⌘⇧V / trang riêng; đây là tuỳ
            // chỉnh. Một nút nhảy sang trang nội dung để không mất lối tới.
            SettingsSection {
                HStack(spacing: XFinderTokens.Space.inline) {
                    Image(systemName: "square.on.square").foregroundColor(.accentColor)
                    Text(L10n.t("Lịch sử copy mở bằng ⌘⇧V, ở notch hoặc khay nổi."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    Spacer()
                    Button(L10n.t("Mở clipboard (⌘⇧V)")) {
                        ClipboardShelfController.shared.hotkeyPressed()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .settingsRow()
            }

            SettingsSection(title: L10n.t("Phím tắt & quyền"),
                            footer: L10n.t("⌘⇧V mở clipboard trên mọi ứng dụng")) {
                ToggleRow(title: L10n.t("Phím tắt toàn cục ⌘⇧V"), isOn: $globalHotkey)
                    .onChange(of: globalHotkey) {
                        ClipboardShelfController.shared.applySettings()
                    }
                    .settingsRow()
                SettingsDivider()

                // D0: one control, one key. The old shelf is kept behind it, not deleted.
                PickerRow(title: L10n.t("⌘⇧V mở ở"), selection: $hotkeySurface, width: 150) {
                    Text(L10n.t("Ở notch")).tag("notch")
                    Text(L10n.t("Khay nổi cũ")).tag("shelf")
                }
                .settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Phím ⌘⌥C mở khay nổi cũ"),
                          subtitle: L10n.t("Tắt mặc định. Bật nếu muốn khay nổi dưới màn hình song song với notch."),
                          isOn: $shelfHotkey)
                    .onChange(of: shelfHotkey) { ClipboardShelfController.shared.applySettings() }
                    .settingsRow()

                if !WindowManager.isTrusted {
                    SettingsDivider()
                    InlineNote(kind: .warning,
                               text: L10n.t("XFinder chưa được cấp quyền Trợ năng — ⌘⇧V sẽ không mở được khay. Cấp quyền một lần là mọi tính năng cần Trợ năng (khay clipboard, dán phím, bảng lệnh ⌘K, đổi độ sáng) cùng sống lại."))
                        .settingsRow()
                    SettingsDivider()
                    HStack {
                        Button(L10n.t("Cấp quyền Trợ năng…")) {
                            _ = WindowManager.requestAccessibilityTrust()
                        }
                        Button(L10n.t("Mở Cài đặt")) { WindowManager.openAccessibilityPane() }
                    }
                    .controlSize(.small)
                    .settingsRow()
                } else {
                    SettingsDivider()
                    InlineNote(text: L10n.t("Đã có quyền Trợ năng — ⌘⇧V hoạt động ở mọi ứng dụng."))
                        .settingsRow()
                }
            }

            // Rule-based ranking (recency · usage · pinned · app role from bundle ID).
            // Not a model — do not call it Apple Intelligence here; see
            // ClipboardIntelligenceEngine's doc comment.
            SettingsSection(title: L10n.t("Gợi ý theo ngữ cảnh")) {
                ToggleRow(title: L10n.t("Tab Gợi ý trong khay ⌘⇧V"),
                          subtitle: L10n.t("Xếp hạng lịch sử theo ứng dụng sắp dán vào, độ mới, tần suất dùng và mục đã ghim. Chạy hoàn toàn trên máy bằng quy tắc, không dùng mô hình AI."),
                          isOn: $intelligentSuggestions)
                    .settingsRow()
            }

            SettingsSection(title: L10n.t("Dán & Thao tác")) {
                ToggleRow(title: L10n.t("Tự động dán sau khi chọn"),
                          subtitle: L10n.t("Nhấn Return dán thẳng vào ứng dụng. Khi tắt: chỉ sao chép vào bộ nhớ tạm."),
                          isOn: $autoPaste)
                    .settingsRow()
            }

            // REQUIRED dedup: maxHistory/autoDeleteDays were each bound by TWO controls
            // (the pickers here and the sliders in the old "Lịch sử" card). Keeping both
            // is the duplicate-control trap (CLAUDE.md Part 0 #4) — the sliders are gone.
            SettingsSection(title: L10n.t("Lưu trữ & Hiển thị")) {
                // Three sizes (user, 2026-10-12). A value stored by an older build (200, 5000, 0 = unlimited)
                // keeps a row of its own, so the control always shows what is in effect instead of a blank.
                PickerRow(title: L10n.t("Giới hạn lịch sử"),
                          subtitle: L10n.t("Số lượng mục lưu tối đa trong lịch sử clipboard"),
                          selection: $maxHistory) {
                    Text(L10n.t("20 mục")).tag(20)
                    Text(L10n.t("100 mục")).tag(100)
                    Text(L10n.t("1000 mục")).tag(1000)
                    if ![20, 100, 1000].contains(maxHistory) {
                        if maxHistory == 0 {
                            Text(L10n.t("Không giới hạn")).tag(0)
                        } else {
                            Text("\(maxHistory)\(L10n.t(" mục"))").tag(maxHistory)
                        }
                    }
                }
                .onChange(of: maxHistory) { clipboard.trimToCap() }
                .settingsRow()

                SettingsDivider()

                PickerRow(title: L10n.t("Tự động xóa sau"),
                          subtitle: L10n.t("Thời gian tự động dọn dẹp các mục cũ trong lịch sử"),
                          selection: $autoDeleteDays) {
                    Text(L10n.t("7 ngày")).tag(7)
                    Text(L10n.t("30 ngày")).tag(30)
                    Text(L10n.t("90 ngày")).tag(90)
                    Text(L10n.t("Không bao giờ")).tag(0)
                }
                .settingsRow()

                SettingsDivider()

                PickerRow(title: L10n.t("Cỡ chữ thẻ"),
                          subtitle: L10n.t("Kích thước chữ trong nội dung thẻ clipboard"),
                          selection: $textSize) {
                    Text(L10n.t("Nhỏ (12pt)")).tag(12.0)
                    Text(L10n.t("Vừa (13.5pt)")).tag(13.5)
                    Text(L10n.t("Lớn (15.5pt)")).tag(15.5)
                }
                .settingsRow()
            }

            // D — one file for the whole history + boards + media; import never overwrites.
            SettingsSection(
                title: L10n.t("Sao lưu & chuyển máy"),
                footer: L10n.t("Xuất toàn bộ lịch sử và bảng ghim, kèm ảnh, thành một tệp .xfinderclip. Nhập không ghi đè mục đang có. Mục từ trình quản lý mật khẩu không bao giờ được xuất.")
            ) {
                HStack(spacing: XFinderTokens.Space.inline) {
                    Button(L10n.t("Xuất tệp .xfinderclip…")) {
                        Task { transferBusy = true; transferOutcome = await ClipTransfer.exportViaPanel(); transferBusy = false }
                    }
                    Button(L10n.t("Nhập tệp .xfinderclip…")) {
                        Task { transferBusy = true; transferOutcome = await ClipTransfer.importViaPanel(); transferBusy = false }
                    }
                    if transferBusy { ProgressView().controlSize(.small) }
                }
                .disabled(transferBusy)
                .settingsRow()
                if let line = transferLine {
                    SettingsDivider()
                    Text(line).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        .settingsRow()
                }
            }

            // D — Clipboard MCP: the app binary as a stdio server for Claude Code / Cursor / Codex.
            // XF-T29 — Pro only: the switch here is informational in Free (the server itself always
            // answers "XFinder Pro is required…" per LicenseManager, whatever this toggle says), so it is
            // disabled and tagged rather than silently doing nothing (CLAUDE.md rule 7).
            SettingsSection(
                title: "\(L10n.t("Clipboard MCP cho agent AI"))\(L10n.t(" · PRO"))",
                footer: L10n.t("Claude Code, Cursor, Codex đọc được lịch sử clipboard qua MCP. Chỉ đọc, chỉ văn bản, không bao giờ trả mục từ trình quản lý mật khẩu; tắt công tắc thì mọi lệnh trả lỗi.")
            ) {
                ToggleRow(title: L10n.t("Cho phép agent đọc clipboard qua MCP"), isOn: $mcpEnabled)
                    .proGated(.clipboardMCP)
                    .settingsRow()
                SettingsDivider()
                HStack(alignment: .top, spacing: XFinderTokens.Space.inline) {
                    Text(Self.mcpConfigSnippet)
                        .font(XFinderTokens.Font.mono)
                        .textSelection(.enabled)
                        .padding(XFinderTokens.Space.row)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).fill(XFinderTokens.Fill.inset))
                    Button(mcpSnippetCopied ? L10n.t("Đã sao chép") : L10n.t("Sao chép")) {
                        let pb = NSPasteboard.general
                        pb.clearContents(); pb.setString(Self.mcpConfigSnippet, forType: .string)
                        mcpSnippetCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { mcpSnippetCopied = false }
                    }
                    .controlSize(.small)
                }
                .settingsRow()
                SettingsDivider()
                InlineNote(text: L10n.t("Dán đoạn này vào cấu hình MCP của agent (Claude Code: ~/.claude.json hoặc .mcp.json). Server chạy khi agent khởi động nó; XFinder không mở cổng mạng nào."))
                    .settingsRow()
            }

            SettingsSection(title: L10n.t("Riêng tư"),
                            footer: L10n.t("Ứng dụng không bao giờ được ghi vào Clipboard.")) {
                ToggleRow(title: L10n.t("Tạm dừng ghi clipboard"),
                          subtitle: L10n.t("Không ghi gì vào lịch sử cho tới khi bật lại. ⌘⇧V vẫn mở được; trang notch báo đang tạm dừng."),
                          isOn: $paused)
                    .settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Bỏ qua trình quản lý mật khẩu"),
                          subtitle: "1Password, Bitwarden, LastPass, KeePassXC, Dashlane, Keychain",
                          isOn: $excludePW)
                    .settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Bỏ qua số thẻ thanh toán (Credit Card)"),
                          subtitle: L10n.t("Tự động lọc số thẻ 13-19 số thỏa thuật toán Luhn"),
                          isOn: $excludeCreditCards)
                    .settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Khóa Touch ID"),
                          subtitle: L10n.t("Yêu cầu Touch ID hoặc mật khẩu máy khi mở lịch sử"),
                          isOn: $touchIDLock)
                    .settingsRow()
                SettingsDivider()

                // `.menu`, not `.segmented`: five options would sum into a window-resizing
                // ideal width (CLAUDE.md Part 3c). The copy states what this does NOT do —
                // it clears the macOS clipboard, not XFinder's own history.
                PickerRow(title: L10n.t("Tự xóa clipboard"),
                          subtitle: L10n.t("Xóa clipboard của macOS sau khoảng thời gian bạn chọn nếu không có gì được sao chép sau đó. Chỉ chạy khi XFinder đang mở. Lịch sử của XFinder không bị xóa."),
                          selection: $autoClearSeconds,
                          width: 110) {
                    ForEach(ClipboardAutoClear.choices, id: \.self) { s in
                        Text(autoClearLabel(s)).tag(s)
                    }
                }
                .settingsRow()

                if autoClearSeconds > 0 {
                    SettingsDivider()
                    if let last = clipboard.lastAutoClear {
                        Text("\(L10n.t("Lần tự xóa gần nhất: "))\(last.formatted(date: .omitted, time: .standard))")
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            .settingsRow()
                    } else {
                        Text(L10n.t("Chưa tự xóa lần nào kể từ khi mở XFinder."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            .settingsRow()
                    }
                }

                SettingsDivider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("Bỏ qua ứng dụng tùy chỉnh"))
                        .font(XFinderTokens.Font.row)
                    Text(L10n.t("Danh sách Bundle ID ứng dụng bỏ qua (phân tách bởi dấu phẩy)"))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    TextField("com.example.app, com.another.app", text: $customExcludedApps)
                        .textFieldStyle(.roundedBorder)
                        .font(XFinderTokens.Font.rowValue)
                }
                .settingsRow()

                SettingsDivider()
                InlineNote(text: L10n.t("Ngoài ra XFinder luôn bỏ qua nội dung được đánh dấu Concealed / AutoGenerated / Transient, kể cả khi tắt công tắc trên."))
                    .settingsRow()
                SettingsDivider()
                InlineNote(text: L10n.t("Lịch sử clipboard nằm trên máy này và không được tải lên server nào. Xem trước liên kết, nếu bạn bật, chỉ mở chính liên kết đó để lấy tiêu đề và ảnh."))
                    .settingsRow()
            }

            TextSnippetsSettingsSection()

            SettingsSection(title: L10n.t("Đồng bộ iCloud"),
                            footer: L10n.t("Cho ứng dụng Clipboard trên iPhone sau này.")) {
                ToggleRow(title: L10n.t("Đồng bộ clipboard qua iCloud"), isOn: $icloudSync)
                    .onChange(of: icloudSync) { CloudSyncController.shared.applySettings() }
                    .settingsRow()
                SettingsDivider()

                switch cloud.status {
                case .disabled:
                    InlineNote(text: L10n.t("Đang tắt."))
                        .settingsRow()
                case .unavailable(let why):
                    InlineNote(kind: .warning, text: why)
                        .settingsRow()
                case .ready(let count, let last):
                    InlineNote(kind: .success,
                               text: "\(L10n.t("Sẵn sàng — "))\(count)\(L10n.t(" mục trên iCloud"))" +
                                   (last.map { L10n.t(" · lần cuối ") + Self.time($0) } ?? ""))
                        .settingsRow()
                }

                SettingsDivider()
                Text(L10n.md("Dùng iCloud Key-Value Store: giới hạn 1 MB của Apple nên **chỉ đồng bộ văn bản** (tối đa 60 mục, mỗi mục 2000 ký tự). Ảnh và tệp luôn ở lại máy Mac."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .settingsRow()
                SettingsDivider()
                InlineNote(text: L10n.t("Cần entitlement iCloud + tài khoản Apple Developer trả phí. Khi chưa có, công tắc sẽ báo rõ thay vì giả vờ đồng bộ."))
                    .settingsRow()
            }

            SettingsSection(title: L10n.t("Thu thập")) {
                ToggleRow(title: L10n.t("Ảnh chụp / hình ảnh"), isOn: $captureImages)
                    .settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Đường link"), isOn: $captureLinks)
                    .settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Làm sạch liên kết khi sao chép"),
                          subtitle: L10n.t("Xóa tham số theo dõi (utm_*, fbclid, gclid…) khỏi liên kết bạn vừa sao chép bằng cách ghi lại clipboard. Chỉ áp dụng khi toàn bộ nội dung sao chép là một liên kết duy nhất."),
                          isOn: $cleanURLs)
                    .settingsRow()
                // The app rewrites what the user copied, so it shows what it did — the
                // last cleaning this session — rather than asking to be trusted.
                if cleanURLs {
                    SettingsDivider()
                    if let last = clipboard.lastCleanedLink {
                        Text("\(L10n.t("Lần gần nhất: đã bỏ "))\(last.removed.joined(separator: ", "))\(L10n.t(" khỏi "))\(last.host)")
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            .settingsRow()
                    } else {
                        Text(L10n.t("Chưa làm sạch liên kết nào kể từ khi mở XFinder."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            .settingsRow()
                    }
                }
                SettingsDivider()
                ToggleRow(title: L10n.t("Nhận diện chữ (OCR)"), subtitle: "Vision Framework", isOn: $enableOCR)
                    .settingsRow()
                SettingsDivider()
                // D4b: the switch is back WITH a reader (LinkPreviewFetcher) and honest copy — it is the one
                // network action a copy can trigger, so it is opt-in and says what it sends.
                ToggleRow(title: L10n.t("Tải xem trước liên kết (mạng)"),
                          subtitle: L10n.t("Với mỗi link bạn copy, XFinder gửi một yêu cầu tới chính trang đó để lấy tiêu đề và ảnh (LinkPresentation của Apple). Đây là lần duy nhất clipboard chạm mạng; mặc định tắt. Không bao giờ tải link tới localhost hay mạng nội bộ."),
                          isOn: $linkPreviews)
                    .onChange(of: linkPreviews) { LinkPreviewFetcher.shared.applySettings() }
                    .settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Âm thanh khi sao chép/dán"), subtitle: L10n.t("Tink/Pop hệ thống"), isOn: $sounds)
                    .settingsRow()
                SettingsDivider()
                PickerRow(title: L10n.t("Âm sao chép"), selection: $copySound, width: 120) {
                    ForEach(ClipboardSounds.copySoundChoices, id: \.self) { Text($0).tag($0) }
                }
                .disabled(!sounds)
                .settingsRow()
                SettingsDivider()
                ToggleRow(title: L10n.t("Rung nhẹ khi lướt qua các thẻ"),
                          subtitle: L10n.t("Mỗi thẻ lướt qua ở notch hoặc khay nổi là một nhịp rung. Chỉ trackpad Force Touch, và chỉ cảm nhận được khi ngón tay đang trên trackpad."),
                          isOn: $cardHaptic)
                    .settingsRow()
            }

            SettingsSection(title: L10n.t("Bảng ghim (Categories)"),
                            footer: "\(clipboard.pinboards.count)\(L10n.t(" bảng — sửa tên hoặc xóa"))") {
                ForEach(Array(clipboard.pinboards.enumerated()), id: \.element.id) { entry in
                    if entry.offset > 0 { SettingsDivider() }
                    let board = entry.element
                    HStack(spacing: XFinderTokens.Space.inline) {
                        Circle().fill(board.color.color).frame(width: 10, height: 10)
                        Image(systemName: board.icon).font(.caption).foregroundColor(.secondary)
                        // Name + badge share ONE flexible region so the badge stays snug
                        // against the name while the buttons sit flush right. A
                        // `maxWidth: .infinity` on the name alone pushed the badge to the
                        // trailing edge next to the buttons (A3 review finding).
                        HStack(spacing: XFinderTokens.Space.tight) {
                            Text(board.name).font(XFinderTokens.Font.rowValue)
                                .lineLimit(1).truncationMode(.middle)
                            if board.isBuiltIn {
                                Text(L10n.t("mặc định")).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        Button(L10n.t("Sửa")) {
                            editingBoard = board
                            showRenameBoard = true
                        }
                        .buttonStyle(.link).font(XFinderTokens.Font.caption)
                        if !board.isBuiltIn {
                            // D4: deleting a LOCKED board would delete the only handle to its key; the
                            // manager refuses, and the button says why instead of pretending.
                            Button(L10n.t("Xóa"), role: .destructive) {
                                clipboard.deletePinboard(board.id)
                            }
                            .buttonStyle(.link).font(XFinderTokens.Font.caption)
                            .disabled(board.isLocked)
                            .help(board.isLocked ? L10n.t("Gỡ khoá bảng trước khi xoá.") : "")
                        }
                    }
                    .settingsRow()
                }
            }
        }
        .onAppear { cloud.applySettings() }
        .sheet(isPresented: $showRenameBoard) {
            RenameBoardSheet(isPresented: $showRenameBoard, board: editingBoard)
        }
    }
}

// `MenubarSettingsBody` and the `settingsMenubar` destination ("Bảng menubar")
// were removed: their three controls duplicated Điều khiển nhanh, and a second
// page bound to the same keys is the duplicate-control trap. Of those keys only
// `menubar.updateInterval` is still read (SystemMonitorManager); the menu-bar
// popover that read the other two became a plain menu in P13.

// MARK: - AppKit side effects

@MainActor
enum AppearanceController {
    static func apply(_ theme: String) {
        switch theme {
        case "Light": NSApp.appearance = NSAppearance(named: .aqua)
        case "Dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil
        }
    }
}

@MainActor
enum DockController {
    /// "Hiện icon trên Dock" (Tổng quan; the page's `@AppStorage("ShowDockIcon")` default is the same `true`).
    static var showDockIcon: Bool { UserDefaults.standard.object(forKey: "ShowDockIcon") as? Bool ?? true }

    /// Whether at least one file browser window is open (XF-T38).
    private static var browserWindowsOpen = false

    static func apply(_ show: Bool) {
        setRegular(BrowserMenuLayout.needsRegularApp(showDockIcon: show, browserWindowsOpen: browserWindowsOpen))
    }

    /// XF-T38 — macOS gives the menu bar only to a regular app (one with a Dock icon); with "Hiện icon trên Dock" off,
    /// XFinder runs as an accessory and the browser had no menu bar at all (measured in the Atlas helper: the bar still
    /// showed Finder's menus with the browser window in front). Like FileOctopus, the browser is a regular app while one
    /// of its windows is open; closing the last one restores the user's choice.
    static func browserWindows(open: Bool) {
        guard open != browserWindowsOpen else { return }
        browserWindowsOpen = open
        setRegular(BrowserMenuLayout.needsRegularApp(showDockIcon: showDockIcon, browserWindowsOpen: open))
    }

    private static func setRegular(_ regular: Bool) {
        let policy: NSApplication.ActivationPolicy = regular ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if regular { NSApp.activate() }   // the menu bar belongs to the active regular app
    }
}

/// Sheet đổi tên bảng ghim (Category) — sửa từ trang Cài đặt Clipboard.
private struct RenameBoardSheet: View {
    @Binding var isPresented: Bool
    let board: Pinboard?
    @State private var name = ""

    var body: some View {
        VStack(spacing: 14) {
            Text(L10n.t("Đổi tên bảng ghim"))
                .font(XFinderTokens.Font.sectionTitle)
            TextField(L10n.t("Tên bảng"), text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(L10n.t("Hủy")) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.t("Lưu")) {
                    if let board { ClipboardManager.shared.renamePinboard(board.id, name: name) }
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear { name = board?.name ?? "" }
    }
}

private struct TextSnippetsSettingsSection: View {
    @AppStorage("clipboard.snippetsAutoExpand") private var autoExpand = false
    @State private var store = TextSnippetStore.shared
    @State private var expander = TextSnippetExpander.shared
    @State private var trigger = ""
    @State private var expansion = ""
    @State private var errorMessage: String?

    var body: some View {
        SettingsSection(
            title: L10n.t("Đoạn văn bản nhanh (Snippets)"),
            footer: L10n.t("Hỗ trợ biến {date}, {time}, {datetime} và {clipboard}. Bấm Sao chép để mở rộng và đưa ngay vào clipboard.")
        ) {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                ToggleRow(
                    title: L10n.t("Tự động mở rộng khi gõ"),
                    subtitle: L10n.t("Gõ từ khóa ở bất kỳ ứng dụng nào để tự thay bằng nội dung mở rộng. Bỏ qua ô mật khẩu."),
                    isOn: $autoExpand
                )
                .onChange(of: autoExpand) { expander.applySettings() }

                if autoExpand {
                    HStack(spacing: 6) {
                        switch expander.state {
                        case .running:
                            Text(L10n.t("Đang lắng nghe gõ tắt."))
                                .font(XFinderTokens.Font.caption)
                                .foregroundColor(.secondary)
                        case .needsAccessibility:
                            Text(L10n.t("Cần quyền Trợ năng để tự động mở rộng khi gõ."))
                                .font(XFinderTokens.Font.caption)
                                .foregroundColor(.orange)
                            Spacer()
                            Button(L10n.t("Cấp quyền Trợ năng…")) {
                                if !WindowManager.requestAccessibilityTrust() {
                                    WindowManager.openAccessibilityPane()
                                }
                            }
                            .controlSize(.small)
                        case .noSnippets:
                            Text(L10n.t("Thêm ít nhất một đoạn văn bản nhanh đang bật để kích hoạt."))
                                .font(XFinderTokens.Font.caption)
                                .foregroundColor(.secondary)
                        case .off:
                            EmptyView()
                        }
                    }
                }

                Divider()

                HStack(spacing: XFinderTokens.Space.inline) {
                    TextField(L10n.t("Từ khóa (ví dụ ;sig)"), text: $trigger)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    TextField(L10n.t("Nội dung mở rộng"), text: $expansion)
                        .textFieldStyle(.roundedBorder)
                    Button(L10n.t("Thêm")) {
                        if let err = store.add(trigger: trigger, expansion: expansion) {
                            switch err {
                            case .emptyTrigger:
                                errorMessage = L10n.t("Từ khóa không được để trống.")
                            case .emptyExpansion:
                                errorMessage = L10n.t("Nội dung mở rộng không được để trống.")
                            case .duplicateTrigger:
                                errorMessage = L10n.t("Từ khóa này đã tồn tại.")
                            }
                        } else {
                            trigger = ""
                            expansion = ""
                            errorMessage = nil
                        }
                    }
                    .controlSize(.small)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.orange)
                }

                if store.snippets.isEmpty {
                    Text(L10n.t("Chưa có đoạn văn bản nhanh nào."))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(store.snippets) { item in
                        HStack(spacing: XFinderTokens.Space.inline) {
                            Toggle("", isOn: Binding(
                                get: { item.isEnabled },
                                set: { next in
                                    if next != item.isEnabled { store.toggle(id: item.id) }
                                }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            Text(item.trigger)
                                .font(XFinderTokens.Font.row)
                                .monospaced()
                                .opacity(item.isEnabled ? 1.0 : 0.5)
                            Text(item.expansion)
                                .font(XFinderTokens.Font.rowValue)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .opacity(item.isEnabled ? 1.0 : 0.5)
                            Spacer()
                            Button(L10n.t("Sao chép")) { store.copyExpanded(item) }
                                .controlSize(.small)
                            Button(L10n.t("Xoá")) { store.delete(id: item.id) }
                                .controlSize(.small)
                        }
                    }
                }
            }
            .settingsRow()
            .onAppear { expander.applySettings() }
        }
    }
}
