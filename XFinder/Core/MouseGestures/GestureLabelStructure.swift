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

    /// The label for a control drawn on the mouse diagram: **the bare number**, always.
    ///
    /// ── Why a number and not “Left click” (measured) ────────────────────────────────
    /// One chip is 46 pt wide. The named form fits for the three shared controls
    /// (`Middle click`) but the Vietnamese name for the wheel — `Bấm con lăn xuống`, 17
    /// characters — does not fit at any size that is still legible, and a chip that
    /// silently truncates its own label is worse than a number that always fits. The
    /// brief asked for a bare number here for the same reason, and the user asked for
    /// buttons to be named by number.
    ///
    /// Nothing is lost: the chip sits **at the position of that control on the mouse**, its
    /// tooltip prints the full name, and the Assigned-buttons list directly below prints it
    /// in a full-width row. The number is the user-facing one (`n + 1`), produced by
    /// `displayNumber(forButtonNumber:)` — the single place that offset is defined, and the
    /// offset that was already wrong once.
    static func compactLabel(forButtonNumber n: Int) -> ButtonLabel {
        return ButtonLabel(key: numberedPrefixKey,
                           appendNumber: displayNumber(forButtonNumber: n))
    }

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

/// The two pieces of a button label, with no words in them: a store key, and the number
/// to append when that key is the interpolated prefix fragment.
///
/// The same shape as `ButtonParts`, but without the motion half — a chip names a control,
/// not a gesture, and reusing `ButtonParts` would force every chip to pretend to have a
/// direction.
struct ButtonLabel: Equatable, Sendable {
    /// The store key: the prefix fragment (`"Nút "`) for the chip form, or a named label
    /// (`"Nút trái"`) when a caller wants the descriptive form.
    var key: String
    /// Set only when `key` is the fragment, because a fragment cannot interpolate.
    var appendNumber: Int?
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

/// The Mouse & Gestures page's ONE status line (T14a): which sentence, decided here so a test can
/// hold it — the page is SwiftUI, which the test package cannot compile.
///
/// `GestureController.recording` is one Bool for BOTH recording modes (`recordTrigger` and
/// `recordShortcut` share `ensureRecordingEngine()`), so the page passes which one it started. T14a's
/// first version said "press a button on the mouse" while a KEYBOARD shortcut was being recorded.
/// The engine takes any key for a shortcut (no modifier required) and Esc (key 53) cancels both modes,
/// which is what the two recording sentences say.
enum GesturePageStatus: Equatable, Sendable {
    case recordingShortcut, recordingButton, off, ready, tapFailure(String), needsAccessibility

    /// Recording outranks everything: it is what the user is doing right now.
    static func of(recording: Bool, recordingShortcut: Bool, enabled: Bool,
                   tapActive: Bool, tapFailure: String) -> GesturePageStatus {
        if recording { return recordingShortcut ? .recordingShortcut : .recordingButton }
        if !enabled { return .off }
        if tapActive { return .ready }
        if !tapFailure.isEmpty { return .tapFailure(tapFailure) }
        return .needsAccessibility
    }

    /// The store key (Vietnamese literal) of the sentence. `tapFailure` carries the controller's own
    /// key, which the page already resolved through `L10n.t` before T14a.
    var textKey: String {
        switch self {
        case .recordingShortcut: return "Đang ghi phím tắt — bấm tổ hợp phím trên bàn phím (Esc để hủy)."
        case .recordingButton: return "Đang ghi — bấm nút trên chuột (Esc để hủy)."
        case .off: return "Cử chỉ đang tắt. Bật công tắc ở góc trên để dùng; sơ đồ bên dưới đã có sẵn phím tắt."
        case .ready: return "Sẵn sàng — các ứng dụng bên dưới đã có phím tắt sẵn, không cần cấu hình thêm."
        case .tapFailure(let key): return key
        case .needsAccessibility: return "Chưa mở được Event Tap — cần quyền Trợ năng. Nhấn “Mở Cài đặt Trợ năng” ở trên."
        }
    }

    var isRecording: Bool { self == .recordingShortcut || self == .recordingButton }
}

/// Which app chip on the Mouse & Gestures page carries the "this is the app in front" dot (T14b review).
///
/// The dot marks the chip whose mapping APPLIES to the frontmost app — the app's own chip when it has
/// one, otherwise Global, which is what the engine falls back to. T14b's first version only ever dotted
/// a chip whose id equalled the frontmost bundle, so for every app without a preset (most apps) no chip
/// was dotted and the page hid which mapping was in force — the wireframe dots Global in that case.
/// No dot when nothing is in front (we cannot name an app) or when that chip is already the selected one
/// (the selection frame says it).
enum GestureAppChooser {
    static func dottedChip(front: String, chipIDs: [String], selected: String, fallback: String) -> String? {
        guard !front.isEmpty else { return nil }
        let governing = chipIDs.contains(front) ? front : fallback
        return governing == selected ? nil : governing
    }
}
