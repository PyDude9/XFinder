import Foundation

/// Reads the user's own `com.apple.symbolichotkeys` and answers one question the
/// Settings page and the engine both need:
///
///   **Which keys is *this* machine actually listening for?**
///
/// ── Why this exists (measured 2026-09-22, corrected the next day) ─────────────────────
/// The Global preset used to *invent* keys: `⌃↑`/`⌃↓` for Mission Control / App Exposé
/// and `⌃←`/`⌃→` for Spaces, on the belief that those are "the macOS keys". Two separate
/// probes showed that belief was wrong, and the user reported exactly what it produces —
/// *"chỉ là xuất hiện và nhận dạng cho có, không làm việc"* (recognised, does nothing):
///
///   * an earlier read showed ids 79–82 ("Move left/right a space") present with
///     `enabled = true` but **no `value` block**, i.e. the switch on with no key
///     assigned — so nothing listened for `⌃←`/`⌃→`;
///   * the same read showed Mission Control (id 32) storing `vk = 232`, an NX
///     *system-defined* keytype with no `CGKeyCode`, so a `CGEvent` could never express it.
///
/// But the later read (after the user reset the shortcut in System Settings) showed the
/// machine **had** assigned ids 32/33 to `⌃↑`/`⌃↓` and 79–82 to `⌃←`/`⌃→`, with the stored
/// modifier mask `0x840000` (`control | maskSecondaryFn`). Both states are legitimate and
/// both occur. **That is the whole point of this type: the preset must not guess which one
/// is in force — it must read it.**
///
/// So the Global preset names an *intent* (`GestureSystemAction`) and the exact keystroke
/// is resolved here, from the user's own settings, at both display and dispatch time.
/// `⌃←` is no longer shipped as a constant anywhere; it is what this host happens to have.
///
/// A binding is reported only when the switch is on **and** a key is assigned. An entry
/// that is `enabled` with no `value` is not a binding, and the page says so rather than
/// promising a keypress the machine will ignore.
enum SpaceBinding {

    /// The symbolic-hotkey ids, taken from the reverse-engineered table that
    /// `/System/Library/PreferencePanes/Keyboard.prefPane` itself uses. Named so a caller
    /// reads intent rather than magic numbers.
    enum Hotkey: Int, CaseIterable {
        case missionControl = 32
        /// App Exposé. A **separate id from Mission Control** (33, not 32), which the
        /// first version of this table missed — so App Exposé could not be resolved even
        /// though the machine had it bound. Found by dumping the ids rather than by
        /// assuming a contiguous block.
        case appExpose = 33
        case showDesktop = 34
        case moveLeftASpace = 79
        /// `⇧⌃←` — macOS stores the "and shift" variants as separate ids. Preferring 79
        /// and falling back to 80 is what lets a machine that only bound the shifted form
        /// still switch Spaces.
        case moveLeftASpaceAlt = 80
        case moveRightASpace = 81
        case moveRightASpaceAlt = 82

        /// Whether this id belongs to a Space move, i.e. one whose absence means
        /// "`⌃←`/`⌃→` will do nothing here".
        var movesASpace: Bool {
            switch self {
            case .moveLeftASpace, .moveLeftASpaceAlt, .moveRightASpace, .moveRightASpaceAlt:
                return true
            case .missionControl, .appExpose, .showDesktop:
                return false
            }
        }
    }

    /// One stored entry, already reduced to the fields that matter.
    struct Entry: Equatable, Sendable {
        var id: Int
        /// `false` means the user switched this shortcut off. A disabled entry is
        /// **not** a binding, so it must read as "unbound" rather than as "bound".
        var enabled: Bool
        /// The virtual keycode, or nil when the entry has no `value` block — the exact
        /// state the Space ids were in on the first read.
        var keyCode: Int?
        /// The modifier bitmask macOS stores (`131072` shift, `262144` control, `8388608`
        /// the secondary-fn mask, …).
        var modifiers: Int?

        /// A binding exists only when the switch is on **and** a key is assigned.
        var isBound: Bool { enabled && keyCode != nil }
    }

    /// Parses the `AppleSymbolicHotKeys` dictionary into the fields the UI asks about.
    ///
    /// Pure, so it is covered by the test package: the parsing is where the two measured
    /// failure modes live (enabled-but-keyless, and `mods` in a non-flag encoding), and a
    /// unit test pins both. The plist read itself is in the app-only extension below.
    static func parse(_ raw: [String: Any]) -> [Entry] {
        var out: [Entry] = []
        for (key, value) in raw {
            guard let id = Int(key), let dict = value as? [String: Any] else { continue }
            // `enabled` is absent on some entries, which means enabled — that is how the
            // OS writes a shortcut the user has never touched. Treating absent as
            // disabled would report a working shortcut as unbound.
            //
            // It arrives as an **integer** (`1`/`0`), not a `Bool`: measured on macOS 27,
            // `id 32` reads `enabled = 1`. `as? Bool` therefore fails for every entry the
            // OS itself wrote, which silently fell through to "enabled" — right by
            // accident for a switch that is on, and wrong for one the user turned **off**.
            // So both representations are accepted explicitly.
            let enabled = Self.bool(dict["enabled"]) ?? true
            let valueDict = dict["value"] as? [String: Any]
            let parameters = valueDict?["parameters"] as? [Any]
            // parameters = [character, virtualKey, modifiers]; `modifiers` is index 2.
            let keyCode = (parameters?.count ?? 0) > 1 ? (parameters?[1] as? Int) : nil
            let modifiers = (parameters?.count ?? 0) > 2 ? (parameters?[2] as? Int) : nil
            out.append(Entry(id: id, enabled: enabled, keyCode: keyCode, modifiers: modifiers))
        }
        return out.sorted { $0.id < $1.id }
    }

    /// Reads a plist boolean that may be stored as `Bool`, `Int`, or a string.
    /// `NSNumber` bridges to `Bool` only when it was *created* as one, so a plist written
    /// by `defaults`/System Settings (which write `1`/`0`) does not match `as? Bool`.
    static func bool(_ any: Any?) -> Bool? {
        switch any {
        case let value as Bool: return value
        case let value as Int: return value != 0
        case let value as NSNumber: return value.boolValue
        case let value as String: return value == "1" || value.lowercased() == "true"
        default: return nil
        }
    }

    /// The entries that move a Space, i.e. the ones whose absence makes `⌃←`/`⌃→` dead.
    static func spaceEntries(_ entries: [Entry]) -> [Entry] {
        entries.filter { entry in
            guard let hotkey = Hotkey(rawValue: entry.id) else { return false }
            return hotkey.movesASpace
        }
    }

    /// Whether **any** Space move is bound by a key. When this is `false`, a gesture that
    /// sends `⌃←`/`⌃→` cannot switch Spaces on this machine, and the page says so.
    static func hasAnySpaceBinding(_ entries: [Entry]) -> Bool {
        spaceEntries(entries).contains { $0.isBound }
    }

    /// The keystroke bound to one symbolic-hotkey id, or nil when that id is switched off
    /// or carries no key. The modifier mask is returned **verbatim**, including the
    /// secondary-fn bit: Apple's own factory encoding for these arrow shortcuts sets it,
    /// so masking it away would post a keystroke the system does not recognise.
    static func boundShortcut(for hotkey: Hotkey, in entries: [Entry]) -> GestureShortcut? {
        guard let entry = entries.first(where: { $0.id == hotkey.rawValue && $0.isBound }),
              let key = entry.keyCode else { return nil }
        // A keycode outside the `CGKeyCode` range is not a key a `CGEvent` can carry, so it
        // must read as **unbound** rather than be posted. The 2026-09-22 read of this
        // machine found id 32 holding `vk = 232` — an NX keytype, not a virtual keycode —
        // and posting that would produce garbage rather than Mission Control. Reporting it
        // unbound is the honest read: the row then says macOS has no shortcut set and points
        // at the pane where one can be set. (The current read has 126 = `↑`, which passes.)
        guard (0...127).contains(key) else { return nil }
        return GestureShortcut(key: UInt16(clamping: key), flags: UInt64(entry.modifiers ?? 0))
    }

    /// The symbolic-hotkey ids that can carry a given system action, **in preference
    /// order**. A Space move has a shifted alternative; the others have one id each.
    static func hotkeys(for action: GestureSystemAction) -> [Hotkey] {
        switch action {
        case .missionControl: return [.missionControl]
        case .appExpose: return [.appExpose]
        case .showDesktop: return [.showDesktop]
        case .previousSpace: return [.moveLeftASpace, .moveLeftASpaceAlt]
        case .nextSpace: return [.moveRightASpace, .moveRightASpaceAlt]
        }
    }

    /// The keystroke this machine uses for a system action, or nil when it is unbound.
    /// Resolved from the user's own settings rather than from a shipped constant — that
    /// is the fix for "recognised but does nothing".
    static func boundShortcut(for action: GestureSystemAction, in entries: [Entry]) -> GestureShortcut? {
        for hotkey in hotkeys(for: action) {
            if let shortcut = boundShortcut(for: hotkey, in: entries) { return shortcut }
        }
        return nil
    }
}

/// The machine's own bindings for the system actions a gesture can dispatch.
///
/// An immutable value, threaded explicitly into the resolver and the engine rather than
/// read from a global — so a test can pass `.empty` and see the honest "not bound on this
/// machine" row instead of a fabricated key, and the engine cannot read a binding that
/// disagrees with what the page displayed.
struct GestureSystemBindings: Equatable, Sendable {
    private let shortcuts: [GestureSystemAction: GestureShortcut]

    /// Nothing bound: what a fresh install with no symbolic hotkeys looks like, and what
    /// the tests use to pin the unbound path.
    static let empty = GestureSystemBindings([:])

    init(_ shortcuts: [GestureSystemAction: GestureShortcut]) {
        self.shortcuts = shortcuts
    }

    /// Resolve every system action from a parsed `com.apple.symbolichotkeys`. Actions the
    /// machine does not bind are simply absent, never defaulted to an invented key.
    init(entries: [SpaceBinding.Entry]) {
        var out: [GestureSystemAction: GestureShortcut] = [:]
        for action in GestureSystemAction.allCases {
            if let shortcut = SpaceBinding.boundShortcut(for: action, in: entries) {
                out[action] = shortcut
            }
        }
        self.shortcuts = out
    }

    /// The keys to post for an action, or nil when this machine does not bind it — in
    /// which case the engine must post **nothing** and say so, rather than guess.
    func shortcut(for action: GestureSystemAction) -> GestureShortcut? { shortcuts[action] }

    var isEmpty: Bool { shortcuts.isEmpty }

    /// The actions this machine has a key for. Used by the page to summarise coverage and
    /// by the tests to assert the alternate ids are honoured.
    var boundActions: [GestureSystemAction] {
        GestureSystemAction.allCases.filter { shortcuts[$0] != nil }
    }
}

#if canImport(AppKit)
import AppKit

extension SpaceBinding {
    /// Reads the user's symbolic hotkeys.
    ///
    /// `UserDefaults(suiteName: "com.apple.symbolichotkeys")` is the documented-in-practice
    /// way to read another app's domain and it works for this domain (unlike
    /// `NSGlobalDomain`, which macOS rejects outright — see the `Claude.md` trap table).
    ///
    /// `synchronize()` is called first for the same reason the appearance read-back needs
    /// it: the defaults cache can hold a stale copy right after the user edits a shortcut
    /// in System Settings, which is exactly the moment the user would open this page.
    static func read() -> [Entry] {
        let suite = "com.apple.symbolichotkeys"
        let defaults = UserDefaults(suiteName: suite)
        CFPreferencesSynchronize(suite as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard let raw = defaults?.dictionary(forKey: "AppleSymbolicHotKeys") else { return [] }
        return parse(raw)
    }

    /// The current bindings, resolved in one call. The page and the engine both go
    /// through this so a displayed key and a dispatched key cannot come from two reads
    /// that disagree.
    static func currentBindings() -> GestureSystemBindings {
        GestureSystemBindings(entries: read())
    }
}
#endif
