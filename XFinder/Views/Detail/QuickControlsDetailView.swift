import SwiftUI
import AppKit

/// Điều khiển nhanh — flat System-Settings layout matching the reference
/// screenshot: a "Hệ thống" group of machine-wide switches, then a "Cửa sổ"
/// group for XFinder's own window features.
///
/// Honesty Rule notes kept from the previous version:
/// * brightness has no public read API, so it is −/+ only and never shows a %.
/// * the appearance switch drives the *system* appearance via System Events,
///   and names the Automation permission when it is refused.
struct QuickControlsDetailView: View {
    @State private var volumeObserver = VolumeObserver.shared
    @State private var appearance: SystemControls.AppearanceMode = SystemControls.currentAppearance()
    @State private var appearanceError: String? = nil
    @State private var appearanceBusy = false
    @State private var brightDenied = false
    /// XFinder's own record of where the brightness slider sits. NOT a reading
    /// of the system value — none is available — so it starts centred.
    @State private var brightnessPosition: Double = 0.5
    @State private var caffeine = CaffeineController.shared

    @AppStorage("windowPreview.hoverEnabled") private var hoverEnabled = true
    // MUST match `CommandTabController`'s own default (false). An @AppStorage
    // default that disagrees with the reader silently turns the feature on for
    // anyone who has never touched the switch.
    @AppStorage("windowPreview.commandTabEnabled") private var commandTabEnabled = false

    /// Dock auto-hide is a real, readable/writable public preference, so it is
    /// a genuine two-way toggle rather than a fire-and-forget button.
    @State private var dockAutohide = DockPrefs.autohide()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(icon: "slider.horizontal.3",
                           title: "Điều khiển nhanh",
                           subtitle: "Điều khiển nhanh máy Mac và các cửa sổ.")

                systemSection

                Divider().padding(.horizontal, 20)

                windowSection

            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            appearance = SystemControls.currentAppearance()
            dockAutohide = DockPrefs.autohide()
            volumeObserver.retain()
        }
        .onDisappear { volumeObserver.release() }
    }

    // MARK: - Hệ thống

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "desktopcomputer",
                          title: "Hệ thống",
                          subtitle: "Áp dụng cho toàn máy, không chỉ XFinder.")

            VStack(spacing: 10) {
                // Volume — real, and live via the CoreAudio listener.
                HStack(spacing: 12) {
                    Label {
                        Text("Âm lượng").font(.system(size: 13))
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
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 38, alignment: .trailing)
                }

                ToggleRow(title: "Tắt tiếng",
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
                HStack(spacing: 12) {
                    Label {
                        Text("Độ sáng màn hình").font(.system(size: 13))
                    } icon: {
                        Image(systemName: "sun.max.fill").foregroundColor(.secondary)
                    }
                    .frame(width: 130, alignment: .leading)

                    Slider(value: $brightnessPosition, in: 0...1)
                        .tint(.blue)
                        .onChange(of: brightnessPosition) { old, new in
                            applyBrightnessDelta(from: old, to: new)
                        }

                    // No % label: the number would be XFinder's own guess, not
                    // the system's real brightness.
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }

                if brightDenied {
                    permissionNote(
                        "Chưa có quyền Trợ năng — thanh trượt độ sáng sẽ không có tác dụng.",
                        button: "Mở Cài đặt quyền Trợ năng",
                        action: { WindowManager.openAccessibilityPane() })
                } else {
                    Text("macOS không cho đọc % độ sáng, nên thanh này chỉnh theo mức tương đối (giống phím độ sáng trên bàn phím) và không hiện số.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // System-wide appearance.
                HStack(spacing: 12) {
                    Label {
                        Text("Chế độ giao diện").font(.system(size: 13))
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
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 230)
                    .disabled(appearanceBusy)
                    .onChange(of: appearance) { _, new in applyAppearance(new) }
                }

                if let err = appearanceError {
                    permissionNote(err,
                                   button: "Mở Cài đặt Tự động hóa",
                                   action: { SystemControls.openAutomationPane() })
                }

                Divider()

                ToggleRow(title: "Chống ngủ",
                          subtitle: caffeine.isActive ? "Đang bật" : "Đang tắt",
                          isOn: Binding(get: { caffeine.isActive },
                                        set: { on in
                                            if on { caffeine.activate(duration: .indefinite) }
                                            else { caffeine.deactivate() }
                                        }))

                ToggleRow(title: "Tự động ẩn Dock", isOn: $dockAutohide)
                    .onChange(of: dockAutohide) { _, on in DockPrefs.setAutohide(on) }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Cửa sổ

    private var windowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "macwindow",
                          title: "Cửa sổ",
                          subtitle: "Các tính năng cửa sổ của XFinder.")

            VStack(spacing: 10) {
                ToggleRow(title: "Xem trước Dock",
                          subtitle: "Rê chuột lên icon trên Dock để xem các cửa sổ.",
                          isOn: $hoverEnabled)
                    .onChange(of: hoverEnabled) { DockPreviewController.shared.applySettings() }

                ToggleRow(title: "Chuyển đổi ứng dụng (⌘-Tab)",
                          subtitle: "Thay trình chuyển ứng dụng của macOS bằng bản có ảnh thu nhỏ.",
                          isOn: $commandTabEnabled)
                    .onChange(of: commandTabEnabled) { CommandTabController.shared.applySettings() }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Helpers

    private func permissionNote(_ message: String,
                                button: String,
                                action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.system(size: 11)).foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Button(button, action: action)
                .buttonStyle(.bordered).controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applyAppearance(_ mode: SystemControls.AppearanceMode) {
        guard !appearanceBusy else { return }
        appearanceError = nil
        appearanceBusy = true
        Task {
            let result = await SystemControls.setAppearance(mode)
            appearanceBusy = false
            switch result {
            case .ok:
                appearance = SystemControls.currentAppearance()
            case .notPermitted:
                appearance = SystemControls.currentAppearance()
                appearanceError = "Chưa được cấp quyền Tự động hóa cho System Events. Mở Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Tự động hóa → XFinder → bật System Events."
            case .failed(let msg):
                appearance = SystemControls.currentAppearance()
                appearanceError = "Không đổi được giao diện: \(msg)"
            }
        }
    }

    /// Converts slider travel into brightness key presses.
    ///
    /// macOS has ~16 brightness notches, so one full sweep of the slider maps
    /// to 16 steps. Sending them in a burst matches what holding the keyboard
    /// key does. Rounding means tiny drags send nothing rather than jittering.
    private func applyBrightnessDelta(from old: Double, to new: Double) {
        brightDenied = !WindowManager.isTrusted
        guard !brightDenied else { return }
        let notches = 16.0
        let steps = Int((new - old) * notches)
        guard steps != 0 else { return }
        for _ in 0..<abs(steps) {
            SystemControls.adjustBrightness(up: steps > 0)
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
        d?.synchronize()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Dock"]
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
