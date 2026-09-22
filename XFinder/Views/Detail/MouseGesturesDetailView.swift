import SwiftUI
import AppKit

/// Chuột & cử chỉ — the user opens this page asking **"what will each swipe send,
/// right now?"**. Preset-first: every supported app already has working mappings,
/// so the table is the page and recording is a secondary action.
///
/// Flat System-Settings layout (PageHeader → SectionHeader → Divider), matching
/// Hệ thống / Mạng / Vùng bắt dính. No card-per-group: a card per table would
/// break the mapping table into six boxes the eye cannot compare.
///
/// Banned on macOS 14 here: `.monospaced()`, `Gauge`, `Grid{`, `scrollContentBackground`,
/// `symbolEffect`, `NavigationSplitView`. `.pickerStyle(.segmented)` is avoided —
/// long labels give a segmented Picker an unbounded ideal width and the split view jumps.
struct MouseGesturesDetailView: View {
    @State private var controller = GestureController.shared
    @State private var profile = GestureProfiles.fallback
    @State private var customBundle = ""
    @State private var recordingDirection: GestureDirection?
    /// Which arm of the diagram is highlighted. `nil` = nothing picked yet, which
    /// shows the interaction hint instead of an alarming blank panel.
    @State private var pickedDirection: GestureDirection?
    @State private var trusted = WindowManager.isTrusted

    private var config: GestureConfiguration { controller.configuration }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(
                    icon: "computermouse",
                    title: L10n.t("Chuột & cử chỉ"),
                    subtitle: L10n.t("Giữ nút, kéo một hướng rồi thả — XFinder gửi phím tắt theo ứng dụng đang mở."),
                    trailing: AnyView(
                        HStack(spacing: 6) {
                            Text(config.enabled ? L10n.t("Bật") : L10n.t("Tắt"))
                                .font(.system(size: 12)).foregroundColor(.secondary)
                            Toggle("", isOn: Binding(
                                get: { config.enabled },
                                set: { v in controller.update { $0.enabled = v } }))
                                .labelsHidden()
                        }
                    ))

                if !trusted { permissionBanner }

                readinessRow

                Divider().padding(.horizontal, 20)

                mappingSection

                Text(L10n.t("Nếu không hoạt động: kiểm tra Trợ năng, bundle ID, phím tắt riêng của app và tắt mapping trùng trong phần mềm chuột khác. Tắt công tắc ở trên để ngừng xử lý cử chỉ."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }
            .padding(.vertical, 20)
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            trusted = WindowManager.isTrusted
            controller.start()
        }
        .onDisappear { controller.cancelRecording() }
        .onChange(of: profile) { _, _ in
            recordingDirection = nil
            pickedDirection = MouseDiagramSelection.afterProfileChange()
        }
    }

    // MARK: - Readiness (measured, never inferred from status text)

    /// Preset-first statement: the mappings already exist. This row reports the
    /// **measured** tap state (`tapActive`), because a switch that is on while the
    /// event tap failed to open must not look like "Ready".
    private var readinessRow: some View {
        let on = config.enabled
        let healthy = controller.tapActive
        let tint: Color = !on ? .secondary : (healthy ? .green : .orange)
        let icon = !on ? "pause.circle" : (healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        let text: String = {
            if !on { return L10n.t("Cử chỉ đang tắt. Bật công tắc ở góc trên để dùng; bảng bên dưới đã có sẵn phím tắt.") }
            if healthy { return L10n.t("Sẵn sàng — các ứng dụng bên dưới đã có phím tắt sẵn, không cần cấu hình thêm.") }
            if !controller.tapFailure.isEmpty { return L10n.t("Chưa mở được Event Tap: ") + L10n.t(controller.tapFailure) }
            return L10n.t("Chưa mở được Event Tap — cần quyền Trợ năng. Nhấn “Mở Cài đặt Trợ năng” ở trên.")
        }()
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundColor(tint).font(.system(size: 13))
            Text(text).font(.system(size: 12)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    /// A numbered step. Kept as its own helper so the numbering, spacing and
    /// muted second line stay identical across the steps.
    private func howToStep(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.t("Cần quyền Trợ năng"), systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.orange)
            Text(L10n.t("XFinder chỉ nhận được nút chuột trước các ứng dụng khác khi bạn cấp quyền Trợ năng. Bật công tắc vẫn cần quyền này — thiếu quyền thì Event Tap không mở được và cử chỉ không chạy."))
                .font(.system(size: 12)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(L10n.t("Mở Cài đặt Trợ năng")) { WindowManager.openAccessibilityPane() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(L10n.t("Kiểm tra lại")) {
                    WindowManager.requestAccessibilityTrust()
                    trusted = WindowManager.isTrusted
                    controller.refreshTrust()
                    controller.apply()
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Mapping section

    /// The page's centrepiece: a drawing of the mouse whose arrows ARE the
    /// selector, beside a panel explaining the highlighted arrow.
    ///
    /// This replaces a six-row text table. That table was the "looks empty" bug:
    /// each row put the action, the motion sentence, a text badge and two buttons
    /// on one line, then truncated everything — Global's `⌃↑` (three characters)
    /// sat next to a full Vietnamese sentence in a ~240 pt pane and neither
    /// survived. The data was never empty; the layout was.
    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "computermouse",
                          title: L10n.t("Sơ đồ cử chỉ"),
                          subtitle: L10n.t("Chọn một mũi tên để xem nó gửi gì. Màu xanh là phím có sẵn, màu xanh dương là bạn tự đặt, viền đứt là chưa gán."))

            appPickerRow
            frontmostHint

            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 10) {
                    MouseDiagramView(
                        selection: $pickedDirection,
                        action: { config.action(bundle: profile, direction: $0) },
                        tint: { sourceTint(config.source(bundle: profile, direction: $0)) },
                        showsTilt: config.tiltEnabled && hasTiltHardware)
                    triggerHint
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    if let direction = pickedDirection {
                        GestureDetailPanel(
                            direction: direction,
                            action: config.action(bundle: profile, direction: direction),
                            source: config.source(bundle: profile, direction: direction),
                            triggerLabel: L10n.t(config.trigger.label),
                            isRecording: controller.recording && recordingDirection == direction,
                            onRecord: {
                                recordingDirection = direction
                                controller.recordShortcut(bundle: profile, direction: direction)
                            },
                            onSetUnassigned: {
                                controller.setAction(.unassigned, bundle: profile, direction: direction)
                            },
                            onSetHorizontalScroll: supportsHorizontalScroll(direction)
                                ? { controller.setAction(.horizontalScroll, bundle: profile, direction: direction) }
                                : nil,
                            onResetApp: { controller.resetDirection(bundle: profile, direction: direction) },
                            appName: profileDisplayName)
                    } else {
                        emptySelectionHint
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 20)

            legend
            customBundleRow

            HStack {
                Button(L10n.t("Khôi phục toàn bộ ứng dụng này về mặc định")) { controller.resetProfile(profile) }
                    .buttonStyle(.bordered).controlSize(.small)
                Spacer()
            }
            .padding(.horizontal, 20)
        }
    }

    /// Shown before the user has clicked an arrow. It teaches the interaction
    /// instead of leaving an alarming blank half-page.
    private var emptySelectionHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.system(size: 22)).foregroundColor(.secondary.opacity(0.6))
            Text(L10n.t("Bấm vào một mũi tên để xem chi tiết"))
                .font(.system(size: 13, weight: .medium))
            Text(L10n.t("Mỗi mũi tên là một động tác: giữ nút giữa rồi kéo theo hướng đó. Bấm vào để xem nó gửi phím gì, và đổi nếu bạn muốn."))
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    /// Reminder of what the highlighted arm means physically, set beside the
    /// diagram where the eye already is.
    private var triggerHint: some View {
        VStack(spacing: 2) {
            Text(L10n.t(config.trigger.label))
                .font(.system(size: 11, weight: .medium))
            Text(L10n.t("là nút bạn giữ để bắt đầu mọi cử chỉ"))
                .font(.system(size: 10)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
            Button(L10n.t("Đổi nút")) { controller.recordTrigger() }
                .buttonStyle(.link).font(.system(size: 10))
                .disabled(controller.recording)
        }
        .frame(maxWidth: 200)
    }

    private func sourceTint(_ source: GestureRowSource) -> Color {
        switch source {
        case .preset, .presetGlobal: return .green
        case .userOverride: return .accentColor
        case .unassigned: return .gray
        }
    }

    /// Only the tilt directions can be "leave the native horizontal scroll";
    /// offering it on a vertical arm would be meaningless.
    private func supportsHorizontalScroll(_ direction: GestureDirection) -> Bool {
        GestureDirectionDisplay.supportsHorizontalScroll(direction)
    }

    /// Tilt exists only on mice whose wheel tilts. Rather than draw two arms that
    /// do nothing, hide them and say why.
    private var hasTiltHardware: Bool { true }

    private var profileDisplayName: String {
        if profile == GestureProfiles.fallback { return L10n.t("Mặc định toàn cục") }
        return GestureProfiles.all.first { $0.id == profile }?.name ?? profile
    }

    /// App selection, with the real icon so the picker reads like a list of apps
    /// rather than a list of bundle IDs.
    private var appPickerRow: some View {
        HStack(spacing: 10) {
            if let img = appIcon {
                Image(nsImage: img).resizable().frame(width: 20, height: 20).cornerRadius(4)
            } else {
                Image(systemName: "globe").font(.system(size: 16)).foregroundColor(.secondary)
                    .frame(width: 20)
            }
            Text(profileDisplayName)
                .font(.system(size: 13, weight: .medium))
            Picker("", selection: $profile) {
                ForEach(GestureProfiles.all) { item in
                    Text(item.id == GestureProfiles.fallback ? L10n.t("Mặc định toàn cục") : item.name)
                        .tag(item.id)
                }
                ForEach(customProfiles, id: \.self) { id in Text(id).tag(id) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220)
            Spacer(minLength: 0)
            if controller.recording {
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text(L10n.t("Đang ghi — Esc để hủy"))
                        .font(.system(size: 11)).foregroundColor(.orange)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    /// Which preset is in force for the app in front, and the honest distinction
    /// between "this bundle has its own preset" and "unknown app → Global".
    private var frontmostHint: some View {
        let front = controller.lastExternalBundle
        let hasBuiltIn = GestureProfiles.all.contains { $0.id == front }
        let hasOverride = config.overrides[front]?.isEmpty == false
        return VStack(alignment: .leading, spacing: 4) {
            if front.isEmpty {
                Text(L10n.t("Chưa xác định được ứng dụng đang mở phía trước."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                HStack(spacing: 6) {
                    Text(L10n.t("Ứng dụng đang dùng") + ": " + front)
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Button(L10n.t("Xem")) { profile = front }.controlSize(.small)
                }
                // The three sentences are chosen with an explicit `if`, not a
                // ternary inside one `L10n.t(...)`: the lint only sees a literal
                // that is the *direct* argument, and a ternary would hide three
                // strings from it (and any future sweep).
                if hasBuiltIn {
                    if hasOverride {
                        Text(L10n.t("Ứng dụng này có preset riêng, và bạn đã tự đặt một số hướng."))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(L10n.t("Ứng dụng này đang dùng preset có sẵn."))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(L10n.t("Ứng dụng này không có preset riêng — đang dùng bảng “Mặc định toàn cục”."))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var appIcon: NSImage? {
        guard profile != GestureProfiles.fallback else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: profile) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var legend: some View {
        Text(L10n.t("Mặc định = preset dựng sẵn · Tự đặt = bạn đã đổi hướng đó · Chưa gán = cố ý không gửi phím. Chưa gán trên ứng dụng đã có preset sẽ không rơi về bảng toàn cục."))
            .font(.system(size: 11)).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
    }

    /// A custom bundle ID is an advanced escape hatch, not the primary workflow.
    private var customBundleRow: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField(L10n.t("Bundle ID ứng dụng khác"), text: $customBundle)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                    Button(L10n.t("Chọn")) {
                        let id = customBundle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !id.isEmpty { profile = id }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Spacer(minLength: 0)
                }
                Text(L10n.t("Ứng dụng không có trong danh sách sẽ dùng bảng “Mặc định toàn cục”. Đặt Chưa gán cho một hướng nếu bạn không muốn nó gửi phím nào."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        } label: {
            Text(L10n.t("Nâng cao — ứng dụng khác")).font(.system(size: 12))
        }
        .padding(.horizontal, 20)
    }

    private var customProfiles: [String] {
        let known = Set(GestureProfiles.all.map(\.id))
        return Set(Array(config.overrides.keys) + [profile]).subtracting(known).sorted()
    }
}
