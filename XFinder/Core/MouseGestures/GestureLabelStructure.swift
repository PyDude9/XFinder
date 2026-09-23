import Foundation

// The **sentence structure** of every gesture string that is assembled at runtime,
// with the words left out.
//
// Why this is separate from `L10n.swift`
// -------------------------------------
// `L10n.swift` imports SwiftUI, so the test package cannot compile it. That made a
// real hole: the button numbering (`n + 1`) and the heading assembly
// (`<button>: <motion>`) lived there, so no test could reach them and a mutation
// injected into either one stayed **green**. The mutation harness reported exactly
// that —
//
//     M1 invented physical button names: *** STAYED GREEN ***
//     M2 heading omits the held button:   *** STAYED GREEN ***
//     M5 button name drops the number offset: *** STAYED GREEN ***
//
// — which is a hole in the *gates*, not just a missing test. So the structure moved
// here: this file imports nothing but Foundation, is symlinked into the test
// package, and every one of those three mutations now goes red.
//
// The split is: this file decides **which key** a value resolves to and **how the
// pieces join**; `L10n.t` decides what those keys say in the current language.
// Nothing here contains a translatable sentence, so nothing here can leak a
// language.

/// Which store key a `ButtonKey` resolves to, and the separator used when an
/// un-named button's number is appended.
///
/// The numbering is load-bearing and was reported by the user: macOS numbers mouse
/// buttons from **0** (left click is button 0), people count from **1**. Off by one
/// here and every number on the page is wrong.
enum ButtonLabelStructure {
    /// The separator between the `"Nút "` fragment and the appended number. Kept as
    /// a named constant so the fragment's trailing space and this string cannot
    /// drift apart.
    static let fragmentGap = ""

    /// `"Nút "` — a *fragment*, so it carries its trailing space. The English is
    /// `"Button "` with the same shape.
    static let numberedPrefixKey = "Nút "

    /// The buttons every mouse shares, with the short factual note each one carries.
    /// Keyed by the **macOS** button number, not the user-facing one.
    ///
    /// macOS numbers mouse buttons from 0, so the labels below describe button 0, 1
    /// and 2. The previous version of this table had two defects, and both were
    /// visible to the user:
    ///
    /// 1. It labelled button 2 (the middle/wheel click) "Nút 3 (bấm con lăn xuống)"
    ///    — combining the *user-facing* number with a description of a different
    ///    physical button. macOS's button 2 IS the wheel, so the pairing happened to
    ///    read acceptably, but the number was the display number, not the stored one,
    ///    which is what made the table impossible to reason about.
    /// 2. The note was a Vietnamese sentence declared "language-neutral", so it was
    ///    returned verbatim in the English UI. The notes are now ordinary translatable
    ///    sentences.
    ///
    /// Notes describe **where the button is**, because that is the question the user
    /// actually asked ("Which button of the mouse do I use?") — not what macOS calls
    /// it.
    static func namedKey(forButtonNumber n: Int) -> String? {
        switch n {
        case 0: return "Nút trái"
        case 1: return "Nút phải"
        case 2: return "Bấm con lăn xuống"
        default: return nil
        }
    }

    /// Buttons that exist on most multi-button mice but that no macOS API can
    /// distinguish by position. Shown as a hint under the number so the user can map
    /// "Button 4" onto a physical spot on their own mouse.
    ///
    /// This is a *hint*, never a claim: the index comes from the HID descriptor's
    /// declaration order, and a descriptor proves a button exists — not where it sits.
    /// That is why the page still offers Record, and why the wording says "usually".
    static func hintKey(forButtonNumber n: Int) -> String? {
        switch n {
        case 3: return "thường là nút hông trên (gần con lăn)"
        case 4: return "thường là nút hông dưới (ngón cái)"
        default: return nil
        }
    }

    /// The number a user sees for a macOS button number. Exposed so a test can pin
    /// the offset directly rather than inferring it from a rendered string.
    static func displayNumber(forButtonNumber n: Int) -> Int { n + 1 }

    /// The two halves of a hold-direction heading, as keys.
    ///
    /// A separate type because the heading is the one string where the *join*
    /// matters: it names the held button and the motion, and printing the button on
    /// every arm instead of once is the L1 bug the user reported.
    enum HeadingStructure {
        /// Between the button name and the motion — e.g. `"Button 3: pull up"`.
        static let separator = ": "

        /// Which keys compose the heading for a direction, plus the button number to
        /// append when the key is the interpolated prefix.
        ///
        /// Returning the number here rather than re-deriving it at the call site is
        /// deliberate: `L10n` must not know how button numbers map, or the offset
        /// would exist in two places and one of them would eventually be wrong.
        static func parts(for direction: GestureDirection,
                          trigger: TriggerSource) -> ButtonParts {
            if GestureTriggerKind.isTilt(direction) {
                return ButtonParts(buttonKey: nil, appendNumber: nil, motionKey: direction.titleKey)
            }
            switch trigger {
            case .mouseButton(let n):
                if let named = ButtonLabelStructure.namedKey(forButtonNumber: n) {
                    return ButtonParts(buttonKey: named, appendNumber: nil,
                                       motionKey: direction.motionHintKey)
                }
                return ButtonParts(buttonKey: ButtonLabelStructure.numberedPrefixKey,
                                   appendNumber: ButtonLabelStructure.displayNumber(forButtonNumber: n),
                                   motionKey: direction.motionHintKey)
            case .modifierKey:
                // No key and no number: a modifier trigger is not a button, so it
                // cannot contribute a button half to the heading at all.
                return ButtonParts(buttonKey: nil, appendNumber: nil,
                                   motionKey: direction.motionHintKey)
            }
        }
    }
}

/// The resolved pieces of a heading, with no words in them.
struct ButtonParts: Equatable, Sendable {
    /// The store key for the button half, or `nil` when this heading has none
    /// (tilt, and modifier triggers).
    var buttonKey: String?
    /// The user-facing number to append after `buttonKey`, when the key is the
    /// interpolated prefix fragment.
    var appendNumber: Int?
    /// The store key for the motion half.
    var motionKey: String
}
