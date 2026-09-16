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

    @State private var trusted = WindowManager.isTrusted
    @State private var canRecord = WindowManager.canRecordScreen
    @State private var automationOK = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(icon: "square.grid.2x2",
                           title: L10n.t("Tổng quan"),
                           subtitle: L10n.t("Xem những gì đã sẵn sàng và hoàn tất thiết lập."))

                preferences
                Divider().padding(.horizontal, 20)
                checklist
                Divider().padding(.horizontal, 20)
                gettingStarted
            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
        // Only sample metrics while a page that shows them is on screen.
        .onAppear { SystemMonitorManager.shared.retain() }
        .onDisappear { SystemMonitorManager.shared.release() }
        .onAppear { refreshPermissions() }
    }

    // MARK: Preferences

    private var preferences: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "globe").foregroundColor(.secondary).frame(width: 20)
                Text(L10n.t("Ngôn ngữ ứng dụng")).font(.system(size: 13))
                Spacer()
                Picker("", selection: Binding(get: { l10n.language },
                                               set: { l10n.set($0) })) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 140)
            }
            .padding(.vertical, 8)

            Divider()

            ToggleRow(title: L10n.t("Khởi động XFinder khi đăng nhập"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { LoginItemController.apply($0) }
                .padding(.vertical, 4)

            Divider()

            ToggleRow(title: L10n.t("Hiện biểu tượng trong Dock"),
                      subtitle: L10n.t("Tắt để dùng XFinder thuần menubar."),
                      isOn: $showDockIcon)
                .onChange(of: showDockIcon) { DockController.apply($0) }
                .padding(.vertical, 4)
        }
        .padding(.horizontal, 20)
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

            // Honest: Finder context-menu items and Quick Actions need a Finder
            // Sync/Action extension target this app does not ship.
            StatusChecklistRow(
                state: .warning,
                title: L10n.t("Tác vụ nhanh trong Finder"),
                status: L10n.t("Chưa có"),
                actionTitle: L10n.t("Mở…"),
                action: { appState.navigate(to: .finderUtils) })

            StatusChecklistRow(
                state: clipboardManager.history.isEmpty ? .neutral : .ok,
                title: L10n.t("Clipboard"),
                status: clipboardManager.history.isEmpty
                    ? L10n.t("Chưa có mục") : "\(clipboardManager.history.count) mục",
                actionTitle: L10n.t("Mở…"),
                action: { appState.navigate(to: .clipboard) })

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
        .padding(.horizontal, 20)
    }

    // MARK: Getting started

    private var gettingStarted: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("Bắt đầu")).font(.system(size: 14, weight: .semibold))
            shortcutLine("⌘⇧V", L10n.t("Mở khay Clipboard nổi ở bất kỳ đâu"))
            shortcutLine("⌘⇧C", L10n.t("Bắt đầu Paste Stack"))
            shortcutLine("⌃⌥ ←→↑↓", L10n.t("Bắt dính cửa sổ đang focus"))
            shortcutLine("⌘⇥", L10n.t("Chuyển cửa sổ kèm ảnh xem trước"))
            Text(L10n.t("Di chuột lên icon app trên Dock để xem trước cửa sổ; lắc chuột khi kéo file hoặc trỏ vào tai thỏ để mở Khay thả."))
                .font(.system(size: 12)).foregroundColor(.secondary)
            HStack(spacing: 8) {
                Button(L10n.t("Điều khiển nhanh…")) { appState.navigate(to: .quickControls) }
                    .buttonStyle(.bordered).controlSize(.small)
                Button(L10n.t("Kiểm tra lại quyền")) { refreshPermissions() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func shortcutLine(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
        }
    }

    /// Accessibility and Screen Recording expose real preflight checks.
    /// Automation has none — asking would trigger a permission prompt — so it
    /// is inferred from whether an appearance change has ever succeeded.
    private func refreshPermissions() {
        trusted = WindowManager.isTrusted
        canRecord = WindowManager.canRecordScreen
        automationOK = UserDefaults.standard.bool(forKey: "general.automationVerified")
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
            SMLoginItemSetEnabled(Bundle.main.bundleIdentifier! as CFString, enabled)
        }
    }
}
