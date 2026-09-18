import SwiftUI
import AppKit

/// Xem trước cửa sổ — MFinder-style Dock-hover preview. Di chuột lên icon app
/// trên Dock → panel thumbnails các cửa sổ của app đó; bấm để chuyển tới.
/// Cần quyền Trợ năng (đọc vị trí icon Dock). Grid thủ công bên dưới cho các
/// máy chưa cấp quyền, và vẫn giữ danh sách cửa sổ + làm mới thủ công.
struct WindowPreviewDetailView: View {
    @AppStorage("windowPreview.hoverEnabled") private var hoverEnabled = true
    @AppStorage("windowPreview.commandTabEnabled") private var commandTabEnabled = false
    @AppStorage("windowPreview.showHiddenWindows") private var showHiddenWindows = false
    @State private var controller = DockPreviewController.shared
    @State private var trusted = WindowManager.isTrusted
    @State private var canRecord = WindowManager.canRecordScreen

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "macwindow.on.rectangle",
                           title: L10n.t("Xem trước cửa sổ"),
                           subtitle: L10n.t("Xem trước và chuyển cửa sổ ứng dụng ngay từ Dock."))

                SectionHeader(icon: "square.on.square",
                              title: L10n.t("Cách hoạt động"),
                              subtitle: L10n.t("Di chuột qua ứng dụng trên Dock để xem trước các cửa sổ."))

                VStack(alignment: .leading, spacing: 4) {
                    ToggleRow(title: L10n.t("Hiện bản xem trước cửa sổ khi di chuột qua ứng dụng trên Dock"),
                              isOn: $hoverEnabled)
                        .onChange(of: hoverEnabled) { controller.applySettings() }
                    Text(L10n.t("XFinder chỉ chụp ảnh thu nhỏ khi bảng xem trước đang hiển thị."))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    if hoverEnabled {
                        Text(controller.statusHint)
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                SectionHeader(icon: "command",
                              title: L10n.t("Xem trước cửa sổ bằng Command-Tab"),
                              subtitle: L10n.t("Chuyển trực tiếp giữa các cửa sổ bằng hình xem trước trực tiếp."))

                VStack(alignment: .leading, spacing: 4) {
                    ToggleRow(title: L10n.t("Hiện bản xem trước cửa sổ bằng Command-Tab"),
                              isOn: $commandTabEnabled)
                        .onChange(of: commandTabEnabled) { CommandTabController.shared.applySettings() }
                    Text(L10n.t("Khi bật, XFinder xử lý Command-Tab thay cho bộ chuyển ứng dụng của macOS. Giữ Command và nhấn Tab hoặc Shift-Tab để chọn cửa sổ; thả Command để mở hoặc nhấn Escape để hủy."))
                        .font(.system(size: 11)).foregroundColor(.secondary)

                    ToggleRow(title: L10n.t("Hiện cả cửa sổ ẩn trong App Switcher"),
                              isOn: $showHiddenWindows)
                        .padding(.top, 8)
                    Text(L10n.t("Một số ứng dụng chỉ ẩn cửa sổ khi bạn đóng thay vì thoát — Spotify, Slack, Synology Chat. Liệt kê những cửa sổ đó cho phép Command-Tab gọi lại chúng, nhưng ứng dụng phải mở lại cửa sổ trước, nên sẽ hiện chậm hơn một chút."))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                SectionHeader(icon: "lock.shield",
                              title: L10n.t("Quyền cần thiết"),
                              subtitle: L10n.t("Trợ năng nhận diện ứng dụng trên Dock; Ghi màn hình hiển thị ảnh thu nhỏ trực tiếp."))

                VStack(spacing: 10) {
                    PermissionRow(title: L10n.t("Trợ năng"),
                                  granted: trusted,
                                  grantedText: L10n.t("Đã cấp")) {
                        WindowManager.openAccessibilityPane()
                    }
                    PermissionRow(title: L10n.t("Ghi màn hình"),
                                  granted: canRecord,
                                  grantedText: L10n.t("Đã cấp")) {
                        WindowManager.openScreenRecordingPane()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            trusted = WindowManager.isTrusted
            canRecord = WindowManager.canRecordScreen
            controller.applySettings()
        }
    }
}

/// Permission row with a live status and a "Cấp…" button, matching the
/// screenshot's Đã cấp / Chưa cấp layout.
struct PermissionRow: View {
    let title: String
    let granted: Bool
    let grantedText: String
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(granted ? .green : .orange)
            Text(title).font(.system(size: 13))
            Spacer()
            Text(granted ? grantedText : L10n.t("Chưa cấp"))
                .font(.system(size: 12)).foregroundColor(.secondary)
            Button(L10n.t("Cấp…")) { onGrant() }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }
}


/// Vùng bắt dính — snaps the *focused* window: drag it to a screen edge, or
/// use ⌃⌥ + arrows. Both need Accessibility trust, so the page leads with the
/// grant flow when it is missing rather than showing controls that do nothing.
struct SnapZonesDetailView: View {
    @AppStorage("snapzones.enabled") private var snapEnabled = true
    @AppStorage("snapzones.restoreOnUnsnap") private var restoreOnUnsnap = true
    @AppStorage("snapzones.showPreview") private var showPreview = true
    @AppStorage("snapzones.haptic") private var hapticEnabled = false
    @AppStorage("snapzones.dragEnabled") private var dragEnabled = true
    @AppStorage("snapzones.hotkeysEnabled") private var hotkeysEnabled = true
    @AppStorage("snapzones.edgeMargin") private var edgeMargin = 20.0
    @AppStorage("snapzones.stageInset") private var stageInset = 68.0
    @AppStorage("snapzones.reserveStage") private var reserveStage = true
    @State private var controller = SnapZoneController.shared
    @State private var trusted = WindowManager.isTrusted

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(
                    icon: "rectangle.split.2x2",
                    title: L10n.t("Vùng bắt dính"),
                    subtitle: L10n.t("Bắt dính cửa sổ bằng cách kéo chúng đến cạnh và góc màn hình."),
                    trailing: AnyView(
                        HStack(spacing: 6) {
                            Text(snapEnabled ? L10n.t("Bật") : L10n.t("Tắt"))
                                .font(.system(size: 12)).foregroundColor(.secondary)
                            Toggle("", isOn: $snapEnabled)
                                .labelsHidden()
                                .onChange(of: snapEnabled) { controller.applySettings() }
                        }
                    ))

                if !trusted {
                    permissionBanner
                    Divider().padding(.horizontal, 20)
                }

                // Ba toggle đầu trang — khớp screenshot MFinder.
                VStack(spacing: 10) {
                    ToggleRow(title: L10n.t("Khôi phục kích thước cửa sổ khi gỡ bắt dính"), isOn: $restoreOnUnsnap)
                    ToggleRow(title: L10n.t("Tạo hiệu ứng cho vùng xem trước"), isOn: $showPreview)
                    ToggleRow(title: L10n.t("Phản hồi rung"), isOn: $hapticEnabled)
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                SectionHeader(icon: "hand.draw",
                              title: L10n.t("Kéo tới mép màn hình"),
                              subtitle: L10n.t("Kéo cửa sổ tới mép; vùng đích sẽ sáng lên, thả chuột để bắt dính."))

                VStack(alignment: .leading, spacing: 8) {
                    ToggleRow(title: L10n.t("Bật bắt dính khi kéo tới mép"), isOn: $dragEnabled)
                        .onChange(of: dragEnabled) { controller.applySettings() }
                        .disabled(!trusted)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(L10n.t("Độ nhạy mép "))\(Int(edgeMargin)) pt")
                            .font(.system(size: 13))
                        Slider(value: $edgeMargin, in: 8...60, step: 1)
                            .onChange(of: edgeMargin) { controller.applySettings() }
                            .disabled(!trusted || !dragEnabled)
                    }

                    Text(L10n.t("Mép trái/phải → nửa màn hình · góc → một phần tư · mép trên → toàn màn hình · mép dưới → nửa dưới."))
                        .font(.system(size: 11)).foregroundColor(.secondary)

                    if WindowManager.isStageManagerEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            ToggleRow(title: L10n.t("Chừa mép trái cho Stage Manager"),
                                      isOn: $reserveStage)
                                .disabled(!snapEnabled)

                            if reserveStage {
                                Text("\(L10n.t("Bề rộng chừa: "))\(Int(stageInset)) pt")
                                    .font(.system(size: 13))
                                Slider(value: $stageInset, in: 48...140, step: 2)
                                    .disabled(!snapEnabled)
                                Text(L10n.t("macOS không tự thu nhỏ vùng làm việc cho Stage Manager, nên XFinder chừa mép trái để bạn vẫn thấy icon app đang xếp ở đó. Kéo nhỏ lại nếu bạn chỉ cần thấy icon."))
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                            } else {
                                Text(L10n.t("Cửa sổ sẽ bắt dính hết chiều ngang màn hình và có thể che dải Stage Manager."))
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                SectionHeader(icon: "keyboard",
                              title: L10n.t("Phím tắt toàn hệ thống"),
                              subtitle: L10n.t("Áp dụng cho cửa sổ đang được focus."))

                VStack(alignment: .leading, spacing: 8) {
                    ToggleRow(title: L10n.t("Bật phím tắt bắt dính"), isOn: $hotkeysEnabled)
                        .onChange(of: hotkeysEnabled) { controller.applySettings() }
                        .disabled(!trusted)

                    VStack(spacing: 4) {
                        shortcutRow("⌃⌥ ←", L10n.t("Nửa trái"))
                        shortcutRow("⌃⌥ →", L10n.t("Nửa phải"))
                        shortcutRow("⌃⌥ ↑", L10n.t("Toàn màn hình"))
                        shortcutRow("⌃⌥ ↓", L10n.t("Nửa dưới"))
                        shortcutRow("⌃⌥ ↩", L10n.t("Giữa màn hình"))
                    }
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                // Hướng dẫn chia cửa sổ — khớp MFinder: Ngang/Dọc + 8 checkbox quanh 2×2 grid.
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("Hướng dẫn chia cửa sổ")).font(.system(size: 14, weight: .semibold))
                            Text(L10n.t("Kéo đến cạnh hoặc góc màn hình, rồi thả."))
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { UserDefaults.standard.string(forKey: "snapzones.orientation") ?? "horizontal" },
                            set: { UserDefaults.standard.set($0, forKey: "snapzones.orientation") }
                        )) {
                            Text("Ngang").tag("horizontal")
                            Text(L10n.t("Dọc")).tag("vertical")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }

                    snapGuideGrid

                    HStack {
                        Text(L10n.t("Các lựa chọn được áp dụng cho mọi màn hình có cùng hướng này."))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        Button(L10n.t("Khôi phục mặc định")) { resetSnapDefaults() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }

                    DisclosureGroup(L10n.t("Chia cửa sổ của macOS")) {
                        Text(L10n.t("macOS Sequoia có tính năng chia cửa sổ riêng (Window Tiling). Mở Cài đặt hệ thống → Màn hình & Dock → Chia cửa sổ để cấu hình."))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        Button(L10n.t("Mở Cài đặt Màn hình & Dock")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.link).font(.system(size: 11))
                    }
                    .font(.system(size: 12))
                }
                .padding(14)
                .background(Color(.controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                SectionHeader(icon: "square.grid.3x3",
                              title: L10n.t("Bắt dính ngay"),
                              subtitle: L10n.t("Bấm một vùng để áp dụng cho cửa sổ vừa dùng."))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(WindowManager.SnapTarget.allCases) { zone in
                        Button {
                            if hapticEnabled {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                            }
                            let ok = WindowManager.snapFrontmost(to: zone)
                            controller.lastOutcome = ok
                                ? "\(L10n.t("Đã đưa cửa sổ vào “"))\(zone.titleVI)”."
                                : L10n.t("Không di chuyển được — ứng dụng không cho phép hoặc thiếu quyền.")
                        } label: {
                            Text(zone.titleVI)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!trusted)
                    }
                }
                .padding(.horizontal, 20)

                if let msg = controller.lastOutcome {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            trusted = WindowManager.isTrusted
            controller.applySettings()
        }
    }

    // 2×2 grid với 8 checkbox xung quanh — wording MFinder.
    private var snapGuideGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                guideCheck(title: L10n.t("Trên bên trái"), subtitle: L10n.t("Một phần tư trên bên trái"))
                Spacer()
                VStack(spacing: 2) {
                    Image(systemName: "checkmark.square.fill").foregroundColor(.accentColor)
                    Text(L10n.t("Trên")).font(.system(size: 11, weight: .medium))
                    Text(L10n.t("Phóng to")).font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer()
                guideCheck(title: L10n.t("Trên bên phải"), subtitle: L10n.t("Một phần tư trên bên phải"), trailing: true)
            }
            HStack(spacing: 8) {
                guideCheck(title: L10n.t("Trái"), subtitle: L10n.t("Cạnh trái, nửa trên/dưới khi gần góc"))
                Spacer()
                snapCenterGrid
                Spacer()
                guideCheck(title: L10n.t("Phải"), subtitle: L10n.t("Cạnh phải, nửa trên/dưới khi gần góc"), trailing: true)
            }
            HStack(spacing: 12) {
                guideCheck(title: L10n.t("Dưới bên trái"), subtitle: L10n.t("Một phần tư dưới bên trái"))
                Spacer()
                VStack(spacing: 2) {
                    Image(systemName: "checkmark.square.fill").foregroundColor(.accentColor)
                    Text(L10n.t("Dưới")).font(.system(size: 11, weight: .medium))
                    Text(L10n.t("Một phần ba. Rê về giữa để lấy hai phần ba.")).font(.system(size: 9)).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                Spacer()
                guideCheck(title: L10n.t("Dưới bên phải"), subtitle: L10n.t("Một phần tư dưới bên phải"), trailing: true)
            }
        }
    }

    private var snapCenterGrid: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                snapArrow("arrow.up.left")
                snapArrow("arrow.up.right")
            }
            HStack(spacing: 4) {
                snapArrow("arrow.down.left")
                snapArrow("arrow.down.right")
            }
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
    }

    private func snapArrow(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 14, weight: .medium)).foregroundColor(.accentColor)
            .frame(width: 36, height: 28)
            .background(Color.accentColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func guideCheck(title: String, subtitle: String, trailing: Bool = false) -> some View {
        HStack(spacing: 4) {
            if !trailing {
                Image(systemName: "checkmark.square.fill").foregroundColor(.accentColor).font(.system(size: 12))
            }
            VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(subtitle).font(.system(size: 9)).foregroundColor(.secondary)
            }
            if trailing {
                Image(systemName: "checkmark.square.fill").foregroundColor(.accentColor).font(.system(size: 12))
            }
        }
    }

    private func resetSnapDefaults() {
        edgeMargin = 20
        stageInset = 68
        reserveStage = true
        restoreOnUnsnap = true
        showPreview = true
        hapticEnabled = false
        dragEnabled = true
        hotkeysEnabled = true
        SnapZoneController.shared.applySettings()
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.t("Cần quyền Trợ năng"), systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.orange)
            Text(L10n.t("macOS chỉ cho phép di chuyển cửa sổ của ứng dụng khác khi bạn cấp quyền Trợ năng cho XFinder."))
                .font(.system(size: 12)).foregroundColor(.secondary)
            HStack {
                Button(L10n.t("Mở Cài đặt Trợ năng")) { WindowManager.openAccessibilityPane() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(L10n.t("Kiểm tra lại")) {
                    trusted = WindowManager.isTrusted
                    controller.applySettings()
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
    }

    private func shortcutRow(_ keys: String, _ label: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.primary.opacity(0.07))
                .cornerRadius(4)
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
        }
    }
}
