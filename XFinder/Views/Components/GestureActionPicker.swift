import SwiftUI

/// The action picker: pick what a gesture *does*, then see the exact keys that will
/// be sent.
///
/// This is a menu rather than a free-form recorder for one measured reason — the
/// screen was reported as *"rỗng"* (empty) twice. Both times the cause was the same
/// class of mistake: a control that only offered what the engine happened to have, so
/// a user who had not recorded anything saw an empty list and concluded the feature
/// had no options. The catalogue here is generated from `GestureActionKind.allCases`,
/// so the list can never be shorter than the vocabulary, and every row shows its
/// keystroke, so a row can never look like a blank cell.
///
/// The keystrokes are grouped by intent, and the intent names are the *only* place an
/// action is described in words — a shortcut on its own (`⌘⇧]`) does not tell a user
/// what it does, and an action name on its own does not tell them what will be typed
/// into their app.
struct GestureActionPicker: View {
    /// The row being edited, so the picker can say which gesture it is changing.
    let title: String
    /// The shortcut currently in force.
    let current: GestureShortcut?
    /// The intent the row currently carries, used to pre-select the menu.
    let currentKind: GestureActionKind?
    /// Whether this arm can carry "forward the wheel's own sideways motion" instead.
    let allowsHorizontalScroll: Bool
    let isRecording: Bool
    /// Which app the binding belongs to, so the picker can say whether the shortcut
    /// is that app's own or a platform convention. `nil` = the Global table.
    let appName: String?
    /// The machine's own hotkeys, so a system-action row can name the chord that would
    /// actually be posted. Without it the row could only print the action's *name* — the
    /// old behaviour — and the user could not tell what gets typed into their app.
    var systemBindings: GestureSystemBindings = .empty
    let onPick: (GestureActionChoice) -> Void
    let onCustomKeys: () -> Void
    /// `nil` when there is no override to drop, which disables the row instead of
    /// offering a button that would do nothing.
    let onReset: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(current?.label ?? L10n.t("Chưa gán"))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(current == nil ? .secondary : .primary)
                .frame(width: 74, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let detail = detailText {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if isRecording {
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text(L10n.t("Đang ghi…")).font(.system(size: 11)).foregroundColor(.orange)
                }
            }

            Menu {
                actionMenu
            } label: {
                HStack(spacing: 4) {
                    Text(currentActionLabel)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .medium))   // spec floor: nothing under 11 pt
                        .foregroundColor(.secondary)
                }
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)
            .disabled(isRecording)
            .help(L10n.t("Đổi hành động cho hướng này"))

            if let onReset {
                Button {
                    onReset()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help(L10n.t("Đưa hướng này về preset — không đụng các hướng khác"))
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var currentActionLabel: String {
        if let currentKind {
            if let sys = GestureSystemAction.allCases.first(where: { $0.defaultKind == currentKind }) {
                return L10n.t(sys.captionKey)
            }
            if currentKind == .horizontalScroll {
                return L10n.t("Cuộn ngang nguyên bản")
            }
            if current != nil {
                return L10n.t(currentKind.labelKey)
            }
            return L10n.t("Chưa gán")
        }
        if current != nil {
            return L10n.t("Phím bạn tự ghi")
        }
        return L10n.t("Chưa gán")
    }

    /// The second line: what the shortcut *means* here, and — when the shortcut is one
    /// app's own rather than a platform convention — that it is that app's key rather
    /// than a universal one.
    private var detailText: String? {
        guard let kind = currentKind, current != nil else { return nil }
        let name = L10n.t(kind.labelKey)
        let provenance = provenanceText(kind)
        return provenance.isEmpty ? name : name + " · " + provenance
    }

    private func provenanceText(_ kind: GestureActionKind) -> String {
        guard let appName else { return L10n.t("Quy ước chung của macOS") }
        // Only mark a shortcut as the app's own when it is the one the built-in table
        // declares for this intent. A user-recorded key is not the app's documented
        // shortcut, and saying so would be a claim about the app that nothing verified.
        let bundle = GestureMap.effectiveBundle(for: appBundleForProvenance)
        guard let builtIn = GestureProfiles.all.first(where: { $0.id == bundle })?
            .gestureMap.first(where: { $0.value.kind == kind })?.value else {
            return L10n.t("Quy ước chung của macOS")
        }
        if builtIn.source == .appShortcut, builtIn.shortcut == current {
            return L10n.t("Phím tắt riêng của ứng dụng") + " " + appName
        }
        return L10n.t("Quy ước chung của macOS")
    }

    /// The bundle whose table should be consulted for provenance text. The row's own
    /// app when it has one, otherwise Global — which `effectiveBundle` already decides.
    private var appBundleForProvenance: String {
        GestureProfiles.all.first { $0.name == appName }?.id ?? GestureProfiles.fallback
    }

    /// What a picker row says it sends. Three forms, and the middle one is why this
    /// helper exists: a **system action** carries no keystroke, and the old
    /// `shortcut?.label ?? ""` left the row reading "Mission Control — ".
    private func sentLabel(_ choice: GestureActionChoice) -> String {
        if let shortcut = choice.shortcut { return shortcut.label }
        if let system = choice.systemAction {
            // Resolved from this machine's own hotkeys, so the row shows the real chord
            // (`⌃↑`) or says it is unbound — never a constant on a row that may post a
            // different one. The unbound form is a store key, so it goes through `L10n`;
            // a resolved chord is a language-neutral symbol and passes through unchanged.
            return L10n.t(GestureMap.systemCaption(for: system, bindings: systemBindings))
        }
        return L10n.t("Không gửi phím nào")
    }

    @ViewBuilder
    private var actionMenu: some View {
        ForEach(GestureActionCatalog.choices(), id: \.group) { section in
            Section(L10n.t(section.group)) {
                ForEach(section.items) { choice in
                    Button {
                        onPick(choice)
                    } label: {
                        // What is sent is part of the label on purpose: choosing an
                        // action IS choosing what gets sent, and the two must be picked
                        // together or the user is guessing. A system action has no
                        // keystroke, so it names its mechanism instead of showing an
                        // empty suffix after the dash.
                        Text(L10n.t(choice.kind.labelKey) + "  —  " + sentLabel(choice))
                    }
                }
            }
        }
        Divider()
        if allowsHorizontalScroll {
            Button(L10n.t("Cuộn ngang nguyên bản")) {
                onPick(GestureActionChoice(kind: .horizontalScroll, shortcut: nil))
            }
        }
        Button(L10n.t("Chưa gán")) {
            onPick(GestureActionChoice(kind: currentKind ?? .back, shortcut: nil))
        }
        Divider()
        Button(L10n.t("Ghi phím tắt…")) { onCustomKeys() }
    }
}
