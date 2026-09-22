import SwiftUI

/// A clickable mouse diagram: the whole point of the page, drawn instead of
/// tabulated. The user opens "Chuột & cử chỉ" asking *"what happens if I do
/// this?"* — a diagram answers that in one look, where six text rows of
/// `⌃↑ / Giữ nút rồi kéo LÊN / Mặc định / Ghi phím / Đổi` do not.
///
/// Modelled on Mac Mouse Fix and MOS: the device is the navigation, and the
/// arrow you press is the gesture you perform. Each arm is a real `Button`, so
/// the diagram is also the selector — there is no separate list to correlate.
///
/// Geometry is hand-placed rather than `GeometryReader`-derived so the layout
/// stays byte-identical at any pane width; only the canvas size is flexible.
struct MouseDiagramView: View {
    /// The direction currently selected by the user, or nil when none is picked.
    @Binding var selection: GestureDirection?
    /// Resolved action per direction — the caller owns resolution so the diagram
    /// can never disagree with the runtime engine.
    let action: (GestureDirection) -> GestureAction
    /// Badge colour per direction: preset / user override / unassigned.
    let tint: (GestureDirection) -> Color
    /// Directions that can be shown at all. Tilt arms are hidden when the user's
    /// hardware has no tilt, rather than drawn as a control that does nothing.
    let showsTilt: Bool

    private let bodyWidth: CGFloat = 84
    private let bodyHeight: CGFloat = 132
    private let armLength: CGFloat = 46

    var body: some View {
        ZStack {
            mouseBody
            arrow(.up,    x: 0,                  y: -(bodyHeight / 2 + armLength * 0.62), angle: 0)
            arrow(.down,  x: 0,                  y:  (bodyHeight / 2 + armLength * 0.62), angle: 180)
            arrow(.left,  x: -(bodyWidth / 2 + armLength * 0.72), y: -6, angle: -90)
            arrow(.right, x:  (bodyWidth / 2 + armLength * 0.72), y: -6, angle: 90)
            if showsTilt {
                tiltHint(.tiltLeft,  x: -30)
                tiltHint(.tiltRight, x:  30)
            }
        }
        .frame(width: bodyWidth + armLength * 3.4, height: bodyHeight + armLength * 2.6)
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

            // The scroll wheel, drawn as the highlighted trigger when the user's
            // active trigger actually is the middle button — so the picture always
            // matches the configured trigger instead of asserting a fixed one.
            Capsule()
                .fill(Color.secondary.opacity(0.22))
                .frame(width: 9, height: 22)
                .offset(y: -bodyHeight / 2 + 22)
        }
    }

    // MARK: - Arms

    private func arrow(_ direction: GestureDirection, x: CGFloat, y: CGFloat, angle: Double) -> some View {
        let isSelected = selection == direction
        let assigned = isAssigned(direction)
        return Button {
            // Toggle semantics live in `MouseDiagramSelection` so the interaction
            // itself is assertable — see GestureUIDisplay.swift.
            selection = MouseDiagramSelection.afterClick(current: selection, clicked: direction)
        } label: {
            ZStack {
                Circle()
                    .fill(isSelected ? tint(direction).opacity(0.20) : Color.clear)
                    .frame(width: 34, height: 34)
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(assigned ? tint(direction) : Color.secondary.opacity(0.45))
                    .rotationEffect(.degrees(angle))
                // A dot marks "this arm sends something"; absence is honest and
                // reads as Unassigned without needing the word.
                if !assigned {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 34, height: 34)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: x, y: y)
        .help(helpText(direction))
        .accessibilityLabel(helpText(direction))
    }

    /// Tilt is shown as a small rotation hint on the wheel, not as a fifth arm:
    /// it is a different physical motion and drawing it as another arrow would
    /// teach the wrong gesture.
    private func tiltHint(_ direction: GestureDirection, x: CGFloat) -> some View {
        let isSelected = selection == direction
        let assigned = isAssigned(direction)
        let usable = showsTilt
        return Button {
            selection = MouseDiagramSelection.afterClick(current: selection, clicked: direction)
        } label: {
            HStack(spacing: 2) {
                Image(systemName: direction == .tiltLeft ? "arrow.uturn.left" : "arrow.uturn.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(usable && assigned ? tint(direction) : Color.secondary.opacity(0.4))
                Image(systemName: "arrowtriangle.left.fill")
                    .font(.system(size: 7))
                    .foregroundColor(Color.secondary.opacity(usable ? 0.5 : 0.25))
                    .scaleEffect(x: direction == .tiltLeft ? 1 : -1)
                    .opacity(direction == .tiltLeft ? 1 : 0)
            }
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? tint(direction).opacity(0.20) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: x, y: bodyHeight / 2 - 16)
        .help(helpText(direction))
        .accessibilityLabel(helpText(direction))
    }

    // MARK: - Helpers

    private func isAssigned(_ direction: GestureDirection) -> Bool {
        if case .unassigned = action(direction) { return false }
        return true
    }

    /// The tooltip is the sentence the diagram cannot draw: the motion *and* what
    /// it sends. Both are needed — an arrow alone says neither.
    private func helpText(_ direction: GestureDirection) -> String {
        let motion = L10n.t(direction.instruction)
        let sent: String
        switch action(direction) {
        case .unassigned:
            sent = L10n.t("chưa gán phím nào")
        case .horizontalScroll:
            sent = L10n.t("cuộn ngang nguyên bản")
        case .shortcut(let s):
            sent = L10n.t("gửi ") + s.label
        }
        return motion + " — " + sent
    }
}
