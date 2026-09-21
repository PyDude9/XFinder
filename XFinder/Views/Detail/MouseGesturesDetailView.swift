import SwiftUI
import AppKit

// No .monospaced() on a Font, no Gauge/Grid/scrollContentBackground/symbolEffect/NavigationSplitView.
struct MouseGesturesDetailView: View {
    @State private var controller = GestureController.shared
    @State private var profile = GestureProfiles.fallback
    @State private var customBundle = ""
    @State private var recordingDirection: GestureDirection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(icon: "computermouse", title: L10n.t("Chuột & cử chỉ"),
                           subtitle: L10n.t("Giữ nút, kéo một hướng, thả để gửi phím tắt theo ứng dụng."))
                heroCard
                triggerCard
                sensitivityCard
                optInCard
                mappingSection
                Text(L10n.t("Nếu không hoạt động: kiểm tra Trợ năng, bundle ID, phím tắt của app và tắt mapping trùng trong phần mềm chuột khác. Tắt công tắc để ngừng xử lý cử chỉ."))
                    .font(.system(size: 11)).foregroundColor(.secondary).padding(.horizontal, 20)
            }.padding(.vertical, 20)
        }
        .onAppear { controller.start() }
        .onDisappear { controller.cancelRecording() }
        .onChange(of: profile) { _, _ in recordingDirection = nil }
    }

    // MARK: Hero — tiny decoration, never hit-tested. Highlights the direction
    // currently being recorded so the picker → card connection is legible.
    private var heroCard: some View {
        let active: GestureDirection? = controller.recording ? recordingDirection : nil
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.controlBackgroundColor))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            HStack(spacing: 0) {
                Canvas { ctx, size in
                    let r = min(size.width, size.height) * 0.52
                    let c = CGPoint(x: size.width/2, y: size.height/2)
                    var p = Path()
                    p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r*2, height: r*2))
                    ctx.stroke(p, with: .color(Color.secondary.opacity(0.18)), lineWidth: 1)
                }.frame(width: 96, height: 96).opacity(0.9)
                ZStack {
                    Image(systemName: "computermouse.fill")
                        .font(.system(size: 30)).foregroundColor(.primary.opacity(0.9))
                    Circle().fill(Color.primary.opacity(0.12)).frame(width: 18, height: 18)
                        .offset(y: 8)
                }.frame(width: 96, height: 96)
                Canvas { ctx, size in
                    let r = min(size.width, size.height) * 0.52
                    let c = CGPoint(x: size.width/2, y: size.height/2)
                    var p = Path()
                    p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r*2, height: r*2))
                    ctx.stroke(p, with: .color(Color.secondary.opacity(0.18)), lineWidth: 1)
                }.frame(width: 96, height: 96).opacity(0.9)
            }
            .overlay(alignment: .top) { arrow(L10n.t("↑"), active == .up).offset(y: 8) }
            .overlay(alignment: .bottom) { arrow(L10n.t("↓"), active == .down).offset(y: -8) }
            .overlay(alignment: .leading) { arrow(L10n.t("←"), active == .left).offset(x: 18) }
            .overlay(alignment: .trailing) { arrow(L10n.t("→"), active == .right).offset(x: -18) }
            .allowsHitTesting(false)
        }
        .frame(height: 126)
        .padding(.horizontal, 20)
    }
    private func arrow(_ s: String, _ on: Bool) -> some View {
        Text(s).font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(on ? .accentColor : .secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill((on ? Color.accentColor : Color.secondary).opacity(0.12)))
    }

    private var triggerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCard(title: L10n.t("Kích hoạt"), subtitle: L10n.t("Chọn nút hoặc modifier giữ để bắt cử chỉ")) {
                Toggle(L10n.t("Bật cử chỉ chuột"), isOn: Binding(
                    get: { controller.configuration.enabled },
                    set: { v in controller.update { $0.enabled = v } }))
                Text(L10n.t(controller.status)).font(.system(size: 11)).foregroundColor(.secondary)
                Divider()
                HStack {
                    Text(L10n.t("Nút kích hoạt") + ": " + controller.configuration.trigger.label).font(.system(size: 12))
                    Spacer()
                    Button(L10n.t("Ghi nút / modifier")) { controller.recordTrigger() }.disabled(controller.recording)
                    Button(L10n.t("Cấp quyền Trợ năng")) { WindowManager.requestAccessibilityTrust() }
                }
                Text(L10n.t("Mặc định: nút giữa (Button 2). Không dùng nút trái. Khi đổi chuột, ghi lại nút nếu mã nút khác. Modifier vẫn giữ chức năng bàn phím thông thường."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                if controller.recording {
                    Text(L10n.t("Đang ghi — Esc để hủy, tự dừng sau 10 giây")).font(.system(size: 11)).foregroundColor(.orange)
                    Button(L10n.t("Hủy ghi")) { controller.cancelRecording() }
                }
            }
        }.padding(.horizontal, 20)
    }

    private var sensitivityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCard(title: L10n.t("Độ nhạy"), subtitle: L10n.t("Ngưỡng chuyển động và giữ")) {
                HStack {
                    Text(L10n.t("Ngưỡng chuyển động (delta)")).font(.system(size: 12))
                    Slider(value: Binding(get: { controller.configuration.deadzone },
                        set: { v in controller.update { $0.deadzone = v } }), in: 4...200, step: 1)
                    Text(String(format: "%.0f", controller.configuration.deadzone))
                        .font(.system(size: 12, design: .monospaced)).frame(width: 28, alignment: .trailing)
                }
                Text(L10n.t("Đơn vị delta, không phải điểm màn hình. Kéo dưới ngưỡng sẽ phát lại click; kéo rồi quay về không tạo click. Nút giữ tối đa 15 giây."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
        }.padding(.horizontal, 20)
    }

    private var optInCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCard(title: L10n.t("Tuỳ chọn"), subtitle: L10n.t("Bật khi cần")) {
                Toggle(L10n.t("Ánh xạ tilt ngang rời rạc (không cần giữ nút)"), isOn: Binding(
                    get: { controller.configuration.tiltEnabled },
                    set: { v in controller.update { $0.tiltEnabled = v } }))
                Text(L10n.t("Không bắt cuộn liên tục của Magic Mouse/trackpad. Tilt dùng phím tắt có giới hạn 350 ms; cuộn ngang nguyên bản không làm mượt thêm."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                Toggle(L10n.t("Log chẩn đoán (tối đa 4 lần/giây)"), isOn: Binding(
                    get: { controller.configuration.debug },
                    set: { v in controller.update { $0.debug = v } }))
            }
        }.padding(.horizontal, 20)
    }

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "keyboard", title: L10n.t("Phím gửi theo ứng dụng"),
                          subtitle: L10n.t("Đây là phím được gửi, không đảm bảo mọi app gán cùng chức năng. Mục chưa rõ để Chưa gán; ghi phím riêng để thay đổi."))
            HStack(spacing: 8) {
                Picker(L10n.t("Ứng dụng"), selection: $profile) {
                    ForEach(GestureProfiles.all) { item in
                        Text(item.id == "*" ? L10n.t("Mặc định toàn cục") : item.name).tag(item.id)
                    }
                    ForEach(customProfiles, id: \.self) { id in Text(id).tag(id) }
                }.pickerStyle(.menu).frame(maxWidth: 260)
                Spacer()
            }.padding(.horizontal, 20)
            HStack(spacing: 8) {
                TextField(L10n.t("Bundle ID ứng dụng khác"), text: $customBundle).textFieldStyle(.roundedBorder)
                Button(L10n.t("Chọn")) {
                    let id = customBundle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !id.isEmpty { profile = id }
                }
            }.padding(.horizontal, 20)
            if !controller.lastExternalBundle.isEmpty {
                Button(L10n.t("Dùng ứng dụng vừa hoạt động") + ": " + controller.lastExternalBundle) {
                    profile = controller.lastExternalBundle
                }.lineLimit(1).padding(.horizontal, 20)
            }
            Text(profile).font(.system(size: 11)).foregroundColor(.secondary).textSelection(.enabled).padding(.horizontal, 20)
            ForEach(GestureDirection.allCases, id: \.self) { direction in
                actionRow(direction).padding(.horizontal, 20)
            }
            Button(L10n.t("Khôi phục mapping mặc định của ứng dụng")) { controller.resetProfile(profile) }
                .padding(.horizontal, 20)
        }
    }

    private var customProfiles: [String] {
        let known = Set(GestureProfiles.all.map(\.id))
        return Set(Array(controller.configuration.overrides.keys) + [profile]).subtracting(known).sorted()
    }

    private func actionRow(_ direction: GestureDirection) -> some View {
        let action = controller.configuration.action(bundle: profile, direction: direction)
        let isUnassigned: Bool = {
            if case .unassigned = action { return true }
            return false
        }()
        let appIcon: NSImage? = {
            guard profile != GestureProfiles.fallback else { return nil }
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: profile) {
                return NSWorkspace.shared.icon(forFile: app.path)
            }
            return nil
        }()
        return HStack(spacing: 10) {
            if let img = appIcon {
                Image(nsImage: img).resizable().frame(width: 16, height: 16).cornerRadius(3)
            } else {
                Image(systemName: "app.fill").foregroundColor(.secondary).frame(width: 16)
            }
            Text(direction.symbol).font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(width: 42, alignment: .leading)
            Text(actionLabel(action))
                .font(.system(size: 12, weight: isUnassigned ? .regular : .medium, design: .rounded))
                .foregroundColor(isUnassigned ? .secondary : .primary)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).lineLimit(1)
            Group {
                if isUnassigned {
                    Button(L10n.t("Ghi phím")) {
                        recordingDirection = direction
                        controller.recordShortcut(bundle: profile, direction: direction)
                    }.buttonStyle(.borderedProminent).controlSize(.small)
                } else {
                    Button(L10n.t("Ghi phím")) {
                        recordingDirection = direction
                        controller.recordShortcut(bundle: profile, direction: direction)
                    }.buttonStyle(.bordered).controlSize(.small)
                }
            }.disabled(controller.recording)
            Menu(L10n.t("Đổi")) {
                Button(L10n.t("Chưa gán")) { controller.setAction(.unassigned, bundle: profile, direction: direction) }
                if direction == .tiltLeft || direction == .tiltRight {
                    Button(L10n.t("Cuộn ngang nguyên bản")) {
                        controller.setAction(.horizontalScroll, bundle: profile, direction: direction)
                    }
                }
            }.fixedSize()
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
    private func actionLabel(_ action: GestureAction) -> String {
        switch action {
        case .unassigned: return L10n.t("Chưa gán")
        case .shortcut(let s): return s.label
        case .horizontalScroll: return L10n.t("Cuộn ngang nguyên bản")
        }
    }
}
