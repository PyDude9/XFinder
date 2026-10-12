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
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(icon: "gearshape", title: destination.titleVI)

                Group {
                    switch destination {
                    case .settingsClipboard:  ClipboardSettingsBody()
                    default:                  EmptyView()
                    }
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Fill.window)
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
    @AppStorage("clipboard.autoClearSeconds") private var autoClearSeconds = 0
    @AppStorage("clipboard.enableOCR") private var enableOCR = true
    @AppStorage("clipboard.maxHistory") private var maxHistory = 1000
    @AppStorage("clipboard.autoDeleteDays") private var autoDeleteDays = 30
    @AppStorage("clipboard.sounds") private var sounds = true
    /// D1 #16 — which system sound plays on copy; one reader: `ClipboardSounds.copySoundName`.
    @AppStorage("clipboard.copySound") private var copySound = "Pop"
    /// D1 #14 — pause recording; one reader: `ClipboardManager.isPaused`.
    @AppStorage("clipboard.paused") private var paused = false
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

    private static func time(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
            // Nội dung clipboard hiển thị ở khay ⌘⇧V / trang riêng; đây là tuỳ
            // chỉnh. Một nút nhảy sang trang nội dung để không mất lối tới.
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
            .padding(.horizontal, XFinderTokens.Space.page)

            Divider().padding(.horizontal, XFinderTokens.Space.page)

            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                SectionHeader(icon: "command",
                              title: L10n.t("Phím tắt & quyền"),
                              subtitle: L10n.t("⌘⇧V mở clipboard trên mọi ứng dụng"))

                ToggleRow(title: L10n.t("Phím tắt toàn cục ⌘⇧V"), isOn: $globalHotkey)
                    .padding(.horizontal, XFinderTokens.Space.page)
                    .onChange(of: globalHotkey) {
                        ClipboardShelfController.shared.applySettings()
                    }

                // D0: one control, one key. The old shelf is kept behind it, not deleted.
                PickerRow(title: L10n.t("⌘⇧V mở ở"), selection: $hotkeySurface, width: 150) {
                    Text(L10n.t("Ở notch")).tag("notch")
                    Text(L10n.t("Khay nổi cũ")).tag("shelf")
                }
                .padding(.horizontal, XFinderTokens.Space.page)

                if !WindowManager.isTrusted {
                    InlineNote(kind: .warning,
                               text: L10n.t("XFinder chưa được cấp quyền Trợ năng — ⌘⇧V sẽ không mở được khay. Cấp quyền một lần là mọi tính năng cần Trợ năng (khay clipboard, dán phím, bảng lệnh ⌘K, đổi độ sáng) cùng sống lại."))
                        .padding(.horizontal, XFinderTokens.Space.page)
                    HStack {
                        Button(L10n.t("Cấp quyền Trợ năng…")) {
                            _ = WindowManager.requestAccessibilityTrust()
                        }
                        Button(L10n.t("Mở Cài đặt")) { WindowManager.openAccessibilityPane() }
                    }
                    .controlSize(.small)
                    .padding(.horizontal, XFinderTokens.Space.page)
                } else {
                    InlineNote(text: L10n.t("Đã có quyền Trợ năng — ⌘⇧V hoạt động ở mọi ứng dụng."))
                        .padding(.horizontal, XFinderTokens.Space.page)
                }
            }

            Divider().padding(.horizontal, XFinderTokens.Space.page)

            // Rule-based ranking (recency · usage · pinned · app role from bundle ID).
            // Not a model — do not call it Apple Intelligence here; see
            // ClipboardIntelligenceEngine's doc comment.
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                SectionHeader(icon: "wand.and.stars", title: L10n.t("Gợi ý theo ngữ cảnh"))

                ToggleRow(title: L10n.t("Tab Gợi ý trong khay ⌘⇧V"),
                          subtitle: L10n.t("Xếp hạng lịch sử theo ứng dụng sắp dán vào, độ mới, tần suất dùng và mục đã ghim. Chạy hoàn toàn trên máy bằng quy tắc, không dùng mô hình AI."),
                          isOn: $intelligentSuggestions)
                    .padding(.horizontal, XFinderTokens.Space.page)
            }

            Divider().padding(.horizontal, XFinderTokens.Space.page)

            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                SectionHeader(icon: "arrow.down.doc", title: L10n.t("Dán & Thao tác"))

                ToggleRow(title: L10n.t("Tự động dán sau khi chọn"),
                          subtitle: L10n.t("Nhấn Return dán thẳng vào ứng dụng. Khi tắt: chỉ sao chép vào bộ nhớ tạm."),
                          isOn: $autoPaste)
                    .padding(.horizontal, XFinderTokens.Space.page)
            }

            Divider().padding(.horizontal, XFinderTokens.Space.page)

            // REQUIRED dedup: maxHistory/autoDeleteDays were each bound by TWO controls
            // (the pickers here and the sliders in the old "Lịch sử" card). Keeping both
            // is the duplicate-control trap (CLAUDE.md Part 0 #4) — the sliders are gone.
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                SectionHeader(icon: "archivebox", title: L10n.t("Lưu trữ & Hiển thị"))

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
                .padding(.horizontal, XFinderTokens.Space.page)
                .onChange(of: maxHistory) { clipboard.trimToCap() }

                Divider().padding(.horizontal, XFinderTokens.Space.page)

                PickerRow(title: L10n.t("Tự động xóa sau"),
                          subtitle: L10n.t("Thời gian tự động dọn dẹp các mục cũ trong lịch sử"),
                          selection: $autoDeleteDays) {
                    Text(L10n.t("7 ngày")).tag(7)
                    Text(L10n.t("30 ngày")).tag(30)
                    Text(L10n.t("90 ngày")).tag(90)
                    Text(L10n.t("Không bao giờ")).tag(0)
                }
                .padding(.horizontal, XFinderTokens.Space.page)

                Divider().padding(.horizontal, XFinderTokens.Space.page)

                PickerRow(title: L10n.t("Cỡ chữ thẻ"),
                          subtitle: L10n.t("Kích thước chữ trong nội dung thẻ clipboard"),
                          selection: $textSize) {
                    Text(L10n.t("Nhỏ (12pt)")).tag(12.0)
                    Text(L10n.t("Vừa (13.5pt)")).tag(13.5)
                    Text(L10n.t("Lớn (15.5pt)")).tag(15.5)
                }
                .padding(.horizontal, XFinderTokens.Space.page)
            }

            Divider().padding(.horizontal, XFinderTokens.Space.page)

            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                SectionHeader(icon: "hand.raised",
                              title: L10n.t("Riêng tư"),
                              subtitle: L10n.t("Ứng dụng không bao giờ được ghi vào Clipboard."))

                ToggleRow(title: L10n.t("Tạm dừng ghi clipboard"),
                          subtitle: L10n.t("Không ghi gì vào lịch sử cho tới khi bật lại. ⌘⇧V vẫn mở được; trang notch báo đang tạm dừng."),
                          isOn: $paused)
                    .padding(.horizontal, XFinderTokens.Space.page)
                ToggleRow(title: L10n.t("Bỏ qua trình quản lý mật khẩu"),
                          subtitle: "1Password, Bitwarden, LastPass, KeePassXC, Dashlane, Keychain",
                          isOn: $excludePW)
                    .padding(.horizontal, XFinderTokens.Space.page)
                ToggleRow(title: L10n.t("Bỏ qua số thẻ thanh toán (Credit Card)"),
                          subtitle: L10n.t("Tự động lọc số thẻ 13-19 số thỏa thuật toán Luhn"),
                          isOn: $excludeCreditCards)
                    .padding(.horizontal, XFinderTokens.Space.page)
                ToggleRow(title: L10n.t("Khóa Touch ID"),
                          subtitle: L10n.t("Yêu cầu Touch ID hoặc mật khẩu máy khi mở lịch sử"),
                          isOn: $touchIDLock)
                    .padding(.horizontal, XFinderTokens.Space.page)

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
                .padding(.horizontal, XFinderTokens.Space.page)

                if autoClearSeconds > 0 {
                    if let last = clipboard.lastAutoClear {
                        Text("\(L10n.t("Lần tự xóa gần nhất: "))\(last.formatted(date: .omitted, time: .standard))")
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            .padding(.horizontal, XFinderTokens.Space.page)
                    } else {
                        Text(L10n.t("Chưa tự xóa lần nào kể từ khi mở XFinder."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            .padding(.horizontal, XFinderTokens.Space.page)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("Bỏ qua ứng dụng tùy chỉnh"))
                        .font(XFinderTokens.Font.row)
                    Text(L10n.t("Danh sách Bundle ID ứng dụng bỏ qua (phân tách bởi dấu phẩy)"))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    TextField("com.example.app, com.another.app", text: $customExcludedApps)
                        .textFieldStyle(.roundedBorder)
                        .font(XFinderTokens.Font.rowValue)
                }
                .padding(.horizontal, XFinderTokens.Space.page)
                .padding(.top, 2)

                InlineNote(text: L10n.t("Ngoài ra XFinder luôn bỏ qua nội dung được đánh dấu Concealed / AutoGenerated / Transient, kể cả khi tắt công tắc trên."))
                    .padding(.horizontal, XFinderTokens.Space.page)
                InlineNote(text: L10n.t("Toàn bộ dữ liệu nằm trên máy này. Không telemetry, không gửi lên server."))
                    .padding(.horizontal, XFinderTokens.Space.page)
            }

            Divider().padding(.horizontal, XFinderTokens.Space.page)

            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                SectionHeader(icon: "icloud",
                              title: L10n.t("Đồng bộ iCloud"),
                              subtitle: L10n.t("Cho ứng dụng Clipboard trên iPhone sau này."))

                ToggleRow(title: L10n.t("Đồng bộ clipboard qua iCloud"), isOn: $icloudSync)
                    .padding(.horizontal, XFinderTokens.Space.page)
                    .onChange(of: icloudSync) { CloudSyncController.shared.applySettings() }

                switch cloud.status {
                case .disabled:
                    InlineNote(text: L10n.t("Đang tắt."))
                        .padding(.horizontal, XFinderTokens.Space.page)
                case .unavailable(let why):
                    InlineNote(kind: .warning, text: why)
                        .padding(.horizontal, XFinderTokens.Space.page)
                case .ready(let count, let last):
                    InlineNote(kind: .success,
                               text: "\(L10n.t("Sẵn sàng — "))\(count)\(L10n.t(" mục trên iCloud"))" +
                                   (last.map { L10n.t(" · lần cuối ") + Self.time($0) } ?? ""))
                        .padding(.horizontal, XFinderTokens.Space.page)
                }

                Text(L10n.md("Dùng iCloud Key-Value Store: giới hạn 1 MB của Apple nên **chỉ đồng bộ văn bản** (tối đa 60 mục, mỗi mục 2000 ký tự). Ảnh và tệp luôn ở lại máy Mac."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, XFinderTokens.Space.page)
                InlineNote(text: L10n.t("Cần entitlement iCloud + tài khoản Apple Developer trả phí. Khi chưa có, công tắc sẽ báo rõ thay vì giả vờ đồng bộ."))
                    .padding(.horizontal, XFinderTokens.Space.page)
            }

            Divider().padding(.horizontal, XFinderTokens.Space.page)

            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                SectionHeader(icon: "tray.and.arrow.down", title: L10n.t("Thu thập"))

                ToggleRow(title: L10n.t("Ảnh chụp / hình ảnh"), isOn: $captureImages)
                    .padding(.horizontal, XFinderTokens.Space.page)
                ToggleRow(title: L10n.t("Đường link"), isOn: $captureLinks)
                    .padding(.horizontal, XFinderTokens.Space.page)
                ToggleRow(title: L10n.t("Làm sạch liên kết khi sao chép"),
                          subtitle: L10n.t("Xóa tham số theo dõi (utm_*, fbclid, gclid…) khỏi liên kết bạn vừa sao chép bằng cách ghi lại clipboard. Chỉ áp dụng khi toàn bộ nội dung sao chép là một liên kết duy nhất."),
                          isOn: $cleanURLs)
                    .padding(.horizontal, XFinderTokens.Space.page)
                // The app rewrites what the user copied, so it shows what it did — the
                // last cleaning this session — rather than asking to be trusted.
                if cleanURLs {
                    if let last = clipboard.lastCleanedLink {
                        Text("\(L10n.t("Lần gần nhất: đã bỏ "))\(last.removed.joined(separator: ", "))\(L10n.t(" khỏi "))\(last.host)")
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            .padding(.horizontal, XFinderTokens.Space.page)
                    } else {
                        Text(L10n.t("Chưa làm sạch liên kết nào kể từ khi mở XFinder."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            .padding(.horizontal, XFinderTokens.Space.page)
                    }
                }
                ToggleRow(title: L10n.t("Nhận diện chữ (OCR)"), subtitle: "Vision Framework", isOn: $enableOCR)
                    .padding(.horizontal, XFinderTokens.Space.page)
                // "Tải trước ảnh xem trước liên kết" was removed here: nothing ever read
                // `clipboard.linkPreviews`, and fetching every copied URL would also break
                // the local-only promise. A switch with no reader is a lie (Part 0 §6).
                ToggleRow(title: L10n.t("Âm thanh khi sao chép/dán"), subtitle: L10n.t("Tink/Pop hệ thống"), isOn: $sounds)
                    .padding(.horizontal, XFinderTokens.Space.page)
                PickerRow(title: L10n.t("Âm sao chép"), selection: $copySound, width: 120) {
                    ForEach(ClipboardSounds.copySoundChoices, id: \.self) { Text($0).tag($0) }
                }
                .padding(.horizontal, XFinderTokens.Space.page)
                .disabled(!sounds)
            }

            Divider().padding(.horizontal, XFinderTokens.Space.page)

            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                SectionHeader(icon: "folder",
                              title: L10n.t("Bảng ghim (Categories)"),
                              subtitle: "\(clipboard.pinboards.count)\(L10n.t(" bảng — sửa tên hoặc xóa"))")

                ForEach(clipboard.pinboards) { board in
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
                            Button(L10n.t("Xóa"), role: .destructive) {
                                clipboard.deletePinboard(board.id)
                            }
                            .buttonStyle(.link).font(XFinderTokens.Font.caption)
                        }
                    }
                    .padding(.horizontal, XFinderTokens.Space.page)
                    .padding(.vertical, 4)
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
// page bound to the same keys is the duplicate-control trap. The menubar
// flyout keys are still read at point of use by MenubarController /
// SystemMonitorManager.

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
    static func apply(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
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
