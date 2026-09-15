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
    @AppStorage("general.colorfulIcon") private var colorfulIcon = false
    @AppStorage("notes.edgeEnabled") private var edgeNotesEnabled = false
    @AppStorage("windowPreview.hoverEnabled") private var hoverEnabled = true

    @State private var trusted = WindowManager.isTrusted
    @State private var canRecord = WindowManager.canRecordScreen
    @State private var automationOK = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(icon: "square.grid.2x2",
                           title: "Tổng quan",
                           subtitle: "Xem những gì đã sẵn sàng và hoàn tất thiết lập.")

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
                Text("Ngôn ngữ ứng dụng").font(.system(size: 13))
                Spacer()
                // The UI ships Vietnamese-only; offering a picker with one real
                // option would be a dead control, so state it plainly instead.
                Text("Tiếng Việt").font(.system(size: 12)).foregroundColor(.secondary)
            }
            .padding(.vertical, 8)

            Divider()

            ToggleRow(title: "Khởi động XFinder khi đăng nhập", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { LoginItemController.apply($0) }
                .padding(.vertical, 4)

            Divider()

            ToggleRow(title: "Hiện biểu tượng trong Dock",
                      subtitle: "Tắt để dùng XFinder thuần menubar.",
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
                title: "Trợ năng (cửa sổ, Dock, độ sáng)",
                status: trusted ? "Đã cấp" : "Chưa cấp",
                actionTitle: trusted ? nil : "Mở…",
                action: trusted ? nil : { WindowManager.openAccessibilityPane() })

            StatusChecklistRow(
                state: canRecord ? .ok : .warning,
                title: "Ghi màn hình (ảnh thu nhỏ cửa sổ)",
                status: canRecord ? "Đã cấp" : "Chưa cấp",
                actionTitle: canRecord ? nil : "Mở…",
                action: canRecord ? nil : { WindowManager.openScreenRecordingPane() })

            StatusChecklistRow(
                state: automationOK ? .ok : .warning,
                title: "Tự động hóa (đổi giao diện Sáng/Tối)",
                status: automationOK ? "Đã cấp" : "Chưa xác định",
                actionTitle: automationOK ? nil : "Mở…",
                action: automationOK ? nil : { SystemControls.openAutomationPane() })

            StatusChecklistRow(
                state: hoverEnabled ? .ok : .neutral,
                title: "Xem trước cửa sổ từ Dock",
                status: hoverEnabled ? "Đã bật" : "Đang tắt",
                actionTitle: "Mở…",
                action: { appState.navigate(to: .windowPreview) })

            StatusChecklistRow(
                state: clipboardManager.history.isEmpty ? .neutral : .ok,
                title: "Clipboard",
                status: clipboardManager.history.isEmpty
                    ? "Chưa có mục" : "\(clipboardManager.history.count) mục",
                actionTitle: "Mở…",
                action: { appState.navigate(to: .clipboard) })

            StatusChecklistRow(
                state: edgeNotesEnabled ? .ok : .neutral,
                title: "Ghi chú ở mép màn hình",
                status: edgeNotesEnabled ? "Đã bật" : "Đang tắt",
                actionTitle: "Mở…",
                action: { appState.navigate(to: .notes) })

            StatusChecklistRow(
                state: CaffeineController.shared.isActive ? .ok : .neutral,
                title: "Chống ngủ",
                status: CaffeineController.shared.isActive ? "Đang bật" : "Đang tắt",
                actionTitle: "Mở…",
                action: { appState.navigate(to: .antiSleep) })
        }
        .padding(.horizontal, 20)
    }

    // MARK: Getting started

    private var gettingStarted: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bắt đầu").font(.system(size: 14, weight: .semibold))
            shortcutLine("⌘⇧V", "Mở khay Clipboard nổi ở bất kỳ đâu")
            shortcutLine("⌘⇧C", "Bắt đầu Paste Stack")
            shortcutLine("⌃⌥ ←→↑↓", "Bắt dính cửa sổ đang focus")
            Text("Di chuột lên icon app trên Dock để xem trước cửa sổ; lắc chuột khi kéo file hoặc trỏ vào tai thỏ để mở Khay thả.")
                .font(.system(size: 12)).foregroundColor(.secondary)
            HStack(spacing: 8) {
                Button("Điều khiển nhanh…") { appState.navigate(to: .quickControls) }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Kiểm tra lại quyền") { refreshPermissions() }
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
