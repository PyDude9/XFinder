import SwiftUI

/// The list of mouse controls XFinder can actually see, with what each one is doing.
///
/// ── Why a list when there is already a drawing (PATCH v9.1 R3) ─────────────────────────
/// The drawing answers *"where is this control on my mouse?"*. This answers *"which
/// controls does XFinder know about, and what is each one set to?"* — and it is the only
/// surface that can name a control the archetype drawing has no position for.
///
/// It is also where a role is changed. Deliberately one place, not a popup on every chip:
/// a menu on each of six chips is six chances to mis-click a picture, and the drawing's job
/// is to be read, not to be a control panel.
///
/// ── What this list will NOT do ─────────────────────────────────────────────────────────
/// It does not offer to rebind a **single click** on a control, because the engine has no
/// path for one: a click on button 3/4/5 is currently forwarded to the application, where
/// most apps already read 3 and 4 as back and forward. Offering a row that claimed to
/// rebind it would be a control that cannot do what its label says (AGENTS.md Part 0 §6).
/// Instead each row **states what the click does today** via
/// `DeviceCapabilityModel.passthroughNoteKey`, so the user learns the real behaviour
/// instead of an empty cell — and the role vocabulary here is exactly the set of
/// behaviours that exist.
struct GestureButtonList: View {
    /// Every control to list, ascending: the archetype slots plus anything the mouse
    /// declares beyond them.
    let buttons: [Int]
    /// The single role function the drawing also reads, so the two cannot disagree.
    let role: (Int) -> MouseButtonRole
    /// The control the drawing has highlighted, if any.
    @Binding var selected: Int?
    /// Which controls the descriptor declared. `nil` = nothing was read, which the header
    /// reports as "not read" rather than as an empty mouse.
    let declaredEventButtons: [Int]?
    /// How many button-typed elements the descriptor declares on a **vendor** page.
    /// Evidence that the standard button page is not the whole story — never added to the
    /// declared count, because a vendor usage has no `CGEvent` number.
    var vendorControlCount: Int = 0
    /// How many usages the descriptor declares on the **Consumer** page (`0x0C`). Same
    /// rule as `vendorControlCount`: evidence, never a button, never numbered. Its own
    /// count so the two facts cannot be added together on screen either.
    var consumerUsageCount: Int = 0
    /// A press the engine saw that the descriptor does not declare, or `nil`.
    let undeclaredPress: Int?
    /// Whether the descriptor under-reports this mouse, on evidence. Separate from
    /// `undeclaredPress` because a vendor-page declaration is also evidence.
    var underReported: Bool = false
    let onSetTrigger: (Int) -> Void
    /// Press-a-button recording, for a control the descriptor under-reports.
    ///
    /// The control the record was armed **for**, or `nil` when it was armed from the
    /// header rather than a row (PATCH v11). The row passes its own button so the page can
    /// mark *which* control XFinder is waiting for; the header passes `nil` because it
    /// deliberately targets no single row. The number that is stored is still whatever the
    /// engine measures — this only carries intent for the highlight, never a fabricated
    /// button.
    let onRecordTrigger: (Int?) -> Void
    /// The row whose Record button is armed, so the row itself shows it is listening.
    var recordingButton: Int?
    var holdButtonSingleClickEnabled: Binding<Bool>? = nil
    var onSetAction: ((Int, ButtonAction) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let undeclared = undeclaredPress { undeclaredWarning(undeclared) }
            else if underReported { underReportedWarning }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(buttons.enumerated()), id: \.element) { index, button in
                    if index > 0 { Divider() }
                    row(button)
                }
            }
            hardwareExclusionNote
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 12)).foregroundColor(.secondary).frame(width: 16)
                Text(L10n.t("Nút chuột XFinder thấy"))
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                // The header arms the same recording as every row, but targets no single
                // row — it passes `nil`, so no row is marked and the next real press is
                // measured. The row buttons below pass their own number instead.
                Button(recordingButton != nil ? L10n.t("Đang ghi…") : L10n.t("Ghi nút thật"))
                { onRecordTrigger(nil) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(recordingButton != nil)
            }
            Text(declarationSummary)
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if vendorControlCount > 0 {
                Text(L10n.t("Ngoài ra mô tả HID còn khai báo các phần tử nút trên trang riêng của hãng: ")
                     + "\(vendorControlCount)."
                     + L10n.t(" Số đó không phải số nút và XFinder không đánh số được chúng — chỉ bấm nút thật mới biết số."))
                    .font(.system(size: 11)).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The Consumer page is a second kind of evidence, reported separately so a
            // reader cannot add it to the vendor count. A Consumer usage has no `CGEvent`
            // number, so it is stated as a fact and never numbered.
            if consumerUsageCount > 0 {
                Text(L10n.t("Ngoài ra mô tả HID còn khai báo các mã điều khiển trên trang Consumer: ")
                     + "\(consumerUsageCount)."
                     + L10n.t(" Số đó không phải số nút và XFinder không đánh số được chúng."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What the descriptor declared, in numbers — the measured half of the section.
    ///
    /// Three states, and the middle one is why this is a computed string rather than a
    /// count: "we read the mouse and it declares these five" and "we could not read it"
    /// describe the same empty answer with different meanings, and only one of them says
    /// anything about the hardware.
    private var declarationSummary: String {
        guard let declared = declaredEventButtons else {
            return L10n.t("Chưa đọc được mô tả HID của chuột, nên danh sách dưới chỉ là các nút thường gặp. “Ghi nút thật” luôn dùng được.")
        }
        if declared.isEmpty {
            return L10n.t("Mô tả HID của chuột không khai báo nút nào.")
        }
        let names = declared.map { L10n.t(compactButton: ButtonKey.index($0)) }.joined(separator: ", ")
        return L10n.t("Mô tả HID của chuột khai báo: ") + names
    }

    /// The one prompt that is caused by evidence rather than shown to everybody.
    ///
    /// A descriptor that under-reports is a real limitation of HID on this hardware, and the
    /// honest reply is not to widen the filter until a number appears (that is how an
    /// invented sixth button was shipped once already). It is to notice that the engine
    /// **saw a press the descriptor did not mention** and offer the record path, which
    /// measures the number instead of guessing it.
    private func undeclaredWarning(_ button: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12)).foregroundColor(.orange).frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("XFinder nhận được ") + L10n.t(ButtonKey.index(button))
                     + L10n.t(" khi bạn bấm, nhưng mô tả HID của chuột không khai báo nút đó."))
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.t("Đây là số đo thật từ chuột bạn, không phải phỏng đoán. Bấm “Đặt làm nút giữ” ở dòng tương ứng bên dưới để dùng nó."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// The same prompt, raised by the other piece of evidence (PATCH v10 R1).
    ///
    /// A descriptor that declares fewer controls than the figure has positions **and** also
    /// declares extra vendor-page controls is under-reporting: the standard button page
    /// demonstrably does not describe everything on this mouse. That is a measurement, not a
    /// guess about the hardware, and it is the case the brief asks the page to name — "if it
    /// is still five, say so" — instead of widening the filter until a sixth number appears,
    /// which is how an invented button shipped once already.
    private var underReportedWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12)).foregroundColor(.orange).frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("Mô tả HID khai báo ít nút hơn số vị trí trên hình, nhưng lại có thêm nút trên trang riêng của hãng — nghĩa là mô tả này chưa kể hết chuột của bạn."))
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.t("XFinder không tự đoán số cho những nút đó. Bấm “Ghi” ở dòng bạn muốn rồi bấm nút thật trên chuột — số nhận được là số đo thật, và nó được lưu ngay."))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// The controls on the mouse that never reach macOS (PATCH v10 R2).
    ///
    /// Stated for one reason: the user counted six controls on their mouse and the
    /// descriptor declares five, so the page must explain the difference rather than leave
    /// them to conclude that XFinder is broken. What is claimed here is only the
    /// observation — those controls are not in the descriptor — plus the plausible reason,
    /// worded as the usual explanation rather than as a measured fact.
    private var hardwareExclusionNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("Nút do chuột tự xử lý"))
                .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
            ForEach(MouseHardwareExclusion.all, id: \.titleKey) { exclusion in
                HStack(alignment: .top, spacing: 6) {
                    Text(L10n.t(exclusion.titleKey))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .frame(width: 130, alignment: .leading)
                        .lineLimit(1)
                    Text(L10n.t(exclusion.explanationKey))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - One control

    private func row(_ button: Int) -> some View {
        let role = role(button)
        let isSelected = selected == button
        let isRecording = recordingButton == button
        return HStack(alignment: .top, spacing: 8) {
            Button {
                selected = MouseDiagramSelection.afterButtonClick(current: selected, clicked: button)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(L10n.t(ButtonKey.index(button)))
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let position = MouseControlSlot.slot(forEventButton: button)?.positionKey {
                            Text(L10n.t(position))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .fixedSize()
                        }
                    }
                    // What a single click does today, for the controls where that is a
                    // fact worth stating. `nil` for the rest — an empty line is better
                    // than a sentence invented to fill it.
                    if let note = DeviceCapabilityModel.passthroughNoteKey(forEventButton: button) {
                        Text(L10n.t(note))
                            .font(.system(size: 10)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            roleChip(role)
            Spacer(minLength: 0)
            action(button, role: role, isRecording: isRecording)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(minWidth: 0, maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected || isRecording ? Color.accentColor.opacity(0.08) : Color.clear)
        )
    }

    private func roleChip(_ role: MouseButtonRole) -> some View {
        Text(L10n.t(role.labelKey))
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(roleColor(role))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(roleColor(role).opacity(0.14)))
            .fixedSize()
            .help(L10n.t(role.explanationKey))
    }

    @ViewBuilder
    private func action(_ button: Int, role: MouseButtonRole, isRecording: Bool) -> some View {
        switch role {
        case .holdTrigger, .holdTriggerWithAction:
            VStack(alignment: .trailing, spacing: 4) {
                Label(L10n.t("Đang là nút giữ"), systemImage: "checkmark")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                    .fixedSize()
                if case .holdTriggerWithAction = role, let binding = holdButtonSingleClickEnabled {
                    Toggle(L10n.t("Bấm nhanh = Tiến"), isOn: binding)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10))
                        .help(L10n.t("Bấm nhanh dưới 200ms là Tiến, giữ và kéo là cử chỉ"))
                }
            }
        default:
            if role.isAssignable {
                HStack(spacing: 6) {
                    // Per-row recording (PATCH v10 R3). It arms the same recording the header
                    // button does — the engine can only listen for "the next press" — but the
                    // row makes the intent explicit: press *this* control, and whatever number
                    // arrives is what gets stored. That is the only path that works for a
                    // control the descriptor never declared, and it costs the user one click
                    // on the row they are looking at instead of a trip to a header button.
                    // The row passes **its own** button (PATCH v11) so the page knows which
                    // control is being recorded; the engine still stores whatever it measures.
                    Button(isRecording ? L10n.t("Đang ghi…") : L10n.t("Ghi")) { onRecordTrigger(button) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(recordingButton != nil)
                        .help(L10n.t("Bấm “Ghi” rồi bấm nút này trên chuột — số XFinder nhận được sẽ được lưu ngay."))
                    Button(L10n.t("Đặt làm nút giữ")) { onSetTrigger(button) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(recordingButton != nil || !role.isDeclared)
                        .help(role.isDeclared
                              ? L10n.t("Đặt nút này làm nút giữ")
                              : L10n.t("Bấm “Ghi” rồi bấm nút thật trước khi đặt làm nút giữ."))
                    if let onSetAction = onSetAction {
                        Menu {
                            Button(L10n.t("Lùi (Cmd+[)")) { onSetAction(button, .instant(.back)) }
                            Button(L10n.t("Tiến (Cmd+])")) { onSetAction(button, .instant(.forward)) }
                            Button(L10n.t("Chưa gán")) { onSetAction(button, .unassigned) }
                        } label: {
                            Text(L10n.t("Gán hành động"))
                        }
                        .menuStyle(.borderedButton)
                        .controlSize(.small)
                        .disabled(recordingButton != nil)
                    }
                }
            } else {
                Text(L10n.t("Không đổi được"))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize()
            }
        }
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
}
