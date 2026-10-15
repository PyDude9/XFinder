import SwiftUI

/// The panel that answers *"OK, and what exactly does THIS arrow do?"*.
///
/// Four questions, in the order a user asks them:
///
/// 1. **Which motion is it?** — in words, not a glyph;
/// 2. **What will be typed?** — the exact keys, big enough to read without clicking;
/// 3. **What does that do here?** — the intent, *only* when the shortcut is the one this
///    app binds to that intent. A recorded key gets no name rather than a wrong one;
/// 4. **Where did this value come from?** — preset, your override, or deliberately
///    unassigned. These mean different things and the row must not blur them.
///
/// The old version named an action from its key code (`case 29: return "Vừa khung"`),
/// which answers "what is key 29?" — a question with a different answer per app. It
/// lived in this SwiftUI file, so nothing could test it either. The intent now comes
/// from `GestureMapEntry.kind`, which is declared in the Foundation-only map file.
struct GestureDetailPanel: View {
    let direction: GestureDirection
    /// Everything about this row, resolved once by `GestureMap`.
    let row: ResolvedGestureRow
    /// What to call the action here, or `nil` when we cannot vouch for the meaning.
    let actionName: String?
    /// The configured trigger, so the heading can name the button that is held.
    let trigger: TriggerSource
    let isRecording: Bool
    let appName: String
    /// Whether the app in the picker has a preset of its own. A profile with none
    /// inherits Global, and "Chưa gán" there means something different from a preset
    /// that deliberately leaves a direction empty — so the copy has to branch on it.
    let hasAppPreset: Bool
    /// The machine's own hotkeys for the system actions, passed straight to the picker so
    /// its rows can name the key that would actually be posted. The row's **own** resolved
    /// key arrives in `row.systemShortcut`; this is only for the catalogue.
    var systemBindings: GestureSystemBindings = .empty
    let onPick: (GestureActionChoice) -> Void
    let onRecord: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            motionRow
            sendsRow
            GestureActionPicker(title: L10n.t("Hành động"),
                                current: row.systemShortcut ?? row.entry.shortcut,
                                currentKind: row.entry.kind,
                                allowsHorizontalScroll: GestureTriggerKind.supportsHorizontalScroll(direction),
                                isRecording: isRecording,
                                appName: hasAppPreset ? appName : nil,
                                systemBindings: systemBindings,
                                onPick: onPick,
                                onCustomKeys: onRecord,
                                onReset: row.isUserOverride ? onReset : nil)
            sourceRow
        }
        .padding(14)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(sourceColor.opacity(row.isUserOverride ? 1 : 0.35),
                              lineWidth: row.isUserOverride ? 1.5 : 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: directionIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(sourceColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t(direction, trigger: trigger))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
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
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(sourceColor)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(sourceColor.opacity(0.14)))
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
                Text(L10n.t(direction.motionKey))
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.t("Giữ") + " " + L10n.t(compactButton: trigger.key))
                    .font(.system(size: 11)).foregroundColor(.secondary)
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
                if row.isUnboundSystemAction {
                    // There is no key to be honest about, so the "sends exactly this" note
                    // would be false here — the warning replaces it.
                    systemUnboundWarning
                } else {
                    // The honesty note the brief asks for by name: the keys are sent, but
                    // whether they still mean this in a given app version is the app's
                    // business, and macOS lets the user rebind almost anything.
                    Text(L10n.t("XFinder gửi đúng phím này. Việc phím đó có làm đúng hành động hay không còn tuỳ phím tắt riêng của ứng dụng — macOS cho phép đổi gần như mọi phím tắt."))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var keyCap: some View {
        Group {
            if row.entry.isUnassigned {
                Text(L10n.t("Không gửi phím nào"))
                    .font(.system(size: 12)).foregroundColor(.secondary)
            } else if row.action == .horizontalScroll {
                Text(L10n.t("Cuộn ngang nguyên bản của chuột"))
                    .font(.system(size: 12)).foregroundColor(.secondary)
            } else if let system = row.entry.systemAction {
                // A system action resolves to the chord **this machine** binds, read from
                // `com.apple.symbolichotkeys`, so the panel shows the real keys — `⌃↑`, not
                // a shipped constant. The old version printed the action's name alone
                // because it believed these actions had no keystroke at all; they do, it is
                // just the user's own. When the machine binds nothing, the row says so and
                // the warning below offers the fix rather than drawing an invented key.
                if row.isUnboundSystemAction {
                    HStack(spacing: 6) {
                        Text(L10n.t(system.captionKey))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        Text(L10n.t("chưa có phím tắt trong macOS"))
                            .font(.system(size: 11)).foregroundColor(.orange)
                            .lineLimit(1)
                    }
                } else if let resolved = row.systemShortcut {
                    HStack(spacing: 6) {
                        Text(resolved.label)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        Text(L10n.t(system.captionKey))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            } else if let shortcut = row.entry.shortcut {
                HStack(spacing: 6) {
                    Text(shortcut.label)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    if let actionName {
                        Text(actionName)
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    } else {
                        Text(L10n.t("Phím bạn tự ghi"))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Provenance

    /// The unbound case, with the one action that fixes it.
    ///
    /// This is the exact state the user reported as "recognised but does nothing": their
    /// gesture resolved to Mission Control, and the machine had no shortcut bound for it.
    /// The page must not post a guessed key — it must say so and offer the pane where the
    /// shortcut is set, because that is the only thing that makes the gesture work.
    private var systemUnboundWarning: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("macOS trên máy này chưa gán phím tắt cho hành động này, nên cử chỉ sẽ không gửi gì. Mở Bàn phím → Phím tắt để gán, hoặc chọn một hành động khác."))
                .font(.system(size: 11)).foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.t("Mở Phím tắt trong Cài đặt")) { WindowManager.openKeyboardShortcutsPane() }
                .buttonStyle(.link).font(.system(size: 11))
        }
    }

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

    // MARK: - Derived

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

    private var sourceColor: Color {
        if row.isUserOverride { return .accentColor }
        if row.isUnboundSystemAction { return .orange }
        if row.entry.isUnassigned { return .secondary }
        return .green
    }

    private var sourceText: String {
        if row.isUserOverride { return L10n.t("Bạn tự đặt") }
        if row.entry.isUnassigned { return L10n.t("Chưa gán") }
        if row.effectiveBundle == GestureProfiles.fallback { return L10n.t("Toàn cục") }
        return L10n.t("Mặc định")
    }

    /// Says *why* the row says what it says. The distinction between a factory preset
    /// and the Global fallback matters: one means "this app was designed for", the other
    /// means "we had nothing specific, so here is the fallback".
    private var sourceExplanation: String {
        if row.isUnboundSystemAction {
            return L10n.t("Đây là hành động hệ thống của macOS, nhưng máy này chưa gán phím tắt cho nó. XFinder gửi đúng phím bạn gán trong Bàn phím → Phím tắt, nên hãy gán ở đó hoặc chọn hành động khác.")
        }
        if row.isUserOverride {
            return L10n.t("Bạn đã tự đặt phím cho hướng này. Bấm mũi tên quay lại để trả về preset.")
        }
        if row.effectiveBundle == GestureProfiles.fallback, hasAppPreset {
            return L10n.t("Ứng dụng này chưa có bảng riêng, nên đang dùng bảng Toàn cục. Bạn có thể tự đặt riêng cho nó.")
        }
        if row.entry.isUnassigned {
            if hasAppPreset {
                return L10n.t("Preset của ứng dụng này cố ý để trống hướng này, nên không rơi về bảng Toàn cục.")
            }
            return L10n.t("Ứng dụng này không có preset riêng, và bảng Toàn cục cũng chưa gán hướng này.")
        }
        if row.entry.source == .appShortcut {
            return L10n.t("Phím tắt riêng của ứng dụng này — có sẵn, không cần cấu hình gì.")
        }
        return L10n.t("Quy ước chung của macOS, hầu hết ứng dụng đều hiểu.")
    }
}
