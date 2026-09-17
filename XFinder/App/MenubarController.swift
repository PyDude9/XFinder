import AppKit
import SwiftUI

class MenubarController: NSObject, NSPopoverDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var monitor: Any?

    func setup() {
        let statusBar = NSStatusBar.system
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        applyIcon()
        setupPopover()
    }

    /// Các lựa chọn biểu tượng menubar (monochrome, SF Symbols kiểu macOS).
    static let iconChoices: [(id: String, symbol: String, title: String)] = [
        ("magnifier", "magnifyingglass", "Kính lúp"),
        ("folder", "folder.fill", "Thư mục"),
        ("stack", "rectangle.stack.fill", "Chồng lớp"),
    ]

    func applyIcon() {
        let raw = UserDefaults.standard.string(forKey: "menubar.icon") ?? "magnifier"
        let symbol = Self.iconChoices.first(where: { $0.id == raw })?.symbol ?? "magnifyingglass"
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "XFinder") else { return }
        // Màu (xanh accent) thay vì trắng đơn sắc — để thấy rõ "logo", không còn
        // icon trắng trơn như trước.
        let colored = base.withSymbolConfiguration(
            NSImage.SymbolConfiguration(paletteColors: [.systemBlue])) ?? base
        colored.isTemplate = false
        statusItem?.button?.image = colored
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 340, height: 500)
        popover?.behavior = .transient
        popover?.animates = true
        popover?.delegate = self

        let menubarView = MenubarFlyoutView()
        let hostingController = NSHostingController(rootView: menubarView)
        popover?.contentViewController = hostingController
    }

    // NSPopoverDelegate — clean up the global click monitor when transient
    // dismiss fires (click outside). Without this the monitor leaked.
    func popoverDidClose(_ notification: Notification) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        } else if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Fallback for cases where .transient doesn't fire (e.g. click on
            // a non-key window behind the popover) — mirror ClipboardShelf's
            // global+local monitor pattern.
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self, self.popover?.isShown == true else { return }
                self.popover?.performClose(nil)
                if let m = self.monitor { NSEvent.removeMonitor(m) }
                self.monitor = nil
            }
        }
    }
}
/// Menubar flyout — tabbed layout matching the reference screenshots: a row of
/// section icons under the app name, the selected section's live content, then
/// a fixed action list and footer.
struct MenubarFlyoutView: View {
    @State private var systemMonitor = SystemMonitorManager.shared
    @State private var appState = AppState.shared
    @State private var caffeine = CaffeineController.shared
    @State private var volumeObserver = VolumeObserver.shared
    @State private var noteStore = NoteStore.shared
    @State private var tab: FlyoutTab = .controls
    @AppStorage("menubar.showBattery") private var showBattery = true
    @AppStorage("menubar.showNetwork") private var showNetwork = true
    @AppStorage("notes.edgeEnabled") private var edgeNotesEnabled = false

    enum FlyoutTab: String, CaseIterable, Identifiable {
        case controls, antiSleep, system, network, storage, battery, notes
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .controls:  return "slider.horizontal.3"
            case .antiSleep: return "moon.zzz"
            case .system:    return "cpu"
            case .network:   return "globe"
            case .storage:   return "internaldrive"
            case .battery:   return "battery.100"
            case .notes:     return "note.text"
            }
        }
        var titleVI: String {
            switch self {
            case .controls:  return "Điều khiển"
            case .antiSleep: return "Chống ngủ"
            case .system:    return "Hệ thống"
            case .network:   return "Mạng"
            case .storage:   return "Ổ đĩa"
            case .battery:   return "Pin"
            case .notes:     return "Ghi chú"
            }
        }
        var destination: SidebarDestination {
            switch self {
            case .controls:  return .quickControls
            case .antiSleep: return .antiSleep
            case .system:    return .system
            case .network:   return .network
            case .storage:   return .storage
            case .battery:   return .pin
            case .notes:     return .notes
            }
        }
    }

    private var visibleTabs: [FlyoutTab] {
        FlyoutTab.allCases.filter {
            ($0 != .battery || showBattery) && ($0 != .network || showNetwork)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabStrip
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader
                    content
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 420)

            Divider()
            actionList
            Divider()
            footer
        }
        .frame(width: 340)
        .onAppear {
            volumeObserver.retain()
            systemMonitor.retain()
        }
        .onDisappear {
            volumeObserver.release()
            systemMonitor.release()
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.2x2.fill")
                .foregroundColor(.accentColor)
            Text("XFinder").font(.system(size: 15, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
    }

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ForEach(visibleTabs) { t in
                Button { tab = t } label: {
                    Image(systemName: t.icon)
                        .font(.system(size: 13))
                        .frame(width: 34, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(tab == t ? Color.accentColor : Color.clear))
                        .foregroundColor(tab == t ? .white : .primary)
                }
                .buttonStyle(.plain)
                .help(t.titleVI)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.bottom, 10)
    }

    private var sectionHeader: some View {
        HStack {
            Text(tab.titleVI).font(.system(size: 14, weight: .semibold))
            Spacer()
            Button { navigate(tab.destination) } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Mở trang \(tab.titleVI)")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .controls:  controlsSection
        case .antiSleep: antiSleepSection
        case .system:    systemSection
        case .network:   networkSection
        case .storage:   storageSection
        case .battery:   batterySection
        case .notes:     notesSection
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { volumeObserver.toggleMute() } label: {
                    Image(systemName: volumeObserver.isMuted || volumeObserver.volume == 0
                          ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundColor(volumeObserver.isMuted ? .red : .accentColor)
                }
                .buttonStyle(.plain)
                Slider(value: Binding(get: { volumeObserver.volume },
                                      set: { volumeObserver.setVolume($0) }), in: 0...1)
                Text("\(Int(volumeObserver.volume * 100))%")
                    .font(.system(size: 11, design: .monospaced)).frame(width: 34)
            }

            flyoutToggle("Chống ngủ", "moon.zzz", isOn: Binding(
                get: { caffeine.isActive },
                set: { $0 ? caffeine.activate(duration: .indefinite) : caffeine.deactivate() }))

            flyoutToggle("Chế độ tối", "circle.lefthalf.filled", isOn: Binding(
                get: { SystemControls.isDarkMode() },
                set: { on in Task { await SystemControls.setAppearance(on ? .dark : .light) } }))

            flyoutToggle("Tắt tiếng", "speaker.slash", isOn: Binding(
                get: { volumeObserver.isMuted },
                set: { _ in volumeObserver.toggleMute() }))

            Divider()
            Text("Cửa sổ").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)

            flyoutToggle("Xem trước Dock", "macwindow.on.rectangle", isOn: Binding(
                get: { UserDefaults.standard.object(forKey: "windowPreview.hoverEnabled") as? Bool ?? true },
                set: { on in
                    UserDefaults.standard.set(on, forKey: "windowPreview.hoverEnabled")
                    DockPreviewController.shared.applySettings()
                }))

            flyoutToggle("Chuyển đổi ứng dụng", "square.on.square", isOn: Binding(
                get: { UserDefaults.standard.object(forKey: "windowPreview.commandTabEnabled") as? Bool ?? false },
                set: { on in
                    UserDefaults.standard.set(on, forKey: "windowPreview.commandTabEnabled")
                    CommandTabController.shared.applySettings()
                }))
        }
    }

    private var antiSleepSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            flyoutToggle("Chống ngủ", "moon.zzz", isOn: Binding(
                get: { caffeine.isActive },
                set: { $0 ? caffeine.activate(duration: .indefinite) : caffeine.deactivate() }))
            Text(caffeine.isActive
                 ? "Máy Mac sẽ không tự ngủ."
                 : "Máy Mac tuân theo cài đặt năng lượng thông thường.")
                .font(.system(size: 11)).foregroundColor(.secondary)
            if let remaining = caffeine.remainingSeconds {
                infoRow("Còn lại", "\(remaining / 60) phút")
            }
        }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                tempCell("CPU")
                Divider().frame(height: 34)
                tempCell("GPU")
            }
            meter("CPU", systemMonitor.currentMetrics.cpuUsage, .blue)
            // GPU load has no public API — show the honest placeholder.
            meter("GPU", nil, .teal)
            infoRow("Bộ nhớ", "\(systemMonitor.currentMetrics.memoryUsedString) / \(systemMonitor.currentMetrics.memoryTotalString)")
            infoRow("Áp lực bộ nhớ", systemMonitor.currentMetrics.thermalState.label)
            infoRow("Thời gian hoạt động", systemMonitor.currentMetrics.uptimeString)
        }
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                rateCell("Tải xuống", systemMonitor.currentMetrics.networkDownload, .blue, "arrow.down")
                Divider().frame(height: 34)
                rateCell("Tải lên", systemMonitor.currentMetrics.networkUpload, .green, "arrow.up")
            }
            infoRow("Phiên này",
                    "↓\(fmtBytes(systemMonitor.sessionBytesRX))  ↑\(fmtBytes(systemMonitor.sessionBytesTX))")
            Button("Đo tốc độ") { navigate(.network) }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            infoRow("Dung lượng",
                    "\(systemMonitor.currentMetrics.diskUsedString) / \(systemMonitor.currentMetrics.diskTotalString)")
            meter("Đã dùng", systemMonitor.currentMetrics.diskPercentage, .purple)
            // SMART attributes are not exposed by any public API.
            infoRow("SMART", "Không khả dụng")
        }
    }

    private var batterySection: some View {
        let m = systemMonitor.currentMetrics
        return VStack(alignment: .leading, spacing: 8) {
            if m.batteryLevel > 0 {
                meter("Pin", m.batteryLevel, m.batteryLevel < 20 ? .red : .green)
                infoRow("Trạng thái", m.isCharging ? "Đang sạc" : m.batteryTimeString)
            } else {
                Text("Không có pin").font(.system(size: 12)).foregroundColor(.secondary)
            }
            // Battery temperature needs SMC access — no public API.
            infoRow("Nhiệt độ pin", "Đang thu thập…")
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // These act on the screen-edge panel — that is where notes live.
            // Both used to just open the Settings page, which did nothing useful.
            actionRow("Ghi chú mới", "square.and.pencil") {
                closePopover()
                EdgeNotesController.shared.createNote()
            }
            actionRow("Tất cả ghi chú", "note.text") {
                closePopover()
                EdgeNotesController.shared.revealAll()
            }
            Text("\(noteStore.notes.filter { !$0.isArchived }.count) ghi chú đang dùng")
                .font(.system(size: 11)).foregroundColor(.secondary)
            if !edgeNotesEnabled {
                Text("Bật “Ghi chú ở mép màn hình” trong Cài đặt để dùng.")
                    .font(.system(size: 11)).foregroundColor(.orange)
            }
        }
    }

    // MARK: Fixed lists

    private var actionList: some View {
        VStack(spacing: 0) {
            actionRow("Lịch sử thao tác", "clock.arrow.circlepath") { navigate(.actionHistory) }
            actionRow("Khay thả…", "tray.and.arrow.down") { navigate(.dropTray) }
            actionRow("Đồng bộ thư mục", "arrow.triangle.2.circlepath") { navigate(.sync) }
            HStack {
                Image(systemName: "magnifyingglass").frame(width: 18).foregroundColor(.secondary)
                Text("Tìm file…").font(.system(size: 12))
                Spacer()
                Text("⌘⇧V").font(.system(size: 11)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { navigate(.finderSearch) }
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            // "Cài đặt chung" no longer exists; Điều khiển nhanh is the page
            // that actually holds the app-level switches.
            Button { navigate(.quickControls) } label: {
                Label("Cài đặt XFinder", systemImage: "gearshape")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.small)

            Button { quit() } label: {
                Label("Thoát", systemImage: "power")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(12)
    }

    // MARK: Small builders

    private func flyoutToggle(_ title: String, _ icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 18).foregroundColor(.secondary)
            Text(title).font(.system(size: 12))
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().controlSize(.mini)
        }
    }

    private func actionRow(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 18).foregroundColor(.secondary)
                Text(title).font(.system(size: 12))
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium))
        }
    }

    private func meter(_ label: String, _ percent: Double?, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 12))
                Spacer()
                Text(percent.map { String(format: "%.0f%%", $0) } ?? "Không khả dụng")
                    .font(.system(size: 12, weight: percent == nil ? .regular : .semibold))
                    .foregroundColor(percent == nil ? .secondary : .primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    if let percent {
                        Capsule().fill(tint)
                            .frame(width: geo.size.width * min(max(percent / 100, 0), 1))
                    }
                }
            }
            .frame(height: 5)
        }
    }

    /// CPU/GPU die temperature needs SMC access, which has no public API.
    private func tempCell(_ title: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundColor(.secondary)
            Text("Đang thu thập…").font(.system(size: 12)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func rateCell(_ label: String, _ kbs: Double, _ tint: Color, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(tint).font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(kbs >= 1024 ? String(format: "%.1f MB/s", kbs / 1024)
                                 : String(format: "%.0f KB/s", kbs))
                    .font(.system(size: 12, weight: .semibold))
                Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func fmtBytes(_ b: UInt64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .binary
        return f.string(fromByteCount: Int64(b))
    }


    /// Deep-link: set the sidebar destination, front the main window, close the popover.
    private func navigate(_ destination: SidebarDestination) {
        appState.navigate(to: destination)
        closePopover()
    }

    private func closePopover() {
        (NSApplication.shared.delegate as? AppDelegate)?.menubarController?.popover?.performClose(nil)
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

struct SystemInfoRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

#Preview {
    MenubarFlyoutView()
}
