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
            MenuBarReadoutsController.shared.attach(button)
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
    @State private var hub = FeatureHub.shared
    @State private var readouts = MenuBarReadoutsController.shared
    /// Groups the user collapsed in the Tính năng tab. Windows starts open, the rest closed.
    @State private var collapsedGroups: Set<FeatureGroup> = [.clipboard, .tools, .voice]
    /// HIDDEN tab ids (see `FlyoutLayout`). Optional: nil = never customised, which is what lets the
    /// two legacy keys (`menubar.showBattery/showNetwork`, no UI ever wrote them) still apply once.
    @AppStorage(FlyoutLayout.key) private var hiddenRaw: String?
    @State private var editingTabs = false
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
            case .controls:  return .features
            case .antiSleep: return .antiSleep
            case .system:    return .system
            case .network:   return .network
            case .storage:   return .storage
            case .battery:   return .pin
            case .notes:     return .notes
            }
        }
    }

    private var hiddenTabs: Set<String> {
        FlyoutLayout.hidden(
            stored: hiddenRaw,
            legacyShowBattery: UserDefaults.standard.object(forKey: "menubar.showBattery") as? Bool,
            legacyShowNetwork: UserDefaults.standard.object(forKey: "menubar.showNetwork") as? Bool)
    }

    private var visibleTabs: [FlyoutTab] {
        let ids = Set(FlyoutLayout.visible(all: FlyoutTab.allCases.map(\.rawValue), hidden: hiddenTabs))
        return FlyoutTab.allCases.filter { ids.contains($0.rawValue) }
    }

    /// The tab actually shown: the selected one, or the first visible if it was just hidden.
    private var shownTab: FlyoutTab {
        let sel = FlyoutLayout.selection(current: tab.rawValue, visible: visibleTabs.map(\.rawValue))
        return FlyoutTab(rawValue: sel) ?? .controls
    }

    private func toggleTabVisibility(_ t: FlyoutTab) {
        hiddenRaw = FlyoutLayout.encode(FlyoutLayout.toggled(
            t.rawValue, all: FlyoutTab.allCases.map(\.rawValue), hidden: hiddenTabs))
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
                    if editingTabs { tabPicker } else { content }
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
            hub.retain()
            systemMonitor.retain()
            batteryStore.retain()
        }
        .onDisappear {
            editingTabs = false   // reopening shows content, not a half-finished editor
            volumeObserver.release()
            audioOutputs.release()
            hub.release()
            systemMonitor.release()
            batteryStore.release()
        }
    }

    // MARK: Chrome

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("XFinder").font(.system(size: 17, weight: .bold))
                    // The pill reports ONE true thing: whether the Mac is being kept awake.
                    if caffeine.isActive {
                        HStack(spacing: 5) {
                            Circle().fill(Color.yellow).frame(width: 7, height: 7)
                            Text(L10n.t("Mac đang được giữ thức"))
                                .font(.system(size: 11, weight: .medium)).foregroundColor(.yellow)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(Color.yellow.opacity(0.14)))
                    }
                }
                Spacer()
            }
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
        HStack(spacing: 2) {
            ForEach(visibleTabs) { t in
                Button { tab = t; editingTabs = false } label: {
                    Image(systemName: t.icon)
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(shownTab == t ? Color.accentColor.opacity(0.28) : Color.clear))
                        .foregroundColor(shownTab == t ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(t.titleVI)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 14).padding(.bottom, 10)
    }

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            Text(editingTabs ? L10n.t("Chọn mục hiển thị") : shownTab.titleVI)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            if editingTabs {
                Button(L10n.t("Xong")) { editingTabs = false }
                    .buttonStyle(.bordered).controlSize(.small)
            } else {
                Button { editingTabs = true } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.t("Chọn mục hiển thị"))
                Button { navigate(shownTab.destination) } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.t("Mở trang ") + shownTab.titleVI)
            }
        }
    }

    /// One switch per tab. The last visible tab's switch is disabled (`FlyoutLayout.canHide`), so
    /// the popover can never be emptied from here.
    private var tabPicker: some View {
        let all = FlyoutTab.allCases.map(\.rawValue)
        let hidden = hiddenTabs
        return VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("Tắt mục nào bạn không cần. Mục đã tắt không hiện trên thanh biểu tượng."))
                .font(.system(size: 11)).foregroundColor(.secondary)
            ForEach(FlyoutTab.allCases) { t in
                let shown = !hidden.contains(t.rawValue)
                HStack(spacing: 10) {
                    Image(systemName: t.icon).frame(width: 20).foregroundColor(.accentColor)
                    Text(t.titleVI).font(.system(size: 13))
                    Spacer()
                    Toggle("", isOn: Binding(get: { shown }, set: { _ in toggleTabVisibility(t) }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                        .disabled(shown && !FlyoutLayout.canHide(t.rawValue, all: all, hidden: hidden))
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
            }
            Divider().padding(.vertical, 4)
            readoutsPicker
        }
    }

    /// Live numbers beside the menu-bar icon. The master switch is the catalogue feature
    /// (`menubar.readoutsEnabled`, via `FeatureHub` like every other feature switch); the set and
    /// the cadence are the controller's own keys.
    private var readoutsPicker: some View {
        let def = FeatureCatalog.def(.menuBarReadouts)
        let on = hub.isOn(def)
        let selected = readouts.selection
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: def.symbol).frame(width: 20).foregroundColor(.accentColor)
                Text(L10n.t("Số liệu trên thanh menu")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("", isOn: Binding(get: { on }, set: { hub.set(.menuBarReadouts, on: $0) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
            if on {
                HStack {
                    Text(L10n.t("Cập nhật mỗi")).font(.system(size: 12))
                    Spacer()
                    Picker("", selection: Binding(get: { readouts.interval }, set: { readouts.interval = $0 })) {
                        ForEach(MenuBarReadouts.intervalChoices, id: \.self) { s in Text("\(s) s").tag(s) }
                    }
                    .pickerStyle(.menu).labelsHidden().frame(width: 80)
                }
                .padding(.horizontal, 10)
                ForEach(MenuBarReadouts.Kind.allCases, id: \.self) { k in
                    HStack(spacing: 10) {
                        Image(systemName: k.symbol).frame(width: 20).foregroundColor(.secondary)
                        Text(L10n.t(k.titleKey)).font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: Binding(get: { selected.contains(k) }, set: { want in
                            var sel = readouts.selection
                            if want { if !sel.contains(k) { sel.append(k) } } else { sel.removeAll { $0 == k } }
                            readouts.selection = sel
                        }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                }
                Text(L10n.t("Mỗi lần cập nhật là một lần đọc số liệu (nhanh hơn khi một trang số liệu đang mở); tắt thì không có bộ hẹn giờ nào."))
                    .font(.system(size: 11)).foregroundColor(.secondary).padding(.horizontal, 10)
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var content: some View {
        switch shownTab {
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
            // The ONE place feature on/off lives in the popover (it was a second tab that repeated
            // two hand-rolled switches). Same keys as the Features hub, via `FeatureHub`.
            featuresSection
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
                tempCell(L10n.t("Nhiệt độ SoC"), systemMonitor.currentMetrics.socTempAverage)
                Divider().frame(height: 34)
                tempCell(L10n.t("Nóng nhất"), systemMonitor.currentMetrics.socTempMax)
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
            Text("\(noteStore.notes.filter { !$0.isArchived }.count)\(L10n.t(" ghi chú đang dùng"))")
                .font(.system(size: 11)).foregroundColor(.secondary)
            if !edgeNotesEnabled {
                Text(L10n.t("Bật “Ghi chú ở mép màn hình” trong Cài đặt để dùng."))
                    .font(.system(size: 11)).foregroundColor(.orange)
            }
        }
    }

    // MARK: Fixed lists

    // MARK: Tính năng tab

    /// Every switchable feature, grouped and collapsible, bound to the SAME keys as the Features hub
    /// and each feature's own page (`FeatureHub`). Counts are n on / N in the group.
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(FeatureGroup.allCases, id: \.self) { group in
                let items = FeatureCatalog.features(in: group)
                let onCount = items.filter { hub.isOn($0) }.count
                let open = !collapsedGroups.contains(group)
                Button {
                    if open { collapsedGroups.insert(group) } else { collapsedGroups.remove(group) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold)).foregroundColor(.secondary).frame(width: 12)
                        Text(L10n.t(group.titleKey).uppercased())
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                        Spacer()
                        Text("\(onCount)/\(items.count)")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.accentColor).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if open {
                    ForEach(items, id: \.id) { f in featureCard(f) }
                }
            }
        }
    }

    private func featureCard(_ f: FeatureDef) -> some View {
        let on = hub.isOn(f)
        return HStack(spacing: 10) {
            Image(systemName: f.symbol)
                .font(.system(size: 16)).foregroundColor(.accentColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(f.titleKey)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(L10n.t(f.subtitleKey)).font(.system(size: 11)).foregroundColor(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: Binding(get: { on }, set: { hub.set(f.id, on: $0) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private var actionList: some View {
        VStack(spacing: 0) {
            actionRow(L10n.t("Lịch sử thao tác"), "clock.arrow.circlepath") { navigate(.actionHistory) }
            actionRow(L10n.t("Khay thả…"), "tray.and.arrow.down") { navigate(.dropTray) }
            actionRow(L10n.t("Lấy màu từ màn hình"), "eyedropper") {
                // The popover would cover the pixels being picked; let it close first.
                closePopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ScreenColorPicker.shared.pick() }
            }
            actionRow(L10n.t("Chép chữ từ màn hình"), "text.viewfinder") {
                // Same as the colour picker: let the popover close first so it is not in the capture.
                closePopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ScreenTextCopier.shared.start() }
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
            Button { navigate(.features) } label: {
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

    /// SoC die temperature (HID thermal sensors); nil ⇒ "Không khả dụng", never 0 °C.
    private func tempCell(_ title: String, _ value: Double?) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundColor(.secondary)
            if let value {
                Text(String(format: "%.0f °C", value)).font(.system(size: 12, weight: .medium)).monospacedDigit()
            } else {
                Text(L10n.t("Không khả dụng")).font(.system(size: 12)).foregroundColor(.secondary)
            }
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
