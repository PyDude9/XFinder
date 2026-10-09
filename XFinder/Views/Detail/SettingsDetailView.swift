import SwiftUI
import AppKit

/// Sidebar-hosted settings. The four CÀI ĐẶT destinations share one page
/// scaffold; each renders its pane as bodies using the same SettingsCard /
/// ToggleRow components the system pages use. Preferences persist via
/// `@AppStorage` (UserDefaults); the two that touch the running app — theme
/// and Dock visibility — apply live through AppKit.
struct SettingsDetailView: View {
    let destination: SidebarDestination

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(destination.titleVI)
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Group {
                    switch destination {
                    case .settingsClipboard:  ClipboardSettingsBody()
                    default:                  EmptyView()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color(.windowBackgroundColor))
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
    /// Privacy lives here, not on its own page: excluding password managers is
    /// a property of *what the clipboard records*, not a separate feature.
    @AppStorage("privacy.excludePasswordManagers") private var excludePW = true
    @AppStorage("sync.icloudClipboard") private var icloudSync = false
    /// ⌘⇧V global shelf hotkey — read by `ClipboardShelfController.applySettings`.
    @AppStorage("clipboard.globalHotkey") private var globalHotkey = true
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
        VStack(alignment: .leading, spacing: 16) {
            // Nội dung clipboard hiển thị ở khay ⌘⇧V / trang riêng; đây là tuỳ
            // chỉnh. Một nút nhảy sang trang nội dung để không mất lối tới.
            HStack(spacing: 10) {
                Image(systemName: "square.on.square").foregroundColor(.accentColor)
                Text(L10n.t("Lịch sử copy hiển thị ở khay ⌘⇧V."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Button(L10n.t("Mở khay clipboard (⌘⇧V)")) {
                    ClipboardShelfController.shared.toggle()
                }
                .buttonStyle(.bordered).controlSize(.small)
            }

            SettingsCard(title: L10n.t("Phím tắt & quyền"),
                         subtitle: L10n.t("⌘⇧V mở khay clipboard nổi trên mọi ứng dụng")) {
                VStack(alignment: .leading, spacing: 8) {
                    ToggleRow(title: L10n.t("Phím tắt toàn cục ⌘⇧V"), isOn: $globalHotkey)
                        .onChange(of: globalHotkey) {
                            ClipboardShelfController.shared.applySettings()
                        }

                    if !WindowManager.isTrusted {
                        Text(L10n.t("XFinder chưa được cấp quyền Trợ năng — ⌘⇧V sẽ không mở được khay. Cấp quyền một lần là mọi tính năng cần Trợ năng (khay clipboard, dán phím, bảng lệnh ⌘K, đổi độ sáng) cùng sống lại."))
                            .font(.system(size: 11)).foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(L10n.t("Cấp quyền Trợ năng…")) {
                                _ = WindowManager.requestAccessibilityTrust()
                            }
                            Button(L10n.t("Mở Cài đặt")) { WindowManager.openAccessibilityPane() }
                        }
                        .controlSize(.small)
                    } else {
                        Text(L10n.t("Đã có quyền Trợ năng — ⌘⇧V hoạt động ở mọi ứng dụng."))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
            }

            // Rule-based ranking (recency · usage · pinned · app role from bundle ID).
            // Not a model — do not call it Apple Intelligence here; see
            // ClipboardIntelligenceEngine's doc comment.
            SettingsCard(title: L10n.t("Gợi ý theo ngữ cảnh")) {
                VStack(alignment: .leading, spacing: 10) {
                    ToggleRow(title: L10n.t("Tab Gợi ý trong khay ⌘⇧V"),
                              subtitle: L10n.t("Xếp hạng lịch sử theo ứng dụng sắp dán vào, độ mới, tần suất dùng và mục đã ghim. Chạy hoàn toàn trên máy bằng quy tắc, không dùng mô hình AI."),
                              isOn: $intelligentSuggestions)
                }
            }

            SettingsCard(title: L10n.t("Dán & Thao tác")) {
                VStack(spacing: 10) {
                    ToggleRow(title: L10n.t("Tự động dán sau khi chọn"),
                              subtitle: L10n.t("Nhấn Return dán thẳng vào ứng dụng. Khi tắt: chỉ sao chép vào bộ nhớ tạm."),
                              isOn: $autoPaste)
                }
            }


            SettingsCard(title: L10n.t("Lưu trữ & Hiển thị")) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("Giới hạn lịch sử"))
                            .font(.system(size: 13, weight: .medium))
                        Text(L10n.t("Số lượng mục lưu tối đa trong lịch sử clipboard"))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        Picker("", selection: $maxHistory) {
                            Text(L10n.t("200 mục")).tag(200)
                            Text(L10n.t("1000 mục")).tag(1000)
                            Text(L10n.t("5000 mục")).tag(5000)
                            Text(L10n.t("Không giới hạn")).tag(0)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: maxHistory) { clipboard.trimToCap() }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("Tự động xóa sau"))
                            .font(.system(size: 13, weight: .medium))
                        Text(L10n.t("Thời gian tự động dọn dẹp các mục cũ trong lịch sử"))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        Picker("", selection: $autoDeleteDays) {
                            Text(L10n.t("7 ngày")).tag(7)
                            Text(L10n.t("30 ngày")).tag(30)
                            Text(L10n.t("90 ngày")).tag(90)
                            Text(L10n.t("Không bao giờ")).tag(0)
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("Cỡ chữ thẻ"))
                            .font(.system(size: 13, weight: .medium))
                        Text(L10n.t("Kích thước chữ trong nội dung thẻ clipboard"))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        Picker("", selection: $textSize) {
                            Text(L10n.t("Nhỏ (12pt)")).tag(12.0)
                            Text(L10n.t("Vừa (13.5pt)")).tag(13.5)
                            Text(L10n.t("Lớn (15.5pt)")).tag(15.5)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }

            SettingsCard(title: L10n.t("Riêng tư"),
                         subtitle: L10n.t("Ứng dụng không bao giờ được ghi vào Clipboard.")) {
                VStack(alignment: .leading, spacing: 10) {
                    ToggleRow(title: L10n.t("Bỏ qua trình quản lý mật khẩu"),
                              subtitle: "1Password, Bitwarden, LastPass, KeePassXC, Dashlane, Keychain",
                              isOn: $excludePW)
                    ToggleRow(title: L10n.t("Bỏ qua số thẻ thanh toán (Credit Card)"),
                              subtitle: L10n.t("Tự động lọc số thẻ 13-19 số thỏa thuật toán Luhn"),
                              isOn: $excludeCreditCards)
                    ToggleRow(title: L10n.t("Khóa Touch ID"),
                              subtitle: L10n.t("Yêu cầu Touch ID hoặc mật khẩu máy khi mở lịch sử"),
                              isOn: $touchIDLock)
                    // `.menu`, not `.segmented`: five options would sum into a window-resizing
                    // ideal width (CLAUDE.md Part 3c). The copy states what this does NOT do —
                    // it clears the macOS clipboard, not XFinder's own history.
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("Tự xóa clipboard"))
                                .font(.system(size: 13, weight: .medium))
                            Text(L10n.t("Xóa clipboard của macOS sau khoảng thời gian bạn chọn nếu không có gì được sao chép sau đó. Chỉ chạy khi XFinder đang mở. Lịch sử của XFinder không bị xóa."))
                                .font(.system(size: 11)).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Picker("", selection: $autoClearSeconds) {
                            ForEach(ClipboardAutoClear.choices, id: \.self) { s in
                                Text(autoClearLabel(s)).tag(s)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 110)
                    }
                    if autoClearSeconds > 0 {
                        if let last = clipboard.lastAutoClear {
                            Text("\(L10n.t("Lần tự xóa gần nhất: "))\(last.formatted(date: .omitted, time: .standard))")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        } else {
                            Text(L10n.t("Chưa tự xóa lần nào kể từ khi mở XFinder."))
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("Bỏ qua ứng dụng tùy chỉnh"))
                            .font(.system(size: 13, weight: .medium))
                        Text(L10n.t("Danh sách Bundle ID ứng dụng bỏ qua (phân tách bởi dấu phẩy)"))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        TextField("com.example.app, com.another.app", text: $customExcludedApps)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }
                    .padding(.top, 2)

                    Text(L10n.t("Ngoài ra XFinder luôn bỏ qua nội dung được đánh dấu Concealed / AutoGenerated / Transient, kể cả khi tắt công tắc trên."))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    Text(L10n.t("Toàn bộ dữ liệu nằm trên máy này. Không telemetry, không gửi lên server."))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }

            SettingsCard(title: L10n.t("Đồng bộ iCloud"),
                         subtitle: L10n.t("Cho ứng dụng Clipboard trên iPhone sau này.")) {
                VStack(alignment: .leading, spacing: 8) {
                    ToggleRow(title: L10n.t("Đồng bộ clipboard qua iCloud"), isOn: $icloudSync)
                        .onChange(of: icloudSync) { CloudSyncController.shared.applySettings() }

                    switch cloud.status {
                    case .disabled:
                        Text(L10n.t("Đang tắt.")).font(.system(size: 11)).foregroundColor(.secondary)
                    case .unavailable(let why):
                        Text(why).font(.system(size: 11)).foregroundColor(.orange)
                    case .ready(let count, let last):
                        Text("\(L10n.t("Sẵn sàng — "))\(count)\(L10n.t(" mục trên iCloud"))" +
                             (last.map { L10n.t(" · lần cuối ") + Self.time($0) } ?? ""))
                            .font(.system(size: 11)).foregroundColor(.green)
                    }

                    Text(L10n.md("Dùng iCloud Key-Value Store: giới hạn 1 MB của Apple nên **chỉ đồng bộ văn bản** (tối đa 60 mục, mỗi mục 2000 ký tự). Ảnh và tệp luôn ở lại máy Mac."))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    Text(L10n.t("Cần entitlement iCloud + tài khoản Apple Developer trả phí. Khi chưa có, công tắc sẽ báo rõ thay vì giả vờ đồng bộ."))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }

            SettingsCard(title: L10n.t("Thu thập")) {
                VStack(spacing: 10) {
                    ToggleRow(title: L10n.t("Ảnh chụp / hình ảnh"), isOn: $captureImages)
                    ToggleRow(title: L10n.t("Đường link"), isOn: $captureLinks)
                    ToggleRow(title: L10n.t("Làm sạch liên kết khi sao chép"),
                              subtitle: L10n.t("Xóa tham số theo dõi (utm_*, fbclid, gclid…) khỏi liên kết bạn vừa sao chép bằng cách ghi lại clipboard. Chỉ áp dụng khi toàn bộ nội dung sao chép là một liên kết duy nhất."),
                              isOn: $cleanURLs)
                    // The app rewrites what the user copied, so it shows what it did — the
                    // last cleaning this session — rather than asking to be trusted.
                    if cleanURLs {
                        if let last = clipboard.lastCleanedLink {
                            Text("\(L10n.t("Lần gần nhất: đã bỏ "))\(last.removed.joined(separator: ", "))\(L10n.t(" khỏi "))\(last.host)")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        } else {
                            Text(L10n.t("Chưa làm sạch liên kết nào kể từ khi mở XFinder."))
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                    ToggleRow(title: L10n.t("Nhận diện chữ (OCR)"), subtitle: "Vision Framework", isOn: $enableOCR)
                    // "Tải trước ảnh xem trước liên kết" was removed here: nothing ever read
                    // `clipboard.linkPreviews`, and fetching every copied URL would also break
                    // the local-only promise. A switch with no reader is a lie (Part 0 §6).
                    ToggleRow(title: L10n.t("Âm thanh khi sao chép/dán"), subtitle: L10n.t("Tink/Pop hệ thống"), isOn: $sounds)
                }
            }

            SettingsCard(title: L10n.t("Bảng ghim (Categories)"),
                         subtitle: "\(clipboard.pinboards.count)\(L10n.t(" bảng — sửa tên hoặc xóa"))") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(clipboard.pinboards) { board in
                        HStack(spacing: 10) {
                            Circle().fill(board.color.color).frame(width: 10, height: 10)
                            Image(systemName: board.icon).font(.caption).foregroundColor(.secondary)
                            Text(board.name).font(.system(size: 12))
                            if board.isBuiltIn {
                                Text(L10n.t("mặc định")).font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(L10n.t("Sửa")) {
                                editingBoard = board
                                showRenameBoard = true
                            }
                            .buttonStyle(.link).font(.system(size: 11))
                            if !board.isBuiltIn {
                                Button(L10n.t("Xóa"), role: .destructive) {
                                    clipboard.deletePinboard(board.id)
                                }
                                .buttonStyle(.link).font(.system(size: 11))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            SettingsCard(title: L10n.t("Lịch sử")) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(L10n.t("Giữ "))\(maxHistory)\(L10n.t(" mục"))").font(.system(size: 13, weight: .medium))
                        Slider(value: Binding(get: { Double(maxHistory) }, set: { maxHistory = Int($0) }),
                               in: 100...10000, step: 100)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(L10n.t("Tự xóa sau "))\(autoDeleteDays)\(L10n.t(" ngày"))").font(.system(size: 13, weight: .medium))
                        Slider(value: Binding(get: { Double(autoDeleteDays) }, set: { autoDeleteDays = Int($0) }),
                               in: 1...365)
                    }
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
                .font(.system(size: 15, weight: .semibold))
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
