import SwiftUI
import AppKit

/// Tab 1 of the Menu Bar Popover: Anti-Sleep (`CaffeineController`), quick duration presets,
/// and 2-column quick toggles synchronized with Settings via `@AppStorage`.
struct MenubarUnsleepTabView: View {
    let onClose: () -> Void

    @State private var caffeine = CaffeineController.shared
    @AppStorage("caffeine.keepDisplayOn") private var keepDisplayOn = true
    @AppStorage("spacesOrder.fixedEnabled") private var fixedSpaces = false

    @State private var isDark = false
    @State private var appearanceBusy = false
    @State private var appearanceError: String? = nil
    @State private var desktopIconsHidden = false
    @State private var dockAutohide = false

    var body: some View {
        VStack(spacing: 8) {
            unsleepMainCard
            durationPresetsCard
            quickTogglesCard
        }
        .onAppear {
            isDark = SystemControls.isDarkMode()
            desktopIconsHidden = !DesktopIconsPrefs.showIcons()
            dockAutohide = DockPrefs.autohide()
        }
    }

    private var unsleepMainCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: caffeine.isActive ? "cup.and.saucer.fill" : "moon.zzz.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(caffeine.isActive ? .accentColor : .secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(caffeine.isActive ? L10n.t("Đang giữ máy thức") : L10n.t("Chống ngủ đang tắt"))
                        .font(.system(size: 13, weight: .semibold))
                    if let rem = MenubarPanelRules.formatRemaining(seconds: caffeine.remainingSeconds) {
                        Text("\(L10n.t("Còn lại: "))\(rem)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    } else if caffeine.isActive {
                        Text(L10n.t("Không giới hạn thời gian"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text(L10n.t("Ngăn máy Mac tự ngủ khi đang chạy tác vụ."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { caffeine.isActive },
                    set: { on in
                        if on { caffeine.activate(duration: .indefinite) } else { caffeine.deactivate() }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            Divider().opacity(0.35)

            Toggle(isOn: $keepDisplayOn) {
                Text(L10n.t("Giữ cả màn hình sáng khi Chống ngủ"))
                    .font(.system(size: 11.5))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: keepDisplayOn) { caffeine.applyDisplaySetting() }

            if caffeine.endedForBattery {
                Text(L10n.t("Lần trước đã tự tắt vì pin yếu (≤ 10 %, đang chạy pin)."))
                    .font(.system(size: 10.5))
                    .foregroundColor(.orange)
            }
        }
        .menubarPanelCard()
    }

    private var durationPresetsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("Chọn nhanh thời gian"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(MenubarPanelRules.unsleepPresets) { preset in
                    Button {
                        if preset.minutes == 0 {
                            caffeine.activate(duration: .indefinite)
                        } else {
                            caffeine.activate(duration: .minutes(preset.minutes))
                        }
                    } label: {
                        Text(L10n.t(preset.labelKey))
                            .font(.system(size: 11.5, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.primary.opacity(0.07))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .menubarPanelCard()
    }

    private var quickTogglesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("Đặt nhanh"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                quickTogglePill(icon: "moon.fill", title: L10n.t("Chế độ tối"), isActive: isDark) {
                    toggleAppearance()
                }
                .disabled(appearanceBusy)

                quickTogglePill(icon: "eye.slash", title: L10n.t("Ẩn icon Desktop"), isActive: desktopIconsHidden) {
                    let showNext = desktopIconsHidden
                    DesktopIconsPrefs.setShowIcons(showNext)
                    desktopIconsHidden = !showNext
                }

                quickTogglePill(icon: "dock.rectangle", title: L10n.t("Tự động ẩn Dock"), isActive: dockAutohide) {
                    let next = !dockAutohide
                    DockPrefs.setAutohide(next)
                    dockAutohide = next
                }

                quickTogglePill(icon: "rectangle.3.group", title: L10n.t("Cố định Spaces"), isActive: fixedSpaces) {
                    SpacesOrderController.setFixedOrder(!fixedSpaces)
                }

                quickTogglePill(icon: "lock.fill", title: L10n.t("Tắt màn hình ngay"), isActive: false) {
                    onClose()
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                    p.arguments = ["displaysleepnow"]
                    try? p.run()
                }

                quickTogglePill(icon: "keyboard.badge.eye", title: L10n.t("Lau bàn phím"), isActive: false) {
                    onClose()
                    CleaningModeController.shared.start()
                }
            }

            if let err = appearanceError {
                VStack(alignment: .leading, spacing: 4) {
                    Text(err)
                        .font(.system(size: 10.5))
                        .foregroundColor(.orange)
                    Button(L10n.t("Mở Cài đặt Tự động hóa")) {
                        SystemControls.openAutomationPane()
                    }
                    .controlSize(.small)
                }
            }
        }
        .menubarPanelCard()
    }

    private func quickTogglePill(icon: String, title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(isActive ? .white : .accentColor)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isActive ? .white : .primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? Color.accentColor : Color.primary.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleAppearance() {
        guard !appearanceBusy else { return }
        appearanceError = nil
        appearanceBusy = true
        let target: SystemControls.AppearanceMode = isDark ? .light : .dark
        Task {
            let result = await SystemControls.setAppearance(target)
            isDark = SystemControls.isDarkMode()
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
