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
                           title: "Xem trước cửa sổ",
                           subtitle: "Xem trước và chuyển cửa sổ ứng dụng ngay từ Dock.")

                SectionHeader(icon: "square.on.square",
                              title: "Cách hoạt động",
                              subtitle: "Di chuột qua ứng dụng trên Dock để xem trước các cửa sổ.")

                VStack(alignment: .leading, spacing: 4) {
                    ToggleRow(title: "Hiện bản xem trước cửa sổ khi di chuột qua ứng dụng trên Dock",
                              isOn: $hoverEnabled)
                        .onChange(of: hoverEnabled) { controller.applySettings() }
                    Text("XFinder chỉ chụp ảnh thu nhỏ khi bảng xem trước đang hiển thị.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    if hoverEnabled {
                        Text(controller.statusHint)
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                SectionHeader(icon: "command",
                              title: "Xem trước cửa sổ bằng Command-Tab",
                              subtitle: "Chuyển trực tiếp giữa các cửa sổ bằng hình xem trước trực tiếp.")

                VStack(alignment: .leading, spacing: 4) {
                    ToggleRow(title: "Hiện bản xem trước cửa sổ bằng Command-Tab",
                              isOn: $commandTabEnabled)
                        .onChange(of: commandTabEnabled) { CommandTabController.shared.applySettings() }
                    Text("Khi bật, XFinder xử lý Command-Tab thay cho bộ chuyển ứng dụng của macOS. Giữ Command và nhấn Tab hoặc Shift-Tab để chọn cửa sổ; thả Command để mở hoặc nhấn Escape để hủy.")
                        .font(.system(size: 11)).foregroundColor(.secondary)

                    ToggleRow(title: "Hiện cả cửa sổ ẩn trong App Switcher",
                              isOn: $showHiddenWindows)
                        .padding(.top, 8)
                    Text("Một số ứng dụng chỉ ẩn cửa sổ khi bạn đóng thay vì thoát — Spotify, Slack, Synology Chat. Liệt kê những cửa sổ đó cho phép Command-Tab gọi lại chúng, nhưng ứng dụng phải mở lại cửa sổ trước, nên sẽ hiện chậm hơn một chút.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                SectionHeader(icon: "lock.shield",
                              title: "Quyền cần thiết",
                              subtitle: "Trợ năng nhận diện ứng dụng trên Dock; Ghi màn hình hiển thị ảnh thu nhỏ trực tiếp.")

                VStack(spacing: 10) {
                    PermissionRow(title: "Trợ năng",
                                  granted: trusted,
                                  grantedText: "Đã cấp") {
                        WindowManager.openAccessibilityPane()
                    }
                    PermissionRow(title: "Ghi màn hình",
                                  granted: canRecord,
                                  grantedText: "Đã cấp") {
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
            Text(granted ? grantedText : "Chưa cấp")
                .font(.system(size: 12)).foregroundColor(.secondary)
            Button("Cấp…") { onGrant() }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }
}


/// Vùng bắt dính — snaps the *focused* window: drag it to a screen edge, or
/// use ⌃⌥ + arrows. Both need Accessibility trust, so the page leads with the
/// grant flow when it is missing rather than showing controls that do nothing.
struct SnapZonesDetailView: View {
    @AppStorage("snapzones.enabled") private var snapEnabled = true
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
                    title: "Vùng bắt dính",
                    subtitle: "Kéo cửa sổ tới mép màn hình hoặc dùng phím tắt để bắt dính.",
                    trailing: AnyView(
                        HStack(spacing: 6) {
                            Text(snapEnabled ? "Bật" : "Tắt")
                                .font(.system(size: 12)).foregroundColor(.secondary)
                            // Gate only — the sub-toggles keep their own values
                            // so switching the feature off and on again restores
                            // exactly what the user had configured.
                            Toggle("", isOn: $snapEnabled)
                                .labelsHidden()
                                .onChange(of: snapEnabled) { controller.applySettings() }
                        }
                    ))

                if !trusted {
                    permissionBanner
                    Divider().padding(.horizontal, 20)
                }

                SectionHeader(icon: "hand.draw",
                              title: "Kéo tới mép màn hình",
                              subtitle: "Kéo cửa sổ tới mép; vùng đích sẽ sáng lên, thả chuột để bắt dính.")

                VStack(alignment: .leading, spacing: 8) {
                    ToggleRow(title: "Bật bắt dính khi kéo tới mép", isOn: $dragEnabled)
                        .onChange(of: dragEnabled) { controller.applySettings() }
                        .disabled(!trusted)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Độ nhạy mép \(Int(edgeMargin)) pt")
                            .font(.system(size: 13))
                        Slider(value: $edgeMargin, in: 8...60, step: 1)
                            .onChange(of: edgeMargin) { controller.applySettings() }
                            .disabled(!trusted || !dragEnabled)
                    }

                    Text("Mép trái/phải → nửa màn hình · góc → một phần tư · mép trên → toàn màn hình · mép dưới → nửa dưới.")
                        .font(.system(size: 11)).foregroundColor(.secondary)

                    if WindowManager.isStageManagerEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            ToggleRow(title: "Chừa mép trái cho Stage Manager",
                                      isOn: $reserveStage)
                                .disabled(!snapEnabled)

                            if reserveStage {
                                Text("Bề rộng chừa: \(Int(stageInset)) pt")
                                    .font(.system(size: 13))
                                // Floor of 48pt: measured as the narrowest strip
                                // that still shows a recognisable app icon.
                                // Below that the clearance is useless, so the
                                // honest control is the on/off toggle above,
                                // not a slider that trails off to nothing.
                                Slider(value: $stageInset, in: 48...140, step: 2)
                                    .disabled(!snapEnabled)
                                Text("macOS không tự thu nhỏ vùng làm việc cho Stage Manager, nên XFinder chừa mép trái để bạn vẫn thấy icon app đang xếp ở đó. Kéo nhỏ lại nếu bạn chỉ cần thấy icon.")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                            } else {
                                Text("Cửa sổ sẽ bắt dính hết chiều ngang màn hình và có thể che dải Stage Manager.")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                SectionHeader(icon: "keyboard",
                              title: "Phím tắt toàn hệ thống",
                              subtitle: "Áp dụng cho cửa sổ đang được focus.")

                VStack(alignment: .leading, spacing: 8) {
                    ToggleRow(title: "Bật phím tắt bắt dính", isOn: $hotkeysEnabled)
                        .onChange(of: hotkeysEnabled) { controller.applySettings() }
                        .disabled(!trusted)

                    VStack(spacing: 4) {
                        shortcutRow("⌃⌥ ←", "Nửa trái")
                        shortcutRow("⌃⌥ →", "Nửa phải")
                        shortcutRow("⌃⌥ ↑", "Toàn màn hình")
                        shortcutRow("⌃⌥ ↓", "Nửa dưới")
                        shortcutRow("⌃⌥ ↩", "Giữa màn hình")
                    }
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                SectionHeader(icon: "square.grid.3x3",
                              title: "Bắt dính ngay",
                              subtitle: "Bấm một vùng để áp dụng cho cửa sổ vừa dùng.")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(WindowManager.SnapTarget.allCases) { zone in
                        Button {
                            let ok = WindowManager.snapFrontmost(to: zone)
                            controller.lastOutcome = ok
                                ? "Đã đưa cửa sổ vào “\(zone.titleVI)”."
                                : "Không di chuyển được — ứng dụng không cho phép hoặc thiếu quyền."
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

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cần quyền Trợ năng", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.orange)
            Text("macOS chỉ cho phép di chuyển cửa sổ của ứng dụng khác khi bạn cấp quyền Trợ năng cho XFinder.")
                .font(.system(size: 12)).foregroundColor(.secondary)
            HStack {
                Button("Mở Cài đặt Trợ năng") { WindowManager.openAccessibilityPane() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button("Kiểm tra lại") {
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
