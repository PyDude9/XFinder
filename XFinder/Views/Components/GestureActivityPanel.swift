import SwiftUI

/// The "what actually happened" list, Mac Mouse Fix's **Button tab** insight applied
/// to a hold-and-drag gesture.
///
/// Why this exists at all, in the user's own words: *"tôi ko hiểu dùng nút nào của
/// chuột với mũi tên"* and *"chức năng của gestures không phù hợp"*. Both complaints
/// share a root cause — the page described intentions and the user had no way to see
/// what the engine had done. A diagram that says "Pull up → ⌘[" is an instruction to be
/// trusted; a line that says "you held Button 4, pulled up, and ⌘[ was sent" is evidence.
///
/// **It shows measurements, not a live readout.** The list is filled by the engine's
/// own callback through `GestureDiagnostic`, so it is empty until the user performs a
/// gesture, and the panel says exactly that instead of rendering six grey placeholders
/// that look like broken rows.
///
/// When logging is off the engine records nothing (one boolean load and no allocation),
/// so this panel states the switch and points at it. That is not a limitation being
/// hidden — it is the reason the feature costs no idle CPU.
struct GestureActivityPanel: View {
    let diagnostics: [GestureDiagnostic]
    /// Whether the engine is currently recording events into the ring.
    let loggingEnabled: Bool
    /// Whether the event tap is actually armed. Without the tap nothing can arrive, and
    /// saying "no activity yet" would blame the user's hand for a permission problem.
    let tapActive: Bool
    let onEnableLogging: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !tapActive {
                note(icon: "bolt.horizontal.circle",
                     text: L10n.t("Event Tap chưa mở nên chưa có gì để hiện. Kiểm tra quyền Trợ năng ở trên."))
            } else if !loggingEnabled {
                HStack(spacing: 8) {
                    note(icon: "eye.slash",
                         text: L10n.t("Bật ghi nhật ký để xem XFinder nhận được nút nào và gửi phím gì. Mặc định tắt để không tốn CPU khi rảnh."))
                    Button(L10n.t("Bật ghi nhật ký")) { onEnableLogging() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            } else if diagnostics.isEmpty {
                note(icon: "hand.point.up.left",
                     text: L10n.t("Chưa có cử chỉ nào. Giữ nút trên sơ đồ rồi kéo một hướng — dòng đo sẽ hiện ở đây."))
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(diagnostics.enumerated().reversed()), id: \.offset) { _, entry in
                        row(entry)
                    }
                }
            }
        }
        .padding(10)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func row(_ entry: GestureDiagnostic) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon(for: entry.event))
                .font(.system(size: 10))
                .foregroundColor(color(for: entry.event))
                .frame(width: 14)
            Text(L10n.t(entry.event.labelKey))
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            // Values, not sentences: a button number and a direction glyph are the two
            // things the user needs to correlate with their own hand, and both are
            // language-neutral. The app name is the bundle ID because that is the exact
            // string the resolver matched on — the honest thing to show when the
            // question is "did it pick the right profile?".
            if let button = entry.button {
                Text("B" + "\(button)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            if let direction = entry.direction {
                Text(direction.motionHintKey.isEmpty ? "" : L10n.t(direction.motionHintKey))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            if let kind = entry.kind, entry.event == .actionSent {
                Text(L10n.t(kind.labelKey))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
            }
            if !entry.bundle.isEmpty {
                Text(entry.bundle)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 150, alignment: .trailing)
            }
        }
    }

    private func note(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(.secondary)
            Text(text).font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func icon(for event: GestureDiagnosticEvent) -> String {
        switch event {
        case .triggerHeld: return "hand.tap"
        case .directionLocked: return "arrow.up.and.down.and.arrow.left.and.right"
        case .actionSent: return "paperplane.fill"
        case .clickPreserved: return "cursorarrow.click"
        case .gestureCancelled: return "arrow.uturn.backward"
        case .tiltDiscrete: return "arrow.left.and.right"
        case .scrollDrag: return "scroll"
        case .buttonObserved: return "circle.dashed"
        case .systemActionUnbound: return "exclamationmark.triangle"
        case .actionUnassigned: return "nosign"
        }
    }

    private func color(for event: GestureDiagnosticEvent) -> Color {
        switch event {
        case .actionSent: return .accentColor
        case .clickPreserved, .triggerHeld, .directionLocked: return .green
        case .gestureCancelled, .buttonObserved, .actionUnassigned: return .secondary
        case .tiltDiscrete, .scrollDrag: return .orange
        // A gesture that locked a direction and posted nothing: the same orange as the
        // other "recognised but could not complete" states, so it reads as a warning
        // rather than as a broken row.
        case .systemActionUnbound: return .orange
        }
    }
}
