import SwiftUI

/// A clickable mouse diagram: the whole point of the page, drawn instead of tabulated.
/// The user opens this page asking *"what happens if I do this?"* — a drawing answers
/// that in one look, where six text rows of
/// `⌃↑ / Giữ nút rồi kéo LÊN / Mặc định / Ghi phím / Đổi` do not.
///
/// Modelled on Mac Mouse Fix and MOS: the device is the navigation, and the arrow you
/// press is the gesture you perform.
///
/// The held button is printed **once**, as a badge on the mouse body. Printing it per
/// arm is the L1 bug: the number is identical for every direction (it is what you hold
/// to start *any* gesture), so four copies read as "all four buttons are Button 3".
///
/// Geometry is hand-placed rather than `GeometryReader`-derived so the layout stays
/// byte-identical at any pane width; only the canvas size is flexible.
struct MouseDiagramView: View {
    /// The direction currently selected, or nil when none is picked.
    @Binding var selection: GestureDirection?
    /// The resolved row per direction. One value carries the shortcut, the intent and
    /// the provenance, so the caption and the dispatched action cannot disagree.
    let row: (GestureDirection) -> ResolvedGestureRow
    /// What to call the action in the app on screen, or nil when the shortcut is not
    /// that app's own binding for the intent.
    let actionName: (GestureDirection) -> String?
    /// Badge colour per direction: preset / user override / unassigned.
    let tint: (GestureDirection) -> Color
    /// Directions that can be shown at all. Tilt arms are hidden when the user's
    /// hardware has no tilt, rather than drawn as a control that does nothing.
    let showsTilt: Bool
    /// The configured trigger. Its number is printed once on the mouse body.
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

    private let bodyWidth: CGFloat = 84
    private let bodyHeight: CGFloat = 132
    private let armLength: CGFloat = 46

    var body: some View {
        ZStack {
            mouseBody
            arm(.up,    x: 0,                                    y: -(bodyHeight / 2 + armLength * 0.62))
            arm(.down,  x: 0,                                    y:  (bodyHeight / 2 + armLength * 0.62))
            arm(.left,  x: -(bodyWidth / 2 + armLength * 0.72),   y: -6)
            arm(.right, x:  (bodyWidth / 2 + armLength * 0.72),   y: -6)
            if showsTilt {
                tiltArm(.tiltLeft,  x: -34)
                tiltArm(.tiltRight, x:  34)
            }
        }
        .frame(width: bodyWidth + armLength * 3.6, height: bodyHeight + armLength * 2.6)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selection)
    }

    // MARK: - Device

    private var mouseBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: bodyWidth * 0.46, style: .continuous)
                .fill(LinearGradient(colors: [Color(nsColor: .controlBackgroundColor),
                                              Color(nsColor: .windowBackgroundColor)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: bodyWidth * 0.46, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                )
                .frame(width: bodyWidth, height: bodyHeight)
                .shadow(color: .black.opacity(0.10), radius: 5, y: 1.5)

            // The scroll wheel, drawn where it actually is: it is also where the middle
            // button lives, which is why the label for button 2 says so.
            Capsule()
                .fill(Color.secondary.opacity(0.22))
                .frame(width: 9, height: 22)
                .offset(y: -bodyHeight / 2 + 22)

            holdBadge
        }
    }

    /// The held button, stated **once** on the device. Clicking it records a new one —
    /// the interaction Mac Mouse Fix trains users on, and the shortest path from
    /// "which button am I supposed to hold?" to having picked their own.
    private var holdBadge: some View {
        Button {
            onRecordTrigger?()
        } label: {
            VStack(spacing: 1) {
                Text(L10n.t("Giữ"))
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                Text(L10n.t(trigger.key))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.accentColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .fixedSize(horizontal: false, vertical: true)
                if onRecordTrigger != nil {
                    Text(isRecordingTrigger ? L10n.t("đang ghi…") : L10n.t("bấm để đổi"))
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: bodyWidth - 16)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isRecordingTrigger ? Color.orange.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onRecordTrigger == nil)
        .offset(y: 26)
        .help(L10n.t("Nút bạn giữ để bắt đầu mọi cử chỉ. Bấm để ghi nút khác."))
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

    /// Tilt is shown as a small rotation hint beside the wheel, not as a fifth arm: it
    /// is a different physical motion, and drawing it as another arrow would teach the
    /// wrong gesture.
    private func tiltArm(_ direction: GestureDirection, x: CGFloat) -> some View {
        let support = unsupported(direction)
        return Button {
            selection = MouseDiagramSelection.afterClick(current: selection, clicked: direction)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: direction == .tiltLeft ? "arrow.uturn.left" : "arrow.uturn.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(armColor(direction, support: support))
                Text(row(direction).caption.map { L10n.t($0) } ?? L10n.t("Chưa gán"))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 5).padding(.vertical, 3)
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
        .offset(x: x, y: bodyHeight / 2 - 14)
        .help(L10n.t(direction.motionKey))
        .accessibilityLabel(L10n.t(direction.motionKey))
    }

    private func armColor(_ direction: GestureDirection, support: ArmSupport) -> Color {
        guard support.isSupported else { return Color.secondary.opacity(0.5) }
        return row(direction).entry.isUnassigned ? Color.secondary.opacity(0.45) : tint(direction)
    }
}

/// `ArmSupport` is declared in `DeviceCapabilityModel.swift`, not here.
///
/// It reads like view code but it is domain logic — "can this mouse perform this
/// direction?" — and keeping it in a SwiftUI file would put it out of reach of the
/// test package, which is where the D2/D3 contract is pinned.
