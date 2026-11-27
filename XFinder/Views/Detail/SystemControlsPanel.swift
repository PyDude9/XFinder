import SwiftUI
// audit-ui-tokens: embedded-panel — rendered inside FeaturesHubView, which owns the PageHeader.
import AppKit

/// Điều khiển hệ thống — the "Điều khiển" tab of Tính năng & Quyền: machine-wide switches
/// (volume, output device, brightness, appearance, keep-awake, Dock auto-hide, desktop icons).
///
/// This used to be its own sidebar page ("Điều khiển nhanh") that ALSO carried a "Cửa sổ" group
/// switching Dock preview / ⌘-Tab / hold-⌘Q — the same three keys the Features tab already owns.
/// Those rows are gone from here: one key, one control (Part 0 §4).
///
/// Honesty Rule notes kept:
/// * brightness has no public write API, so it goes through key events and the % follows the slider.
/// * the appearance switch drives the *system* appearance via System Events, and names the
///   Automation permission when it is refused.
struct SystemControlsPanel: View {
    @State private var volumeObserver = VolumeObserver.shared
    @State private var audioOutputs = AudioOutputDevices.shared
    @State private var appearance: SystemControls.AppearanceMode = SystemControls.currentAppearance()
    @State private var appearanceError: String? = nil
    @State private var appearanceBusy = false
    @State private var brightDenied = false
    /// Real brightness, polled from IOKit (see `ScreenBrightness`).
    @State private var brightness = ScreenBrightness.shared
    /// Vị trí con trượt LUÔN là trạng thái kéo cục bộ: macOS không đặt được
    /// độ sáng chính xác (chỉ ~16 nấc phần cứng), nên nếu binding bám thẳng
    /// giá trị registry, giữa lúc kéo con trượt liên tục bị giật về nấc cũ
    /// — đó chính là bug "slider không trượt". Chỉ gửi phím khi buông tay
    /// (onEditingChanged), sau đó poll đồng bộ lại từ phần cứng.
    @State private var brightnessSlider: Double = 0.5
    @State private var brightnessDragging = false
    @AppStorage("cleaning.minutes") private var cleaningMinutes = 2
    @State private var cleaning = CleaningModeController.shared

    /// Dock auto-hide is a real, readable/writable public preference, so it is
    /// a genuine two-way toggle rather than a fire-and-forget button.
    @State private var dockAutohide = DockPrefs.autohide()
    @State private var desktopIconsHidden = false

    var body: some View {
        systemSection
        .onAppear {
            appearance = SystemControls.currentAppearance()
            dockAutohide = DockPrefs.autohide()
            desktopIconsHidden = !DesktopIconsPrefs.showIcons()
            brightDenied = !WindowManager.isTrusted
            brightnessSlider = brightness.level ?? 0.5
            volumeObserver.retain()
            audioOutputs.retain()
            // Polls IOKit while this page is visible so the slider follows the
            // keyboard brightness keys; released on disappear so idle CPU
            // stays at zero.
            brightness.retain()
        }
        .onDisappear {
            volumeObserver.release()
            audioOutputs.release()
            brightness.release()
        }
    }

    // MARK: - Hệ thống

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(icon: "desktopcomputer",
                          title: L10n.t("Hệ thống"),
                          subtitle: L10n.t("Áp dụng cho toàn máy, không chỉ XFinder."))

            VStack(spacing: 10) {
                // Volume — real, and live via the CoreAudio listener.
                HStack(spacing: 12) {
                    Label {
                        Text(L10n.t("Âm lượng")).font(XFinderTokens.Font.row)
                    } icon: {
                        Image(systemName: volumeObserver.isMuted || volumeObserver.volume == 0
                              ? "speaker.slash.fill"
                              : volumeObserver.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill")
                            .foregroundColor(volumeObserver.isMuted ? .red : .secondary)
                    }
                    .frame(width: 130, alignment: .leading)

                    Slider(value: Binding(get: { volumeObserver.volume },
                                          set: { volumeObserver.setVolume($0) }),
                           in: 0...1)
                        .tint(.blue)

                    Text("\(Int(volumeObserver.volume * 100))%")
                        .font(XFinderTokens.Font.mono)
                        .frame(width: 38, alignment: .trailing)
                }

                // Sound output — the list System Settings shows, live via CoreAudio listeners
                // (no polling). With a single device there is nothing to choose, so it is shown
                // as a plain readout and says why, instead of a one-item picker.
                HStack(spacing: 12) {
                    Label {
                        Text(L10n.t("Âm thanh ra")).font(XFinderTokens.Font.row)
                    } icon: {
                        Image(systemName: audioOutputs.current?.symbol ?? "speaker.wave.2")
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 130, alignment: .leading)

                    if audioOutputs.devices.count > 1 {
                        Picker("", selection: Binding(
                            get: { audioOutputs.currentID },
                            set: { id in
                                if let d = audioOutputs.devices.first(where: { $0.id == id }) { audioOutputs.select(d) }
                            })) {
                            ForEach(audioOutputs.devices) { d in
                                Label(d.name, systemImage: d.symbol).tag(d.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(audioOutputs.current?.name ?? "—")
                            .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                            .fileNameRowSafe()
                    }
                }
                if audioOutputs.devices.count <= 1 {
                    Text(L10n.t("Chỉ có một thiết bị âm thanh ra — cắm tai nghe hoặc kết nối loa để chọn thiết bị khác."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let err = audioOutputs.lastError {
                    Text("\(L10n.t("Không đổi được thiết bị âm thanh ra: "))\(err)")
                        .font(XFinderTokens.Font.caption).foregroundColor(.red)
                }

                ToggleRow(title: L10n.t("Tắt tiếng"),
                          isOn: Binding(get: { volumeObserver.isMuted },
                                        set: { _ in volumeObserver.toggleMute() }))

                Divider()

                // Brightness — a slider like the volume row, as requested.
                //
                // Honesty note: macOS exposes no public API to READ screen
                // brightness, so this slider is a *relative* control, not a
                // mirror of the system value. Moving it sends the same
                // brightness key events the keyboard does — one step per
                // notch of travel — and the position is XFinder's own memory
                // of what it has sent. It deliberately starts centred rather
                // than pretending to know the real level.
                // Brightness now shows the REAL value from IOKit and tracks the
                // keyboard keys, because `ScreenBrightness` polls the registry.
                // The previous version had no reader at all, which is why the
                // control never moved and felt decorative.
                HStack(spacing: 12) {
                    Label {
                        Text(L10n.t("Độ sáng màn hình")).font(XFinderTokens.Font.row)
                    } icon: {
                        Image(systemName: "sun.max.fill").foregroundColor(.secondary)
                    }
                    .frame(width: 130, alignment: .leading)

                    // Slider bám trạng thái kéo cục bộ; buông tay mới gửi
                    // phím rồi đọc lại nấc thật (xem note ở brightnessSlider).
                    Slider(value: $brightnessSlider, in: 0...1) { editing in
                        brightnessDragging = editing
                        if !editing { brightness.setLevel(brightnessSlider) }
                    }
                        .tint(.blue)
                        .disabled(brightDenied || brightness.level == nil)

                    Text(brightness.level == nil ? "—" : "\(Int(brightnessSlider * 100))%")
                        .font(XFinderTokens.Font.mono)
                        .frame(width: 38, alignment: .trailing)
                }
                .onChange(of: brightness.level) { _, newValue in
                    // Phím tăng/giảm phần cứng → đồng bộ slider (khi không kéo).
                    if !brightnessDragging, let v = newValue { brightnessSlider = v }
                }

                if brightDenied {
                    InlineNote(kind: .warning,
                               text: L10n.t("Chưa có quyền Trợ năng — kéo thanh trượt sẽ không đổi được độ sáng."),
                               buttonTitle: L10n.t("Cấp quyền Trợ năng…"),
                               action: {
                                   if !WindowManager.requestAccessibilityTrust() {
                                       WindowManager.openAccessibilityPane()
                                   }
                               })
                } else if brightness.level == nil {
                    Text(L10n.t("Không đọc được độ sáng — máy này có thể chỉ dùng màn hình ngoài."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L10n.t("macOS không cho đọc lại % chính xác (trên Apple Silicon giá trị registry thường kẹt), nên % bám theo vị trí bạn kéo — con số thật cho thanh trượt. XFinder gửi từng nấc như phím bấm."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // System-wide appearance.
                HStack(spacing: 12) {
                    Label {
                        Text(L10n.t("Chế độ giao diện")).font(XFinderTokens.Font.row)
                    } icon: {
                        Image(systemName: "circle.lefthalf.filled").foregroundColor(.secondary)
                    }
                    .frame(width: 180, alignment: .leading)

                    Spacer()

                    Picker("", selection: $appearance) {
                        ForEach(SystemControls.AppearanceMode.allCases) { mode in
                            Text(mode.titleVI).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)   // segmented-ok: 3 cases (Sáng/Tối/Hệ thống)
                    .labelsHidden()
                    .frame(width: 230)
                    .disabled(appearanceBusy)
                    .onChange(of: appearance) { _, new in applyAppearance(new) }
                }

                if let err = appearanceError {
                    InlineNote(kind: .warning,
                               text: err,
                               buttonTitle: L10n.t("Mở Cài đặt Tự động hóa"),
                               action: { SystemControls.openAutomationPane() })
                }

                Divider()

                HStack(spacing: XFinderTokens.Space.inline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("Lau bàn phím")).font(XFinderTokens.Font.row)
                        Text(L10n.t("Khoá bàn phím để lau; chuột vẫn dùng được. Esc 5 lần hoặc nút Mở khoá để thoát."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker(L10n.t("Thời lượng"), selection: $cleaningMinutes) {
                        ForEach(Array(CaffeineRules.cleaningRange), id: \.self) { m in Text("\(m)\(L10n.t(" phút"))").tag(m) }
                    }
                    .pickerStyle(.menu).labelsHidden().frame(width: 90)
                    Button(L10n.t("Bắt đầu lau")) { cleaning.start() }.disabled(cleaning.isActive)
                }
                .padding(.vertical, 2)

                ToggleRow(title: L10n.t("Tự động ẩn Dock"), isOn: $dockAutohide)
                    .onChange(of: dockAutohide) { _, on in DockPrefs.setAutohide(on) }

                ToggleRow(title: L10n.t("Ẩn biểu tượng trên Desktop"),
                          subtitle: L10n.t("Icon màn hình nền biến mất cho tới khi bật lại (Finder tự khởi động lại)."),
                          isOn: $desktopIconsHidden)
                    .onChange(of: desktopIconsHidden) { _, hide in
                        DesktopIconsPrefs.setShowIcons(!hide)
                    }
            }
            .padding(.horizontal, XFinderTokens.Space.page)
        }
    }

    // MARK: - Helpers

    private func applyAppearance(_ mode: SystemControls.AppearanceMode) {
        guard !appearanceBusy else { return }
        appearanceError = nil
        appearanceBusy = true
        Task {
            let result = await SystemControls.setAppearance(mode)
            let current = SystemControls.currentAppearance()
            if appearance != current {
                appearance = current
            }
            appearanceBusy = false
            switch result {
            case .ok:
                break
            case .notPermitted:
                appearanceError = L10n.t("Chưa được cấp quyền Tự động hóa cho System Events. Mở Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Tự động hóa → XFinder → bật System Events.")
            case .failed(let msg):
                appearanceError = "\(L10n.t("Không đổi được giao diện: "))\(msg)"
            }
        }
    }


}

/// Dedicated Full Settings destination for the Caffeine hold and lid-wake option.
struct CaffeineDetailView: View {
    @State private var caffeine = CaffeineController.shared
    @State private var hasBattery = PowerManager.hasBattery()
    @State private var durationMinutes: Int? = nil
    @AppStorage("caffeine.keepDisplayOn") private var keepDisplayOn = true
    @AppStorage("caffeine.requestLidWake") private var requestLidWake = false

    private var durationText: String {
        if let seconds = caffeine.remainingSeconds {
            return String(format: L10n.t("Còn %02d:%02d"), seconds / 60, seconds % 60)
        }
        return caffeine.isActive ? L10n.t("∞ Vô hạn") : L10n.t("Đang tắt")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(title: L10n.t("Chống ngủ"),
                           subtitle: L10n.t("Chọn thời lượng giữ máy thức và bật riêng chế độ giữ thức khi đóng nắp."))
                SettingsSection(title: L10n.t("Caffeine")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("Giữ máy thức")).font(XFinderTokens.Font.row)
                            Text(durationText).font(XFinderTokens.Font.caption)
                                .foregroundStyle(caffeine.isActive ? .orange : .secondary)
                                .monospacedDigit()
                        }
                        Spacer()
                        Picker(L10n.t("Thời lượng"), selection: $durationMinutes) {
                            ForEach(MenubarPanelRules.unsleepPresets) { preset in
                                Text(L10n.t(preset.labelKey)).tag(preset.minutes == 0 ? Int?.none : Int?.some(preset.minutes))
                            }
                        }
                        .pickerStyle(.menu).labelsHidden().frame(width: 112)
                        .disabled(caffeine.isActive)
                        Toggle(isOn: Binding(get: { caffeine.isActive }, set: { enabled in
                            if enabled {
                                caffeine.activate(duration: durationMinutes.map { .minutes($0) } ?? .indefinite)
                            } else {
                                caffeine.deactivate()
                            }
                        })) { EmptyView() }
                            .labelsHidden().toggleStyle(.switch)
                            .accessibilityLabel(L10n.t("Giữ máy thức"))
                            .accessibilityValue(durationText)
                    }
                    .settingsRow()
                    SettingsDivider()
                    ToggleRow(title: L10n.t("Giữ cả màn hình sáng khi Chống ngủ"),
                              subtitle: caffeine.endedForBattery ? L10n.t("Lần trước đã tự tắt vì pin yếu (≤ 10 %, đang chạy pin).")
                                                                 : L10n.t("Chống ngủ tự tắt khi chạy pin và còn ≤ 10 %."),
                              isOn: $keepDisplayOn)
                        .onChange(of: keepDisplayOn) { caffeine.applyDisplaySetting() }
                    SettingsDivider()
                    if hasBattery {
                        ToggleRow(title: L10n.t("Giữ thức khi đóng nắp"),
                                  subtitle: lidWakeSubtitle,
                                  isOn: $requestLidWake)
                            .onChange(of: requestLidWake) { _, enabled in caffeine.setLidWakeRequested(enabled) }
                    } else {
                        InlineNote(text: L10n.t("Giữ thức khi đóng nắp chỉ dùng được trên máy Mac có pin và nắp."))
                            .settingsRow()
                    }
                }
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
        .onAppear {
            hasBattery = PowerManager.hasBattery()
            caffeine.refreshPowerState()
        }
    }

    private var lidWakeSubtitle: String {
        switch caffeine.lidWakeState {
        case .active:
            return L10n.t("Đang giữ thức khi đóng nắp (đang cắm nguồn). macOS vẫn có thể cho máy ngủ nếu không có màn hình ngoài.")
        case .waitingForCaffeine:
            return L10n.t("Đã bật yêu cầu đóng nắp — chưa hoạt động vì Chống ngủ đang tắt. Cần cắm nguồn.")
        case .waitingForACPower:
            return L10n.t("Đã bật yêu cầu đóng nắp — đang tạm dừng vì dùng pin (cần cắm nguồn).")
        case .unavailable:
            return L10n.t("Không tạo được yêu cầu giữ thức khi đóng nắp từ macOS.")
        case .off:
            return L10n.t("Cần bật Chống ngủ và cắm nguồn. macOS vẫn có thể cho máy ngủ khi đóng nắp.")
        }
    }
}

/// Dock preferences that macOS exposes publicly and readably.
///
/// `autohide` is a real `com.apple.dock` key, so this is a genuine two-way
/// toggle. Restarting the Dock is how the change takes effect — the same thing
/// System Settings does.
@MainActor
enum DockPrefs {
    static func autohide() -> Bool {
        UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") ?? false
    }

    static func setAutohide(_ on: Bool) {
        let d = UserDefaults(suiteName: "com.apple.dock")
        d?.set(on, forKey: "autohide")
        CFPreferencesSynchronize("com.apple.dock" as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Dock"]
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}

/// Ẩn icon màn hình nền — preference thật của Finder (`CreateDesktop`).
/// Key chưa tồn tại = đang HIỆN icon (mặc định của macOS).
enum DesktopIconsPrefs {
    static func showIcons() -> Bool {
        UserDefaults(suiteName: "com.apple.finder")?
            .object(forKey: "CreateDesktop") as? Bool ?? true
    }

    static func setShowIcons(_ on: Bool) {
        let d = UserDefaults(suiteName: "com.apple.finder")
        d?.set(on, forKey: "CreateDesktop")
        CFPreferencesSynchronize("com.apple.finder" as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Finder"]
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
