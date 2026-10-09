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
    @AppStorage("windowPreview.switcherHotkey") private var switcherHotkey = "commandTab"
    @AppStorage("windowPreview.animationEnabled") private var animationEnabled = true
    @AppStorage("windowPreview.customDockEnabled") private var customDockEnabled = false
    @State private var dockAutohide = DockPrefs.autohide()
    @State private var excludedApps: [String] = UserDefaults.standard.stringArray(forKey: "windowPreview.excludedApps") ?? []
    @State private var newExcludedApp: String = ""
    @State private var controller = DockPreviewController.shared
    @State private var trusted = WindowManager.isTrusted
    @State private var canRecord = WindowManager.canRecordScreen

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "macwindow.on.rectangle",
                           title: L10n.t("Xem trước cửa sổ"),
                           subtitle: L10n.t("Xem trước và chuyển cửa sổ ứng dụng ngay từ Dock."))

                // Section 1: Switcher
                SectionHeader(icon: "command",
                              title: L10n.t("Chuyển cửa sổ bằng phím tắt"),
                              subtitle: L10n.t("Chuyển trực tiếp giữa các cửa sổ bằng hình xem trước trực tiếp."))

                VStack(alignment: .leading, spacing: 10) {
                    ToggleRow(title: L10n.t("Bật bộ chuyển cửa sổ Liquid Glass"),
                              isOn: $commandTabEnabled)
                        .onChange(of: commandTabEnabled) { CommandTabController.shared.applySettings() }
                    Text(L10n.t("Khi bật, XFinder xử lý chuyển cửa sổ thay cho bộ chuyển ứng dụng của macOS. Giữ phím tắt để duyệt danh sách, nhấn dấu phẩy (,) để tìm kiếm, thả phím để mở hoặc nhấn Escape để hủy."))
                        .font(.system(size: 11)).foregroundColor(.secondary)

                    HStack {
                        Text(L10n.t("Phím tắt chuyển cửa sổ"))
                            .font(.system(size: 13))
                        Spacer()
                        Picker("", selection: $switcherHotkey) {
                            Text("⌘ Tab").tag("commandTab")
                            Text("⌥ Tab").tag("optionTab")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        .onChange(of: switcherHotkey) {
                            CommandTabController.shared.applySettings()
                        }
                    }

                    ToggleRow(title: L10n.t("Hiệu ứng chuyển động"),
                              isOn: $animationEnabled)
                    Text(L10n.t("Mượt mà với hoạt cảnh co giãn và bóng mờ Liquid Glass."))
                        .font(.system(size: 11)).foregroundColor(.secondary)

                    ToggleRow(title: L10n.t("Hiện cả cửa sổ ẩn trong App Switcher"),
                              isOn: $showHiddenWindows)
                    Text(L10n.t("Một số ứng dụng chỉ ẩn cửa sổ khi bạn đóng thay vì thoát — Spotify, Slack, Synology Chat. Liệt kê những cửa sổ đó cho phép Command-Tab gọi lại chúng, nhưng ứng dụng phải mở lại cửa sổ trước, nên sẽ hiện chậm hơn một chút."))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                // Section 2: Dock
                SectionHeader(icon: "square.on.square",
                              title: L10n.t("Dải Dock Liquid Glass"),
                              subtitle: L10n.t("Di chuột qua ứng dụng trên Dock để xem trước các cửa sổ."))

                VStack(alignment: .leading, spacing: 10) {
                    ToggleRow(title: L10n.t("Hiện bản xem trước cửa sổ khi di chuột qua ứng dụng trên Dock"),
                              isOn: $hoverEnabled)
                        .onChange(of: hoverEnabled) { controller.applySettings() }
                    Text(L10n.t("XFinder chỉ chụp ảnh thu nhỏ khi bảng xem trước đang hiển thị."))
                        .font(.system(size: 11)).foregroundColor(.secondary)

                    ToggleRow(title: L10n.t("Hiện dải ứng dụng Dock thay thế ở cạnh dưới màn hình"),
                              isOn: $customDockEnabled)
                        .onChange(of: customDockEnabled) {
                            DockLayerController.shared.applySettings()
                        }

                    ToggleRow(title: L10n.t("Tự động ẩn Dock của macOS"),
                              isOn: $dockAutohide)
                        .onChange(of: dockAutohide) {
                            DockPrefs.setAutohide(dockAutohide)
                        }
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                // Section 3: Excluded Apps
                SectionHeader(icon: "nosign",
                              title: L10n.t("Ứng dụng loại trừ"),
                              subtitle: L10n.t("Các ứng dụng này sẽ không xuất hiện trong bộ chuyển cửa sổ."))

                VStack(alignment: .leading, spacing: 8) {
                    if excludedApps.isEmpty {
                        Text(L10n.t("Chưa có ứng dụng nào bị loại trừ."))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(excludedApps, id: \.self) { app in
                                HStack {
                                    Text(app)
                                        .font(.system(size: 12, design: .monospaced))
                                    Spacer()
                                    Button(action: {
                                        excludedApps.removeAll { $0 == app }
                                        UserDefaults.standard.set(excludedApps, forKey: "windowPreview.excludedApps")
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.controlBackgroundColor).opacity(0.4))
                                .cornerRadius(6)
                            }
                        }
                    }

                    HStack {
                        TextField(L10n.t("Thêm ứng dụng..."), text: $newExcludedApp)
                            .textFieldStyle(.roundedBorder)
                        Button(L10n.t("Thêm")) {
                            let trimmed = newExcludedApp.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty && !excludedApps.contains(trimmed) {
                                excludedApps.append(trimmed)
                                UserDefaults.standard.set(excludedApps, forKey: "windowPreview.excludedApps")
                                newExcludedApp = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(newExcludedApp.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                // Section 4: Permissions
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
            dockAutohide = DockPrefs.autohide()
            excludedApps = UserDefaults.standard.stringArray(forKey: "windowPreview.excludedApps") ?? []
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
            VStack(spacing: 16) {
                if !trusted {
                    permissionBanner
                }

                card1General
                card2DragBehavior
                card3Shortcuts
                card4VisualGuideAndSnapNow
            }
            .frame(maxWidth: 760)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            trusted = WindowManager.isTrusted
            controller.applySettings()
        }
    }

    // MARK: - Reusable Card Container
    private func snapCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Card 1: General
    private var card1General: some View {
        snapCard {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "rectangle.split.2x2")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Vùng bắt dính"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(L10n.t("Bắt dính cửa sổ bằng cách kéo chúng đến cạnh và góc màn hình."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text(snapEnabled ? L10n.t("Bật") : L10n.t("Tắt"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Toggle("", isOn: $snapEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: snapEnabled) { controller.applySettings() }
                }
            }

            if snapEnabled {
                Divider().opacity(0.15)

                VStack(spacing: 10) {
                    ToggleRow(title: L10n.t("Khôi phục kích thước cửa sổ khi gỡ bắt dính"), isOn: $restoreOnUnsnap)
                    Divider().opacity(0.15)
                    ToggleRow(title: L10n.t("Tạo hiệu ứng cho vùng xem trước"), isOn: $showPreview)
                    Divider().opacity(0.15)
                    ToggleRow(title: L10n.t("Phản hồi rung"), isOn: $hapticEnabled)
                }
            }
        }
        .animation(.default, value: snapEnabled)
    }

    // MARK: - Card 2: Drag Behavior
    private var card2DragBehavior: some View {
        snapCard {
            HStack(spacing: 8) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Kéo tới mép màn hình"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.t("Kéo cửa sổ tới mép; vùng đích sẽ sáng lên, thả chuột để bắt dính."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Divider().opacity(0.15)

            HStack {
                Text(L10n.t("Bật bắt dính khi kéo tới mép"))
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Toggle("", isOn: $dragEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: dragEnabled) { controller.applySettings() }
                    .disabled(!trusted || !snapEnabled)
            }

            if dragEnabled && snapEnabled {
                Divider().opacity(0.15)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Text(L10n.t("Độ nhạy mép"))
                            .font(.system(size: 13))
                            .frame(width: 120, alignment: .leading)
                        Slider(value: $edgeMargin, in: 8...60, step: 1)
                            .onChange(of: edgeMargin) { controller.applySettings() }
                            .disabled(!trusted)
                        Text("\(Int(edgeMargin)) pt")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 45, alignment: .trailing)
                    }
                    Text(L10n.t("Mép trái/phải → nửa màn hình · góc → một phần tư · mép trên → toàn màn hình · mép dưới → nửa dưới."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                }

                Divider().opacity(0.15)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.t("Chừa mép trái cho Stage Manager"))
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Toggle("", isOn: $reserveStage)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    if reserveStage {
                        HStack(spacing: 12) {
                            Text(L10n.t("Bề rộng chừa"))
                                .font(.system(size: 13))
                                .frame(width: 120, alignment: .leading)
                            Slider(value: $stageInset, in: 48...140, step: 2)
                            Text("\(Int(stageInset)) pt")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 45, alignment: .trailing)
                        }
                        Text(L10n.t("macOS không tự thu nhỏ vùng làm việc cho Stage Manager, nên XFinder chừa mép trái để bạn vẫn thấy icon app đang xếp ở đó. Kéo nhỏ lại nếu bạn chỉ cần thấy icon."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
            }
        }
        .animation(.default, value: dragEnabled)
        .animation(.default, value: reserveStage)
    }

    // MARK: - Card 3: Shortcuts
    private var card3Shortcuts: some View {
        snapCard {
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Phím tắt toàn hệ thống"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.t("Áp dụng cho cửa sổ đang được focus."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Divider().opacity(0.15)

            HStack {
                Text(L10n.t("Bật phím tắt bắt dính"))
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Toggle("", isOn: $hotkeysEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: hotkeysEnabled) { controller.applySettings() }
                    .disabled(!trusted || !snapEnabled)
            }

            if hotkeysEnabled && snapEnabled {
                Divider().opacity(0.15)

                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 8) {
                        shortcutItem(label: L10n.t("Nửa trái"), keys: ["⌃", "⌥", "←"])
                        shortcutItem(label: L10n.t("Toàn màn hình"), keys: ["⌃", "⌥", "↑"])
                        shortcutItem(label: L10n.t("Giữa màn hình"), keys: ["⌃", "⌥", "↩"])
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 8) {
                        shortcutItem(label: L10n.t("Nửa phải"), keys: ["⌃", "⌥", "→"])
                        shortcutItem(label: L10n.t("Nửa dưới"), keys: ["⌃", "⌥", "↓"])
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 2)
            }
        }
        .animation(.default, value: hotkeysEnabled)
    }

    // MARK: - Card 4: Visual Guide & Snap Now
    private var card4VisualGuideAndSnapNow: some View {
        snapCard {
            // Header with Segmented Control
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Hướng dẫn chia cửa sổ"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.t("Kéo đến cạnh hoặc góc màn hình, rồi thả."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("", selection: Binding(
                    get: { UserDefaults.standard.string(forKey: "snapzones.orientation") ?? "horizontal" },
                    set: { UserDefaults.standard.set($0, forKey: "snapzones.orientation") }
                )) {
                    Text(L10n.t("Ngang")).tag("horizontal")
                    Text(L10n.t("Dọc")).tag("vertical")
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            Divider().opacity(0.15)

            // 3-Column Visual Guide
            HStack(alignment: .center, spacing: 14) {
                // Cột trái
                VStack(alignment: .leading, spacing: 14) {
                    guideItem(title: L10n.t("Trên bên trái"), subtitle: L10n.t("Một phần tư trên bên trái"))
                    guideItem(title: L10n.t("Trái"), subtitle: L10n.t("Cạnh trái, nửa trên/dưới khi gần góc"))
                    guideItem(title: L10n.t("Dưới bên trái"), subtitle: L10n.t("Một phần tư dưới bên trái"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Cột giữa (bản đồ 3x3 trực quan)
                VStack(spacing: 6) {
                    guideItemCenter(title: L10n.t("Trên"), subtitle: L10n.t("Phóng to"))

                    snapMap3x3

                    guideItemCenter(title: L10n.t("Dưới"), subtitle: L10n.t("Một phần ba. Rê về giữa để lấy hai phần ba."))
                }
                .frame(width: 150)

                // Cột phải
                VStack(alignment: .trailing, spacing: 14) {
                    guideItem(title: L10n.t("Trên bên phải"), subtitle: L10n.t("Một phần tư trên bên phải"), trailing: true)
                    guideItem(title: L10n.t("Phải"), subtitle: L10n.t("Cạnh phải, nửa trên/dưới khi gần góc"), trailing: true)
                    guideItem(title: L10n.t("Dưới bên phải"), subtitle: L10n.t("Một phần tư dưới bên phải"), trailing: true)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 4)

            // Footer of visual guide
            HStack {
                Text(L10n.t("Các lựa chọn được áp dụng cho mọi màn hình có cùng hướng này."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button(L10n.t("Khôi phục mặc định")) { resetSnapDefaults() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Divider().opacity(0.15)

            // Snap Now section
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Bắt dính ngay"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.t("Bấm một vùng để áp dụng cho cửa sổ vừa dùng."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
                LazyVGrid(columns: cols, spacing: 8) {
                    // Row 1
                    snapNowButton(.leftHalf, title: L10n.t("Nửa trái"), icon: "rectangle.lefthalf.filled", isPrimary: true)
                    snapNowButton(.rightHalf, title: L10n.t("Nửa phải"), icon: "rectangle.righthalf.filled", isPrimary: true)
                    snapNowButton(.topHalf, title: L10n.t("Nửa trên"), icon: "rectangle.tophalf.filled")
                    snapNowButton(.bottomHalf, title: L10n.t("Nửa dưới"), icon: "rectangle.bottomhalf.filled")

                    // Row 2
                    snapNowButton(.topLeft, title: L10n.t("Trên bên trái"), icon: "arrow.up.left")
                    snapNowButton(.topRight, title: L10n.t("Trên bên phải"), icon: "arrow.up.right")
                    snapNowButton(.bottomLeft, title: L10n.t("Dưới bên trái"), icon: "arrow.down.left")
                    snapNowButton(.bottomRight, title: L10n.t("Dưới bên phải"), icon: "arrow.down.right")

                    // Row 3
                    snapNowButton(.maximize, title: L10n.t("Toàn màn hình"), icon: "rectangle.fill")
                    snapNowButton(.center, title: L10n.t("Giữa màn hình"), icon: "rectangle.center.inset.filled")
                    Color.clear.frame(height: 32)
                    Color.clear.frame(height: 32)
                }

                if let msg = controller.lastOutcome {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }

            Divider().opacity(0.15)

            // macOS Window Tiling disclosure
            DisclosureGroup(L10n.t("Chia cửa sổ của macOS")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("macOS Sequoia có tính năng chia cửa sổ riêng (Window Tiling). Mở Cài đặt hệ thống → Màn hình & Dock → Chia cửa sổ để cấu hình."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Button(L10n.t("Mở Cài đặt Màn hình & Dock")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
                .padding(.top, 4)
            }
            .font(.system(size: 12))
        }
    }

    // MARK: - Helpers

    private var snapMap3x3: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                snapMapBtn("arrow.up.left", target: .topLeft)
                snapMapBtn("arrow.up", target: .topHalf)
                snapMapBtn("arrow.up.right", target: .topRight)
            }
            HStack(spacing: 3) {
                snapMapBtn("arrow.left", target: .leftHalf)
                Button {
                    snapAction(.maximize)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.85))
                        Image(systemName: "macwindow")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 34, height: 26)
                }
                .buttonStyle(.plain)
                .help(L10n.t("Toàn màn hình"))

                snapMapBtn("arrow.right", target: .rightHalf)
            }
            HStack(spacing: 3) {
                snapMapBtn("arrow.down.left", target: .bottomLeft)
                snapMapBtn("arrow.down", target: .bottomHalf)
                snapMapBtn("arrow.down.right", target: .bottomRight)
            }
        }
        .padding(6)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    private func snapMapBtn(_ icon: String, target: WindowManager.SnapTarget) -> some View {
        Button {
            snapAction(target)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 34, height: 26)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(target.titleVI)
    }

    private func snapNowButton(_ target: WindowManager.SnapTarget, title: String, icon: String, isPrimary: Bool = false) -> some View {
        Button {
            snapAction(target)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: isPrimary ? .semibold : .regular))
                    .foregroundColor(isPrimary ? .accentColor : .primary.opacity(0.8))
                Text(title)
                    .font(.system(size: 11, weight: isPrimary ? .medium : .regular))
                    .foregroundColor(isPrimary ? .accentColor : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isPrimary ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isPrimary ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!trusted)
    }

    private func snapAction(_ zone: WindowManager.SnapTarget) {
        if hapticEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        let ok = WindowManager.snapFrontmost(to: zone)
        controller.lastOutcome = ok
            ? "\(L10n.t("Đã đưa cửa sổ vào “"))\(zone.titleVI)”."
            : L10n.t("Không di chuyển được — ứng dụng không cho phép hoặc thiếu quyền.")
    }

    private func guideItem(title: String, subtitle: String, trailing: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if !trailing {
                Image(systemName: "checkmark.square.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 13))
                    .padding(.top, 1)
            }
            VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(trailing ? .trailing : .leading)
            }
            if trailing {
                Image(systemName: "checkmark.square.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 13))
                    .padding(.top, 1)
            }
        }
    }

    private func guideItemCenter(title: String, subtitle: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "checkmark.square.fill")
                .foregroundColor(.accentColor)
                .font(.system(size: 13))
            Text(title)
                .font(.system(size: 11, weight: .medium))
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func shortcutItem(label: String, keys: [String]) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.primary)
            Spacer()
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                }
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
        snapCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.t("Cần quyền Trợ năng"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.orange)
                Text(L10n.t("macOS chỉ cho phép di chuyển cửa sổ của ứng dụng khác khi bạn cấp quyền Trợ năng cho XFinder."))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                HStack {
                    Button(L10n.t("Mở Cài đặt Trợ năng")) { WindowManager.openAccessibilityPane() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button(L10n.t("Kiểm tra lại")) {
                        trusted = WindowManager.isTrusted
                        controller.applySettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}
