import Foundation

/// The decision rules for "clear the clipboard N seconds after a copy".
///
/// The job: *"I copied something sensitive (a token, a one-time code); it must not sit on the
/// clipboard all afternoon."* Pure Foundation so the rules are pinned by tests — the part that
/// can silently destroy user data is the guard, not the timer.
///
/// Three rules this type exists to hold:
///
/// 1. **Never clear something the user copied later.** The timer remembers the pasteboard
///    `changeCount` it was armed for and clears only if it is *still* that count. A second copy
///    moves the count, so the first timer does nothing — and the manager also re-arms for the
///    second copy.
/// 2. **Never clear an already-empty pasteboard.** `clearContents()` bumps `changeCount`, and a
///    monitor that arms a timer for every change would then arm one for its *own* clear and loop
///    forever, clearing an empty clipboard every N seconds.
/// 3. **Off means no timer at all** — `delay(forSetting:)` is `nil` for 0, so the disabled path
///    allocates nothing and the app's 0 % idle CPU rule is untouched. It is one-shot: no polling.
enum ClipboardAutoClear {

    /// Offered in the picker, in order. 0 is "off". Anything else a hand-edited
    /// `defaults write` supplies is still honoured by `delay(forSetting:)`.
    static let choices: [Int] = [0, 30, 60, 300, 900]

    /// Floor for a hand-edited value: a 1-second clear would race the user's own paste.
    static let minimumDelay: TimeInterval = 5

    /// Seconds to wait, or `nil` when auto-clear is off (setting ≤ 0).
    static func delay(forSetting seconds: Int) -> TimeInterval? {
        guard seconds > 0 else { return nil }
        return max(minimumDelay, TimeInterval(seconds))
    }

    /// Whether the armed timer may clear the pasteboard *now*.
    static func shouldClear(armedChangeCount: Int, currentChangeCount: Int, pasteboardIsEmpty: Bool) -> Bool {
        armedChangeCount == currentChangeCount && !pasteboardIsEmpty
    }

    /// Whether a change is worth arming a timer for at all (rule 2).
    static func shouldArm(setting seconds: Int, pasteboardIsEmpty: Bool) -> Bool {
        delay(forSetting: seconds) != nil && !pasteboardIsEmpty
    }
}
