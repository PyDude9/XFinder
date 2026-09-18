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
    @State private var cloud = CloudSyncController.shared
    @State private var clipboard = ClipboardManager.shared
    @State private var editingBoard: Pinboard? = nil
    @State private var showRenameBoard = false

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
                Text(L10n.t("Lịch sử copy hiển thị ở khay ⌘⇧V và trang nội dung."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Button(L10n.t("Mở lịch sử…")) { AppState.shared.navigate(to: .clipboard) }
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

            SettingsCard(title: L10n.t("Riêng tư"),
                         subtitle: L10n.t("Ứng dụng không bao giờ được ghi vào Clipboard.")) {
                VStack(alignment: .leading, spacing: 8) {
                    ToggleRow(title: L10n.t("Bỏ qua trình quản lý mật khẩu"),
                              subtitle: "1Password, Bitwarden, LastPass, KeePassXC, Dashlane, Keychain",
                              isOn: $excludePW)
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
                    ToggleRow(title: L10n.t("Nhận diện chữ (OCR)"), subtitle: "Vision Framework", isOn: $enableOCR)
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
