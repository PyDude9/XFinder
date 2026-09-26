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

/// The shape of the mouse on the diagram: its silhouette and its thumb rest, as plain
/// numbers.
///
/// ── Why the outline is data, in a Foundation-only file (PATCH v10.1 R2) ───────────────
/// The figure used to be a `RoundedRectangle` whose corner radius was almost half its
/// width — i.e. a **pill**, which is the Magic Mouse silhouette. On the Razer Basilisk this
/// feature was built for, that figure said "this mouse has no side controls", and the user
/// said so twice: *"mặc định giao diện này là Magic Mouse nên chỉ có 4 nút 4 hướng, chứ ko
/// phải smart mouse"*.
///
/// Two properties make the difference, and both are **numbers**, not drawing calls, so they
/// can be asserted in the test package:
///
///  1. the outline is **not a circle** — its widest point on the left and its widest point
///     on the right sit at *different heights*. That offset is the thumb rest, and it is
///     the one thing a pill cannot have;
///  2. the thumb rest is in the **lower-left**, not centred, because that is where a thumb
///     actually is on a mouse with side buttons.
///
/// `MouseDiagramView` turns these into a smooth closed curve. Nothing here is a claim about
/// the user's hardware: no macOS API reports where a physical button sits, so this is a
/// *drawing schema* — the chips' positions on it, and the list's measured declaration, are
/// the parts that carry information.
enum MouseFigureOutline {
    /// One outline vertex, as a fraction of the drawing rect. Origin is the top-left, so
    /// `y` grows towards the palm and `x` grows to the right.
    struct Point: Equatable, Sendable {
        var x: Double
        var y: Double
    }

    /// A rounded region of the body, in the same fractions.
    struct Region: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var centre: Point { Point(x: x + width / 2, y: y + height / 2) }
    }

    /// The silhouette, clockwise from the front centre.
    ///
    /// The front two vertices are deliberately far enough apart that the two main-button
    /// chips still land on the body: those chips are 46 pt wide on a 116 pt body, so a
    /// narrow "nose" would leave them floating in mid-air, which is a worse drawing than a
    /// blunt front. `MouseFigureTests` pins that blunt front.
    static let points: [Point] = [
        Point(x: 0.500, y: 0.010),   // front centre
        Point(x: 0.750, y: 0.018),
        Point(x: 0.955, y: 0.040),   // right front shoulder
        Point(x: 0.995, y: 0.130),
        Point(x: 1.000, y: 0.280),   // widest on the RIGHT — upper half
        Point(x: 0.985, y: 0.470),
        Point(x: 0.930, y: 0.680),
        Point(x: 0.830, y: 0.880),
        Point(x: 0.640, y: 0.980),
        Point(x: 0.400, y: 0.995),   // rear centre
        Point(x: 0.200, y: 0.945),
        Point(x: 0.055, y: 0.870),
        Point(x: 0.005, y: 0.720),
        Point(x: 0.000, y: 0.640),   // widest on the LEFT — lower half (thumb rest)
        Point(x: 0.010, y: 0.470),
        Point(x: 0.040, y: 0.250),
        Point(x: 0.045, y: 0.040),   // left front shoulder
        Point(x: 0.250, y: 0.018),
    ]

    /// The leftmost vertex. Its `y` is the thumb rest's height.
    static var leftMost: Point { points.min { $0.x < $1.x } ?? Point(x: 0, y: 0.5) }

    /// The rightmost vertex. Its `y` is the palm's flare height.
    static var rightMost: Point { points.max { $0.x < $1.x } ?? Point(x: 1, y: 0.5) }

    /// The seam between the two main buttons, as body fractions. It runs from the front of
    /// the body down to the base of the wheel, which is what makes the figure read as a
    /// mouse with two buttons instead of a blank shell.
    static let seamTopY: Double = 0.030
    static let seamBottomY: Double = 0.330

    /// The thumb rest, as a rounded region. Three controls sit on it (the two side buttons
    /// and the Sniper), and it is in the lower-left on purpose — a centred panel would be a
    /// decoration, while a lower-left one is where a thumb rests.
    static let thumbRest = Region(x: 0.020, y: 0.400, width: 0.480, height: 0.380)
}

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

    /// Clicking one of the mouse's controls on the drawing.
    ///
    /// The same toggle shape as `afterClick`, and for the same reason: clicking the chip
    /// that is already selected clears it. Kept as its own function so the two selections
    /// (a *direction* and a *control*) cannot be accidentally fed into each other's state —
    /// they are different types and the overload would otherwise invite a mix-up.
    static func afterButtonClick(current: Int?, clicked: Int) -> Int? {
        current == clicked ? nil : clicked
    }
}

/// What the tilt switch on the page writes.
///
/// ── The bug this exists to prevent ───────────────────────────────────────────────────
/// The page had **one** switch, and it wrote `GestureConfiguration.tiltAvailable`, which
/// only controls whether the two arms are *drawn*. The engine reads
/// `GestureConfiguration.tiltEnabled`, which nothing ever set. So a user could reveal the
/// arms, assign an action to `tiltLeft`, and the action could never fire — a control whose
/// label promised something it could not do, which is the failure mode AGENTS.md Part 0 §6
/// forbids and the reason `Part 3b` keeps a register of stored-but-unread keys.
///
/// The two fields stay **separate in the model** (`MouseGestureTests` pins that, and
/// `GestureController.Envelope` recovers both from older payloads). What this type fixes is
/// the *view's* write: one switch the user flips must produce both effects, because
/// "revealed but disabled" is not a state a person can have any use for.
///
/// It lives here, in the Foundation-only half, so the contract is testable — a SwiftUI
/// binding's closure cannot be.
enum TiltArmsVisibility {
    /// The two fields the reveal switch must write, as plain values.
    ///
    /// Turning the arms on writes **both**; turning them off writes both off, so a user who
    /// changes their mind does not leave the engine intercepting discrete horizontal wheel
    /// events for arms they can no longer see.
    static func fields(forReveal reveal: Bool) -> (available: Bool, enabled: Bool) {
        (available: reveal, enabled: reveal)
    }

    /// Whether the two tilt arms are **actually live**, read from the two stored fields.
    ///
    /// ── Why the read side needs a contract too (found 2026-09-24) ───────────────────────
    /// `fields(forReveal:)` fixes what the *switch writes*, but it cannot fix what an older
    /// payload already holds. Measured on this machine's own store:
    ///
    ///     tiltAvailable: true, tiltEnabled: false
    ///
    /// — a state the current UI can no longer produce, left behind by the build where the
    /// switch wrote only `tiltAvailable`. Reading `tiltAvailable` alone drew the two arms and
    /// showed the switch **on**, while the engine was switched off: the same "control that
    /// cannot do what its label says" the write-side contract exists to prevent, one layer
    /// down. The conjunction is the honest read — an arm is live only if both fields say so —
    /// and it needs no migration, because a payload that disagrees with itself simply reads
    /// as off until the user turns the switch on again.
    static func isLive(available: Bool, enabled: Bool) -> Bool {
        available && enabled
    }
}
