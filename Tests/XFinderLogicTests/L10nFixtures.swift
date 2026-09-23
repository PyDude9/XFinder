import Foundation

/// The **one** place the tests turn a semantic model value into the Vietnamese
/// literal the L10n store is keyed by.
///
/// Why this exists at all: the model deliberately stopped returning display
/// strings. `TriggerSource.label` and `GestureDirection.title(trigger:)` were
/// Vietnamese sentences produced inside `GestureModel.swift`, a pure-Foundation
/// file the test package symlinks — and that is precisely how Vietnamese reached
/// an English UI, because a call site can only translate a string it can match
/// against a key. `L10n.t(trigger.label)` never fired.
///
/// The app resolves these through `L10n.t(_ key: ButtonKey)`. The test bundle
/// cannot import the app target, so this mirrors that resolution — and the tests
/// assert the two agree on the property that matters (numbering, no invented
/// anatomy, exactly one mention). Unlike the old arrangement this is a *fixture*,
/// not production logic: if it drifts, the tests fail, not the app.
enum L10nFixtures {

    /// Whether a string is an *interpolated* heading rather than a plain lookup key.
    ///
    /// Bug shape #2 in `L10nTests`: a key containing a runtime value can never
    /// match a store entry, so `L10n.t` would silently fall back to the Vietnamese
    /// and the English page would show it. The check is written as a named helper
    /// holding the marker in a `Character` so no source line contains the
    /// backslash-paren sequence that Swift reads as an interpolation opener — which
    /// is what made the first two attempts at this assertion un-parseable.
    static func interpolates(_ key: String) -> Bool {
        let opener = Character("\u{5C}")  // backslash
        let next = Character("(")
        guard let index = key.firstIndex(of: opener), key.index(after: index) < key.endIndex else {
            return false
        }
        return key[key.index(after: index)] == next
    }

    /// Mirrors `L10n.t(_ key: ButtonKey)`: the user-facing number is macOS's button
    /// number plus one, and the buttons every mouse shares carry a note naming where
    /// they are. A side button has no nickname (no API can confirm its position)
    /// but does carry a hedged hint.
    static func buttonName(_ code: Int) -> String {
        switch code {
        case 0:  return "Nút trái"
        case 1:  return "Nút phải"
        case 2:  return "Bấm con lăn xuống"
        default: return "Nút \(code + 1)"
        }
    }

    /// The positional hint a side button carries, mirroring
    /// `ButtonLabelStructure.hintKey(forButtonNumber:)`. `nil` for a button we cannot
    /// even guess at, so the fixture cannot invent anatomy the app would not show.
    static func buttonHint(_ code: Int) -> String? {
        switch code {
        case 3: return "thường là nút hông trên (gần con lăn)"
        case 4: return "thường là nút hông dưới (ngón cái)"
        default: return nil
        }
    }

    /// The name of whatever control a trigger refers to. A modifier trigger prints
    /// its own symbols, which are language-neutral — and deliberately never claim a
    /// button number, since a modifier key is not a button.
    static func buttonName(for trigger: TriggerSource) -> String {
        switch trigger {
        case .mouseButton(let code): return buttonName(code)
        case .modifierKey(let flags):
            return GestureShortcut(key: 0, flags: flags).modifierLabel
        }
    }
}
