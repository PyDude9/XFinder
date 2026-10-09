import AppKit
import SwiftUI

@MainActor
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
        VoiceManager.shared.onStateChange = { [weak self] state in
            self?.updateVoiceState(state)
        }
    }

    private func updateVoiceState(_ state: VoiceState) {
        guard let button = statusItem?.button else { return }
        switch state {
        case .idle:
            applyIcon()
        case .listening(let rms):
            let symbolName = rms > 0.5 ? "waveform.badge.mic" : "mic.fill"
            let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Listening")
            let colored = base?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [.systemRed, .systemOrange])
            ) ?? base
            colored?.isTemplate = false
            button.image = colored
        case .processing:
            let base = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Processing")
            let colored = base?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [.systemBlue])
            ) ?? base
            colored?.isTemplate = false
            button.image = colored
        case .reviewing:
            let base = NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: "Review")
            let colored = base?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
            ) ?? base
            colored?.isTemplate = false
            button.image = colored
        case .error:
            let base = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error")
            let colored = base?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            ) ?? base
            colored?.isTemplate = false
            button.image = colored
        }
    }

    /// Các lựa chọn biểu tượng menubar (monochrome, SF Symbols kiểu macOS).
    static let iconChoices: [(id: String, symbol: String, title: String)] = [
        ("magnifier", "magnifyingglass", L10n.t("Kính lúp")),
        ("folder", "folder.fill", L10n.t("Thư mục")),
        ("stack", "rectangle.stack.fill", L10n.t("Chồng lớp")),
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
    @State private var audioOutputs = AudioOutputDevices.shared
    @State private var noteStore = NoteStore.shared
    @State private var batteryStore = BatteryStore.shared
    /// Raw `diskutil` SMART value for `/`, e.g. "Verified"; nil until checked or when unreadable.
    @State private var smartRaw: String? = nil
    @State private var smartChecked = false
    @ObservedObject private var permissionManager = PermissionManager.shared
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
            case .controls:  return L10n.t("Điều khiển")
            case .antiSleep: return L10n.t("Chống ngủ")
            case .system:    return L10n.t("Hệ thống")
            case .network:   return L10n.t("Mạng")
            case .storage:   return L10n.t("Ổ đĩa")
            case .battery:   return L10n.t("Pin")
            case .notes:     return L10n.t("Ghi chú")
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
            if !permissionManager.isAccessibilityGranted {
                accessibilityBanner
            }
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
        // One `diskutil info /` per flyout appearance — a subprocess, so never on the metrics
        // tick. `.task` cancels when the popover closes; the result is not bound to a timer.
        .task {
            // The popover's hosting controller lives for the whole app, so @State survives
            // close/reopen. Clear the old value FIRST or the row keeps showing the previous
            // answer with full confidence while the new diskutil run is in flight — the
            // "Đang kiểm tra…" branch was dead code from the second open onward.
            smartRaw = nil
            smartChecked = false
            smartRaw = await DiskManager.smartStatus(forMount: "/")
            smartChecked = true
        }
        .onAppear {
            volumeObserver.retain()
            audioOutputs.retain()
            systemMonitor.retain()
            batteryStore.retain()
        }
        .onDisappear {
            volumeObserver.release()
            audioOutputs.release()
            systemMonitor.release()
            batteryStore.release()
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

    private var accessibilityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 13))
            Text(L10n.t("XFinder cần quyền Trợ năng để nhận cử chỉ"))
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(2)
            Spacer()
            Button(L10n.t("Mở Cài đặt")) {
                PermissionManager.shared.openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
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
            .help(L10n.t("Mở trang ") + tab.titleVI)
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

            // Only when there is something to choose; the flyout's space is precious.
            if audioOutputs.devices.count > 1 {
                Menu {
                    ForEach(audioOutputs.devices) { d in
                        Button {
                            audioOutputs.select(d)
                        } label: {
                            Label(d.name, systemImage: d.id == audioOutputs.currentID ? "checkmark" : d.symbol)
                        }
                    }
                } label: {
                    Label(audioOutputs.current?.name ?? L10n.t("Âm thanh ra"),
                          systemImage: audioOutputs.current?.symbol ?? "speaker.wave.2")
                        .font(.system(size: 12))
                        .lineLimit(1).truncationMode(.middle)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            flyoutToggle(L10n.t("Chống ngủ"), "moon.zzz", isOn: Binding(
                get: { caffeine.isActive },
                set: { $0 ? caffeine.activate(duration: .indefinite) : caffeine.deactivate() }))

            flyoutToggle(L10n.t("Chế độ tối"), "circle.lefthalf.filled", isOn: Binding(
                get: { SystemControls.isDarkMode() },
                set: { on in Task { await SystemControls.setAppearance(on ? .dark : .light) } }))

            flyoutToggle(L10n.t("Tắt tiếng"), "speaker.slash", isOn: Binding(
                get: { volumeObserver.isMuted },
                set: { _ in volumeObserver.toggleMute() }))

            Divider()
            Text(L10n.t("Cửa sổ")).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)

            flyoutToggle(L10n.t("Xem trước Dock"), "macwindow.on.rectangle", isOn: Binding(
                get: { UserDefaults.standard.object(forKey: "windowPreview.hoverEnabled") as? Bool ?? true },
                set: { on in
                    UserDefaults.standard.set(on, forKey: "windowPreview.hoverEnabled")
                    DockPreviewController.shared.applySettings()
                }))

            flyoutToggle(L10n.t("Chuyển đổi ứng dụng"), "square.on.square", isOn: Binding(
                get: { UserDefaults.standard.object(forKey: "windowPreview.commandTabEnabled") as? Bool ?? false },
                set: { on in
                    UserDefaults.standard.set(on, forKey: "windowPreview.commandTabEnabled")
                    CommandTabController.shared.applySettings()
                }))
        }
    }

    private var antiSleepSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            flyoutToggle(L10n.t("Chống ngủ"), "moon.zzz", isOn: Binding(
                get: { caffeine.isActive },
                set: { $0 ? caffeine.activate(duration: .indefinite) : caffeine.deactivate() }))
            Text(caffeine.isActive
                 ? L10n.t("Máy Mac sẽ không tự ngủ.")
                 : L10n.t("Máy Mac tuân theo cài đặt năng lượng thông thường."))
                .font(.system(size: 11)).foregroundColor(.secondary)
            if let remaining = caffeine.remainingSeconds {
                infoRow(L10n.t("Còn lại"), String(remaining / 60) + L10n.t(" phút"))
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
            // GPU load from the IORegistry (public, load-tracking — see GPUUtilization);
            // nil on hardware that does not publish it ⇒ the placeholder.
            meter("GPU", systemMonitor.currentMetrics.gpuUsage, .teal)
            infoRow(L10n.t("Bộ nhớ"), "\(systemMonitor.currentMetrics.memoryUsedString) / \(systemMonitor.currentMetrics.memoryTotalString)")
            infoRow(L10n.t("Áp lực bộ nhớ"), systemMonitor.currentMetrics.thermalState.label)
            infoRow(L10n.t("Thời gian hoạt động"), systemMonitor.currentMetrics.uptimeString)
        }
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                rateCell(L10n.t("Tải xuống"), systemMonitor.currentMetrics.networkDownload, .blue, "arrow.down")
                Divider().frame(height: 34)
                rateCell(L10n.t("Tải lên"), systemMonitor.currentMetrics.networkUpload, .green, "arrow.up")
            }
            infoRow(L10n.t("Phiên này"),
                    "↓\(fmtBytes(systemMonitor.sessionBytesRX))  ↑\(fmtBytes(systemMonitor.sessionBytesTX))")
            Button(L10n.t("Đo tốc độ")) { navigate(.network) }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            infoRow(L10n.t("Dung lượng"),
                    "\(systemMonitor.currentMetrics.diskUsedString) / \(systemMonitor.currentMetrics.diskTotalString)")
            meter(L10n.t("Đã dùng"), systemMonitor.currentMetrics.diskPercentage, .purple)
            // SMART *status* IS public (`diskutil info /`), and the Ổ đĩa page already shows
            // it. This row said "Không khả dụng" until 2026-10-09 — two surfaces, two answers.
            // Same reader, same key mapper (SMARTStatus), boot volume only (no picker here).
            smartRow
        }
    }

    /// SMART status of the boot volume, fetched once per flyout appearance (see `.task` on
    /// the root). Only the attribute table is unavailable; that is not what this row claims.
    private var smartRow: some View {
        HStack {
            Text(L10n.t("SMART ổ khởi động")).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
            if let raw = smartRaw {
                let label = SMARTStatus.label(forRaw: raw)
                Text(L10n.t(label.key))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(label.healthy == false ? .red : .primary)
            } else if smartChecked {
                Text(L10n.t("Không đọc được trạng thái SMART của ổ này"))
                    .font(.system(size: 12)).foregroundColor(.secondary)
            } else {
                Text(L10n.t("Đang kiểm tra…"))
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
    }

    private var batterySection: some View {
        let m = systemMonitor.currentMetrics
        return VStack(alignment: .leading, spacing: 8) {
            AirBatteryListView(showDisconnectedToggle: false)

            if m.batteryLevel > 0 {
                Divider().padding(.vertical, 2)
                infoRow(L10n.t("Trạng thái"), m.isCharging ? L10n.t("Đang sạc") : m.batteryTimeString)
                // Battery temperature needs SMC access — no public API.
                infoRow(L10n.t("Nhiệt độ pin"), L10n.t("Đang thu thập…"))
            } else if batteryStore.allDevices.isEmpty {
                Text(L10n.t("Không có pin")).font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // These act on the screen-edge panel — that is where notes live.
            // Both used to just open the Settings page, which did nothing useful.
            actionRow(L10n.t("Ghi chú mới"), "square.and.pencil") {
                closePopover()
                EdgeNotesController.shared.createNote()
            }
            actionRow(L10n.t("Tất cả ghi chú"), "note.text") {
                closePopover()
                EdgeNotesController.shared.revealAll()
            }
            Text(L10n.t("\(noteStore.notes.filter { !$0.isArchived }.count) ghi chú đang dùng"))
                .font(.system(size: 11)).foregroundColor(.secondary)
            if !edgeNotesEnabled {
                Text(L10n.t("Bật “Ghi chú ở mép màn hình” trong Cài đặt để dùng."))
                    .font(.system(size: 11)).foregroundColor(.orange)
            }
        }
    }

    // MARK: Fixed lists

    private var actionList: some View {
        VStack(spacing: 0) {
            actionRow(L10n.t("Lịch sử thao tác"), "clock.arrow.circlepath") { navigate(.actionHistory) }
            actionRow(L10n.t("Khay thả…"), "tray.and.arrow.down") { navigate(.dropTray) }
            actionRow(L10n.t("Lấy màu từ màn hình"), "eyedropper") {
                // The popover would cover the pixels being picked; let it close first.
                closePopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ScreenColorPicker.shared.pick() }
            }
            actionRow(L10n.t("Đồng bộ thư mục"), "arrow.triangle.2.circlepath") { navigate(.sync) }
            HStack {
                Image(systemName: "magnifyingglass").frame(width: 18).foregroundColor(.secondary)
                Text(L10n.t("Tìm file…")).font(.system(size: 12))
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
                Label(L10n.t("Cài đặt XFinder"), systemImage: "gearshape")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.small)

            Button { quit() } label: {
                Label(L10n.t("Thoát"), systemImage: "power")
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
                Text(percent.map { String(format: "%.0f%%", $0) } ?? L10n.t("Không khả dụng"))
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
            Text(L10n.t("Đang thu thập…")).font(.system(size: 12)).foregroundColor(.secondary)
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
