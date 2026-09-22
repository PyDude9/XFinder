import Foundation

// Pure UI logic for the "Chuột & cử chỉ" page, kept out of the View struct so it
// can be tested without AppKit.
//
// Why these live here and not inline in `MouseDiagramView`: a SwiftUI view's
// `@State` mutation inside a closure cannot be exercised by a test, and the old
// version of this page had *no* selection state at all — which is why every
// direction resolved correctly while the page still looked empty. Putting the
// state transition in a named pure function makes the interaction itself
// assertable. The tests compile this exact file (see Tests/XFinderLogicTests).

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

/// Headings shown in `GestureDetailPanel`. Plain Vietnamese sentences with no
/// AppKit dependency, so the view and the tests agree on exactly one spelling.
///
/// These deliberately spell out the physical motion in capitals ("Kéo LÊN")
/// because the user reported the bare `↑` arrow was not enough to know which
/// button to hold or which way to move.
enum GestureDirectionDisplay {
    static func title(_ direction: GestureDirection) -> String {
        switch direction {
        case .up: return "Kéo LÊN"
        case .down: return "Kéo XUỐNG"
        case .left: return "Kéo SANG TRÁI"
        case .right: return "Kéo SANG PHẢI"
        case .tiltLeft: return "Nghiêng con lăn TRÁI"
        case .tiltRight: return "Nghiêng con lăn PHẢI"
        }
    }

    /// Whether this direction is performed by tilting the wheel rather than
    /// holding the trigger button. Used to hide the tilt arms when the feature is
    /// off, instead of drawing a control that does nothing.
    static func isTilt(_ direction: GestureDirection) -> Bool {
        direction == .tiltLeft || direction == .tiltRight
    }

    /// "Raw horizontal scroll" is only a meaningful choice for the tilt arms; the
    /// four button-drag arms always send a keystroke or nothing.
    static func supportsHorizontalScroll(_ direction: GestureDirection) -> Bool {
        isTilt(direction)
    }
}
