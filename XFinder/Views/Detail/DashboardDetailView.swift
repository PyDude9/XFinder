import SwiftUI
import AppKit
import ServiceManagement

/// Tổng quan — a setup/status page, not a metrics dashboard (see the reference
/// screenshot): app-level preferences on top, then a checklist of every
/// capability with its live permission or registration state, each row linking
/// to the place that fixes it.
struct DashboardDetailView: View {
    @Environment(SystemMonitorManager.self) var monitor
    @Environment(ClipboardManager.self) var clipboardManager
    @Environment(AppState.self) var appState

    @AppStorage("general.launchAtLogin") private var launchAtLogin = false
    @AppStorage("ShowDockIcon") private var showDockIcon = true
    @AppStorage("notes.edgeEnabled") private var edgeNotesEnabled = false
    @AppStorage("windowPreview.hoverEnabled") private var hoverEnabled = true
    @State private var l10n = L10n.shared
    @AppStorage("menubar.icon") private var menubarIcon = "magnifier"

    @State private var trusted = WindowManager.isTrusted
    @State private var canRecord = WindowManager.canRecordScreen
    @State private var automationOK = false
    @State private var mediaPreviewInstalled = false
    @State private var appleIntelligence = false
    @State private var finderSyncOn = false
    @State private var activationObserver: NSObjectProtocol?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(icon: "square.grid.2x2",
                           title: L10n.t("Tổng quan"),
                           subtitle: L10n.t("Xem những gì đã sẵn sàng và hoàn tất thiết lập."))

                quickGrantBannerIfNeeded
                preferences
                Divider().padding(.horizontal, XFinderTokens.Space.page)
                checklist
                Divider().padding(.horizontal, XFinderTokens.Space.page)
                gettingStarted
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Fill.window)
        // Only sample metrics while a page that shows them is on screen.
        .onAppear { SystemMonitorManager.shared.retain() }
        .onDisappear { SystemMonitorManager.shared.release() }
        .onAppear {
            refreshPermissions()
            // Người dùng bật quyền trong System Settings rồi quay lại app →
            // checklist tự cập nhật, không cần bấm "Kiểm tra lại quyền".
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil, queue: .main
            ) { _ in
                Task { @MainActor in refreshPermissions() }
            }
        }
        .onDisappear {
            if let activationObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            }
            activationObserver = nil
        }
    }

    // MARK: Preferences

    /// Banner "Cấp quyền nhanh" — chỉ hiện khi còn thiếu quyền; tự ẩn khi
    /// Trợ năng + Ghi màn hình đều đã đủ.
    @ViewBuilder
    private var quickGrantBannerIfNeeded: some View {
        if !trusted || !canRecord {
            quickGrantBanner
        }
    }

    private func setMenubarIcon(_ id: String) {
        menubarIcon = id
        if let delegate = NSApplication.shared.delegate as? AppDelegate {
            delegate.menubarController?.applyIcon()
        }
    }

    /// Nút một chạm — gọi đồng thời hộp thoại xin quyền Trợ năng + Ghi màn
    /// hình, rồi mở pane nếu vẫn thiếu. Tiện nhất cho build test.
    private var quickGrantBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill").foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("Cấp quyền nhanh")).font(XFinderTokens.Font.row)
                Text(L10n.t("Nhắc Trợ năng + Ghi màn hình cùng lúc; mở Cài đặt nếu vẫn thiếu."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                WindowManager.requestAllPermissions()
                refreshPermissions()
            } label: {
                Text(L10n.t("Cấp mọi quyền…"))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control))
        .padding(.horizontal, XFinderTokens.Space.page)
    }

    private var preferences: some View {
        VStack(spacing: 0) {
            PickerRow(title: L10n.t("Ngôn ngữ ứng dụng"),
                      selection: Binding(get: { l10n.language }, set: { l10n.set($0) }),
                      width: 140) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .padding(.horizontal, XFinderTokens.Space.page)

            Divider().padding(.horizontal, XFinderTokens.Space.page)

            PickerRow(title: L10n.t("Biểu tượng thanh menu"),
                      selection: Binding(get: { menubarIcon }, set: { setMenubarIcon($0) }),
                      width: 80) {
                ForEach(MenubarController.iconChoices, id: \.id) { c in
                    Image(systemName: c.symbol).tag(c.id)
                }
            }
            .padding(.horizontal, XFinderTokens.Space.page)

            Divider().padding(.horizontal, XFinderTokens.Space.page)

            ToggleRow(title: L10n.t("Khởi động XFinder khi đăng nhập"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { LoginItemController.apply($0) }
                .padding(.horizontal, XFinderTokens.Space.page)

            Divider().padding(.horizontal, XFinderTokens.Space.page)

            ToggleRow(title: L10n.t("Hiện biểu tượng trong Dock"),
                      subtitle: L10n.t("Tắt để dùng XFinder thuần menubar."),
                      isOn: $showDockIcon)
                .onChange(of: showDockIcon) { DockController.apply($0) }
                .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    // MARK: Checklist

    private var checklist: some View {
        VStack(spacing: 0) {
            StatusChecklistRow(
                state: trusted ? .ok : .warning,
                title: L10n.t("Trợ năng (cửa sổ, Dock, độ sáng)"),
                status: trusted ? L10n.t("Đã cấp") : L10n.t("Chưa cấp"),
                actionTitle: trusted ? nil : L10n.t("Mở…"),
                action: trusted ? nil : { WindowManager.openAccessibilityPane() })

            StatusChecklistRow(
                state: canRecord ? .ok : .warning,
                title: L10n.t("Ghi màn hình (ảnh thu nhỏ cửa sổ)"),
                status: canRecord ? L10n.t("Đã cấp") : L10n.t("Chưa cấp"),
                actionTitle: canRecord ? nil : L10n.t("Mở…"),
                action: canRecord ? nil : { WindowManager.openScreenRecordingPane() })

            StatusChecklistRow(
                state: automationOK ? .ok : .warning,
                title: L10n.t("Tự động hóa (đổi giao diện Sáng/Tối)"),
                status: automationOK ? L10n.t("Đã cấp") : L10n.t("Chưa xác định"),
                actionTitle: automationOK ? nil : L10n.t("Mở…"),
                action: automationOK ? nil : { SystemControls.openAutomationPane() })

            // Hover preview needs BOTH the toggle and Screen Recording: the
            // thumbnails come from ScreenCaptureKit. Reporting L10n.t("Đã bật") while
            // the permission is missing would be a lie — the panel would open
            // with blank boxes, which is exactly the bug the user reported.
            StatusChecklistRow(
                state: hoverEnabled ? (canRecord ? .ok : .warning) : .neutral,
                title: L10n.t("Xem trước cửa sổ từ Dock"),
                status: !hoverEnabled ? L10n.t("Đang tắt")
                    : (canRecord ? L10n.t("Đã bật") : L10n.t("Thiếu quyền Ghi màn hình")),
                actionTitle: L10n.t("Mở…"),
                action: { appState.navigate(to: .windowPreview) })

            StatusChecklistRow(
                state: .ok,
                title: L10n.t("Quick Look nâng cao"),
                status: L10n.t("Đã sẵn sàng"),
                actionTitle: L10n.t("Mở…"),
                action: { appState.navigate(to: .quickLookPage) })

            StatusChecklistRow(
                state: mediaPreviewInstalled ? .ok : .warning,
                title: L10n.t("Xem trước media"),
                status: mediaPreviewInstalled ? L10n.t("Đã cài")
                    : L10n.t("Chưa cài — tải trong trang Quick Look"),
                actionTitle: L10n.t("Mở…"),
                action: { appState.navigate(to: .quickLookPage) })

            StatusChecklistRow(
                state: appleIntelligence ? .ok : .neutral,
                title: L10n.t("Apple Intelligence"),
                status: appleIntelligence ? L10n.t("Sẵn sàng") : L10n.t("Chưa sẵn sàng"),
                actionTitle: nil,
                action: nil)

            // Đã đóng gói XFinderSync.appex — trạng thái thật lấy từ pluginkit.
            StatusChecklistRow(
                state: finderSyncOn ? .ok : .warning,
                title: L10n.t("Tác vụ nhanh trong Finder"),
                status: finderSyncOn ? L10n.t("Đã bật") : L10n.t("Đang tắt"),
                actionTitle: L10n.t("Mở…"),
                action: { _ = WindowManager.openFinderExtensionsPane() })

            StatusChecklistRow(
                state: clipboardManager.history.isEmpty ? .neutral : .ok,
                title: L10n.t("Clipboard"),
                status: clipboardManager.history.isEmpty
                    ? L10n.t("Chưa có mục") : "\(clipboardManager.history.count) " + L10n.t("mục"),
                actionTitle: L10n.t("Mở…"),
                action: { ClipboardShelfController.shared.toggle() })

            StatusChecklistRow(
                state: edgeNotesEnabled ? .ok : .neutral,
                title: L10n.t("Ghi chú ở mép màn hình"),
                status: edgeNotesEnabled ? L10n.t("Đã bật") : L10n.t("Đang tắt"),
                actionTitle: L10n.t("Mở…"),
                action: { appState.navigate(to: .notes) })

            StatusChecklistRow(
                state: CaffeineController.shared.isActive ? .ok : .neutral,
                title: L10n.t("Chống ngủ"),
                status: CaffeineController.shared.isActive ? L10n.t("Đang bật") : L10n.t("Đang tắt"),
                actionTitle: L10n.t("Mở…"),
                action: { appState.navigate(to: .antiSleep) })
        }
        .padding(.horizontal, XFinderTokens.Space.page)
    }

    // MARK: Getting started

    private var gettingStarted: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            SectionHeader(icon: "flag.checkered", title: L10n.t("Bắt đầu"))
            shortcutLine("⌘⇧V", L10n.t("Mở khay Clipboard nổi ở bất kỳ đâu"))
            shortcutLine("⌘⇧C", L10n.t("Bắt đầu Paste Stack"))
            shortcutLine("⌃⌥ ←→↑↓", L10n.t("Bắt dính cửa sổ đang focus"))
            shortcutLine("⌘⇥", L10n.t("Chuyển cửa sổ kèm ảnh xem trước"))
            Text(L10n.t("Di chuột lên icon app trên Dock để xem trước cửa sổ; lắc chuột khi kéo file hoặc trỏ vào tai thỏ để mở Khay thả."))
                .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                .padding(.horizontal, XFinderTokens.Space.page)
            HStack(spacing: 8) {
                Button(L10n.t("Tính năng & Quyền…")) { appState.navigate(to: .features) }
                    .buttonStyle(.bordered).controlSize(.small)
                Button(L10n.t("Kiểm tra lại quyền")) { refreshPermissions() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, XFinderTokens.Space.page)
            .padding(.top, 4)
        }
    }

    private func shortcutLine(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(XFinderTokens.Font.mono)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge).fill(XFinderTokens.Fill.inset))
            Text(label).font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, XFinderTokens.Space.page)
    }

    /// Accessibility and Screen Recording expose real preflight checks.
    /// Automation has none — asking would trigger a permission prompt — so it
    /// is inferred from whether an appearance change has ever succeeded.
    private func refreshPermissions() {
        trusted = WindowManager.isTrusted
        canRecord = WindowManager.canRecordScreen
        automationOK = UserDefaults.standard.bool(forKey: "general.automationVerified")
        Task.detached {
            let media = Self.pluginkitLists(bundleFragment: "QuickLookVideo")
            let ai = Self.appleIntelligenceDownloaded()
            let bundleID = Bundle.main.bundleIdentifier ?? "com.xfinder.app"
            let finderSync = Self.pluginkitLists(bundleFragment: bundleID, pluginType: "com.apple.FinderSync")
            await MainActor.run {
                self.mediaPreviewInstalled = media
                self.appleIntelligence = ai
                self.finderSyncOn = finderSync
            }
        }
    }

    /// Trạng thái thật từ `pluginkit -m` (không có "✓" cứng).
    nonisolated private static func pluginkitLists(bundleFragment: String, pluginType: String? = nil) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        p.arguments = ["-m"] + (pluginType.map { ["-p", $0] } ?? [])
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        return out.contains(bundleFragment)
    }

    /// Apple Intelligence không có API kiểm tra công khai — heuristic trung
    /// thực: model on-device phát hành qua MobileAsset; thư mục asset trống
    /// nghĩa là chưa tải/chưa bật.
    nonisolated private static func appleIntelligenceDownloaded() -> Bool {
        let paths = [
            NSHomeDirectory() + "/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_GenerativeExperiences",
            "/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_GenerativeExperiences",
        ]
        for path in paths {
            if let sub = try? FileManager.default.subpaths(atPath: path), !sub.isEmpty {
                return true
            }
        }
        return false
    }
}

/// Login item registration. `SMAppService` is macOS 13+; the 12.0 deployment
/// target falls back to the (deprecated but functional) shared file list API.
enum LoginItemController {
    static func apply(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("XFinder: login item change failed — \(error.localizedDescription)")
            }
        } else {
            guard let bundleID = Bundle.main.bundleIdentifier else { return }
            SMLoginItemSetEnabled(bundleID as CFString, enabled)
        }
    }
}
