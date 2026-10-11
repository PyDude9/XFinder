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
    // Phase C. Reader: WindowPreviewStore.currentScreenOnly (default must match — FeatureKeyDefaultsTests).
    @AppStorage("windowPreview.currentScreenOnly") private var currentScreenOnly = false
    @State private var dockAutohide = DockPrefs.autohide()
    @State private var excludedApps: [String] = WindowPreviewStore.excludedApps
    @State private var newExcludedApp: String = ""
    @State private var controller = DockPreviewController.shared
    @State private var trusted = WindowManager.isTrusted
    @State private var canRecord = WindowManager.canRecordScreen

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(icon: "macwindow.on.rectangle",
                           title: L10n.t("Xem trước cửa sổ"),
                           subtitle: L10n.t("Xem trước và chuyển cửa sổ ứng dụng ngay từ Dock."))

                // Section 1: Switcher
                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(icon: "command",
                                  title: L10n.t("Chuyển cửa sổ bằng phím tắt"),
                                  subtitle: L10n.t("Chuyển trực tiếp giữa các cửa sổ bằng hình xem trước trực tiếp."))

                    ToggleRow(title: L10n.t("Bật bộ chuyển cửa sổ Liquid Glass"),
                              isOn: $commandTabEnabled)
                        .onChange(of: commandTabEnabled) { CommandTabController.shared.applySettings() }
                    InlineNote(text: L10n.t("Khi bật, XFinder xử lý chuyển cửa sổ thay cho bộ chuyển ứng dụng của macOS. Giữ phím tắt để duyệt; trong lúc giữ: Q đóng cửa sổ đang chọn, H ẩn ứng dụng, Space phóng to ảnh, dấu huyền (`) chuyển giữa một thẻ mỗi ứng dụng và từng cửa sổ của ứng dụng đó, dấu phẩy (,) để tìm; thả phím để mở, Escape để hủy."))

                    ToggleRow(title: L10n.t("Chỉ cửa sổ trên màn hình có con trỏ"),
                              subtitle: L10n.t("Nhiều màn hình: danh sách chỉ gồm cửa sổ nằm (một phần hoặc toàn bộ) trên màn hình đang có con trỏ."),
                              isOn: $currentScreenOnly)

                    HStack {
                        Text(L10n.t("Phím tắt chuyển cửa sổ"))
                            .font(XFinderTokens.Font.row)
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
                    InlineNote(text: L10n.t("Mượt mà với hoạt cảnh co giãn và bóng mờ Liquid Glass."))

                    ToggleRow(title: L10n.t("Hiện cả cửa sổ ẩn trong App Switcher"),
                              isOn: $showHiddenWindows)
                    InlineNote(text: L10n.t("Một số ứng dụng chỉ ẩn cửa sổ khi bạn đóng thay vì thoát — Spotify, Slack, Synology Chat. Liệt kê những cửa sổ đó cho phép Command-Tab gọi lại chúng, nhưng ứng dụng phải mở lại cửa sổ trước, nên sẽ hiện chậm hơn một chút."))
                }
                .padding(.horizontal, XFinderTokens.Space.page)

                Divider().padding(.horizontal, XFinderTokens.Space.page)

                // Section 2: Dock
                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(icon: "square.on.square",
                                  title: L10n.t("Dải Dock Liquid Glass"),
                                  subtitle: L10n.t("Di chuột qua ứng dụng trên Dock để xem trước các cửa sổ."))

                    ToggleRow(title: L10n.t("Hiện bản xem trước cửa sổ khi di chuột qua ứng dụng trên Dock"),
                              isOn: $hoverEnabled)
                        .onChange(of: hoverEnabled) { controller.applySettings() }
                    InlineNote(text: L10n.t("XFinder chỉ chụp ảnh thu nhỏ khi bảng xem trước đang hiển thị."))

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
                .padding(.horizontal, XFinderTokens.Space.page)

                Divider().padding(.horizontal, XFinderTokens.Space.page)

                // Section 3: Excluded Apps
                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(icon: "nosign",
                                  title: L10n.t("Ứng dụng loại trừ"),
                                  subtitle: L10n.t("Các ứng dụng này sẽ không xuất hiện trong bộ chuyển cửa sổ."))

                    if excludedApps.isEmpty {
                        Text(L10n.t("Chưa có ứng dụng nào bị loại trừ."))
                            .font(XFinderTokens.Font.rowValue)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: XFinderTokens.Space.tight) {
                            ForEach(excludedApps, id: \.self) { app in
                                HStack {
                                    Text(app)
                                        .font(XFinderTokens.Font.mono)
                                        .fileNameRowSafe()
                                    Spacer()
                                    Button(action: {
                                        excludedApps.removeAll { $0 == app }
                                        WindowPreviewStore.setExcludedApps(excludedApps)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, XFinderTokens.Space.inline)
                                .padding(.vertical, XFinderTokens.Space.tight)
                                .background(XFinderTokens.Fill.inset)
                                .cornerRadius(XFinderTokens.Radius.badge)
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
                                WindowPreviewStore.setExcludedApps(excludedApps)
                                newExcludedApp = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(newExcludedApp.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.horizontal, XFinderTokens.Space.page)

                Divider().padding(.horizontal, XFinderTokens.Space.page)

                // Section 4: Permissions
                VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                    SectionHeader(icon: "lock.shield",
                                  title: L10n.t("Quyền cần thiết"),
                                  subtitle: L10n.t("Trợ năng nhận diện ứng dụng trên Dock; Ghi màn hình hiển thị ảnh thu nhỏ trực tiếp."))

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
                .padding(.horizontal, XFinderTokens.Space.page)
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Fill.window)
        .onAppear {
            trusted = WindowManager.isTrusted
            canRecord = WindowManager.canRecordScreen
            dockAutohide = DockPrefs.autohide()
            excludedApps = WindowPreviewStore.excludedApps
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
        HStack(spacing: XFinderTokens.Space.inline) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(granted ? .green : .orange)
            Text(title).font(XFinderTokens.Font.row)
            Spacer()
            Text(granted ? grantedText : L10n.t("Chưa cấp"))
                .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
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
    // B3: dragging a window to the notch shows a layout row. Reader: SnapZoneController (default must match).
    @AppStorage("snapzones.notchRow") private var notchRow = true
    @State private var controller = SnapZoneController.shared
    @State private var trusted = WindowManager.isTrusted

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                PageHeader(icon: "rectangle.split.2x2",
                           title: L10n.t("Vùng bắt dính"),
                           subtitle: L10n.t("Bắt dính cửa sổ bằng cách kéo chúng đến cạnh và góc màn hình."))

                if !trusted {
                    permissionBanner
                }

                section1General
                section2DragBehavior
                section3Shortcuts
                section4VisualGuideAndSnapNow
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Fill.window)
        .onAppear {
            trusted = WindowManager.isTrusted
            controller.applySettings()
        }
    }

    // MARK: - Section 1: General

    private var section1General: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            ToggleRow(title: L10n.t("Vùng bắt dính"),
                      subtitle: L10n.t("Bắt dính cửa sổ bằng cách kéo chúng đến cạnh và góc màn hình."),
                      isOn: $snapEnabled)
                .onChange(of: snapEnabled) { controller.applySettings() }
                .padding(.horizontal, XFinderTokens.Space.page)

            if snapEnabled {
                ToggleRow(title: L10n.t("Khôi phục kích thước cửa sổ khi gỡ bắt dính"), isOn: $restoreOnUnsnap)
                    .padding(.horizontal, XFinderTokens.Space.page)
                Divider().padding(.horizontal, XFinderTokens.Space.page)
                ToggleRow(title: L10n.t("Tạo hiệu ứng cho vùng xem trước"), isOn: $showPreview)
                    .padding(.horizontal, XFinderTokens.Space.page)
                Divider().padding(.horizontal, XFinderTokens.Space.page)
                ToggleRow(title: L10n.t("Phản hồi rung"), isOn: $hapticEnabled)
                    .padding(.horizontal, XFinderTokens.Space.page)
            }

            Divider().padding(.horizontal, XFinderTokens.Space.page)
        }
        .animation(.default, value: snapEnabled)
    }

    // MARK: - Section 2: Drag Behavior

    private var section2DragBehavior: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(icon: "hand.draw",
                          title: L10n.t("Kéo tới mép màn hình"),
                          subtitle: L10n.t("Kéo cửa sổ tới mép; vùng đích sẽ sáng lên, thả chuột để bắt dính."))

            ToggleRow(title: L10n.t("Bật bắt dính khi kéo tới mép"), isOn: $dragEnabled)
                .onChange(of: dragEnabled) { controller.applySettings() }
                .disabled(!trusted || !snapEnabled)
                .padding(.horizontal, XFinderTokens.Space.page)

            ToggleRow(title: L10n.t("Hàng bố cục khi kéo cửa sổ tới notch"),
                      subtitle: L10n.t("Kéo cửa sổ lên giữa cạnh trên: một hàng bố cục hiện ra (nửa, ba phần, tập trung, toàn màn hình). Thả lên một ô để đặt cửa sổ. Tắt thì cạnh trên vẫn phóng to như trước."),
                      isOn: $notchRow)
                .disabled(!trusted || !snapEnabled || !dragEnabled)
                .padding(.horizontal, XFinderTokens.Space.page)

            if dragEnabled && snapEnabled {
                Divider().padding(.horizontal, XFinderTokens.Space.page)

                VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                    HStack(spacing: XFinderTokens.Space.inline) {
                        Text(L10n.t("Độ nhạy mép"))
                            .font(XFinderTokens.Font.row)
                            .frame(width: 120, alignment: .leading)
                        Slider(value: $edgeMargin, in: 8...60, step: 1)
                            .onChange(of: edgeMargin) { controller.applySettings() }
                            .disabled(!trusted)
                        Text("\(Int(edgeMargin)) pt")
                            .font(XFinderTokens.Font.mono)
                            .foregroundColor(.secondary)
                            .frame(width: 45, alignment: .trailing)
                    }
                    Text(L10n.t("Mép trái/phải → nửa màn hình · góc → một phần tư · mép trên → toàn màn hình · mép dưới → nửa dưới."))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, XFinderTokens.Space.page)

                Divider().padding(.horizontal, XFinderTokens.Space.page)

                VStack(alignment: .leading, spacing: XFinderTokens.Space.inline) {
                    ToggleRow(title: L10n.t("Chừa mép trái cho Stage Manager"), isOn: $reserveStage)

                    if reserveStage {
                        HStack(spacing: XFinderTokens.Space.inline) {
                            Text(L10n.t("Bề rộng chừa"))
                                .font(XFinderTokens.Font.row)
                                .frame(width: 120, alignment: .leading)
                            Slider(value: $stageInset, in: 48...140, step: 2)
                            Text("\(Int(stageInset)) pt")
                                .font(XFinderTokens.Font.mono)
                                .foregroundColor(.secondary)
                                .frame(width: 45, alignment: .trailing)
                        }
                        Text(L10n.t("macOS không tự thu nhỏ vùng làm việc cho Stage Manager, nên XFinder chừa mép trái để bạn vẫn thấy icon app đang xếp ở đó. Kéo nhỏ lại nếu bạn chỉ cần thấy icon."))
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, XFinderTokens.Space.page)
            }

            Divider().padding(.horizontal, XFinderTokens.Space.page)
        }
        .animation(.default, value: dragEnabled)
        .animation(.default, value: reserveStage)
    }

    // MARK: - Section 3: Shortcuts

    private var section3Shortcuts: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            SectionHeader(icon: "keyboard",
                          title: L10n.t("Phím tắt toàn hệ thống"),
                          subtitle: L10n.t("Áp dụng cho cửa sổ đang được focus."))

            ToggleRow(title: L10n.t("Bật phím tắt bắt dính"), isOn: $hotkeysEnabled)
                .onChange(of: hotkeysEnabled) { controller.applySettings() }
                .disabled(!trusted || !snapEnabled)
                .padding(.horizontal, XFinderTokens.Space.page)

            if hotkeysEnabled && snapEnabled {
                Divider().padding(.horizontal, XFinderTokens.Space.page)

                HStack(alignment: .top, spacing: XFinderTokens.Space.section) {
                    VStack(spacing: XFinderTokens.Space.inline) {
                        shortcutItem(label: L10n.t("Nửa trái"), keys: ["⌃", "⌥", "←"])
                        shortcutItem(label: L10n.t("Toàn màn hình"), keys: ["⌃", "⌥", "↑"])
                        shortcutItem(label: L10n.t("Giữa màn hình"), keys: ["⌃", "⌥", "↩"])
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: XFinderTokens.Space.inline) {
                        shortcutItem(label: L10n.t("Nửa phải"), keys: ["⌃", "⌥", "→"])
                        shortcutItem(label: L10n.t("Nửa dưới"), keys: ["⌃", "⌥", "↓"])
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, XFinderTokens.Space.page)
                .padding(.vertical, 2)
            }

            Divider().padding(.horizontal, XFinderTokens.Space.page)
        }
        .animation(.default, value: hotkeysEnabled)
    }

    // MARK: - Section 4: Visual Guide & Snap Now

    private var section4VisualGuideAndSnapNow: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            // Header with Segmented Control
            HStack {
                SectionHeader(icon: "square.grid.3x3",
                              title: L10n.t("Hướng dẫn chia cửa sổ"),
                              subtitle: L10n.t("Kéo đến cạnh hoặc góc màn hình, rồi thả."))
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
                .padding(.trailing, XFinderTokens.Space.page)
            }

            // 3-Column Visual Guide — true grid, keeps the tile look
            HStack(alignment: .center, spacing: XFinderTokens.Space.inline) {
                // Cột trái
                VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                    guideItem(title: L10n.t("Trên bên trái"), subtitle: L10n.t("Một phần tư trên bên trái"))
                    guideItem(title: L10n.t("Trái"), subtitle: L10n.t("Cạnh trái, nửa trên/dưới khi gần góc"))
                    guideItem(title: L10n.t("Dưới bên trái"), subtitle: L10n.t("Một phần tư dưới bên trái"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Cột giữa (bản đồ 3x3 trực quan)
                VStack(spacing: XFinderTokens.Space.tight) {
                    guideItemCenter(title: L10n.t("Trên"), subtitle: L10n.t("Phóng to"))

                    snapMap3x3

                    guideItemCenter(title: L10n.t("Dưới"), subtitle: L10n.t("Một phần ba. Rê về giữa để lấy hai phần ba."))
                }
                .frame(width: 150)

                // Cột phải
                VStack(alignment: .trailing, spacing: XFinderTokens.Space.section) {
                    guideItem(title: L10n.t("Trên bên phải"), subtitle: L10n.t("Một phần tư trên bên phải"), trailing: true)
                    guideItem(title: L10n.t("Phải"), subtitle: L10n.t("Cạnh phải, nửa trên/dưới khi gần góc"), trailing: true)
                    guideItem(title: L10n.t("Dưới bên phải"), subtitle: L10n.t("Một phần tư dưới bên phải"), trailing: true)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, XFinderTokens.Space.page)
            .padding(.vertical, 4)

            // Footer of visual guide
            HStack {
                Text(L10n.t("Các lựa chọn được áp dụng cho mọi màn hình có cùng hướng này."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(L10n.t("Khôi phục mặc định")) { resetSnapDefaults() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, XFinderTokens.Space.page)

            Divider().padding(.horizontal, XFinderTokens.Space.page)

            // Snap Now section
            VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                SectionHeader(icon: "square.and.arrow.down.on.square",
                              title: L10n.t("Bắt dính ngay"),
                              subtitle: L10n.t("Bấm một vùng để áp dụng cho cửa sổ vừa dùng."))

                let cols = Array(repeating: GridItem(.flexible(), spacing: XFinderTokens.Space.tight), count: 4)
                LazyVGrid(columns: cols, spacing: XFinderTokens.Space.tight) {
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
                    snapNowButton(.leftThird, title: L10n.t("Một phần ba bên trái"), icon: "rectangle.leadingthird.inset.filled")
                    snapNowButton(.centerThird, title: L10n.t("Một phần ba ở giữa"), icon: "rectangle.center.inset.filled")
                    snapNowButton(.rightThird, title: L10n.t("Một phần ba bên phải"), icon: "rectangle.trailingthird.inset.filled")
                    snapNowButton(.focus, title: L10n.t("Tập trung (giữa, 60% bề ngang)"), icon: "rectangle.inset.filled")
                    Color.clear.frame(height: 32)
                    Color.clear.frame(height: 32)
                }

                if let msg = controller.lastOutcome {
                    Text(msg)
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, XFinderTokens.Space.page)

            Divider().padding(.horizontal, XFinderTokens.Space.page)

            // macOS Window Tiling disclosure
            DisclosureGroup(L10n.t("Chia cửa sổ của macOS")) {
                VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                    Text(L10n.t("macOS Sequoia có tính năng chia cửa sổ riêng (Window Tiling). Mở Cài đặt hệ thống → Màn hình & Dock → Chia cửa sổ để cấu hình."))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                    Button(L10n.t("Mở Cài đặt Màn hình & Dock")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(XFinderTokens.Font.caption)
                }
                .padding(.top, 4)
            }
            .font(XFinderTokens.Font.rowValue)
            .padding(.horizontal, XFinderTokens.Space.page)
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
                        RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                            .fill(Color.accentColor.opacity(0.85))
                        Image(systemName: "macwindow")
                            .font(XFinderTokens.Font.sectionTitle)
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
        .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    private func snapMapBtn(_ icon: String, target: WindowManager.SnapTarget) -> some View {
        Button {
            snapAction(target)
        } label: {
            Image(systemName: icon)
                .font(XFinderTokens.Font.rowValue)
                .foregroundColor(.accentColor)
                .frame(width: 34, height: 26)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(target.titleVI)
    }

    private func snapNowButton(_ target: WindowManager.SnapTarget, title: String, icon: String, isPrimary: Bool = false) -> some View {
        Button {
            snapAction(target)
        } label: {
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: icon)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(isPrimary ? .accentColor : .primary.opacity(0.8))
                Text(title)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(isPrimary ? .accentColor : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                    .fill(isPrimary ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
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
        HStack(alignment: .top, spacing: XFinderTokens.Space.tight) {
            if !trailing {
                Image(systemName: "checkmark.square.fill")
                    .foregroundColor(.accentColor)
                    .font(XFinderTokens.Font.sectionTitle)
                    .padding(.top, 1)
            }
            VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
                Text(title)
                    .font(XFinderTokens.Font.caption)
                Text(subtitle)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(trailing ? .trailing : .leading)
            }
            if trailing {
                Image(systemName: "checkmark.square.fill")
                    .foregroundColor(.accentColor)
                    .font(XFinderTokens.Font.sectionTitle)
                    .padding(.top, 1)
            }
        }
    }

    private func guideItemCenter(title: String, subtitle: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "checkmark.square.fill")
                .foregroundColor(.accentColor)
                .font(XFinderTokens.Font.sectionTitle)
            Text(title)
                .font(XFinderTokens.Font.caption)
            Text(subtitle)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func shortcutItem(label: String, keys: [String]) -> some View {
        HStack {
            Text(label)
                .font(XFinderTokens.Font.rowValue)
                .foregroundColor(.primary)
            Spacer()
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(XFinderTokens.Font.mono)
                        .foregroundColor(.primary.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(XFinderTokens.Radius.badge)
                        .overlay(
                            RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
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
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            Label(L10n.t("Cần quyền Trợ năng"), systemImage: "exclamationmark.triangle.fill")
                .font(XFinderTokens.Font.row)
                .foregroundColor(.orange)
            InlineNote(kind: .warning,
                       text: L10n.t("macOS chỉ cho phép di chuyển cửa sổ của ứng dụng khác khi bạn cấp quyền Trợ năng cho XFinder."))
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
        .padding(.horizontal, XFinderTokens.Space.page)
    }
}
