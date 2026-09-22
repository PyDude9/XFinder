import SwiftUI

/// The panel that answers "OK, and what exactly does THIS arrow do?".
///
/// Replaces the old flat `HStack` row, which put the action name, the motion
/// instruction, a text badge and two buttons on one line and then truncated all
/// of them — which is why Global looked empty even though its six presets
/// resolved correctly (`⌃↑` is three characters competing with a full sentence
/// for a ~240 pt pane).
///
/// Everything here is stacked and given room: the motion in plain words, the
/// exact keys in a monospaced field, the provenance as a coloured source pill,
/// and the two secondary actions at the bottom where they belong.
struct GestureDetailPanel: View {
    let direction: GestureDirection
    let action: GestureAction
    let source: GestureRowSource
    /// The configured trigger, so the heading can name the button that is held.
    let trigger: TriggerSource
    let isRecording: Bool
    let onRecord: () -> Void
    let onSetUnassigned: () -> Void
    let onSetHorizontalScroll: (() -> Void)?
    let onResetApp: () -> Void
    let appName: String

    /// Whether the app in the picker has a preset of its own. A profile with no
    /// preset inherits Global, and "Chưa gán" there means something different
    /// from a preset that deliberately leaves a direction empty — so the copy has
    /// to branch on it rather than call everything a preset.
    let hasAppPreset: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            motionRow
            sendsRow
            sourceRow
            Divider()
            actions
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(sourceColor.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: directionIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(sourceColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(directionTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(appName)
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            sourcePill
        }
    }

    private var sourcePill: some View {
        Text(sourceText)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(sourceColor)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(
                Capsule().fill(sourceColor.opacity(0.14))
            )
            .fixedSize()
    }

    // MARK: - What to do

    private var motionRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "computermouse")
                .font(.system(size: 12)).foregroundColor(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("Động tác"))
                    .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                Text(motionText)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - What is sent

    private var sendsRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 12)).foregroundColor(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("XFinder gửi"))
                    .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                keyCap
            }
            Spacer(minLength: 0)
        }
    }

    /// The keys are shown in a key-cap field so the exact keystroke is legible
    /// even when the row is narrow — this is the one value the user must be able
    /// to read without clicking anything.
    private var keyCap: some View {
        Group {
            switch action {
            case .unassigned:
                Text(L10n.t("Không gửi phím nào"))
                    .font(.system(size: 12)).foregroundColor(.secondary)
            case .horizontalScroll:
                Text(L10n.t("Cuộn ngang nguyên bản của chuột"))
                    .font(.system(size: 12)).foregroundColor(.secondary)
            case .shortcut(let s):
                HStack(spacing: 6) {
                    Text(s.label)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(actionName(s))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Provenance

    private var sourceRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "tag")
                .font(.system(size: 12)).foregroundColor(.secondary)
                .frame(width: 16)
            Text(sourceExplanation)
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Secondary actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button(isRecording ? L10n.t("Đang ghi…") : L10n.t("Đổi phím tắt")) { onRecord() }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(isRecording)
            if action != .unassigned {
                Button(L10n.t("Chưa gán")) { onSetUnassigned() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            if let onSetHorizontalScroll {
                Button(L10n.t("Cuộn ngang")) { onSetHorizontalScroll() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            Spacer(minLength: 0)
            Button(L10n.t("Về mặc định")) { onResetApp() }
                .buttonStyle(.bordered).controlSize(.small)
                .help(L10n.t("Chỉ đặt lại hướng này về bảng có sẵn, không đụng các hướng khác."))
        }
    }

    // MARK: - Derived text

    private var directionIcon: String {
        switch direction {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .tiltLeft: return "arrow.uturn.left"
        case .tiltRight: return "arrow.uturn.right"
        }
    }

    private var directionTitle: String {
        // Wrapped at the call site, not inside the helper: `GestureDirectionDisplay`
        // is a pure-Foundation file the test package symlinks, so it must not grow
        // an `L10n` dependency. This line was the leak — the helper returned
        // Vietnamese and nothing here asked for the translation, so "Kéo LÊN"
        // rendered verbatim in the English UI.
        L10n.t(GestureDirectionDisplay.title(direction, trigger: trigger))
    }

    /// The motion sentence with the trigger's number in it, so "what do I press?"
    /// is answered by the same row that says what is sent.
    private var motionText: String {
        if GestureDirectionDisplay.isTilt(direction) {
            return L10n.t(direction.title(trigger: trigger))
        }
        return L10n.t(trigger.label) + " · " + L10n.t(direction.title(trigger: trigger))
    }

    private var sourceColor: Color {
        switch source {
        case .preset, .presetGlobal: return .green
        case .userOverride: return .accentColor
        case .unassigned: return .secondary
        }
    }

    private var sourceText: String {
        switch source {
        case .preset: return L10n.t("Có sẵn")
        case .presetGlobal: return L10n.t("Toàn cục")
        case .userOverride: return L10n.t("Bạn tự đặt")
        case .unassigned: return L10n.t("Chưa gán")
        }
    }

    /// Says *why* the row says what it says. The distinction between a factory
    /// preset and the global fallback matters: one means "this app was designed
    /// for", the other means "we had nothing specific, so here is the fallback".
    private var sourceExplanation: String {
        switch source {
        case .preset:
            return L10n.t("Phím tắt có sẵn của ứng dụng này. Bạn không cần cấu hình gì.")
        case .presetGlobal:
            return L10n.t("Ứng dụng này chưa có bảng riêng, nên đang dùng bảng Toàn cục. Bạn có thể tự đặt riêng cho nó.")
        case .userOverride:
            return L10n.t("Bạn đã tự đặt phím cho hướng này. Bấm “Về mặc định” để quay lại bảng có sẵn.")
        case .unassigned:
            // An app with no preset is inheriting Global, so an empty direction
            // here means Global had nothing either — not a deliberate choice by an
            // app author. Saying "cố ý" for that case would be a false claim.
            if hasAppPreset {
                return L10n.t("Preset của ứng dụng này cố ý để trống hướng này, nên không rơi về bảng Toàn cục.")
            }
            return L10n.t("Ứng dụng này không có preset riêng, và bảng Toàn cục cũng chưa gán hướng này. Bấm “Đổi phím tắt” để tự đặt.")
        }
    }

    private func actionName(_ s: GestureShortcut) -> String {
        switch s.key {
        case 17: return L10n.t("Tab mới")
        case 13: return L10n.t("Đóng tab")
        case 48: return L10n.t("Chuyển tab")
        case 29: return L10n.t("Vừa khung")
        case 6:  return s.flags == GestureShortcut.command ? L10n.t("Hoàn tác") : L10n.t("Làm lại")
        case 33: return L10n.t("Thu nhỏ cọ")
        case 30: return L10n.t("Phóng to cọ")
        case 35: return L10n.t("Bảng lệnh")
        case 27: return L10n.t("Ẩn/hiện khung")
        default:
            if s.flags & GestureShortcut.control != 0 { return L10n.t("Phím hệ thống macOS") }
            return ""
        }
    }
}
