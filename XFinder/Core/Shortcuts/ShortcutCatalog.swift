import Foundation

/// P3 D1 — "Phím tắt": one place to see every shortcut XFinder owns, change the ones that can change, and spot
/// clashes. Foundation-only (symlinked into the test package) so the catalog and its conflict check are testable
/// without a running app.
///
/// This file only describes FIXED/structural facts: which chord an owner uses today, its scope, which gate key
/// turns the owner on, and that gate's default. It does NOT read `UserDefaults` or know about recorders — the page
/// (`ShortcutsDetailView`) binds the live `@AppStorage` values and calls the existing controllers
/// (`CaptureController`, `QuickSearchPanelController`) for the two recordable ones.
enum ShortcutCatalog {

    // MARK: - Chord

    /// A key combination: a virtual key code (macOS's own stable ANSI layout constants, the same values Carbon's
    /// `kVK_*` enum publishes) plus a modifier set. Deliberately a SEPARATE bit layout from `CaptureShortcut`'s
    /// (and from `NSEvent.ModifierFlags`'s raw bits, which `quickSearch.hotkeyModifiers` stores) — this type only
    /// ever appears as catalog DATA, built once per entry below from each owner's own already-resolved facts, so
    /// it never needs to decode another file's bit layout.
    struct Modifiers: OptionSet, Hashable {
        let rawValue: Int
        init(rawValue: Int) { self.rawValue = rawValue }

        static let command = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let shift = Modifiers(rawValue: 1 << 3)

        /// P3: `quickSearch.hotkeyModifiers` stores `NSEvent.ModifierFlags.rawValue` — device-independent bits
        /// shift 1<<17, control 1<<18, option 1<<19, command 1<<20 (AppKit's published values; this file stays
        /// Foundation-only, so they are spelled out and pinned by a test). Without this the ⌘K recorder sat outside
        /// the clash check.
        init(nsEventRaw raw: Int) {
            var m: Modifiers = []
            if raw & (1 << 20) != 0 { m.insert(.command) }
            if raw & (1 << 19) != 0 { m.insert(.option) }
            if raw & (1 << 18) != 0 { m.insert(.control) }
            if raw & (1 << 17) != 0 { m.insert(.shift) }
            self = m
        }
    }

    struct Chord: Equatable, Hashable {
        var keyCode: UInt16
        var modifiers: Modifiers

        /// Display order ⌃⌥⇧⌘ then the key's own name — matches `CaptureShortcut.label`'s order so a chord
        /// drawn here reads identically to the one drawn on the Capture/Search pages.
        var label: String {
            var s = ""
            if modifiers.contains(.control) { s += "⌃" }
            if modifiers.contains(.option) { s += "⌥" }
            if modifiers.contains(.shift) { s += "⇧" }
            if modifiers.contains(.command) { s += "⌘" }
            s += Self.keyName(for: keyCode)
            return s
        }

        // kVK_ANSI_A...Z, kVK_ANSI_0...9 and the handful of named keys every entry below actually uses.
        // (A small, closed table — unlike CaptureRules.keyName this catalog never needs F-keys.)
        private static let letterNames: [UInt16: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
            38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
            15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        ]
        private static let namedKeys: [UInt16: String] = [
            123: "←", 124: "→", 126: "↑", 125: "↓",
            49: "Space", 36: "↩", 48: "Tab", 53: "Esc", 51: "⌫",
        ]

        static func keyName(for keyCode: UInt16) -> String {
            if let letter = letterNames[keyCode] { return letter }
            if let named = namedKeys[keyCode] { return named }
            return "Key \(keyCode)"
        }
    }

    // MARK: - Entry

    enum Scope: Equatable {
        /// Works everywhere, any app frontmost (Carbon hotkeys, CGEvent taps that are not scoped to one app).
        case global
        /// Local `NSEvent` monitor — only fires while an XFinder window is frontmost.
        case whenXFinderFrontmost
        /// A CGEvent tap scoped to Finder only (key rewrites).
        case finderOnly
    }

    struct Entry: Identifiable, Equatable {
        let id: String
        /// Vietnamese literal — the L10n store key.
        let titleKey: String
        let chord: Chord
        let scope: Scope
        /// The `SidebarDestination` that owns the setting (a `String` so this file stays model-free, like
        /// `GlanceRules`'s notes-by-page-name pattern — the test resolves it against the real enum).
        let ownerPage: String
        /// `UserDefaults` key that turns this shortcut's OWNER on/off, if any. `nil` for a shortcut with no
        /// independent gate (e.g. the Paste Stack passthrough, which is part of the clipboard shelf's own tap).
        let gateKey: String?
        /// The gate key's default — MUST equal the one Core reader's default (checked by a source-parsing test,
        /// the same technique `FeatureKeyDefaultsTests` uses).
        let gateDefault: Bool?
        /// Whether this entry can be re-recorded today (only Capture's 6 modes and ⌘K).

        init(id: String, titleKey: String, chord: Chord, scope: Scope, ownerPage: String,
             gateKey: String? = nil, gateDefault: Bool? = nil) {
            self.id = id
            self.titleKey = titleKey
            self.chord = chord
            self.scope = scope
            self.ownerPage = ownerPage
            self.gateKey = gateKey
            self.gateDefault = gateDefault
        }
    }

    // MARK: - Fixed entries

    /// Every shortcut XFinder owns outside of Capture's six per-mode chords (which are read live from
    /// `CaptureController.shortcut(for:)`/`CaptureRules.oneNotchPreset` by the page, since they are user-editable
    /// per mode) and ⌘K (read live from `QuickSearchPanelController`, same reason). This list holds the ones with
    /// no independent per-entry state: fixed chords, and the Finder-keyboard rewrites (three independent toggles,
    /// one chord group each).
    static var fixedEntries: [Entry] {
        [
            Entry(id: "browser.downloads", titleKey: "Mở khay Tải về",
                  chord: Chord(keyCode: 2, modifiers: [.control, .option, .command]),
                  scope: .global, ownerPage: SidebarDestination.fileBrowser.rawValue,
                  gateKey: "fileBrowser.downloadsHotkey", gateDefault: false),
            // Clipboard shelf — ClipboardShelfController.swift
            Entry(id: "clipboard.shelf", titleKey: "Mở Clipboard ở notch hoặc khay nổi (theo Cài đặt Clipboard)",
                  chord: Chord(keyCode: 9, modifiers: [.command, .shift]), // V
                  scope: .global, ownerPage: SidebarDestination.settingsClipboard.rawValue,
                  gateKey: "clipboard.globalHotkey", gateDefault: true),
            Entry(id: "clipboard.shelfAlt", titleKey: "Mở khay Clipboard nổi",
                  chord: Chord(keyCode: 8, modifiers: [.command, .option]), // C
                  scope: .global, ownerPage: SidebarDestination.settingsClipboard.rawValue,
                  gateKey: "clipboard.shelfHotkey", gateDefault: false),
            // Paste Stack — XFinderApp.swift setupGlobalHotkeys(), local-only, always on (no gate key)
            Entry(id: "clipboard.pasteStack", titleKey: "Xếp hàng Paste Stack từ 10 mục gần nhất rồi mở khay nổi",
                  chord: Chord(keyCode: 8, modifiers: [.command, .shift]), // C
                  scope: .whenXFinderFrontmost, ownerPage: SidebarDestination.settingsClipboard.rawValue),

            // Translate vùng chọn — TranslateSelectionController.swift / TranslateSelectionRules.swift
            Entry(id: "translate.selection", titleKey: "Dịch vùng chọn đang có trên màn hình",
                  chord: Chord(keyCode: UInt16(TranslateSelectionRules.keyCodeG), modifiers: [.command, .shift]),
                  scope: .global, ownerPage: SidebarDestination.smartSelect.rawValue,
                  gateKey: TranslateSelectionRules.enabledKey, gateDefault: false),

            // Snap zones — SnapZoneController.swift handleKey(), fixed, 8 chords
            Entry(id: "snap.leftHalf", titleKey: "Bắt dính nửa trái",
                  chord: Chord(keyCode: 123, modifiers: [.control, .option]), scope: .global,
                  ownerPage: SidebarDestination.snapZones.rawValue, gateKey: "snapzones.hotkeysEnabled", gateDefault: true),
            Entry(id: "snap.rightHalf", titleKey: "Bắt dính nửa phải",
                  chord: Chord(keyCode: 124, modifiers: [.control, .option]), scope: .global,
                  ownerPage: SidebarDestination.snapZones.rawValue, gateKey: "snapzones.hotkeysEnabled", gateDefault: true),
            Entry(id: "snap.maximize", titleKey: "Bắt dính toàn màn hình",
                  chord: Chord(keyCode: 126, modifiers: [.control, .option]), scope: .global,
                  ownerPage: SidebarDestination.snapZones.rawValue, gateKey: "snapzones.hotkeysEnabled", gateDefault: true),
            Entry(id: "snap.bottomHalf", titleKey: "Bắt dính nửa dưới",
                  chord: Chord(keyCode: 125, modifiers: [.control, .option]), scope: .global,
                  ownerPage: SidebarDestination.snapZones.rawValue, gateKey: "snapzones.hotkeysEnabled", gateDefault: true),
            Entry(id: "snap.center", titleKey: "Bắt dính giữa màn hình",
                  chord: Chord(keyCode: 36, modifiers: [.control, .option]), scope: .global,
                  ownerPage: SidebarDestination.snapZones.rawValue, gateKey: "snapzones.hotkeysEnabled", gateDefault: true),
            Entry(id: "snap.leftThird", titleKey: "Bắt dính một phần ba trái",
                  chord: Chord(keyCode: 2, modifiers: [.control, .option]), scope: .global,
                  ownerPage: SidebarDestination.snapZones.rawValue, gateKey: "snapzones.hotkeysEnabled", gateDefault: true),
            Entry(id: "snap.centerThird", titleKey: "Bắt dính một phần ba giữa",
                  chord: Chord(keyCode: 3, modifiers: [.control, .option]), scope: .global,
                  ownerPage: SidebarDestination.snapZones.rawValue, gateKey: "snapzones.hotkeysEnabled", gateDefault: true),
            Entry(id: "snap.rightThird", titleKey: "Bắt dính một phần ba phải",
                  chord: Chord(keyCode: 5, modifiers: [.control, .option]), scope: .global,
                  ownerPage: SidebarDestination.snapZones.rawValue, gateKey: "snapzones.hotkeysEnabled", gateDefault: true),

            // Hold ⌘Q — QuitProtectionController.swift, fixed
            Entry(id: "quit.hold", titleKey: "Giữ ⌘Q khoảng 1 giây để thoát",
                  chord: Chord(keyCode: 12, modifiers: [.command]), // Q
                  scope: .global, ownerPage: SidebarDestination.appQuit.rawValue,
                  gateKey: "quitProtection.enabled", gateDefault: false),

            // Switcher — CommandTabController.swift, picker of two fixed choices (chord shown is whichever is
            // active; both labelled here so the page can show the alternative too).
            Entry(id: "switcher.commandTab", titleKey: "Chuyển đổi ứng dụng kèm xem trước cửa sổ",
                  chord: Chord(keyCode: 48, modifiers: [.command]), // Tab
                  scope: .global, ownerPage: SidebarDestination.windowPreview.rawValue,
                  gateKey: "windowPreview.commandTabEnabled", gateDefault: false),

            // Finder keyboard rewrites — FinderKeyboardController.swift, three independent toggles
            Entry(id: "finderKeyboard.cutPaste", titleKey: "Cắt rồi dán trong Finder (⌘X sau đó ⌘V)",
                  chord: Chord(keyCode: 7, modifiers: [.command]), // X
                  scope: .finderOnly, ownerPage: SidebarDestination.finderKeyboard.rawValue,
                  gateKey: "finderKeyboard.cutPaste", gateDefault: false),
            Entry(id: "finderKeyboard.deleteToTrash", titleKey: "Delete chuyển vào Thùng rác trong Finder",
                  chord: Chord(keyCode: 51, modifiers: []), // Delete
                  scope: .finderOnly, ownerPage: SidebarDestination.finderKeyboard.rawValue,
                  gateKey: "finderKeyboard.deleteToTrash", gateDefault: false),
            Entry(id: "finderKeyboard.returnOpens", titleKey: "Return mở mục đang chọn trong Finder",
                  chord: Chord(keyCode: 36, modifiers: []), // Return
                  scope: .finderOnly, ownerPage: SidebarDestination.finderKeyboard.rawValue,
                  gateKey: "finderKeyboard.returnOpens", gateDefault: false),

            // Notes — XFinderApp.swift setupGlobalHotkeys(), local-only, always on (no gate key)
            Entry(id: "notes.new", titleKey: "Ghi chú mới",
                  chord: Chord(keyCode: 45, modifiers: [.command, .option]), // N
                  scope: .whenXFinderFrontmost, ownerPage: SidebarDestination.notes.rawValue),
            Entry(id: "notes.library", titleKey: "Mở trang Ghi chú",
                  chord: Chord(keyCode: 37, modifiers: [.command, .option]), // L
                  scope: .whenXFinderFrontmost, ownerPage: SidebarDestination.notes.rawValue),
            Entry(id: "notes.pin", titleKey: "Ghim hoặc bỏ ghim ghi chú đầu danh sách (chưa lưu trữ)",
                  chord: Chord(keyCode: 35, modifiers: [.command, .option]), // P
                  scope: .whenXFinderFrontmost, ownerPage: SidebarDestination.notes.rawValue),
            // XF-T28 — BrowserSettings.applySettings (Carbon, opt-in)
            Entry(id: "fileBrowser.open", titleKey: "Mở trình duyệt tệp từ mọi app",
                  chord: Chord(keyCode: 3, modifiers: [.control, .option, .command]), // F
                  scope: .global, ownerPage: SidebarDestination.fileBrowser.rawValue,
                  gateKey: "fileBrowser.globalHotkey", gateDefault: false),
            // XF-T24 — EdgeNotesController.syncGlobalHotkey (Carbon, opt-in)
            Entry(id: "notes.summon", titleKey: "Mở ghi chú mép từ mọi app",
                  chord: Chord(keyCode: 45, modifiers: [.control, .option]), // N
                  scope: .global, ownerPage: SidebarDestination.notes.rawValue,
                  gateKey: "notes.globalHotkey", gateDefault: false),
        ]
    }

    /// The chord an entry fires TODAY. Only the switcher varies: it follows `windowPreview.switcherHotkey`
    /// ("commandTab" / "optionTab" — CommandTabController reads it), and the page used to print ⌘Tab whatever the
    /// user had picked (P3 review).
    static func liveChord(of entry: Entry, switcherSetting: String) -> Chord {
        guard entry.id == "switcher.commandTab", switcherSetting == "optionTab" else { return entry.chord }
        return Chord(keyCode: entry.chord.keyCode, modifiers: [.option])
    }

    // MARK: - System conventions

    /// macOS/Cocoa chords this app's shortcuts can collide with, but does not own. `reserved` reuses
    /// `CaptureRules.systemReserved` verbatim (both Foundation-only, both symlinked) rather than re-typing the
    /// same five chords a second time, which would drift the moment one file changed. `other` lists the two
    /// system/app conventions no engine file already tracks.
    struct SystemConvention: Equatable {
        let chord: Chord
        let nameKey: String
        /// A "Find Next" collision is a naming convention, not a Reserved-by-the-OS fact — the page shows it as
        /// a WARNING, never the same wording as a true system-reserved clash.
        let isConventionOnly: Bool
    }

    static var systemConventions: [SystemConvention] {
        var list: [SystemConvention] = CaptureRules.systemReserved.map {
            SystemConvention(chord: Chord(keyCode: UInt16($0.shortcut.keyCode),
                                           modifiers: captureModifiers($0.shortcut)),
                              nameKey: $0.nameKey, isConventionOnly: false)
        }
        list.append(SystemConvention(chord: Chord(keyCode: 49, modifiers: [.command]), // Space
                                      nameKey: "Spotlight của macOS", isConventionOnly: false))
        list.append(SystemConvention(chord: Chord(keyCode: UInt16(TranslateSelectionRules.keyCodeG), modifiers: [.command, .shift]),
                                      nameKey: "Find Next (quy ước Sửa ▸ Tìm ▸ Tìm tiếp của macOS/Cocoa)",
                                      isConventionOnly: true))
        return list
    }

    private static func captureModifiers(_ s: CaptureShortcut) -> Modifiers {
        var m: Modifiers = []
        if s.hasCommand { m.insert(.command) }
        if s.hasOption { m.insert(.option) }
        if s.hasControl { m.insert(.control) }
        if s.hasShift { m.insert(.shift) }
        return m
    }

    // MARK: - Conflicts

    struct ConflictResult: Equatable {
        /// Other XFinder owners (page rawValue) sharing this exact chord, excluding `owner` itself.
        let owners: [String]
        /// System/app conventions sharing this chord. `isWarningOnly` mirrors `SystemConvention.isConventionOnly`
        /// for the FIRST matching convention (there is at most one match per chord in this table).
        let conventions: [SystemConvention]

        var isEmpty: Bool { owners.isEmpty && conventions.isEmpty }
    }

    /// Who else is holding `chord` right now. `owner` never conflicts with itself (an entry re-recorded to its
    /// own current chord is not a clash). `recorded` carries each OTHER owner's chord (by id, so two Capture
    /// modes or Capture + ⌘K can both be checked); `isActive` decides whether an inactive entry still counts —
    /// a shortcut whose feature is off cannot actually fire, so it is not a real clash.
    static func conflicts(for chord: Chord, owner: String, recorded: [String: Chord], isActive: (String) -> Bool) -> ConflictResult {
        var owners: [String] = []
        for (otherID, otherChord) in recorded where otherID != owner && otherChord == chord && isActive(otherID) {
            owners.append(otherID)
        }
        let conventions = systemConventions.filter { $0.chord == chord }
        return ConflictResult(owners: owners, conventions: conventions)
    }
}
