import Foundation

/// XF-T30 W4 — remappable browser shortcuts (FileOctopus Settings ▸ Keyboard): two bindings per command, three
/// profiles, validation, conflicts, JSON import/export that is data only. Pure, symlinked into the test package.
/// Contract XF-T30-w4 §2. W4 builder (pure): implement.
enum KeyProfile: String, Codable, CaseIterable, Sendable {
    case finder, explorer, commander, custom
}

enum MouseBackForward: String, Codable, CaseIterable, Sendable { case on, off, swapped }

struct KeyBinding: Codable, Equatable, Sendable {
    var primary: KeyChord?
    var extra: KeyChord?
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

    /// The binding a command has under this profile + overrides.
    func binding(for command: BrowserCommand) -> KeyBinding { KeyBinding(primary: BrowserCommands.chord(for: command), extra: nil) }
    /// The command a chord fires (primary or extra), or nil. Replaces `BrowserCommands.command(for:)` at the dispatcher.
    func command(for chord: KeyChord) -> BrowserCommand? { BrowserCommands.command(for: chord) }
    /// nil = allowed.
    func validate(_ chord: KeyChord) -> Rejection? { nil }
    /// The command already holding `chord` (the UI asks "Use Anyway" before `assign`).
    func conflict(for chord: KeyChord, excluding command: BrowserCommand) -> BrowserCommand? { nil }
    mutating func assign(_ chord: KeyChord?, to command: BrowserCommand, extra: Bool) {}
    mutating func restoreDefault(_ command: BrowserCommand) {}
    mutating func restoreAllDefaults() {}
    mutating func apply(_ profile: KeyProfile) {}
    func export() -> Data { Data() }
    /// Validates the whole file first; any error ⇒ nothing applied.
    static func importing(_ data: Data) -> Result<KeyBindings, ImportFailure> { .failure(ImportFailure(errors: [.unreadable])) }
}
