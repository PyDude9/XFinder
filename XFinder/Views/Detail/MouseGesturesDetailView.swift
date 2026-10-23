import SwiftUI
import AppKit

/// Compile-time lever for the measured-activity block at the bottom of the page.
///
/// **`false` is the shipped value, and it is now authoritative.** The block is a development
/// instrument — the only place the engine's own view of a press (button number, locked
/// direction, the app it resolved for) is visible — so it is not part of the page a normal
/// user reads, and the user asked for it to be gone from the shipped build.
///
/// ── What changed, and the mistake it corrects (PATCH v10.1) ───────────────────────────
/// The section used to render on `DEBUG_SHOW_ENGINE_LOG || config.debug`. The reasoning was
/// that the page's own switch says *"Bật ghi nhật ký để xem XFinder nhận được gì"*, so
/// removing the block at compile time would leave a control promising something it cannot do.
/// The reasoning was wrong on its own facts: **that switch lives inside this section**, so
/// gating the section removes the switch with it and nothing is left promising anything.
/// What the `||` actually did was let a stored `debug = true` keep a developer block on the
/// user's page — which is what the user reported.
///
/// So the flag alone decides. `GestureConfiguration.debug` is untouched and still gates the
/// engine's own diagnostic ring, and the switch that writes it is offered exactly when the
/// block it controls is visible. A diagnostic build sets this to `true` and gets both back.
private let DEBUG_SHOW_ENGINE_LOG = false

/// Chuột & cử chỉ — the user opens this page asking **"what will each swipe send,
/// right now?"**. Preset-first: every supported app already has working mappings, so
/// the diagram is the page and recording is a secondary action.
///
/// Layout — the nine blocks of variant B (`docs/specs/T14-mouse-gestures-B.md`):
/// 1 header · 2 status line · 3 app chooser · 4 gesture map · 5 side buttons ·
/// 6 hold & scroll · 7 tilt · 8 diagnostics · 9 footer. T14a builds the skeleton; later
/// steps replace blocks 3-9 in place. The old `mappingSection` is kept on disk but no
/// longer called from `body` (deleted in T14e). Flat System-Settings look, matching
/// Hệ thống / Mạng / Vùng bắt dính. No card-per-group: a card per row would break the
/// mapping into boxes the eye cannot compare.
///
/// Banned on macOS 14 here: `.monospaced()`, `Gauge`, `Grid{`, `scrollContentBackground`,
/// `symbolEffect`, `NavigationSplitView`. `.pickerStyle(.segmented)` is avoided — long
/// labels give a segmented Picker an unbounded ideal width and the split view jumps.
struct MouseGesturesDetailView: View {
    @State private var controller = GestureController.shared
    @State private var profile = GestureProfiles.fallback
    @State private var customBundle = ""
    /// Set by the strip's "＋" chip (T14b): expands the "Nâng cao — ứng dụng khác" disclosure
    /// that holds the bundle-ID field, which used to be a redundant sidebar row (Lỗi #15).
    @State private var showAdvancedApps = false
    @State private var recordingDirection: GestureDirection?
    @State private var recordingTrigger = false
    /// The row whose per-row **Ghi** button armed the recording, or `nil` when the
    /// recording was started from a header button (PATCH v10 R3). Purely a highlight: the
    /// engine can only listen for "the next press", so the row exists to make the *intent*
    /// explicit — press this control — and to show that XFinder is listening.
    @State private var recordingButton: Int?
    /// Which arm of the diagram is highlighted. `nil` = nothing picked yet, which shows
    /// the interaction hint instead of an alarming blank panel.
    @State private var pickedDirection: GestureDirection?
    /// Which *control* of the mouse is highlighted, tracked separately from the direction
    /// because they are different questions and can be open at once: "what does this arrow
    /// send" and "what is this button doing".
    @State private var pickedButton: Int?
    @State private var trusted = WindowManager.isTrusted
    /// The pointing devices IOHID could actually read. Empty means "the probe found
    /// nothing", which is NOT the same as "the mouse has no buttons" — the diagram says
    /// "not detected yet" for that case rather than greying an arm out.
    @State private var devices: [CapabilityDescriptor] = []
    @State private var probed = false
    /// A device the user pinned manually. Honoured as-is and never replaced by a
    /// detection result — see `DeviceSelection.active`.
    @State private var pinnedDevice: CapabilityDescriptor?
    /// The raw HID element facts, read **only** when the user opens the disclosure
    /// (PATCH v10 R1). Reading it costs another `IOHIDManagerOpen` plus an element copy
    /// per device, so it must never be on the page-load path — the summary above is
    /// enough to use the page, and this exists so the summary can be checked.
    @State private var hidDump: [String] = []
    @State private var hidDumpExpanded = false
    @State private var hidDumpLoading = false
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

    /// Everything the role function needs, built once per render from the device in force.
    private var roleContext: MouseRoleContext {
        DeviceCapabilityModel.roleContext(for: activeDevice, configuration: config)
    }

    /// The single role function the drawing and the list both read.
    private func buttonRole(_ button: Int) -> MouseButtonRole {
        DeviceCapabilityModel.role(forEventButton: button, context: roleContext)
    }

    /// The controls to draw and list: the archetype slots, plus anything beyond them the
    /// mouse declares.
    private var drawnButtons: [Int] {
        DeviceCapabilityModel.drawnButtons(declaredEventButtons: roleContext.declaredEventButtons)
    }

    /// A press the engine saw that the descriptor never declared — measured evidence that
    /// the probe under-reports this mouse, which is the only thing that should raise the
    /// "missing button" prompt.
    private var undeclaredPress: Int? {
        DeviceCapabilityModel.undeclaredPress(observed: observedButton, context: roleContext)
    }

    /// Which figure to draw (PATCH v10 R2). Derived from the descriptor, so a device that is
    /// not a multi-button mouse gets the generic figure instead of six chips it does not
    /// have — and a device nothing could be read from still gets the archetype, greyed and
    /// labelled "not read yet", because a blank figure would read as "no buttons".
    private var diagramStyle: MouseDiagramStyle {
        DeviceCapabilityModel.diagramStyle(for: activeDevice)
    }

    /// Button-typed elements the descriptor declares on a vendor-defined page. Evidence
    /// only — never added to the declared button count.
    private var vendorControlCount: Int {
        DeviceCapabilityModel.vendorControlCount(for: activeDevice)
    }

    /// Consumer-page controls are raw HID evidence only; they never become mouse buttons.
    private var consumerUsageCount: Int {
        activeDevice?.physical.consumerUsages.count ?? 0
    }

    /// Whether the descriptor under-reports this mouse, on evidence. See
    /// `DeviceCapabilityModel.underReportedControls` for why this cannot fire on a mouse
    /// that simply has fewer buttons.
    private var underReported: Bool {
        DeviceCapabilityModel.underReportedControls(
            declaredEventButtons: roleContext.declaredEventButtons,
            vendorControlCount: vendorControlCount,
            observed: observedButton,
            context: roleContext)
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
                PageHeader(title: L10n.t("Chuột & cử chỉ"),
                    subtitle: L10n.t("Giữ nút, kéo một hướng rồi thả — XFinder gửi phím tắt theo ứng dụng đang mở."),
                    trailing: AnyView(
                        HStack(spacing: 6) {
                            Text(config.enabled ? L10n.t("Bật") : L10n.t("Tắt"))
                                .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
                            Toggle("", isOn: Binding(
                                get: { config.enabled },
                                set: { v in controller.update { $0.enabled = v } }))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                // An empty-label switch reads as nothing to VoiceOver (wireframe B
                                // names it "Bật/tắt cử chỉ").
                                .accessibilityLabel(L10n.t("Bật/tắt cử chỉ"))
                        }
                    ))

                // ── Khối 2 — dòng trạng thái (F2/F3/S2 + S3-S6 + S27) ──────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    if !trusted { permissionBanner }
                    readinessRow
                }

                // ── Khối 3 — chọn ứng dụng (F4/F5/F24/F25, dải chip ở T14b) ────────────────
                VStack(alignment: .leading, spacing: 10) {
                    // F4 — the chip strip replaced the 240-pt `profileSidebar` column (Lỗi #8).
                    // Block 3 stays flat like blocks 5-9 rather than in the wireframe's "Ứng dụng"
                    // card: the sub-line and the disclosure below carry their own 20-pt page
                    // padding (reused verbatim, per the spec), which a `SettingsSection` card would
                    // indent a second time.
                    let installed = Set(installedBundleIDs())
                    let chips = appChips(installed: installed)
                    MouseGestureAppStrip(
                        chips: chips,
                        selected: profile,
                        icon: { appIcon(for: $0) },
                        onSelect: { profile = $0 },
                        onAdd: { showAdvancedApps = true })
                        .padding(.horizontal, 20)
                    frontmostHint(chips: chips)
                    customBundleRow
                    // F25 — spec T14b step 3: right under the strip / sub-line, same disable rule
                    // as the old block-4 copy (which this replaces).
                    HStack(spacing: 8) {
                        Button(L10n.t("Khôi phục toàn bộ ứng dụng này về mặc định")) { controller.resetProfile(profile) }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(config.overrides[profile] == nil)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                }

                // ── Khối 4 — sơ đồ cử chỉ (F6-F12/F15/S7/S28/S54-S68) ──────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "computermouse",
                                  title: L10n.t("Sơ đồ cử chỉ"),
                                  subtitle: L10n.t("Số trên thân chuột là nút bạn giữ — bấm vào đó để đổi. Các nút của chuột hiện ngay trên hình: nút nào mờ là nút máy chưa đọc được."))

                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .center, spacing: 10) {
                            MouseDiagramView(
                                selection: $pickedDirection,
                                selectedButton: $pickedButton,
                                row: { resolved($0) },
                                actionName: { resolvedName($0) },
                                tint: { sourceTint(profile, $0) },
                                buttonRole: { buttonRole($0) },
                                buttons: drawnButtons,
                                style: diagramStyle,
                                declaredEventButtons: roleContext.declaredEventButtons,
                                trigger: config.trigger,
                                unsupported: { DeviceCapabilityModel.armSupport(for: $0, device: activeDevice) },
                                recordingDirection: recordingDirection,
                                onRecordTrigger: { triggerRecording() },
                                isRecordingTrigger: recordingTrigger)
                                .frame(width: 284)
                            if tiltArmsLive {
                                TiltArmsRow(
                                    selection: $pickedDirection,
                                    row: { resolved($0) },
                                    actionName: { resolvedName($0) },
                                    tint: { sourceTint(profile, $0) },
                                    unsupported: { DeviceCapabilityModel.armSupport(for: $0, device: activeDevice) },
                                    recordingDirection: recordingDirection)
                            }
                        }
                        .frame(width: 310)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 10)

                        Divider()

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
                            } else if let button = pickedButton {
                                buttonInspector(button)
                            } else {
                                directionSummaryView
                            }
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                            .fill(XFinderTokens.Fill.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                            .strokeBorder(XFinderTokens.Fill.hairline, lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                }

                // ── Khối 5 — nút hông (F8/F29/S34-S40, danh sách hàng ở T14d) ─────────────
                VStack(alignment: .leading, spacing: 10) {
                    buttonListSection
                    legend
                }

                // ── Khối 6 — nút giữ & cuộn (F7/F22/F23/S47-S51) ──────────────────────────
                switchesSection

                // ── XF-T25 — cuộn chuột mượt (engine + khoá riêng, không thuộc blob cử chỉ) ──────
                SmoothScrollSection()

                // ── Khối 7 — nghiêng con lăn (F20/S41-S42) ────────────────────────────────
                tiltRow

                // ── Khối 8 — chẩn đoán chuột (F19/S13-S33) ───────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    deviceRow
                    hidDumpRow
                    observedButtonRow
                }

                // ── Khối 9 — footer (F26/S53) ────────────────────────────────────────────
                footerNote

                if DEBUG_SHOW_ENGINE_LOG {
                    Divider().padding(.horizontal, 20)

                    activitySection
                }
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
        .onDisappear {
            controller.cancelRecording()
            recordingTrigger = false
            recordingButton = nil
        }
        .onChange(of: controller.recording) { _, recording in
            if !recording {
                recordingDirection = nil
                recordingTrigger = false
                recordingButton = nil
            }
        }
        .onChange(of: controller.observedPress) { _, press in
            guard let press else { return }
            observedButton = press
        }
        .onChange(of: profile) { _, _ in
            recordingDirection = nil
            pickedDirection = MouseDiagramSelection.afterProfileChange()
            pickedButton = nil
        }
        .onChange(of: pickedButton) { _, newBtn in
            if newBtn != nil {
                pickedDirection = nil
            }
        }
        // The other half: an arm on the diagram (or a tilt chip) sets only `pickedDirection`, so without this a
        // previously picked button chip stayed highlighted beside the arrow (T14c review).
        .onChange(of: pickedDirection) { _, newDirection in
            if newDirection != nil {
                pickedButton = nil
            }
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

    /// The page's **single** status line — one pill, not a checklist. Five states:
    /// recording a mouse button or a keyboard shortcut (accent, S27), off (grey), ready (green), a named tap error, and the
    /// generic no-Accessibility error (orange). The two facts that can silently stop a
    /// gesture — the hold button and the frontmost app — are stated where they belong (the
    /// diagram's hold badge and the app picker), not repeated here as a wall of warnings.
    private var readinessRow: some View {
        // Which sentence is decided by `GesturePageStatus` (pure, tested). A direction being recorded
        // means a keyboard shortcut; otherwise the recording is a mouse button.
        let status = GesturePageStatus.of(recording: controller.recording,
                                          recordingShortcut: recordingDirection != nil,
                                          enabled: config.enabled,
                                          tapActive: controller.tapActive,
                                          tapFailure: controller.tapFailure)
        let tint: Color
        let icon: String
        switch status {
        case .recordingShortcut, .recordingButton: tint = .accentColor; icon = "record.circle"
        case .off: tint = .secondary; icon = "pause.circle.fill"
        case .ready: tint = .green; icon = "checkmark.circle.fill"
        case .tapFailure, .needsAccessibility: tint = .orange; icon = "exclamationmark.triangle.fill"
        }
        let text = L10n.t(status.textKey)
        return HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(tint).font(XFinderTokens.Font.rowValue)
            Text(text).font(XFinderTokens.Font.rowValue.weight(.medium)).foregroundColor(tint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.12)))
        .padding(.horizontal, 20)
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.t("Cần quyền Trợ năng"), systemImage: "exclamationmark.triangle.fill")
                .font(XFinderTokens.Font.row)
                .foregroundColor(.orange)
            Text(L10n.t("XFinder chỉ nhận được nút chuột trước các ứng dụng khác khi bạn cấp quyền Trợ năng. Bật công tắc vẫn cần quyền này — thiếu quyền thì Event Tap không mở được và cử chỉ không chạy."))
                .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary)
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
                          subtitle: L10n.t("Số trên thân chuột là nút bạn giữ — bấm vào đó để đổi. Các nút của chuột hiện ngay trên hình: nút nào mờ là nút máy chưa đọc được."))

            HStack(alignment: .top, spacing: 16) {
                profileSidebar
                    .frame(width: 240, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 10) {
                    frontmostHint(chips: appChips(installed: Set(installedBundleIDs())))
                    deviceRow
                    hidDumpRow
                    observedButtonRow

                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            MouseDiagramView(
                                selection: $pickedDirection,
                                selectedButton: $pickedButton,
                                row: { resolved($0) },
                                actionName: { resolvedName($0) },
                                tint: { sourceTint(profile, $0) },
                                buttonRole: { buttonRole($0) },
                                buttons: drawnButtons,
                                style: diagramStyle,
                                declaredEventButtons: roleContext.declaredEventButtons,
                                trigger: config.trigger,
                                unsupported: { DeviceCapabilityModel.armSupport(for: $0, device: activeDevice) },
                                recordingDirection: recordingDirection,
                                onRecordTrigger: { triggerRecording() },
                                isRecordingTrigger: recordingTrigger)
                                .frame(minWidth: 0, maxWidth: .infinity)
                            if tiltArmsLive {
                                TiltArmsRow(
                                    selection: $pickedDirection,
                                    row: { resolved($0) },
                                    actionName: { resolvedName($0) },
                                    tint: { sourceTint(profile, $0) },
                                    unsupported: { DeviceCapabilityModel.armSupport(for: $0, device: activeDevice) },
                                    recordingDirection: recordingDirection)
                            }
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)

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

                    buttonListSection
                    legend
                    tiltRow
                    customBundleRow

                    HStack(spacing: 8) {
                        Button(L10n.t("Khôi phục toàn bộ ứng dụng này về mặc định")) { controller.resetProfile(profile) }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(config.overrides[profile] == nil)
                        Spacer(minLength: 0)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 20)
            .frame(minWidth: 0, maxWidth: 920, alignment: .leading)
        }
    }

    private var profileSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("Ứng dụng"))
                .font(XFinderTokens.Font.rowValue.weight(.semibold))
            ForEach(orderedProfiles) { item in
                profileRow(id: item.id, title: item.id == GestureProfiles.fallback ? L10n.t("Mặc định toàn cục") : item.name)
            }
            if !GestureProfiles.hasPreset(bundle: frontmostBundle) && !frontmostBundle.isEmpty {
                profileRow(id: frontmostBundle, title: L10n.t("Ứng dụng đang dùng"))
            }
            ForEach(customProfiles, id: \.self) { id in
                profileRow(id: id, title: id)
            }
            if controller.recording {
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text(L10n.t("Đang ghi — Esc để hủy"))
                        .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                }
                .padding(.top, 4)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).fill(Color.secondary.opacity(0.05)))
    }

    private func profileRow(id: String, title: String) -> some View {
        Button {
            profile = id
            pickedDirection = MouseDiagramSelection.afterProfileChange()
            pickedButton = nil
        } label: {
            HStack(spacing: 7) {
                if id == profile, let img = appIcon {
                    Image(nsImage: img).resizable().frame(width: 18, height: 18).cornerRadius(4)
                } else {
                    Image(systemName: id == GestureProfiles.fallback ? "globe" : "app" )
                        .font(XFinderTokens.Font.sectionIcon).foregroundColor(.secondary).frame(width: 18)
                }
                Text(title)
                    .font(XFinderTokens.Font.rowValue.weight(id == profile ? .semibold : .regular))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(id == profile ? .accentColor : .primary)
    }

    /// Shown before the user has clicked an arrow. It teaches the interaction instead of
    /// leaving an alarming blank half-page — and it states the *measured* button number
    /// when the engine has already seen one, so the first question ("which button?") is
    /// answered with evidence rather than with the word "Button 4".
    private var emptySelectionHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "hand.tap")
                .font(XFinderTokens.Font.pageIcon).foregroundColor(.secondary.opacity(0.6))
            Text(L10n.t("Bấm vào một mũi tên để xem chi tiết"))
                .font(XFinderTokens.Font.row)
            Text(L10n.t("Mỗi mũi tên là một động tác: giữ nút trên thân chuột rồi kéo theo hướng đó. Bấm vào mũi tên để xem và đổi phím nó gửi."))
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.t("Ba bước: giữ nút → kéo quá ngưỡng → thả. Kéo chưa đủ xa thì XFinder phát lại click bình thường, nên không mất thao tác nào."))
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    // MARK: - Block 4: Direction Summary & Button Inspector (T14c)

    private func directionIcon(_ direction: GestureDirection) -> String {
        switch direction {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .tiltLeft: return "arrow.uturn.left"
        case .tiltRight: return "arrow.uturn.right"
        }
    }

    private func summaryActionName(_ direction: GestureDirection, row: ResolvedGestureRow) -> String {
        if row.entry.isUnassigned {
            return L10n.t("Chưa gán")
        }
        if let name = resolvedName(direction) {
            return name
        }
        if let system = row.entry.systemAction {
            return L10n.t(system.captionKey)
        }
        if row.entry.shortcut != nil {
            return L10n.t("Phím bạn tự ghi")
        }
        return L10n.t("Chưa gán")
    }

    private func directionSummaryRow(_ direction: GestureDirection) -> some View {
        let row = resolved(direction)
        let action = summaryActionName(direction, row: row)
        // A chord in glyphs, or — for a system action this Mac has no shortcut for — a translated sentence.
        let chord = row.displayCaption(translate: { L10n.t($0) }) ?? ""
        return Button {
            pickedDirection = direction
            pickedButton = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: directionIcon(direction))
                    .font(XFinderTokens.Font.caption.weight(.semibold))
                    .foregroundColor(sourceTint(profile, direction))
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                            .fill(XFinderTokens.Fill.inset)
                    )

                HStack(spacing: 6) {
                    Text(L10n.t(direction.titleKey))
                        .font(XFinderTokens.Font.row)
                        .foregroundColor(.primary)
                    Text("—")
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                    Text(action)
                        .font(XFinderTokens.Font.row)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(minWidth: 0, alignment: .leading)
                }

                Spacer(minLength: 4)

                if !chord.isEmpty {
                    Text(chord)
                        .font(XFinderTokens.Font.mono.weight(.semibold))
                        .foregroundColor(row.isUnboundSystemAction ? .orange : .primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                                .fill(XFinderTokens.Fill.inset)
                        )
                }

                if row.isUserOverride {
                    Text(L10n.t("Bạn tự đặt"))
                        .font(XFinderTokens.Font.caption.weight(.medium))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var directionSummaryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(GestureDirection.holdDrag, id: \.self) { direction in
                directionSummaryRow(direction)
                if direction != GestureDirection.holdDrag.last {
                    Divider()
                }
            }

            Divider().padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("Mỗi mũi tên là một động tác: giữ nút trên thân chuột rồi kéo theo hướng đó. Bấm vào mũi tên để xem và đổi phím nó gửi."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.t("Ba bước: giữ nút → kéo quá ngưỡng → thả. Kéo chưa đủ xa thì XFinder phát lại click bình thường, nên không mất thao tác nào."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                .fill(Color.secondary.opacity(0.04))
        )
    }

    private func buttonClickActionLabel(_ button: Int, role: MouseButtonRole) -> String {
        switch role {
        case .holdTriggerWithAction(let action):
            return buttonActionDisplay(action)
        case .assigned(let action):
            return buttonActionDisplay(action)
        case .holdTrigger:
            return L10n.t("Nút giữ")
        case .scrollButton:
            return L10n.t("Nút cuộn")
        case .reserved:
            return L10n.t("Chỉ bấm")
        case .unassigned:
            return L10n.t("Chưa gán")
        case .notDeclared:
            return L10n.t("Chuột không khai báo")
        case .unknown:
            return L10n.t("Chưa đọc được")
        }
    }

    private func buttonActionDisplay(_ action: ButtonAction) -> String {
        switch action {
        case .instant(.back):
            return "\(L10n.t(InstantAction.back.labelKey)) (\(InstantAction.back.shortcut.label))"
        case .instant(.forward):
            return "\(L10n.t(InstantAction.forward.labelKey)) (\(InstantAction.forward.shortcut.label))"
        case .shortcut(let s):
            return s.label
        case .unassigned:
            return L10n.t("Chưa gán")
        }
    }

    private func rolePill(_ role: MouseButtonRole) -> some View {
        Text(L10n.t(role.labelKey))
            .font(XFinderTokens.Font.caption.weight(.medium))
            .foregroundColor(roleColor(role))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(roleColor(role).opacity(0.14)))
            .fixedSize()
    }

    private func roleColor(_ role: MouseButtonRole) -> Color {
        switch role {
        case .holdTrigger, .holdTriggerWithAction: return .accentColor
        case .assigned:     return .accentColor
        case .scrollButton: return .accentColor
        case .reserved:     return .primary
        case .unassigned:   return .secondary
        case .notDeclared:  return .orange
        case .unknown:      return .secondary
        }
    }

    private func buttonInspector(_ button: Int) -> some View {
        let role = buttonRole(button)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "computermouse.fill")
                    .font(XFinderTokens.Font.sectionIcon)
                    .foregroundColor(roleColor(role))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                            .fill(roleColor(role).opacity(0.14))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(ButtonKey.index(button)))
                        .font(XFinderTokens.Font.row.weight(.semibold))
                        .lineLimit(1)
                    if let hint = ButtonLabelStructure.hintKey(forButtonNumber: button) {
                        Text(L10n.t(hint))
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if let pos = MouseControlSlot.slot(forEventButton: button)?.positionKey {
                        Text(L10n.t(pos))
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(L10n.t(role.labelKey))
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                rolePill(role)
            }

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Text(L10n.t("Bấm nhanh"))
                    .font(XFinderTokens.Font.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                Text(buttonClickActionLabel(button, role: role))
                    .font(XFinderTokens.Font.row)
                    .foregroundColor(.primary)
                Spacer()
            }

            Divider()

            switch role {
            case .holdTrigger, .holdTriggerWithAction:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(L10n.t("Đây là nút giữ hiện tại"))
                        .font(XFinderTokens.Font.row)
                        .foregroundColor(.primary)
                    Spacer()
                }
            default:
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 0) {
                        Text(L10n.t("Nút giữ cử chỉ hiện tại là "))
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(.secondary)
                        Text(L10n.t(compactButton: config.trigger.key))
                            .font(XFinderTokens.Font.caption.weight(.semibold))
                            .foregroundColor(.primary)
                    }
                    Spacer(minLength: 4)
                    // `isAssignable`, not `isDeclared`: left and right click are declared but RESERVED. T14c gated on
                    // `isDeclared`, so the right-click chip offered to become the hold trigger (a valid button number,
                    // so validate() kept it) and left click silently snapped back. GestureButtonList always used
                    // `isAssignable`; an undeclared button the user really pressed stays assignable on purpose.
                    if role.isAssignable {
                        Button(L10n.t("Dùng làm nút giữ")) {
                            controller.update { $0.trigger = .mouseButton(button) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Divider()

            if let note = DeviceCapabilityModel.passthroughNoteKey(forEventButton: button) {
                Text(L10n.t(note))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L10n.t(role.explanationKey))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                .fill(Color.secondary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile, style: .continuous)
                .strokeBorder(roleColor(role).opacity(0.35), lineWidth: 1)
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
                Image(systemName: "globe").font(XFinderTokens.Font.sectionIcon).foregroundColor(.secondary)
                    .frame(width: 20)
            }
            Text(profileDisplayName())
                .font(XFinderTokens.Font.row)
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
                        .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    /// Preset-first ordering: apps the user is actually running come first, then the rest
    /// of the built-in list, then Global last. A picker that opens on a list of
    /// applications the user does not have installed is how "preset-first" reads as
    /// "empty list" — the reader cannot find their own app in it.
    private var orderedProfiles: [GestureProfile] { orderedProfiles(installed: Set(installedBundleIDs())) }

    /// `installedBundleIDs()` is one LaunchServices lookup per preset (21) — the body computes it ONCE per
    /// render and passes it here, instead of the four passes T14b's first version made.
    private func orderedProfiles(installed: Set<String>) -> [GestureProfile] {
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
    private func frontmostHint(chips: [MouseGestureAppChip]) -> some View {
        let front = controller.lastExternalBundle
        let hasBuiltIn = GestureProfiles.hasPreset(bundle: front)
        let hasOverride = config.overrides[front]?.isEmpty == false
        return VStack(alignment: .leading, spacing: 4) {
            if front.isEmpty {
                Text(L10n.t("Chưa xác định được ứng dụng đang mở phía trước."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            } else {
                HStack(spacing: 6) {
                    Text(L10n.t("Ứng dụng đang dùng") + ": " + front)
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    // F5 — kept only when the front app has no chip of its own (T14b.2): if it is
                    // already a clickable chip, this button duplicated that chip (Lỗi #15).
                    if !frontHasChip(in: chips) {
                        Button(L10n.t("Xem")) { profile = front }.controlSize(.small)
                    }
                }
                if hasBuiltIn {
                    if hasOverride {
                        Text(L10n.t("Ứng dụng này có preset riêng, và bạn đã tự đặt một số hướng."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(L10n.t("Ứng dụng này đang dùng preset có sẵn."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(L10n.t("Ứng dụng này không có preset riêng — đang dùng bảng “Mặc định toàn cục”."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
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
                .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(L10n.t("Chuột đang kết nối"))
                        .font(XFinderTokens.Font.caption.weight(.medium)).foregroundColor(.secondary)
                    provenancePill
                }
                Text(deviceDescription)
                    .font(XFinderTokens.Font.rowValue)
                    .lineLimit(1).truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                Text(deviceExplanation)
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private var provenancePill: some View {
        let detected = provenance.isDetected
        return Text(detected ? L10n.t("Đã nhận diện") : L10n.t("Bạn tự đặt"))
            .font(XFinderTokens.Font.caption.weight(.medium))
            .foregroundColor(detected ? .green : .secondary)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill((detected ? Color.green : Color.secondary).opacity(0.14)))
            .fixedSize()
    }

    /// The raw element facts, one disclosure below the summary (PATCH v10 R1).
    ///
    /// Everything the page says about the mouse is derived from these lines, so showing
    /// them is what makes the rest checkable: "the descriptor declares five buttons" and
    /// "there are N vendor-page button elements" are claims, and a claim whose evidence can
    /// be read is worth more than one that cannot. Read on demand — see `hidDump`'s note on
    /// why this is not on the page-load path.
    private var hidDumpRow: some View {
        DisclosureGroup(isExpanded: $hidDumpExpanded) {
            VStack(alignment: .leading, spacing: 2) {
                if hidDumpLoading {
                    Text(L10n.t("Đang đọc mô tả HID…"))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                } else {
                    ForEach(Array(hidDump.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(XFinderTokens.Font.mono)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle")
                    .font(XFinderTokens.Font.rowValue).foregroundColor(.secondary).frame(width: 16)
                Text(L10n.t("Mô tả HID thô"))
                    .font(XFinderTokens.Font.caption.weight(.medium)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .onChange(of: hidDumpExpanded) { _, expanded in
            if expanded, hidDump.isEmpty { loadHIDDump() }
        }
    }

    /// Reads the raw element facts off the main thread, exactly like the summary probe.
    private func loadHIDDump() {
        hidDumpLoading = true
        Task {
            let lines = await Task.detached(priority: .userInitiated) {
                DeviceCapabilityProbe.connectedElementDump()
            }.value
            hidDump = lines
            hidDumpLoading = false
        }
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
                    .font(XFinderTokens.Font.rowValue).foregroundColor(.accentColor).frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Nút bạn vừa bấm: ") + "\(observed + 1)")
                        .font(XFinderTokens.Font.rowValue.weight(.medium))
                    Text(L10n.t("Đây là con số XFinder nhận được từ chuột. Bấm “Ghi nút” rồi bấm đúng nút đó để đặt nó làm nút giữ."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
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

    private var appIcon: NSImage? { appIcon(for: profile) }

    /// The real icon for any bundle id. Block 3's strip needs one per chip, so this is
    /// id-parameterised — `appIcon` above reads the `profile` @State and cannot serve a strip.
    private func appIcon(for bundle: String) -> NSImage? {
        // Through the per-process cache: the page re-renders on every app switch while it is open, and
        // `urlForApplication` + `icon(forFile:)` per chip per render is the cost the clipboard Library
        // paid in hundreds of MB (2026-10-13). One lookup per bundle id per process.
        guard bundle != GestureProfiles.fallback else { return nil }
        return ClipboardAppIcon.icon(forBundleID: bundle)
    }

    /// The list of the mouse's controls and what each one is doing (PATCH v9.1 R3).
    ///
    /// Sits directly under the drawing rather than in a tab of its own: a chip and its row
    /// are two views of one fact, and putting a click target in one place and its options in
    /// another (with a scroll between them) is how "click the thing you want to change"
    /// becomes "click, then hunt for what changed".
    private var buttonListSection: some View {
        GestureButtonList(
            buttons: drawnButtons,
            role: { buttonRole($0) },
            selected: $pickedButton,
            declaredEventButtons: roleContext.declaredEventButtons,
            vendorControlCount: vendorControlCount,
            consumerUsageCount: consumerUsageCount,
            undeclaredPress: undeclaredPress,
            underReported: underReported,
            onSetTrigger: { button in
                // The one write this section performs, and it goes through the same
                // `update` path as every other control so `validate()` runs and the
                // scroll modifier can be repaired if it collided with the new trigger.
                controller.update { $0.trigger = .mouseButton(button) }
            },
            onRecordTrigger: { button in triggerRecording(button: button) },
            recordingButton: recordingButton,
            holdButtonSingleClickEnabled: Binding(
                get: { config.holdButtonSingleClickEnabled },
                set: { v in controller.update { $0.holdButtonSingleClickEnabled = v } }
            ),
            onSetAction: { button, action in
                controller.update { config in
                    config.buttonActions[button + 1] = action
                }
            })
        .padding(.horizontal, 20)
    }

    private var legend: some View {
        Text(L10n.t("Mặc định = preset dựng sẵn · Tự đặt = bạn đã đổi hướng đó · Chưa gán = cố ý không gửi phím. Chưa gán trên ứng dụng đã có preset sẽ không rơi về bảng toàn cục. Biểu tượng ⇄ nhỏ nghĩa là hướng đó chuyển tiếp cuộn ngang nguyên bản của chuột."))
            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
    }

    /// Whether the two tilt arms are **live** — both stored fields, not just the one the
    /// switch used to write.
    ///
    /// Measured on this machine's own store: `tiltAvailable = true, tiltEnabled = false`, a
    /// state the current UI cannot produce but an older build left behind. Reading
    /// `tiltAvailable` alone drew two arms that could never fire *and* showed the switch as
    /// on. `TiltArmsVisibility.isLive` is the tested contract for the read; the switch below
    /// writes both fields through `TiltArmsVisibility.fields(forReveal:)`.
    private var tiltArmsLive: Bool {
        TiltArmsVisibility.isLive(available: config.tiltAvailable, enabled: config.tiltEnabled)
    }

    /// Tilt exists only on mice whose wheel tilts *and* whose driver reports it as a
    /// discrete horizontal wheel. This was hard-coded `true`, so the two tilt arms were
    /// drawn on hardware where they can never fire — the Razer Basilisk 25K/35K and the
    /// Magic Mouse both report every wheel event as `IsContinuous == 1` with axis2 == 0
    /// (measured, see docs/GESTURE_VERIFICATION.md), which `GestureEngine` deliberately
    /// rejects so it never steals trackpad scrolling.
    ///
    /// ── One switch, and it must write both fields (PATCH v10) ──────────────────────────
    /// It used to write only `tiltAvailable` — the field that decides whether the arms are
    /// **drawn**. The engine reads `tiltEnabled`, which nothing set, so an action assigned
    /// to `tiltLeft` could never fire: the switch revealed two arms that were dead on
    /// arrival. `TiltArmsVisibility.fields(forReveal:)` is the tested contract for what this
    /// one switch writes, and the copy below says "turn on" rather than "show" because that
    /// is now what it does.
    private var tiltRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { tiltArmsLive },
                set: { v in
                    let write = TiltArmsVisibility.fields(forReveal: v)
                    controller.update {
                        $0.tiltAvailable = write.available
                        $0.tiltEnabled = write.enabled
                    }
                }))
            {
                Text(L10n.t("Bật hai hướng nghiêng con lăn")).font(XFinderTokens.Font.rowValue)
            }
            .toggleStyle(.switch).controlSize(.small)
            Text(L10n.t("Chỉ dùng cho chuột có con lăn nghiêng được và có driver gửi cuộn ngang rời rạc — ví dụ Logitech MX Master với Logi Options. Đo trên máy này: Razer Basilisk và Magic Mouse đều báo cuộn liên tục, nên hai hướng đó sẽ không bao giờ chạy; tắt để sơ đồ khỏi vẽ thừa. XFinder không thể tự dò ra phần cứng của bạn."))
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if tiltArmsLive {
                Text(L10n.t("Công tắc này vừa hiện hai mũi tên vừa cho engine xử lý nghiêng con lăn — trước đây nó chỉ hiện mũi tên, nên gán phím cho nghiêng xong vẫn không có gì chạy. Nghiêng chỉ chạy khi công tắc chính ở trên cũng đang bật."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Activity (measured, from the engine's own callback)
    //
    // Rendered when `DEBUG_SHOW_ENGINE_LOG` is set — see the constant at the top of the file
    // for why this is a compile-time gate rather than `config.debug`.
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

    /// The buttons the scroll-button menu offers: the drawn buttons the mouse declares, minus the hold
    /// trigger (`validate()` refuses the two being one button). With no device measured yet nothing is
    /// "declared", so the declaration filter is skipped rather than leaving an empty menu — and the stored
    /// value is always listed, or a menu Picker whose selection has no tag renders blank.
    private var scrollButtonChoices: [Int] {
        let declared = roleContext.declaredEventButtons
        var choices = drawnButtons.filter { button in
            if let declared, !declared.contains(button) { return false }
            switch buttonRole(button) {
            case .holdTrigger, .holdTriggerWithAction: return false
            default: return true
            }
        }
        if !choices.contains(config.scrollButton) { choices.append(config.scrollButton) }
        return choices.sorted()
    }

    private var switchesSection: some View {
        SettingsSection(title: L10n.t("Nút giữ và cuộn"),
                        footer: L10n.t("Nút giữ bắt đầu mọi cử chỉ. Nút cuộn là tuỳ chọn riêng, mặc định tắt.")) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Nút giữ"))
                        .font(XFinderTokens.Font.rowValue.weight(.medium))
                    Text(L10n.t("Giữ nút này rồi kéo bốn hướng. Mặc định là nút hông — con số tuỳ chuột, nên hãy ghi lại nếu bạn muốn nút khác."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(L10n.t(compactButton: config.trigger.key))
                    .font(XFinderTokens.Font.rowValue.weight(.semibold))
                Button(recordingTrigger ? L10n.t("Đang ghi…") : L10n.t("Ghi nút")) { triggerRecording() }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(controller.recording)
            }
            .settingsRow()

            SettingsDivider()

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { config.scrollButtonEnabled },
                    set: { v in controller.update { $0.scrollButtonEnabled = v } }))
                {
                    Text(L10n.t("Giữ nút cuộn rồi kéo để cuộn")).font(XFinderTokens.Font.rowValue)
                }
                .toggleStyle(.switch).controlSize(.small)
                Text(L10n.t("Dành cho ứng dụng cần cuộn nhiều như Photoshop hay CapCut: giữ một nút hông rồi kéo là cuộn, không cần nhấc tay khỏi chuột. Nút đó vẫn bấm bình thường khi bạn không kéo. Mặc định tắt vì nó chiếm một nút bạn có thể đang dùng cho việc khác."))
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(L10n.t("Nút cuộn"))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    // A Picker, not the old "Ghi nút" button. That button called
                    // `triggerRecording()`, and the engine only ever records the hold trigger
                    // (`GestureEngine` writes `configuration.trigger`); there is no path that
                    // sets `scrollButton`. The control did something other than what its label
                    // promised, so it is replaced by the control the label described.
                    Picker(selection: Binding(
                        get: { config.scrollButton },
                        set: { button in controller.update { $0.scrollButton = button } })) {
                        ForEach(scrollButtonChoices, id: \.self) { button in
                            Text(L10n.t(ButtonKey.index(button))).tag(button)
                        }
                    } label: {
                        Text(L10n.t("Nút cuộn"))
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 140)
                    Spacer(minLength: 0)
                }
            }
            .settingsRow()
        }
    }

    private var customBundleRow: some View {
        DisclosureGroup(isExpanded: $showAdvancedApps) {
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
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        } label: {
            Text(L10n.t("Nâng cao — ứng dụng khác")).font(XFinderTokens.Font.rowValue)
        }
        .padding(.horizontal, 20)
    }

    /// The small line at the bottom. The machine's symbolic-hotkey table moved out of the
    /// page body: it is a reference, not something to act on while configuring gestures, so
    /// it lives behind a link now.
    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(L10n.t("Mở Phím tắt")) { WindowManager.openKeyboardShortcutsPane() }
                .buttonStyle(.link).font(XFinderTokens.Font.caption)
            Text(L10n.t("Nếu không hoạt động: kiểm tra Trợ năng, bundle ID, phím tắt riêng của app và tắt mapping trùng trong phần mềm chuột khác. Tắt công tắc ở trên để ngừng xử lý cử chỉ."))
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Actions

    /// One entry point for both "record the hold button" and "record the scroll button",
    /// because they are the same interaction — press a button on the mouse — and the
    /// engine's recording mode already accepts either. The page distinguishes them only
    /// in what it *says*.
    ///
    /// `button` is the row the user clicked **Ghi** on, when they did (PATCH v10 R3). It
    /// changes nothing about what is stored — the number that arrives is always the
    /// measured one, and it is persisted the moment the engine reports it — it only marks
    /// the row so the user can see which control XFinder is waiting for.
    private func triggerRecording(button: Int? = nil) {
        recordingTrigger = true
        recordingButton = button
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

    // MARK: - Block 3's chip strip (T14b)

    /// The chips of block 3, in display order: Global pinned first (the anchor every app without
    /// a preset falls back to), then the built-in presets — `orderedProfiles` puts the installed
    /// ones first and the rest are drawn as dashed "ghost" chips — then any bundle the user typed
    /// in. The front app is deliberately given **no** chip of its own when it has no preset: its
    /// sub-line and "Xem" button carry that case (spec T14b step 2).
    private func appChips(installed: Set<String>) -> [MouseGestureAppChip] {
        // The dot's rule reads the RAW frontmost bundle: `frontmostBundle` substitutes Global for
        // "nothing in front", and dotting Global in that state would be a claim we cannot make.
        let front = controller.lastExternalBundle
        let presetIDs = orderedProfiles(installed: installed).map(\.id).filter { $0 != GestureProfiles.fallback }
        let ids = [GestureProfiles.fallback] + presetIDs + customProfiles
        // The chip whose mapping applies to the app in front — its own, or Global (GestureAppChooser, tested).
        let dotted = GestureAppChooser.dottedChip(front: front, chipIDs: ids, selected: profile,
                                                  fallback: GestureProfiles.fallback)
        let names = Dictionary(GestureProfiles.all.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return ids.map { id in
            MouseGestureAppChip(id: id,
                                title: id == GestureProfiles.fallback ? L10n.t("Mặc định toàn cục") : (names[id] ?? id),
                                isGhost: id != GestureProfiles.fallback && names[id] != nil && !installed.contains(id),
                                showsDot: dotted == id)
        }
    }

    /// Whether the app in front already has a clickable chip — the sub-line keeps F5's "Xem"
    /// button only when it does not (T14b step 2). Uses the actual chip list, not `orderedProfiles`
    /// alone, so a chip backed by a custom bundle id (not a built-in preset) also counts.
    private func frontHasChip(in chips: [MouseGestureAppChip]) -> Bool {
        let front = controller.lastExternalBundle
        return !front.isEmpty && chips.contains { $0.id == front }
    }
}
