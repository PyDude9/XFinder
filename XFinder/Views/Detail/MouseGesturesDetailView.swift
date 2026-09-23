import SwiftUI
import AppKit

/// Compile-time lever for the measured-activity block at the bottom of the page.
///
/// **`false` is the shipped value.** The block is a development instrument — the only place
/// the engine's own view of a press (button number, locked direction, the app it resolved
/// for) is visible — so it is not part of the page a normal user reads.
///
/// It is deliberately **not** wrapped in `#if`: the page's own switch says *"Bật ghi nhật ký
/// để xem XFinder nhận được gì"*, so a compile-time-only removal would leave a control that
/// promises something it cannot do — the exact thing Part 0 §6 of `AGENTS.md` forbids. The
/// section therefore renders when `DEBUG_SHOW_ENGINE_LOG || config.debug`: hidden for a
/// fresh user (debug defaults off), shown the moment they flip that switch, and forced on
/// for a diagnostic build by setting this to `true`.
private let DEBUG_SHOW_ENGINE_LOG = false

/// Chuột & cử chỉ — the user opens this page asking **"what will each swipe send,
/// right now?"**. Preset-first: every supported app already has working mappings, so
/// the diagram is the page and recording is a secondary action.
///
/// Layout: `PageHeader` → readiness → the diagram and its detail panel → the
/// per-device switches → advanced. Flat System-Settings look, matching Hệ thống /
/// Mạng / Vùng bắt dính. No card-per-group: a card per row would break the mapping
/// into boxes the eye cannot compare.
///
/// Banned on macOS 14 here: `.monospaced()`, `Gauge`, `Grid{`, `scrollContentBackground`,
/// `symbolEffect`, `NavigationSplitView`. `.pickerStyle(.segmented)` is avoided — long
/// labels give a segmented Picker an unbounded ideal width and the split view jumps.
struct MouseGesturesDetailView: View {
    @State private var controller = GestureController.shared
    @State private var profile = GestureProfiles.fallback
    @State private var customBundle = ""
    @State private var recordingDirection: GestureDirection?
    @State private var recordingTrigger = false
    /// Which arm of the diagram is highlighted. `nil` = nothing picked yet, which shows
    /// the interaction hint instead of an alarming blank panel.
    @State private var pickedDirection: GestureDirection?
    @State private var trusted = WindowManager.isTrusted
    /// The pointing devices IOHID could actually read. Empty means "the probe found
    /// nothing", which is NOT the same as "the mouse has no buttons" — the diagram says
    /// "not detected yet" for that case rather than greying an arm out.
    @State private var devices: [CapabilityDescriptor] = []
    @State private var probed = false
    /// A device the user pinned manually. Honoured as-is and never replaced by a
    /// detection result — see `DeviceSelection.active`.
    @State private var pinnedDevice: CapabilityDescriptor?
    /// Set when the user pressed a button on the mouse while the page was open, so the
    /// page can report the number the engine actually saw. This is the measured answer
    /// to "which button should I hold?", and it costs nothing to collect: the event tap
    /// already receives the press.
    @State private var observedButton: Int?

    private var config: GestureConfiguration { controller.configuration }

    /// The single device in force for this session (D4: one mouse at a time).
    private var activeDevice: CapabilityDescriptor? {
        DeviceSelection.active(from: devices, override: pinnedDevice)
    }

    private var provenance: CapabilityProvenance { DeviceSelection.provenance(for: activeDevice) }

    /// Every direction's row, resolved once. One call site, so the diagram, the panel and
    /// the engine all read the same mapping.
    private func resolved(_ direction: GestureDirection) -> ResolvedGestureRow {
        GestureMap.row(overrides: config.overrides, bundle: profile, direction: direction,
                       systemBindings: controller.systemBindings)
    }

    private func resolvedName(_ direction: GestureDirection) -> String? {
        GestureMap.displayName(for: resolved(direction)).map { L10n.t($0) }
    }

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

                acceptSection

                Divider().padding(.horizontal, 20)

                mappingSection

                if DEBUG_SHOW_ENGINE_LOG || config.debug {
                    Divider().padding(.horizontal, 20)

                    activitySection
                }

                Divider().padding(.horizontal, 20)

                switchesSection

                footerNote
            }
            .padding(.vertical, 20)
            .pageWidthSafe()
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            trusted = WindowManager.isTrusted
            controller.start()
            // Re-read the machine's own symbolic hotkeys every time the page opens: the user
            // edits them in System Settings, i.e. while this app is not frontmost, and a
            // stale binding would make the page disagree with what the engine posts.
            controller.refreshSystemBindings()
            probeDevices()
        }
        .onDisappear { controller.cancelRecording(); recordingTrigger = false }
        .onChange(of: controller.recording) { _, recording in
            if !recording { recordingDirection = nil; recordingTrigger = false }
        }
        .onChange(of: controller.observedPress) { _, press in
            guard let press else { return }
            observedButton = press
        }
        .onChange(of: profile) { _, _ in
            recordingDirection = nil
            pickedDirection = MouseDiagramSelection.afterProfileChange()
        }
    }

    // MARK: - Hardware probe (L4 / R4)

    /// Reads what the connected pointing device actually declares.
    ///
    /// Off the main thread on purpose: `IOHIDManagerOpen` plus the element copy is
    /// measured in milliseconds per device on a descriptor with hundreds of elements
    /// (the Razer mouse in this repo declares 898), which is fine on demand but not as a
    /// main-thread hitch while the page animates in.
    ///
    /// A probe that returns nothing is reported as `probed = true, devices = []`:
    /// "we looked and could not read it", which the diagram renders as "not detected
    /// yet". It is never rendered as a measured absence of buttons, and a denied
    /// permission (the common cause) is named in the UI instead of silently greying
    /// every arm out.
    private func probeDevices() {
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                DeviceCapabilityProbe.connectedPointingDevices()
            }.value
            devices = found
            probed = true
        }
    }

    // MARK: - Readiness (measured, never inferred from status text)

    private var readinessRow: some View {
        let on = config.enabled
        let healthy = controller.tapActive
        let tint: Color = !on ? .secondary : (healthy ? .green : .orange)
        let icon = !on ? "pause.circle" : (healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        let text: String = {
            if !on { return L10n.t("Cử chỉ đang tắt. Bật công tắc ở góc trên để dùng; sơ đồ bên dưới đã có sẵn phím tắt.") }
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

    // MARK: - Mapping

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "computermouse",
                          title: L10n.t("Sơ đồ cử chỉ"),
                          subtitle: L10n.t("Chọn một mũi tên để xem nó gửi gì. Số trên thân chuột là nút bạn giữ — bấm vào đó để đổi."))

            appPickerRow
            frontmostHint
            deviceRow
            observedButtonRow

            HStack(alignment: .top, spacing: 18) {
                MouseDiagramView(
                    selection: $pickedDirection,
                    row: { resolved($0) },
                    actionName: { resolvedName($0) },
                    tint: { sourceTint(profile, $0) },
                    showsTilt: config.tiltAvailable,
                    trigger: config.trigger,
                    unsupported: { DeviceCapabilityModel.armSupport(for: $0, device: activeDevice) },
                    recordingDirection: recordingDirection,
                    onRecordTrigger: { triggerRecording() },
                    isRecordingTrigger: recordingTrigger)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    if let direction = pickedDirection {
                        GestureDetailPanel(
                            direction: direction,
                            row: resolved(direction),
                            actionName: resolvedName(direction),
                            trigger: config.trigger,
                            isRecording: controller.recording && recordingDirection == direction,
                            appName: profileDisplayName(),
                            hasAppPreset: GestureProfiles.hasPreset(bundle: profile),
                            systemBindings: controller.systemBindings,
                            onPick: { choice in
                                controller.setAction(choice.action, bundle: profile, direction: direction)
                            },
                            onRecord: {
                                recordingDirection = direction
                                recordingTrigger = false
                                controller.recordShortcut(bundle: profile, direction: direction)
                            },
                            onReset: { controller.resetDirection(bundle: profile, direction: direction) })
                    } else {
                        emptySelectionHint
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 20)

            legend
            tiltRow
            customBundleRow

            HStack(spacing: 8) {
                Button(L10n.t("Khôi phục toàn bộ ứng dụng này về mặc định")) { controller.resetProfile(profile) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(config.overrides[profile] == nil)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
    }

    /// Shown before the user has clicked an arrow. It teaches the interaction instead of
    /// leaving an alarming blank half-page — and it states the *measured* button number
    /// when the engine has already seen one, so the first question ("which button?") is
    /// answered with evidence rather than with the word "Button 4".
    private var emptySelectionHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.system(size: 22)).foregroundColor(.secondary.opacity(0.6))
            Text(L10n.t("Bấm vào một mũi tên để xem chi tiết"))
                .font(.system(size: 13, weight: .medium))
            Text(L10n.t("Mỗi mũi tên là một động tác: giữ nút trên thân chuột rồi kéo theo hướng đó. Bấm vào mũi tên để xem và đổi phím nó gửi."))
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.t("Ba bước: giữ nút → kéo quá ngưỡng → thả. Kéo chưa đủ xa thì XFinder phát lại click bình thường, nên không mất thao tác nào."))
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private func sourceTint(_ bundle: String, _ direction: GestureDirection) -> Color {
        let row = resolved(direction)
        if row.isUnboundSystemAction { return .orange }
        if row.isUserOverride { return .accentColor }
        if row.entry.isUnassigned { return .gray }
        return .green
    }

    /// Which app the diagram is describing.
    private var appPickerRow: some View {
        HStack(spacing: 10) {
            if let img = appIcon {
                Image(nsImage: img).resizable().frame(width: 20, height: 20).cornerRadius(4)
            } else {
                Image(systemName: "globe").font(.system(size: 16)).foregroundColor(.secondary)
                    .frame(width: 20)
            }
            Text(profileDisplayName())
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1).truncationMode(.middle)
            Picker("", selection: $profile) {
                ForEach(orderedProfiles) { item in
                    Text(item.id == GestureProfiles.fallback ? L10n.t("Mặc định toàn cục") : item.name)
                        .tag(item.id)
                }
                if !GestureProfiles.hasPreset(bundle: frontmostBundle) {
                    Text(L10n.t("Ứng dụng đang dùng") + " — " + frontmostBundle).tag(frontmostBundle)
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

    /// Preset-first ordering: apps the user is actually running come first, then the rest
    /// of the built-in list, then Global last. A picker that opens on a list of
    /// applications the user does not have installed is how "preset-first" reads as
    /// "empty list" — the reader cannot find their own app in it.
    private var orderedProfiles: [GestureProfile] {
        let installed = Set(installedBundleIDs())
        let mine = GestureProfiles.all.filter { $0.id != GestureProfiles.fallback && installed.contains($0.id) }
        let rest = GestureProfiles.all.filter { $0.id != GestureProfiles.fallback && !installed.contains($0.id) }
        let fallback = GestureProfiles.all.filter { $0.id == GestureProfiles.fallback }
        return mine + rest + fallback
    }

    private func installedBundleIDs() -> [String] {
        GestureProfiles.all.compactMap { profile in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: profile.id) != nil ? profile.id : nil
        }
    }

    /// Which preset is in force for the app in front, and the honest distinction between
    /// "this bundle has its own preset" and "unknown app → Global".
    private var frontmostHint: some View {
        let front = controller.lastExternalBundle
        let hasBuiltIn = GestureProfiles.hasPreset(bundle: front)
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

    /// Which mouse the diagram describes, and where that description came from.
    private var deviceRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "computermouse")
                .font(.system(size: 12)).foregroundColor(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(L10n.t("Chuột đang kết nối"))
                        .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                    provenancePill
                }
                Text(deviceDescription)
                    .font(.system(size: 12))
                    .lineLimit(1).truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                Text(deviceExplanation)
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private var provenancePill: some View {
        let detected = provenance.isDetected
        return Text(detected ? L10n.t("Đã nhận diện") : L10n.t("Bạn tự đặt"))
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(detected ? .green : .secondary)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill((detected ? Color.green : Color.secondary).opacity(0.14)))
            .fixedSize()
    }

    /// The measured answer to "which button is my mouse's side button?".
    ///
    /// The engine's event tap already receives every mouse press, so the page can report
    /// the number it actually saw instead of leaving the user to deduce it from a label.
    /// This is the one fact that cannot be obtained any other way: `CGEventField` has no
    /// vendor/product field, so no API can map a number to a physical control — but the
    /// user can simply press the button and read off the number.
    @ViewBuilder
    private var observedButtonRow: some View {
        if let observed = observedButton {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "dot.circle.and.hand.point.up.left.fill")
                    .font(.system(size: 12)).foregroundColor(.accentColor).frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Nút bạn vừa bấm: ") + "\(observed + 1)")
                        .font(.system(size: 12, weight: .medium))
                    Text(L10n.t("Đây là con số XFinder nhận được từ chuột. Bấm “Ghi nút” rồi bấm đúng nút đó để đặt nó làm nút giữ."))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
    }

    private var deviceDescription: String {
        if let label = DeviceCapabilityModel.deviceLabel(provenance) { return label }
        if pinnedDevice != nil { return L10n.t("Thiết bị do bạn chọn") }
        if !probed { return L10n.t("Đang dò thiết bị…") }
        return L10n.t("Chưa nhận diện được chuột")
    }

    /// Why the arms look the way they do. Separate from the description because "which
    /// mouse" and "how much do we trust this" are different facts.
    private var deviceExplanation: String {
        if let device = activeDevice, device.confidence != .verified {
            return L10n.t("Thiết bị này không khai đủ mã định danh, nên XFinder chỉ biết chắc những nút nó khai. Hướng nào chưa chắc thì để trống chứ không báo là không hỗ trợ.")
        }
        if activeDevice == nil {
            if !probed { return L10n.t("XFinder đang đọc mô tả HID của chuột bạn.") }
            if !trusted {
                return L10n.t("Không đọc được mô tả chuột vì thiếu quyền. Sơ đồ vẫn dùng được — chỉ là XFinder chưa biết chuột bạn có nút nào.")
            }
            return L10n.t("Không đọc được mô tả chuột nào. Sơ đồ vẫn dùng được với các nút cơ bản.")
        }
        let count = activeDevice?.physical.buttons.count ?? 0
        return L10n.t("XFinder đọc trực tiếp mô tả HID của chuột: ")
            + "\(count) " + L10n.t("nút.")
    }

    private var appIcon: NSImage? {
        guard profile != GestureProfiles.fallback else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: profile) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var legend: some View {
        Text(L10n.t("Mặc định = preset dựng sẵn · Tự đặt = bạn đã đổi hướng đó · Chưa gán = cố ý không gửi phím. Chưa gán trên ứng dụng đã có preset sẽ không rơi về bảng toàn cục. Biểu tượng ⇄ nhỏ nghĩa là hướng đó chuyển tiếp cuộn ngang nguyên bản của chuột."))
            .font(.system(size: 11)).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
    }

    /// Tilt exists only on mice whose wheel tilts *and* whose driver reports it as a
    /// discrete horizontal wheel. This was hard-coded `true`, so the two tilt arms were
    /// drawn on hardware where they can never fire — the Razer Basilisk 25K/35K and the
    /// Magic Mouse both report every wheel event as `IsContinuous == 1` with axis2 == 0
    /// (measured, see docs/GESTURE_VERIFICATION.md), which `GestureEngine` deliberately
    /// rejects so it never steals trackpad scrolling.
    private var tiltRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { config.tiltAvailable },
                set: { v in controller.update { $0.tiltAvailable = v } }))
            {
                Text(L10n.t("Hiện hai hướng nghiêng con lăn")).font(.system(size: 12))
            }
            .toggleStyle(.switch).controlSize(.small)
            Text(L10n.t("Chỉ dùng cho chuột có con lăn nghiêng được và có driver gửi cuộn ngang rời rạc — ví dụ Logitech MX Master với Logi Options. Đo trên máy này: Razer Basilisk và Magic Mouse đều báo cuộn liên tục, nên hai hướng đó sẽ không bao giờ chạy; tắt để sơ đồ khỏi vẽ thừa. XFinder không thể tự dò ra phần cứng của bạn."))
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Acceptance (the two things that are actually wrong when nothing fires)

    /// The first section on the page, because when the user says *"chức năng không
    /// hiển thị gì cả"* there are exactly two causes, and both are invisible from the
    /// mapping table:
    ///
    /// 1. **The hold button is wrong.** Measured on this machine: the shipped default is
    ///    `mouseButton(2)` — the wheel click — because it was the value in an older build's
    ///    default and `validate()` only repairs an *invalid* trigger. B2 is valid, so no
    ///    migration touched it, and holding the wheel while dragging is not something a
    ///    hand can do. The user reported this twice.
    /// 2. **The app in front is XFinder.** The engine resolves the preset from the bundle
    ///    ID of the frontmost app. While the user is *testing* from this page, XFinder is
    ///    frontmost, so the log legitimately says `com.xfinder.app` and the gesture looks
    ///    broken when it is working exactly as configured.
    ///
    /// Both are stated here as **measurements** (this button number, this bundle ID)
    /// rather than as advice. Nothing is changed silently: the button row only *offers*
    /// a re-record, and the frontmost row says which app to switch to.
    private var acceptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "checkmark.seal",
                          title: L10n.t("Kiểm tra nhanh"),
                          subtitle: L10n.t("Hai nguyên nhân duy nhất khiến cử chỉ không chạy: nút giữ chưa đúng, hoặc XFinder đang là ứng dụng phía trước."))

            holdButtonRow
            frontmostTargetRow
            systemShortcutRow
        }
        .padding(.horizontal, 20)
    }

    /// The machine's own shortcuts for the four system actions the Global preset uses.
    ///
    /// Shown because it is the one fact that explains an arm reading "no shortcut set in
    /// macOS" — and because it is **read, not assumed**: XFinder posts exactly what this row
    /// prints, so a green line means the gesture will run and an orange one names the fix.
    /// This is also the honest answer to "why does my Space gesture do nothing", which was
    /// the round-7 report when the preset shipped a constant that no machine listened for.
    @ViewBuilder
    private var systemShortcutRow: some View {
        let bindings = controller.systemBindings
        let actions: [GestureSystemAction] = [.missionControl, .appExpose, .previousSpace, .nextSpace]
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: bindings.isEmpty ? "exclamationmark.triangle.fill" : "keyboard")
                    .font(.system(size: 12))
                    .foregroundColor(bindings.isEmpty ? .orange : .green)
                    .frame(width: 16)
                Text(L10n.t("Phím hệ thống trên máy này"))
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Button(L10n.t("Mở Phím tắt")) { WindowManager.openKeyboardShortcutsPane() }
                    .buttonStyle(.link).font(.system(size: 11))
            }
            ForEach(actions, id: \.rawValue) { action in
                HStack(spacing: 6) {
                    Text(L10n.t(action.captionKey))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .frame(width: 130, alignment: .leading)
                        .lineLimit(1)
                    if let shortcut = bindings.shortcut(for: action) {
                        Text(shortcut.label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    } else {
                        Text(L10n.t("chưa gán trong macOS"))
                            .font(.system(size: 11)).foregroundColor(.orange)
                    }
                    Spacer(minLength: 0)
                }
            }
            Text(L10n.t("XFinder gửi đúng phím bạn gán trong Bàn phím → Phím tắt, nên bốn hướng của bảng Toàn cục chạy đúng như bàn phím của bạn."))
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The hold button, with the two measured facts that make it actionable.
    @ViewBuilder
    private var holdButtonRow: some View {
        let held = config.trigger
        // A wheel hold is the specific ergonomic impossibility. `mouseButton(2)` is the
        // value the shipped default has used, so it gets an explicit warning rather than
        // the generic copy — the user should not have to know that 2 means wheel.
        let wheelHold = held.buttonNumber == 2
        let justPressed = observedButton != nil && observedButton != held.buttonNumber

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: wheelHold ? "exclamationmark.triangle.fill" : "hand.tap")
                    .font(.system(size: 12))
                    .foregroundColor(wheelHold ? .orange : .green)
                    .frame(width: 16)
                Text(L10n.t("Nút giữ") + ": " + L10n.t(held.key))
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Button(recordingTrigger ? L10n.t("Đang ghi…") : L10n.t("Ghi lại nút giữ")) { triggerRecording() }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(controller.recording)
            }

            if wheelHold {
                Text(L10n.t("Đây là nút bấm con lăn. Giữ con lăn rồi kéo là thao tác tay không làm được — cử chỉ sẽ như không chạy. Bấm “Ghi lại nút giữ” rồi bấm một nút hông."))
                    .font(.system(size: 11)).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if held.isMouseButton {
                Text(L10n.t("Giữ nút này rồi kéo một trong bốn hướng. Con số là con số XFinder nhận được từ chuột, không phải tên cố định — mỗi chuột một khác."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L10n.t("Đang dùng phím bổ trợ làm nút giữ. Giữ phím đó rồi kéo chuột để bắt đầu cử chỉ."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Offered only after a real press of a *different* button. Gating on an
            // observed press is what keeps this from firing on every fresh install —
            // the earlier auto-prompt matched every user who had never touched the
            // setting, which is why it was rejected.
            if justPressed, let observed = observedButton {
                HStack(spacing: 8) {
                    Text(L10n.t("Bạn vừa bấm") + " " + L10n.t(ButtonKey.index(observed)) + ". "
                         + L10n.t("Đặt nút này làm nút giữ?"))
                        .font(.system(size: 11))
                    Button(L10n.t("Đặt làm nút giữ")) {
                        controller.update { $0.trigger = .mouseButton(observed) }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// Which app the engine will actually target. This is the row that explains a log
    /// full of `com.xfinder.app`: the resolver keys on the frontmost bundle ID, so a
    /// gesture performed while XFinder is in front is resolved *for XFinder*, not for the
    /// app the user was thinking of. Saying so is the honest fix; silently substituting
    /// the Global table would make the page disagree with the engine.
    @ViewBuilder
    private var frontmostTargetRow: some View {
        let front = controller.activeBundle
        let selfID = Bundle.main.bundleIdentifier ?? ""
        let isSelf = !front.isEmpty && front == selfID
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: isSelf ? "exclamationmark.circle.fill" : "app.badge.checkmark")
                    .font(.system(size: 12))
                    .foregroundColor(isSelf ? .orange : .green)
                    .frame(width: 16)
                Text(L10n.t("Cử chỉ sẽ gửi tới") + ": " + (front.isEmpty ? L10n.t("chưa xác định") : front))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            if isSelf {
                Text(L10n.t("XFinder đang là ứng dụng phía trước, nên cử chỉ được tra theo chính XFinder. Hãy chuyển sang ứng dụng bạn muốn dùng (Zed, Chrome, Excel…) rồi thử lại — đây là lý do nhật ký bên dưới chỉ hiện com.xfinder.app."))
                    .font(.system(size: 11)).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !front.isEmpty {
                Text(L10n.t("Bấm “Xem” ở mục dưới để mở đúng bảng của ứng dụng này."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Activity (measured, from the engine's own callback)
    //
    // Rendered when `DEBUG_SHOW_ENGINE_LOG || config.debug` — see the constant at the top of
    // the file for why this is a runtime condition rather than a `#if`.
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "waveform.path.ecg",
                          title: L10n.t("XFinder đã nhận gì"),
                          subtitle: L10n.t("Dòng đo thật từ engine — không phải hướng dẫn. Giữ nút rồi kéo để thấy nó ghi lại."))
            GestureActivityPanel(diagnostics: controller.diagnostics,
                                 loggingEnabled: config.debug,
                                 tapActive: controller.tapActive,
                                 onEnableLogging: { controller.update { $0.debug = true } })
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Switches

    private var switchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "switch.2",
                          title: L10n.t("Nút giữ và cuộn"),
                          subtitle: L10n.t("Nút giữ bắt đầu mọi cử chỉ. Nút cuộn là tuỳ chọn riêng, mặc định tắt."))

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Nút giữ"))
                        .font(.system(size: 12, weight: .medium))
                    Text(L10n.t("Giữ nút này rồi kéo bốn hướng. Mặc định là nút hông — con số tuỳ chuột, nên hãy ghi lại nếu bạn muốn nút khác."))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(L10n.t(config.trigger.key))
                    .font(.system(size: 12, weight: .semibold))
                Button(recordingTrigger ? L10n.t("Đang ghi…") : L10n.t("Ghi nút")) { triggerRecording() }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(controller.recording)
            }
            .padding(.horizontal, 20)

            Divider().padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { config.scrollButtonEnabled },
                    set: { v in controller.update { $0.scrollButtonEnabled = v } }))
                {
                    Text(L10n.t("Giữ nút cuộn rồi kéo để cuộn")).font(.system(size: 12))
                }
                .toggleStyle(.switch).controlSize(.small)
                Text(L10n.t("Dành cho ứng dụng cần cuộn nhiều như Photoshop hay CapCut: giữ một nút hông rồi kéo là cuộn, không cần nhấc tay khỏi chuột. Nút đó vẫn bấm bình thường khi bạn không kéo. Mặc định tắt vì nó chiếm một nút bạn có thể đang dùng cho việc khác."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(L10n.t("Nút cuộn"))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    Text(L10n.t(ButtonKey.index(config.scrollButton)))
                        .font(.system(size: 11, weight: .medium))
                    Button(L10n.t("Ghi nút")) { triggerRecording() }
                        .buttonStyle(.link).font(.system(size: 11))
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 20)
        }
    }

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

    private var footerNote: some View {
        Text(L10n.t("Nếu không hoạt động: kiểm tra Trợ năng, bundle ID, phím tắt riêng của app và tắt mapping trùng trong phần mềm chuột khác. Tắt công tắc ở trên để ngừng xử lý cử chỉ."))
            .font(.system(size: 11)).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
    }

    // MARK: - Actions

    /// One entry point for both "record the hold button" and "record the scroll button",
    /// because they are the same interaction — press a button on the mouse — and the
    /// engine's recording mode already accepts either. The page distinguishes them only
    /// in what it *says*.
    private func triggerRecording() {
        recordingTrigger = true
        recordingDirection = nil
        controller.recordTrigger()
    }

    private func profileDisplayName() -> String {
        if profile == GestureProfiles.fallback { return L10n.t("Mặc định toàn cục") }
        if !GestureProfiles.hasPreset(bundle: profile) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: profile) {
                return FileManager.default.displayName(atPath: url.path)
            }
            return profile
        }
        return GestureProfiles.all.first { $0.id == profile }?.name ?? profile
    }

    /// The app in front, when macOS reports one that is not XFinder itself.
    private var frontmostBundle: String {
        let id = controller.lastExternalBundle
        return id.isEmpty ? GestureProfiles.fallback : id
    }

    private var customProfiles: [String] {
        let known = Set(GestureProfiles.all.map(\.id))
        return Set(Array(config.overrides.keys) + [profile]).subtracting(known).sorted()
    }
}
