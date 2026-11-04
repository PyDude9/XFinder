import Foundation

/// XF-T30 W4 — remappable browser shortcuts (FileOctopus Settings ▸ Keyboard): two bindings per command, three
/// profiles, validation, conflicts, JSON import/export that is data only. Pure, symlinked into the test package.
/// Contract XF-T30-w4 §2.
enum KeyProfile: String, Codable, CaseIterable, Sendable {
    case finder, explorer, commander, custom
}

enum MouseBackForward: String, Codable, CaseIterable, Sendable { case on, off, swapped }

struct KeyBinding: Codable, Equatable, Sendable {
    var primary: KeyChord?
    var extra: KeyChord?

    static let empty = KeyBinding(primary: nil, extra: nil)
}

struct KeyBindings: Codable, Equatable, Sendable {
    var profile: KeyProfile = .finder
    /// Only commands that differ from the profile's defaults are stored.
    var overrides: [String: KeyBinding] = [:]
    var tabSwitchesPanes = false
    var mouse: MouseBackForward = .on

    enum Rejection: Equatable, Sendable { case needsCommandOrControl, reservedBySystem, reservedByViews }
    enum ImportError: Equatable, Sendable { case unreadable, unknownCommand(String), keyUsedTwice(String), reservedKey(String) }
    /// Every problem found in an imported file, all at once (nothing is applied when any exists).
    struct ImportFailure: Error, Equatable, Sendable { let errors: [ImportError] }

    // MARK: - Profile tables (contract §2: Windows Explorer / Total Commander bulk rebinds)

    /// Reserved-by-views keys (Return/Space/Tab/arrows/F2) a profile is allowed to assign away from their usual
    /// meaning, keyed by the chord each profile actually binds there — `validate` consults this so e.g. Windows
    /// Explorer's bare `Return` (open) and Total Commander's bare `Tab` (switch panes) are not rejected by the
    /// very rule a profile exists to override, while an identical chord typed as a CUSTOM override under the
    /// Finder profile is still refused.
    private static func profileAllowedReserved(_ profile: KeyProfile) -> Set<KeyChord> {
        switch profile {
        case .finder, .custom: return []
        case .explorer: return [KeyChord("return"), KeyChord("f2")]
        case .commander: return [KeyChord("tab"), KeyChord("return"), KeyChord("f2")]
        }
    }

    /// Per-profile overrides layered on top of `BrowserCommands`' Finder defaults (contract §2 / spec §5.2).
    private static func profileTable(_ profile: KeyProfile) -> [BrowserCommand: KeyBinding] {
        switch profile {
        case .finder, .custom:
            return [:]
        case .explorer:
            return [
                .open: KeyBinding(primary: KeyChord("return"), extra: nil),
                .rename: KeyBinding(primary: KeyChord("f2"), extra: nil),
                .cut: KeyBinding(primary: KeyChord("x", command: true), extra: nil),
                // "Delete does not move to Trash" (contract §2) — ⌘⌫ (moveToTrash's Finder chord) is unbound here;
                // Windows Explorer habits leave the bare Delete key alone (it is not a BrowserCommand chord at all).
                .moveToTrash: KeyBinding(primary: nil, extra: nil),
            ]
        case .commander:
            return [
                .copyToOtherPane: KeyBinding(primary: KeyChord("f5"), extra: nil),
                .moveToOtherPane: KeyBinding(primary: KeyChord("f6"), extra: nil),
                .newFolder: KeyBinding(primary: KeyChord("f7"), extra: nil),
                .moveToTrash: KeyBinding(primary: KeyChord("f8"), extra: nil),
                .open: KeyBinding(primary: KeyChord("return"), extra: nil),
                // Rename moves off bare Return (Total Commander's own convention, like Windows Explorer's) onto F2
                // so it never collides with `.open`'s own Return above — the Finder default binds BOTH `.rename`
                // and (via `openExtra`) effectively the same key family to Return, which only works because Finder
                // itself never rebinds `.open`'s primary away from ⌘O.
                .rename: KeyBinding(primary: KeyChord("f2"), extra: nil),
                // Tab switches panes is a separate boolean (`tabSwitchesPanes`), not a per-command chord — Tab is
                // not a `BrowserCommand` binding so there is nothing to list here for it.
            ]
        }
    }

    /// Chords the system itself reserves regardless of profile (Mission Control, Hide, Minimize, Quit, app
    /// switcher, Spotlight, input-source switch) — never assignable to any browser command.
    private static let systemReserved: Set<KeyChord> = [
        KeyChord("q", command: true),
        KeyChord("h", command: true),
        KeyChord("m", command: true),
        KeyChord("tab", command: true),
        KeyChord("space", command: true),
        KeyChord("`", command: true),
    ]

    /// Bare keys the file-list views reserve for their own built-in meaning (rename-via-Return, Quick Look via
    /// Space, focus traversal via Tab/arrows, Finder's own rename-via-F2 convention) — refused as a REBIND target
    /// unless the active profile explicitly claims that exact chord (`profileAllowedReserved`).
    private static let viewReserved: Set<KeyChord> = [
        KeyChord("return"), KeyChord("space"), KeyChord("tab"),
        KeyChord("left"), KeyChord("right"), KeyChord("up"), KeyChord("down"),
        KeyChord("f2"),
    ]

    private static let functionKeys: Set<String> = Set((1...12).map { "f\($0)" })

    // MARK: - Lookup

    /// `open`'s extra chord (⌘↓, Finder's own "open" convention) is fixed and not part of any profile's bulk
    /// rebind table or `BrowserCommands.table` (which only stores one chord per command) — `BrowserCommands`
    /// itself recognizes it separately via `openSecondary` (XF-T28 contract §2: "⌘↓ là chord phụ của open"). It
    /// survives every profile/override combination so `command(for: ⌘↓) == .open` always holds, matching the
    /// base contract's required-chords table.
    private static let openExtra = KeyChord("down", command: true)

    /// The binding a command has under this profile + overrides (contract: "mặc định từ BrowserCommands").
    func binding(for command: BrowserCommand) -> KeyBinding {
        if let override = overrides[command.rawValue] { return override }
        if let profileBinding = Self.profileTable(profile)[command] {
            if command == .open, profileBinding.extra == nil {
                return KeyBinding(primary: profileBinding.primary, extra: Self.openExtra)
            }
            return profileBinding
        }
        if command == .quickOpen {
            let primary = BrowserCommands.chord(for: command)
            let extra = KeyChord("p", command: true, control: true)
            let explicitlyClaimed = overrides.filter { $0.key != command.rawValue }.values
            return KeyBinding(primary: explicitlyClaimed.contains { $0.primary == primary || $0.extra == primary } ? nil : primary,
                              extra: explicitlyClaimed.contains { $0.primary == extra || $0.extra == extra } ? nil : extra)
        }
        if command == .open {
            return KeyBinding(primary: BrowserCommands.chord(for: command), extra: Self.openExtra)
        }
        return KeyBinding(primary: BrowserCommands.chord(for: command), extra: nil)
    }

    /// The command a chord fires (primary or extra across every command), or nil if unbound. Replaces
    /// `BrowserCommands.command(for:)` at the dispatcher (contract §2) so remapped/profile chords are honored.
    func command(for chord: KeyChord) -> BrowserCommand? {
        for command in BrowserCommand.allCases {
            let b = binding(for: command)
            if b.primary == chord || b.extra == chord { return command }
        }
        return nil
    }

    /// The command already holding `chord` in either slot, excluding `command` itself — the UI asks "Use Anyway"
    /// before `assign` transfers the key away from it.
    func conflict(for chord: KeyChord, excluding command: BrowserCommand) -> BrowserCommand? {
        for other in BrowserCommand.allCases where other != command {
            let b = binding(for: other)
            if b.primary == chord || b.extra == chord { return other }
        }
        return nil
    }

    // MARK: - Validation

    /// nil = allowed. A reserved-by-views chord is allowed when the ACTIVE profile is the one that claims it
    /// (so re-validating Windows Explorer's own `Return → open` or Total Commander's own `Tab` never fails), but a
    /// custom rebind attempting to reuse a view-reserved chord under a profile that does not claim it is refused.
    /// `viewReserved`'s own members (Return/Space/Tab/arrows/F2) are BARE by nature — Finder's own "Return renames"
    /// never carries ⌘/⌃ — so they are checked, and can be allowed, before the "needs ⌘ or ⌃" rule, which otherwise
    /// would reject every one of them before the view-reserved branch is ever reached.
    func validate(_ chord: KeyChord) -> Rejection? {
        if Self.systemReserved.contains(chord) { return .reservedBySystem }
        if Self.viewReserved.contains(chord) {
            return Self.profileAllowedReserved(profile).contains(chord) ? nil : .reservedByViews
        }
        let isFunctionKey = Self.functionKeys.contains(chord.key)
        if !chord.command && !chord.control && !isFunctionKey {
            return .needsCommandOrControl
        }
        return nil
    }

    // MARK: - Mutation

    /// Assigns `chord` (or clears the slot when nil) to `command`'s primary or extra binding. Does not itself
    /// validate or check conflicts — callers run `validate`/`conflict(for:excluding:)` first and the UI confirms
    /// "Use Anyway"; `assign` is the step that actually moves the key, stripping it from whatever other command
    /// held it so the invariant "a chord fires at most one command" (contract §2) never breaks.
    mutating func assign(_ chord: KeyChord?, to command: BrowserCommand, extra: Bool) {
        if let chord {
            for other in BrowserCommand.allCases where other != command {
                var b = binding(for: other)
                var changed = false
                if b.primary == chord { b.primary = nil; changed = true }
                if b.extra == chord { b.extra = nil; changed = true }
                if changed { overrides[other.rawValue] = b }
            }
        }
        var mine = binding(for: command)
        if extra { mine.extra = chord } else { mine.primary = chord }
        overrides[command.rawValue] = mine
    }

    /// Reverts one command to the active profile's own default (removing any override for it).
    mutating func restoreDefault(_ command: BrowserCommand) {
        overrides.removeValue(forKey: command.rawValue)
    }

    /// Reverts every command to the active profile's defaults, keeping the profile itself and the two mouse/tab
    /// options untouched.
    mutating func restoreAllDefaults() {
        overrides.removeAll()
    }

    /// Switches to `profile`'s bulk rebind, clearing prior per-command overrides (contract: "áp hồ sơ rồi vẫn sửa
    /// được" — the table stays freely editable afterward, it just starts from the new profile's defaults) and
    /// setting `tabSwitchesPanes` to the profile's own convention (Total Commander: on; otherwise off).
    mutating func apply(_ profile: KeyProfile) {
        self.profile = profile
        overrides.removeAll()
        tabSwitchesPanes = (profile == .commander)
    }

    // MARK: - Export / Import

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }

    /// The full table + the two mouse/tab options, as JSON (contract: "export() -> Data (bảng + 2 tuỳ chọn
    /// chuột)"). `KeyBindings` is already `Codable` end to end, so this is a direct encode — no derived/transient
    /// state to strip.
    func export() -> Data {
        (try? Self.encoder().encode(self)) ?? Data()
    }

    /// Validates the whole file FIRST and reports every problem found — unknown command names, a key (primary or
    /// extra, across all commands including the two profile/system reserved sets) used twice, and reserved keys —
    /// before applying anything. A decode failure (garbage/malicious bytes, wrong shape) is its own error rather
    /// than a crash: `Data` with arbitrary bytes only ever reaches `JSONDecoder`, never code execution (spec R30).
    static func importing(_ data: Data) -> Result<KeyBindings, ImportFailure> {
        guard let raw = try? JSONDecoder().decode(RawImport.self, from: data) else {
            return .failure(ImportFailure(errors: [.unreadable]))
        }

        var errors: [ImportError] = []
        var seenChords: [KeyChord: String] = [:]   // chord -> first command name that claimed it

        func check(_ chord: KeyChord?, commandName: String) {
            guard let chord else { return }
            let candidate = KeyBindings(profile: raw.profile)
            if candidate.validate(chord) != nil {
                errors.append(.reservedKey(commandName))
            }
            if seenChords[chord] != nil {
                errors.append(.keyUsedTwice(commandName))
            } else {
                seenChords[chord] = commandName
            }
        }

        for (name, binding) in raw.overrides {
            guard BrowserCommand(rawValue: name) != nil else {
                errors.append(.unknownCommand(name))
                continue
            }
            check(binding.primary, commandName: name)
            check(binding.extra, commandName: name)
        }

        guard errors.isEmpty else { return .failure(ImportFailure(errors: errors)) }

        let bindings = KeyBindings(
            profile: raw.profile,
            overrides: raw.overrides,
            tabSwitchesPanes: raw.tabSwitchesPanes,
            mouse: raw.mouse
        )
        // Review 2026-10-25: duplicates were only looked for INSIDE the file's overrides, so an override taking a
        // chord that an untouched command still holds by default (⌘C for .duplicate while .copy keeps ⌘C) imported
        // cleanly and left one of them unreachable. Check the EFFECTIVE table the import would produce.
        let clashes: [ImportError] = Self.effectiveClashes(of: bindings, overridden: Set(raw.overrides.keys))
        guard clashes.isEmpty else { return .failure(ImportFailure(errors: clashes)) }
        return .success(bindings)
    }

    /// Every overridden command whose chord (primary or extra) is also held by another command in the effective table.
    private static func effectiveClashes(of bindings: KeyBindings, overridden: Set<String>) -> [ImportError] {
        var holders: [KeyChord: [BrowserCommand]] = [:]
        for command: BrowserCommand in BrowserCommand.allCases {
            let binding: KeyBinding = bindings.binding(for: command)
            for chord: KeyChord in [binding.primary, binding.extra].compactMap({ $0 }) {
                holders[chord, default: []].append(command)
            }
        }
        var reported: Set<String> = []
        var errors: [ImportError] = []
        for (_, commands) in holders where Set(commands).count > 1 {
            for command: BrowserCommand in commands where overridden.contains(command.rawValue) && !reported.contains(command.rawValue) {
                reported.insert(command.rawValue)
                errors.append(.keyUsedTwice(command.rawValue))
            }
        }
        return errors.sorted { String(describing: $0) < String(describing: $1) }
    }

    /// Mirrors `KeyBindings`' own shape so a garbage/partial file still decodes far enough to report WHICH fields
    /// are bad (unknown command names, duplicate/reserved keys) instead of only `.unreadable`. Kept distinct from
    /// `KeyBindings` itself so a future field added to one does not silently change the other's decode behavior.
    private struct RawImport: Codable {
        var profile: KeyProfile = .finder
        var overrides: [String: KeyBinding] = [:]
        var tabSwitchesPanes = false
        var mouse: MouseBackForward = .on
    }
}
