import SwiftUI

/// The mouse itself, drawn: which controls it has, what each one does, and what the
/// four hold-and-drag directions send.
///
/// ── Why it is drawn from the device, not from a fixed picture (PATCH v9.1 R2) ──────────
/// The previous version was a **Magic-Mouse-shaped** figure: a body and four arrows, with
/// the held button printed as a single badge. On the Razer Basilisk this feature was built
/// for, that figure showed *one* control and no hint that five others exist — so the user's
/// report was exact: *"tất cả các nút là Button 3"* and *"tôi không hiểu dùng nút nào của
/// chuột với mũi tên"*. A diagram that cannot show the Sniper button cannot explain a
/// gesture bound to it.
///
/// So the controls come from `CapabilityDescriptor.physical.buttons`, via
/// `DeviceCapabilityModel`. Three rules follow from that and are not stylistic:
///
///   * a control the mouse **declares** is drawn labelled, at the position that control
///     occupies on the archetype mouse;
///   * a control it does **not** declare is still drawn, disabled and dashed, with a
///     tooltip. Omitting it would make the drawing silently wrong about the hardware;
///   * `nil` (nothing was read) is **not** the same as "not declared" — the chips say
///     "not read yet" instead, because a failed probe is not a measured absence.
///
/// The held button appears **once**, as a badge on the body, and it prints the **user-facing
/// number** (`Nút 3` / `Button 3`) — the same vocabulary the chips use (PATCH v10.1 R2).
/// Printing it on every arm is the L1 bug: the number is identical for every direction (it
/// is what you hold to start *any* gesture), so four copies read as "all four buttons are
/// Button 3".
///
/// ── Why the body is not a pill any more ──────────────────────────────────────────────
/// It was a `RoundedRectangle` with a corner radius of nearly half its width, i.e. a pill —
/// the Magic Mouse silhouette. The user's report was that the page therefore described the
/// wrong mouse: *"mặc định giao diện này là Magic Mouse nên chỉ có 4 nút 4 hướng, chứ ko
/// phải smart mouse có nhiều button"*. The body is now `MouseSilhouette`, built from
/// `MouseFigureOutline`, and the figure carries the three things a pill cannot: a **seam**
/// between the two main buttons, a **wheel** in that seam, and a **thumb rest** in the
/// lower-left with the side buttons and the Sniper on it.
///
/// Geometry is hand-placed rather than `GeometryReader`-derived so the layout stays
/// byte-identical at any pane width; only the canvas size is flexible.
struct MouseDiagramView: View {
    /// The direction currently selected, or nil when none is picked.
    @Binding var selection: GestureDirection?
    /// The control currently selected, or nil. Selecting a chip highlights its row in the
    /// Assigned-buttons list, which is where the role can be changed — one place where a
    /// click means "change this", instead of a menu on every chip.
    @Binding var selectedButton: Int?
    /// The resolved row per direction. One value carries the shortcut, the intent and
    /// the provenance, so the caption and the dispatched action cannot disagree.
    let row: (GestureDirection) -> ResolvedGestureRow
    /// What to call the action in the app on screen, or nil when the shortcut is not
    /// that app's own binding for the intent.
    let actionName: (GestureDirection) -> String?
    /// Badge colour per direction: preset / user override / unassigned.
    let tint: (GestureDirection) -> Color
    /// What each control is doing right now, from the one role function the list and the
    /// drawing share — so clicking a chip and reading its row cannot disagree.
    let buttonRole: (Int) -> MouseButtonRole
    /// Which controls the drawing has a place for. Ordered ascending.
    let buttons: [Int]
    /// Which figure to draw for the device in force (PATCH v10 R2). The default keeps the
    /// archetype, which is what every earlier call site and the preview harness expect.
    var style: MouseDiagramStyle = .archetype
    /// What the descriptor declared, used by the `.generic` figure so it draws **only**
    /// what was measured. `nil` means nothing was read — the generic figure then has no
    /// chips, which is the truthful drawing of "no readable buttons".
    var declaredEventButtons: [Int]?
    /// The configured trigger. Its label is printed once on the mouse body.
    let trigger: TriggerSource
    /// Arms the current device cannot perform, disabled with a tooltip saying so.
    var unsupported: (GestureDirection) -> ArmSupport = { _ in .supported }
    /// Which arm is waiting for the user to press a key, so the diagram can show it.
    var recordingDirection: GestureDirection?
    /// Clicking the badge re-records the hold button — Mac Mouse Fix's core gesture of
    /// "click the thing you want to change".
    var onRecordTrigger: (() -> Void)?
    /// Whether the page is currently recording the *trigger*.
    var isRecordingTrigger: Bool = false

    private let bodyWidth: CGFloat = 116
    private let bodyHeight: CGFloat = 190
    private let armLength: CGFloat = 46
    /// Where the four arms sit. Named so the frame and the offsets cannot drift apart.
    private var armY: CGFloat { bodyHeight / 2 + armLength * 0.74 }
    private var armX: CGFloat { bodyWidth / 2 + armLength * 0.87 }

    var body: some View {
        ZStack {
            mouseBody
            ForEach(drawnControls, id: \.self) { button in
                if let slot = MouseControlSlot.slot(forEventButton: button) {
                    controlChip(button, slot: slot)
                        .offset(x: chipOffset(slot).x, y: chipOffset(slot).y)
                }
            }
            arm(.up,    x: 0,    y: -armY)
            arm(.down,  x: 0,    y:  armY)
            arm(.left,  x: -armX, y: -6)
            arm(.right, x:  armX, y: -6)
        }
        .frame(width: armX * 2 + 96, height: armY * 2 + 76)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selection)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selectedButton)
    }

    /// The controls this figure draws (R2).
    ///
    /// `.archetype` and `.unknown` keep the full slot list the page passes in, so the
    /// picture does not change shape when the mouse is unplugged — slots go dashed and
    /// say "not read yet" instead of vanishing. `.generic` draws **only** what the
    /// descriptor declared, which is the whole point of the fallback: a device that is not
    /// a multi-button mouse must not be pictured with six chips.
    private var drawnControls: [Int] {
        switch style {
        case .generic: return DeviceCapabilityModel.genericButtons(declaredEventButtons: declaredEventButtons)
        case .archetype, .unknown: return buttons
        }
    }

    // MARK: - Device

    private var mouseBody: some View {
        ZStack {
            MouseSilhouette()
                .fill(LinearGradient(colors: [Color(nsColor: .controlBackgroundColor),
                                              Color(nsColor: .windowBackgroundColor)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(MouseSilhouette()
                    .stroke(Color.secondary.opacity(0.38), lineWidth: 1))
                .frame(width: bodyWidth, height: bodyHeight)
                .shadow(color: .black.opacity(0.10), radius: 5, y: 1.5)

            // Drawn before the chips so the three thumb controls sit *on* it: the region is
            // what says "this mouse has a thumb rest", and the chips are what say which
            // controls are on it.
            thumbRestPanel

            // The seam between the two main buttons, and the wheel that sits in it. Both are
            // drawing only — but they are the two lines that make the figure read as a mouse
            // with two buttons rather than as a shell.
            buttonSeam

            // The wheel, drawn where it actually is: it is also where the middle button
            // lives, which is why button 2's chip sits on it. Hidden for a generic device
            // that declares no middle button — drawing a wheel it does not have would be
            // the same class of claim as drawing chips it does not have.
            if drawnControls.contains(2) {
                Capsule()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: 11, height: 30)
                    .offset(y: -bodyHeight / 2 + 30)
            }

            holdBadge
        }
    }

    /// The thumb rest, in the lower-left, behind the three side controls.
    private var thumbRestPanel: some View {
        let region = MouseFigureOutline.thumbRest
        let centre = region.centre
        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.secondary.opacity(0.09))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.20), lineWidth: 1))
            .frame(width: CGFloat(region.width) * bodyWidth,
                   height: CGFloat(region.height) * bodyHeight)
            .offset(x: (CGFloat(centre.x) - 0.5) * bodyWidth,
                    y: (CGFloat(centre.y) - 0.5) * bodyHeight)
    }

    /// The line that separates the two main buttons, running from the front of the body down
    /// to the base of the wheel.
    private var buttonSeam: some View {
        let top = CGFloat(MouseFigureOutline.seamTopY)
        let bottom = CGFloat(MouseFigureOutline.seamBottomY)
        return Rectangle()
            .fill(Color.secondary.opacity(0.28))
            .frame(width: 1, height: (bottom - top) * bodyHeight)
            .offset(y: ((top + bottom) / 2 - 0.5) * bodyHeight)
    }

    /// The held button, stated **once** on the device. Clicking it records a new one —
    /// the interaction Mac Mouse Fix trains users on, and the shortest path from
    /// "which button am I supposed to hold?" to having picked their own.
    ///
    /// It prints the **user-facing number** (`Nút 3` / `Button 3`), not the descriptive name
    /// (PATCH v10.1 R2). It used to print the name, on the reasoning that this badge is wide
    /// enough for it; what that missed is that the chips right next to it print numbers, so
    /// the two vocabularies disagreed on one screen and the badge read as a *different*
    /// control from the chip for the same button. The name is not lost — it is in this
    /// badge's tooltip, in the chip tooltips, and in the full-width row of the list below,
    /// all three read from the same table.
    private var holdBadge: some View {
        Button {
            onRecordTrigger?()
        } label: {
            VStack(spacing: 1) {
                Text(L10n.t("Giữ"))
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Text(L10n.t(compactButton: trigger.key))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.accentColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if onRecordTrigger != nil {
                    Text(isRecordingTrigger ? L10n.t("đang ghi…") : L10n.t("bấm để đổi"))
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: bodyWidth - 34)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isRecordingTrigger ? Color.orange.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onRecordTrigger == nil)
        .offset(y: 70)
        .help(L10n.t("Nút bạn giữ để bắt đầu mọi cử chỉ. Bấm để ghi nút khác."))
    }

    // MARK: - Controls

    /// Where each control sits on the archetype mouse (PATCH v10 R2).
    ///
    /// Laid out after the reference mouse's own diagram, because that is the mouse this
    /// feature exists for and the user asked twice which physical button each chip means:
    ///
    ///   * the **top row** is left — wheel — right, in that order, left and right flanking
    ///     the wheel exactly as they do on the hardware;
    ///   * the **left flank** carries the three thumb controls top to bottom, with the
    ///     Sniper button last, because it sits lowest under the thumb.
    ///
    /// These numbers describe *this picture* and nothing else. No macOS API reports where a
    /// physical button sits, so the caption under each chip names the drawing's position,
    /// while the list below reports what the descriptor actually declared. A small drawing,
    /// a fixed layout, and no claim that the two are the same fact.
    private func chipOffset(_ slot: MouseControlSlot) -> CGPoint {
        switch slot {
        case .left:      return CGPoint(x: -30, y: -72)
        case .right:     return CGPoint(x:  30, y: -72)
        case .middle:    return CGPoint(x:   0, y: -42)
        case .sideUpper: return CGPoint(x: -22, y:  -6)
        case .sideLower: return CGPoint(x: -22, y:  20)
        case .sniper:    return CGPoint(x: -22, y:  46)
        }
    }

    /// One control. The label is the **bare number** (`Nút 4`), because a chip is 46 pt wide
    /// and the descriptive Vietnamese name for the wheel is 17 characters — see
    /// `ButtonLabelStructure.compactLabel`. Under it sits the drawing's short position name,
    /// which is what answers "which physical button is this chip?" without making the chip
    /// any wider. The full name with its positional hint is in the tooltip here and in the
    /// full-width row of the Detected-buttons list below.
    private func controlChip(_ button: Int, slot: MouseControlSlot) -> some View {
        let role = buttonRole(button)
        let isSelected = selectedButton == button
        return Button {
            selectedButton = MouseDiagramSelection.afterButtonClick(current: selectedButton,
                                                                    clicked: button)
        } label: {
            VStack(spacing: 1) {
                Text(L10n.t(compactButton: ButtonKey.index(button)))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(chipTextColor(role))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .frame(width: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(chipFill(role, isSelected: isSelected))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(chipStroke(role, isSelected: isSelected),
                                          style: StrokeStyle(lineWidth: isSelected ? 1.5 : 1,
                                                             dash: chipIsDashed(role) ? [2.5, 2.5] : []))
                    )
                Text(L10n.t(slot.positionKey))
                    .font(.system(size: 7, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 46)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A control the read did not put on the mouse is **not** clickable (PATCH v10.1 R2).
        // The chip is still drawn, because omitting it would make the figure silently wrong
        // about the hardware — but a live chip claims XFinder can see that button, and on an
        // undeclared control that is the exact claim the press-to-record path exists to
        // disprove. The row below keeps its Record button, so the control is still reachable
        // where the measurement happens.
        .disabled(!role.isDeclared)
        .help(chipTooltip(button, role: role))
        .accessibilityLabel(chipTooltip(button, role: role))
    }

    private func chipIsDashed(_ role: MouseButtonRole) -> Bool {
        role == .notDeclared || role == .unknown
    }

    private func chipFill(_ role: MouseButtonRole, isSelected: Bool) -> Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        switch role {
        case .holdTrigger, .holdTriggerWithAction:  return Color.accentColor.opacity(0.14)
        case .assigned:     return Color.accentColor.opacity(0.09)
        case .scrollButton: return Color.secondary.opacity(0.14)
        default:            return Color.secondary.opacity(0.06)
        }
    }

    private func chipStroke(_ role: MouseButtonRole, isSelected: Bool) -> Color {
        if isSelected { return .accentColor }
        switch role {
        case .holdTrigger, .holdTriggerWithAction:  return .accentColor
        case .assigned:     return .accentColor.opacity(0.7)
        case .scrollButton: return Color.secondary.opacity(0.75)
        case .reserved:     return Color.secondary.opacity(0.5)
        case .notDeclared, .unknown: return Color.secondary.opacity(0.45)
        case .unassigned:   return Color.secondary.opacity(0.35)
        }
    }

    private func chipTextColor(_ role: MouseButtonRole) -> Color {
        switch role {
        case .notDeclared, .unknown: return Color.secondary.opacity(0.75)
        default: return .primary
        }
    }

    /// The chip's tooltip carries the three things the drawing cannot: the full label
    /// (including the positional hint the chip drops), what the control is doing, and — for
    /// a control the read did not put on the mouse — why the chip is not clickable and what
    /// to do about it. All three are existing store keys; nothing new is invented here.
    private func chipTooltip(_ button: Int, role: MouseButtonRole) -> String {
        let head = L10n.t(ButtonKey.index(button)) + " — " + L10n.t(role.labelKey)
        guard !role.isDeclared else { return head }
        if button == 5, let note = DeviceCapabilityModel.passthroughNoteKey(forEventButton: 5) {
            return head + ". " + L10n.t(note)
        }
        return head + ". " + L10n.t(role.explanationKey)
    }

    // MARK: - Arms

    private func arm(_ direction: GestureDirection, x: CGFloat, y: CGFloat) -> some View {
        GestureArmView(direction: direction,
                       row: row(direction),
                       actionName: actionName(direction),
                       isSelected: selection == direction,
                       support: unsupported(direction),
                       tint: tint(direction),
                       isRecording: recordingDirection == direction,
                       onTap: {
                           selection = MouseDiagramSelection.afterClick(current: selection,
                                                                        clicked: direction)
                       })
        .offset(x: x, y: y)
    }
}

/// The two tilt arms, in their own row under the drawing.
///
/// They used to be drawn beside the wheel inside `MouseDiagramView`. Once the drawing began
/// showing the mouse's real controls there was no room left for them near the wheel, and
/// moving them anywhere inside the figure collided with a control chip. Pulling them out is
/// also **more honest**: tilting the wheel is a different physical motion on a different
/// axis, and it is the one direction that needs no hold — which a row of its own can say and
/// a fifth arrow beside the wheel cannot.
struct TiltArmsRow: View {
    @Binding var selection: GestureDirection?
    let row: (GestureDirection) -> ResolvedGestureRow
    let actionName: (GestureDirection) -> String?
    let tint: (GestureDirection) -> Color
    let unsupported: (GestureDirection) -> ArmSupport
    var recordingDirection: GestureDirection?

    var body: some View {
        HStack(spacing: 10) {
            ForEach([GestureDirection.tiltLeft, .tiltRight], id: \.self) { direction in
                tiltChip(direction)
            }
            Spacer(minLength: 0)
        }
    }

    private func tiltChip(_ direction: GestureDirection) -> some View {
        let support = unsupported(direction)
        let resolved = row(direction)
        return Button {
            selection = MouseDiagramSelection.afterClick(current: selection, clicked: direction)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: direction == .tiltLeft ? "arrow.uturn.left" : "arrow.uturn.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(arrowColor(resolved, support: support, direction: direction))
                Text(resolved.caption.map { L10n.t($0) } ?? L10n.t("Chưa gán"))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(resolved.isUnboundSystemAction ? .orange : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(selection == direction ? tint(direction).opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(recordingDirection == direction ? Color.orange
                                                                  : Color.secondary.opacity(0.25),
                                  lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!support.isSupported)
        .opacity(support.isSupported ? 1 : 0.45)
        .help(tooltip(direction, resolved: resolved, support: support))
        .accessibilityLabel(tooltip(direction, resolved: resolved, support: support))
    }

    private func arrowColor(_ resolved: ResolvedGestureRow,
                            support: ArmSupport,
                            direction: GestureDirection) -> Color {
        guard support.isSupported else { return Color.secondary.opacity(0.5) }
        if resolved.isUnboundSystemAction { return .orange }
        return resolved.entry.isUnassigned ? Color.secondary.opacity(0.45) : tint(direction)
    }

    private func tooltip(_ direction: GestureDirection,
                         resolved: ResolvedGestureRow,
                         support: ArmSupport) -> String {
        let motion = L10n.t(direction.motionKey)
        switch support {
        case .unsupportedByMouse:
            return motion + " — " + L10n.t("Chuột này không có phần cứng cho hướng đó")
        case .unknownUntilDetected:
            return motion + " — " + L10n.t("Chưa đọc được mô tả chuột, nên chưa rõ hướng này có chạy được không")
        case .supported:
            break
        }
        if resolved.isUnboundSystemAction {
            return motion + " — " + L10n.t("macOS chưa gán phím tắt cho hành động này, nên hướng này chưa gửi được gì")
        }
        guard let caption = resolved.caption else {
            return motion + " — " + L10n.t("chưa gán phím nào")
        }
        let name = actionName(direction).map { $0 + " " } ?? ""
        return motion + " — " + L10n.t("gửi ") + name + L10n.t(caption)
    }
}

/// `ArmSupport` is declared in `DeviceCapabilityModel.swift`, not here.
///
/// It reads like view code but it is domain logic — "can this mouse perform this
/// direction?" — and keeping it in a SwiftUI file would put it out of reach of the
/// test package, which is where the D2/D3 contract is pinned. `MouseButtonRole` and
/// `MouseControlSlot` live there for exactly the same reason.

/// The mouse's silhouette: `MouseFigureOutline.points`, drawn as a **closed Catmull-Rom
/// curve** so the corners stay round while the shape keeps the thumb rest that separates it
/// from a pill.
///
/// Why Catmull-Rom rather than hand-written Béziers: the outline is data in
/// `GestureUIDisplay.swift` (Foundation-only, symlinked into the test package), so its two
/// load-bearing properties — not a circle, thumb rest lower-left — are asserted by a test.
/// Hand-written control points would put the geometry back in this file, where no test can
/// reach it, and the last three mutations that stayed green all lived in exactly that gap.
struct MouseSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let pts = MouseFigureOutline.points.map {
            CGPoint(x: rect.minX + CGFloat($0.x) * rect.width,
                    y: rect.minY + CGFloat($0.y) * rect.height)
        }
        var path = Path()
        guard pts.count >= 3 else { return path }
        let n = pts.count
        path.move(to: pts[0])
        for i in 0..<n {
            let previous = pts[(i - 1 + n) % n]
            let start = pts[i]
            let end = pts[(i + 1) % n]
            let after = pts[(i + 2) % n]
            // Standard Catmull-Rom → Bézier conversion: each control point is offset along
            // the neighbouring chord by a sixth, which is what makes the curve pass through
            // every vertex smoothly instead of cutting the corners off.
            let control1 = CGPoint(x: start.x + (end.x - previous.x) / 6,
                                   y: start.y + (end.y - previous.y) / 6)
            let control2 = CGPoint(x: end.x - (after.x - start.x) / 6,
                                   y: end.y - (after.y - start.y) / 6)
            path.addCurve(to: end, control1: control1, control2: control2)
        }
        path.closeSubpath()
        return path
    }
}
