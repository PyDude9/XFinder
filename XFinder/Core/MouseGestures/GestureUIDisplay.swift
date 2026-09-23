import Foundation

// Pure UI logic for the "Chuột & cử chỉ" page, kept out of the View struct so it
// can be tested without AppKit.
//
// Why these live here and not inline in `MouseDiagramView`: a SwiftUI view's
// `@State` mutation inside a closure cannot be exercised by a test, and the old
// version of this page had *no* selection state at all — which is why every
// direction resolved correctly while the page still looked empty. Putting the
// state transition in a named pure function makes the interaction itself
// assertable.
//
// What is deliberately NOT here any more
// --------------------------------------
// This file used to be symlinked into the test package and to expose
// `title(_:trigger:)`, which rendered a heading. That was the language leak: a
// heading is a *sentence*, and this file cannot see `L10n` (it is symlinked into a
// plain-Foundation test bundle). The heading therefore came out in Vietnamese and
// the call site's `L10n.t(...)` wrapped an already-rendered string, which can
// never match a key — so the English page showed Vietnamese and every check
// stayed green.
//
// The single spelling now lives on the model as semantic keys
// (`GestureDirection.titleKey` / `.motionKey` / `.motionHintKey`), and the app
// resolves them through `L10n.t`. The pure classification that *is* testable —
// "is this a tilt direction" — moved onto `GestureTriggerKind` in the model, so
// the model file now holds both spellings and this one holds none.
//
// The only thing left is the arrow-click state machine, which is UI logic with no
// text in it at all.

/// The arrow-click state machine driving `MouseDiagramView.selection`.
enum MouseDiagramSelection {
    /// Clicking an arm of the diagram.
    ///
    /// This is a *toggle*, not a radio selection: clicking the arm that is already
    /// open closes it, so the detail panel can be dismissed without hunting for an
    /// X. Clicking a different arm moves the highlight.
    static func afterClick(current: GestureDirection?, clicked: GestureDirection) -> GestureDirection? {
        current == clicked ? nil : clicked
    }

    /// Switching the app in the picker always starts with nothing highlighted.
    ///
    /// Keeping the previous arm would leave the detail panel describing a
    /// direction as it was mapped for the *previous* app — the panel would show
    /// the right keys for the wrong application, which is worse than showing none.
    static func afterProfileChange() -> GestureDirection? { nil }
}
