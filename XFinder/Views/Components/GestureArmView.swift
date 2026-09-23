import SwiftUI

/// One arm of the mouse diagram: an arrow that is itself a `Button`, so the picture
/// *is* the selector rather than something the user has to correlate with a list.
///
/// Three things are drawn here and each answers a different question:
///
/// * the **arrow** — which motion this is;
/// * the **caption** — the exact keystroke it sends, or the word for "nothing";
/// * the **title**, above the arrow — what the keystroke *does* in the app on screen.
///
/// The held button is deliberately **not** here. It is the same button for every arm,
/// so printing it four times read as "all four buttons are Button 3" — the L1 bug the
/// user reported. It appears once, on the mouse body (`MouseDiagramView.holdBadge`).
struct GestureArmView: View {
    let direction: GestureDirection
    /// The resolved row, so the caption and the dispatched action come from one value.
    let row: ResolvedGestureRow
    /// What to call the action in this app, or `nil` when the shortcut is not the one
    /// this app binds to that intent — in which case only the keys are shown, because a
    /// confident name on a key we cannot vouch for is worse than no name.
    let actionName: String?
    let isSelected: Bool
    let support: ArmSupport
    let tint: Color
    /// Set while this arm is waiting for the user to press a key. Shown as a pulse so
    /// the user knows the page is listening and which row it will write to.
    let isRecording: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                arrowGlyph
                caption
            }
            .frame(width: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!support.isSupported || isRecording)
        .opacity(support.isSupported ? 1 : 0.45)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private var arrowGlyph: some View {
        ZStack {
            Circle()
                .fill(isSelected ? tint.opacity(0.18) : Color.clear)
                .frame(width: 30, height: 30)
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(arrowColor)
                .rotationEffect(.degrees(angle))
            // A dashed ring means "this arm sends nothing". Absence reads as Unassigned
            // without needing the word, which is what keeps four captions legible.
            if row.entry.isUnassigned, support.isSupported {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                    .foregroundColor(.secondary.opacity(0.55))
                    .frame(width: 30, height: 30)
            }
            if isRecording {
                Circle()
                    .strokeBorder(Color.orange, lineWidth: 1.5)
                    .frame(width: 30, height: 30)
            }
            if row.action == .horizontalScroll {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(tint)
                    .offset(x: 10, y: -10)
            }
        }
    }

    @ViewBuilder
    private var caption: some View {
        if !support.isSupported {
            // An explicit `if`, not a ternary inside one `L10n.t(...)`: the literal lint
            // only sees a string that is the *direct* argument, so a ternary hides both
            // strings from it — and from any future sweep. The two cases say different
            // things anyway ("this mouse cannot" vs "we cannot tell yet").
            if support == .unsupportedByMouse {
                Text(L10n.t("Không hỗ trợ"))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.75))
                    .lineLimit(1)
            } else {
                Text(L10n.t("Chưa rõ"))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.75))
                    .lineLimit(1)
            }
        } else if let caption = row.caption {
            VStack(spacing: 0) {
                Text(L10n.t(caption))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    // An unbound system action is not "green, working": the gesture is
                    // recognised and sends nothing. Orange is the honest signal, and it
                    // matches the warning the detail panel prints for the same row.
                    .foregroundColor(row.isUnboundSystemAction ? .orange : tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let actionName {
                    Text(actionName)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        } else {
            Text(L10n.t("Chưa gán"))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.secondary.opacity(0.75))
                .lineLimit(1)
        }
    }

    private var arrowColor: Color {
        guard support.isSupported else { return Color.secondary.opacity(0.55) }
        if row.isUnboundSystemAction { return Color.orange.opacity(0.85) }
        return row.caption == nil ? Color.secondary.opacity(0.5) : tint
    }

    private var angle: Double {
        switch direction {
        case .up, .tiltLeft, .tiltRight: return 0
        case .down: return 180
        case .left: return -90
        case .right: return 90
        }
    }

    /// The tooltip carries the two halves the drawing cannot: the motion in words, and
    /// the reason when the arm cannot run at all.
    private var helpText: String {
        let motion = L10n.t(direction.motionKey)
        switch support {
        case .unsupportedByMouse:
            return motion + " — " + L10n.t("Chuột này không có phần cứng cho hướng đó")
        case .unknownUntilDetected:
            return motion + " — " + L10n.t("Chưa đọc được mô tả chuột, nên chưa rõ hướng này có chạy được không")
        case .supported:
            break
        }
        // A system action this machine has no shortcut for. Stated before the "what it
        // sends" line, because there is no key to describe — and this is the exact state
        // the user reported as "nhận dạng cho có, không làm việc".
        if row.isUnboundSystemAction {
            return motion + " — " + L10n.t("macOS chưa gán phím tắt cho hành động này, nên hướng này chưa gửi được gì")
        }
        let sent: String
        if let caption = row.caption {
            let name = actionName.map { $0 + " " } ?? ""
            sent = L10n.t("gửi ") + name + L10n.t(caption)
        } else if row.action == .horizontalScroll {
            sent = L10n.t("chuyển tiếp cuộn ngang của chuột")
        } else {
            sent = L10n.t("chưa gán phím nào")
        }
        return motion + " — " + sent
    }
}
