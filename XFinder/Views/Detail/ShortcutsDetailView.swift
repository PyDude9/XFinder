import SwiftUI

/// P3 D1 — "Phím tắt": one place to see every shortcut XFinder owns, change the ones that can change (the six
/// Capture modes and the global ⌘K palette — the only two recordable mechanisms in the app, per the survey), and
/// spot clashes between them and with macOS's own conventions. Everything else is a fixed chord or a local-only
/// monitor: those are listed read-only, grouped by feature, each linking to the page that owns its on/off switch
/// (Part 0 §4 — one key, one control; this page never adds a second toggle for a setting another page owns).
struct ShortcutsDetailView: View {
    @State private var capture = CaptureController.shared
    @State private var palette = QuickSearchPanelController.shared

    @AppStorage("windowPreview.switcherHotkey") private var switcherHotkey = "commandTab"
    @AppStorage("capture.enabled") private var captureEnabled = true
    @AppStorage("quickSearch.enabled") private var quickSearchEnabled = true

    // Fixed-shortcut gate keys, read here ONLY to show on/off state and to build the conflict check's
    // `isActive` closure — every one of these keys is still bound with @AppStorage on its OWNING page.
    @AppStorage("clipboard.globalHotkey") private var clipboardGlobalHotkey = true
    @AppStorage("clipboard.shelfHotkey") private var clipboardShelfHotkey = false
    @AppStorage("translate.hotkeyEnabled") private var translateEnabled = false
    @AppStorage("snapzones.hotkeysEnabled") private var snapHotkeysEnabled = true
    @AppStorage("quitProtection.enabled") private var quitHoldEnabled = false
    @AppStorage("windowPreview.commandTabEnabled") private var commandTabEnabled = false
    @AppStorage("finderKeyboard.cutPaste") private var finderCutPaste = false
    @AppStorage("finderKeyboard.deleteToTrash") private var finderDeleteToTrash = false
    @AppStorage("finderKeyboard.returnOpens") private var finderReturnOpens = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Settings.sectionGap) {
                PageHeader(icon: "command", title: L10n.t("Phím tắt"),
                           subtitle: L10n.t("Xem mọi phím tắt XFinder đang dùng, đổi những phím đổi được, và phát hiện trùng lặp."))
                captureSection
                paletteSection
                fixedShortcutsSection
            }
            .padding(.bottom, XFinderTokens.Space.section)
            .pageWidthSafe()
        }
        .background(XFinderTokens.Settings.contentBackground)
    }

    // MARK: - Recorded state (for the conflict check across every entry on this page)

    /// Chords for every entry that can clash: Capture's six modes (unassigned ones are simply absent — an unassigned
    /// chord cannot conflict with anything), every fixed entry, and ⌘K (decoded from its `NSEvent` flags through the
    /// palette's own reader, so the palette and Capture are checked against each other and against every fixed chord).
    private var recordedChords: [String: ShortcutCatalog.Chord] {
        var map: [String: ShortcutCatalog.Chord] = [:]
        for mode in CaptureMode.allCases {
            if let s = capture.shortcut(for: mode) {
                map["capture.\(mode.rawValue)"] = ShortcutCatalog.Chord(keyCode: UInt16(s.keyCode), modifiers: catalogModifiers(s))
            }
        }
        for entry in ShortcutCatalog.fixedEntries {
            map[entry.id] = ShortcutCatalog.liveChord(of: entry, switcherSetting: switcherHotkey)
        }
        // ⌘K, through the palette's own reader (QuickSearchPanelController.storedChordRaw — one read of its keys).
        let raw = QuickSearchPanelController.storedChordRaw()
        map[Self.paletteOwner] = ShortcutCatalog.Chord(keyCode: UInt16(clamping: raw.keyCode),
                                                       modifiers: ShortcutCatalog.Modifiers(nsEventRaw: raw.nsModifiers))
        return map
    }

    private func catalogModifiers(_ s: CaptureShortcut) -> ShortcutCatalog.Modifiers {
        var m: ShortcutCatalog.Modifiers = []
        if s.hasCommand { m.insert(.command) }
        if s.hasOption { m.insert(.option) }
        if s.hasControl { m.insert(.control) }
        if s.hasShift { m.insert(.shift) }
        return m
    }

    /// Whether `id` is active right now — read from the same `@AppStorage` properties the fixed rows below
    /// already bind, plus the two master switches, so an inactive owner never counts as a real clash.
    private func isActive(_ id: String) -> Bool {
        switch id {
        case "clipboard.shelf": return clipboardGlobalHotkey
        // ⌘⌥C rides the same tap as ⌘⇧V: `clipboard.globalHotkey` gates the whole tap, `shelfHotkey` only this chord.
        case "clipboard.shelfAlt": return clipboardGlobalHotkey && clipboardShelfHotkey
        case Self.paletteOwner: return quickSearchEnabled
        case "clipboard.pasteStack": return true
        case "translate.selection": return translateEnabled
        case "quit.hold": return quitHoldEnabled
        case "switcher.commandTab": return commandTabEnabled
        case "finderKeyboard.cutPaste": return finderCutPaste
        case "finderKeyboard.deleteToTrash": return finderDeleteToTrash
        case "finderKeyboard.returnOpens": return finderReturnOpens
        case "notes.new", "notes.library", "notes.pin": return true
        case let s where s.hasPrefix("snap."): return snapHotkeysEnabled
        case let s where s.hasPrefix("capture."): return captureEnabled
        default: return true
        }
    }

    private func conflicts(for chord: ShortcutCatalog.Chord, owner: String) -> ShortcutCatalog.ConflictResult {
        ShortcutCatalog.conflicts(for: chord, owner: owner, recorded: recordedChords, isActive: isActive)
    }

    // MARK: - Chụp màn hình (moved from CaptureDetailView per the P3 contract)

    private var captureSection: some View {
        SettingsSection(
            title: L10n.t("Chụp màn hình"),
            footer: captureEnabled
                ? L10n.t("Không có phím tắt mặc định — ⇧⌘3, ⇧⌘4, ⇧⌘5 vẫn là của macOS. Muốn dùng ⇧⌘3 và ⇧⌘4, hãy tắt hai phím đó của macOS trong Cài đặt hệ thống ▸ Bàn phím ▸ Phím tắt ▸ Ảnh màn hình.")
                : nil
        ) {
            // P3 review: the capture switch belongs to Chụp & chú thích (one key, one control) — this page only records.
            if captureEnabled {
                ForEach(Array(CaptureMode.allCases.enumerated()), id: \.element) { index, mode in
                    if index > 0 { SettingsDivider() }
                    captureModeRow(mode)
                }
                SettingsDivider()
                HStack(spacing: XFinderTokens.Space.inline) {
                    Button(L10n.t("Dùng bộ phím giống OneNotch")) { capture.applyOneNotchPreset() }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button(L10n.t("Mở Phím tắt bàn phím")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Spacer()
                }
                .settingsRow()
                SettingsDivider()
                SettingsLinkRow(title: L10n.t("Mở trang Chụp & chú thích"),
                                subtitle: L10n.t("Sau khi chụp, lưu file, định dạng, lịch sử"),
                                destination: .capture)
            } else {
                SettingsLinkRow(title: L10n.t("Chụp màn hình đang tắt."),
                                subtitle: L10n.t("Mở trang Chụp & chú thích"), destination: .capture)
            }
        }
    }

    @ViewBuilder
    private func captureModeRow(_ mode: CaptureMode) -> some View {
        let shortcut = capture.shortcut(for: mode)
        let recording = capture.recordingMode == mode
        let catalogChord = shortcut.map { ShortcutCatalog.Chord(keyCode: UInt16($0.keyCode), modifiers: catalogModifiers($0)) }
        let result = catalogChord.map { conflicts(for: $0, owner: "capture.\(mode.rawValue)") }

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: XFinderTokens.Space.inline) {
                Image(systemName: mode.symbol).foregroundColor(.secondary).frame(width: 18)
                Text(L10n.t(mode.titleKey)).font(XFinderTokens.Font.row)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                if recording {
                    Text(L10n.t("Nhấn tổ hợp phím… (Esc để huỷ)"))
                        .font(XFinderTokens.Font.caption).foregroundColor(.accentColor)
                    Button(L10n.t("Hủy")) { capture.cancelRecording() }.controlSize(.small)
                } else {
                    recorderPill(label: shortcut?.label, isActive: captureEnabled)
                    Button(L10n.t("Gán phím")) { capture.beginRecording(mode) }.controlSize(.small)
                    if shortcut != nil {
                        Button(L10n.t("Xoá")) { capture.clearShortcut(mode) }.controlSize(.small)
                            .help(L10n.t("Xoá"))
                            .accessibilityLabel(L10n.t("Xoá"))
                    }
                }
            }
            if let legacy = capture.lastConflict, legacy.mode == mode {
                captureConflictCaption(legacy.conflict)
            } else if let result, !result.isEmpty {
                catalogConflictCaption(result)
            }
        }
        .settingsRow()
    }

    private func captureConflictCaption(_ conflict: CaptureRules.Conflict) -> some View {
        Group {
            switch conflict {
            case .system(let nameKey):
                Text("\(L10n.t("Trùng với "))\(L10n.t(nameKey))\(L10n.t(" — macOS có thể giành trước."))")
            case .mode(let other):
                Text("\(L10n.t(other.titleKey))\(L10n.t(" đã giữ tổ hợp này rồi."))")
            }
        }
        .font(XFinderTokens.Font.caption).foregroundColor(.orange)
        .padding(.leading, 26)
    }

    // MARK: - Bảng lệnh (moved from SearchDetailViews.paletteSection per the P3 contract)

    private var paletteSection: some View {
        SettingsSection(
            title: L10n.t("Bảng lệnh"),
            footer: quickSearchEnabled
                ? "\(palette.hotkeyLabel)\(L10n.t(" mở bảng lệnh nổi kiểu Spotlight / Raycast / TinyCast"))"
                : nil
        ) {
            // P3 review: the palette switch belongs to the Search page (one key, one control) — this page only records.
            if quickSearchEnabled {
                HStack(spacing: XFinderTokens.Space.inline) {
                    Text(L10n.t("Phím tắt")).font(XFinderTokens.Font.row)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    if palette.isRecording {
                        Text(L10n.t("Đang ghi — nhấn tổ hợp phím mới (phải có ⌘/⌥/⌃, ví dụ ⌘Space). Esc để hủy."))
                            .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(L10n.t("Hủy ghi")) { palette.cancelRecording() }.controlSize(.small)
                    } else {
                        recorderPill(label: palette.hotkeyLabel, isActive: true)
                        Button(L10n.t("Đổi phím…")) { palette.beginRecording() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .settingsRow()
                if let caption = paletteConventionCaption {
                    SettingsDivider()
                    caption
                        .font(XFinderTokens.Font.caption).foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .settingsRow()
                }
            } else {
                SettingsLinkRow(title: L10n.t("Bảng lệnh đang tắt."),
                                subtitle: L10n.t("Bảng lệnh toàn cục + ô tìm nhanh trong trang Tìm kiếm"),
                                destination: .finderSearch)
            }
        }
    }

    /// ⌘K's own recorder keeps no key-code catalog entry (its bit layout is `NSEvent.ModifierFlags`, not
    /// `ShortcutCatalog.Modifiers`), so its clash check is a label compare against the fixed entries and the two
    /// system conventions this page already knows about — the two chords a user is most likely to reach for.
    private var paletteConventionCaption: AnyView? {
        guard let chord = recordedChords[Self.paletteOwner] else { return nil }
        let result = conflicts(for: chord, owner: Self.paletteOwner)
        return result.isEmpty ? nil : AnyView(catalogConflictCaption(result))
    }

    private func catalogConflictCaption(_ result: ShortcutCatalog.ConflictResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(result.owners, id: \.self) { ownerID in
                Text("\(L10n.t("Trùng với "))\(ownerTitle(ownerID))\(L10n.t(" — đổi phím khác để tránh xung đột."))")
            }
            ForEach(Array(result.conventions.enumerated()), id: \.offset) { _, c in
                if c.isConventionOnly {
                    Text("\(L10n.t("Trùng với quy ước "))\(L10n.t(c.nameKey))\(L10n.t(" — có thể làm hỏng phím đó ở app khác."))")
                } else {
                    Text("\(L10n.t("Trùng với "))\(L10n.t(c.nameKey))\(L10n.t(" — macOS có thể giành trước."))")
                }
            }
        }
        .font(XFinderTokens.Font.caption).foregroundColor(.orange)
        .padding(.leading, 26)
    }

    /// The conflict owner, by name — never its raw id (a capture-vs-capture clash used to print "capture.area").
    private func ownerTitle(_ entryID: String) -> String {
        if let entry = ShortcutCatalog.fixedEntries.first(where: { $0.id == entryID }) { return L10n.t(entry.titleKey) }
        if entryID == Self.paletteOwner { return L10n.t("Bảng lệnh") }
        if entryID.hasPrefix("capture."), let mode = CaptureMode(rawValue: String(entryID.dropFirst("capture.".count))) {
            return L10n.t(mode.titleKey)
        }
        return L10n.t("Một phím tắt khác của XFinder")
    }

    private static let paletteOwner = "quickSearch.palette"

    // MARK: - Fixed shortcuts, read-only, grouped by feature

    private var fixedShortcutsSection: some View {
        SettingsSection(title: L10n.t("Phím tắt cố định")) {
            ForEach(Array(groupedFixedEntries.enumerated()), id: \.offset) { index, group in
                if index > 0 { SettingsDivider() }
                fixedGroupRows(group)
            }
            SettingsDivider()
            gestureAndVoiceLinkRows()
        }
    }

    /// Every fixed entry grouped by owner page, in the catalog's own declaration order. Local-only chords (Paste Stack,
    /// the Notes keys) go through the same row — their scope note says "only while XFinder is in front" — so each
    /// shortcut has exactly one source: its catalog entry (the page used to re-type Paste Stack's title and "⇧⌘C").
    private var groupedFixedEntries: [[ShortcutCatalog.Entry]] {
        var seen: [String] = []
        var groups: [String: [ShortcutCatalog.Entry]] = [:]
        for entry in ShortcutCatalog.fixedEntries {
            if groups[entry.ownerPage] == nil { seen.append(entry.ownerPage) }
            groups[entry.ownerPage, default: []].append(entry)
        }
        return seen.compactMap { groups[$0] }
    }

    @ViewBuilder
    private func fixedGroupRows(_ group: [ShortcutCatalog.Entry]) -> some View {
        ForEach(Array(group.enumerated()), id: \.element.id) { index, entry in
            if index > 0 { SettingsDivider() }
            fixedEntryRow(entry)
        }
    }

    @ViewBuilder
    private func fixedEntryRow(_ entry: ShortcutCatalog.Entry) -> some View {
        let active = isActive(entry.id)
        let chord = ShortcutCatalog.liveChord(of: entry, switcherSetting: switcherHotkey)
        let result = conflicts(for: chord, owner: entry.id)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: XFinderTokens.Space.inline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.t(entry.titleKey)).font(XFinderTokens.Font.row)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1).truncationMode(.middle)
                    Text(scopeNote(entry.scope))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                recorderPill(label: chord.label, isActive: active)
                NavigationArrow(destination: SidebarDestination(rawValue: entry.ownerPage))
            }
            if !result.isEmpty {
                catalogConflictCaption(result)
            }
        }
        .settingsRow()
    }

    private func gestureAndVoiceLinkRows() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsLinkRow(title: L10n.t("Cử chỉ chuột"),
                            subtitle: L10n.t("Giữ một nút chuột rồi kéo — không phải phím bàn phím"),
                            destination: .mouseGestures)
            SettingsDivider()
            SettingsLinkRow(title: L10n.t("Phím kích hoạt giọng nói"),
                            subtitle: L10n.t("Một phím modifier giữ hoặc bấm để nói — không phải một tổ hợp phím"),
                            destination: .voiceTyping)
        }
    }

    private func scopeNote(_ scope: ShortcutCatalog.Scope) -> String {
        switch scope {
        case .global: return L10n.t("Mọi lúc, trên toàn hệ thống")
        case .whenXFinderFrontmost: return L10n.t("Chỉ khi XFinder ở phía trước")
        case .finderOnly: return L10n.t("Chỉ trong Finder")
        }
    }

    // MARK: - Shared pieces

    /// The recorder pill: shows the chord or "Chưa gán", drawn quiet when the owner is switched off.
    private func recorderPill(label: String?, isActive: Bool) -> some View {
        ShortcutChip(label: label ?? L10n.t("Chưa gán"), isActive: isActive)
    }
}

/// A bare chevron that opens the owning page — used inside a read-only fixed-shortcut row where the full
/// `SettingsLinkRow` chrome (title/subtitle) is already drawn by the row itself.
private struct NavigationArrow: View {
    let destination: SidebarDestination?

    var body: some View {
        if let destination {
            Button {
                AppState.shared.navigate(to: destination)
            } label: {
                Image(systemName: "chevron.right")
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(destination.titleVI)
            .accessibilityLabel(destination.titleVI)
        }
    }
}
