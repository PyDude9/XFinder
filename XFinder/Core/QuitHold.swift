import Foundation

/// The pure core of "hold ⌘Q to quit": which keystroke starts a hold, and what each later
/// event does to it. No AppKit, no CGEvent — raw key codes and flag masks, so every rule below
/// is pinned by a test and none depends on a live event tap.
///
/// The job: *"a stray ⌘Q must not close my work."* A tap of ⌘Q is swallowed; only holding it
/// for the hold duration quits the app that was frontmost when the press began.
///
/// Why this is a state machine and not a few `if`s: a global key tap that gets its state wrong
/// takes the **Q key away system-wide**. Three properties are therefore load-bearing, and each
/// has a test that goes red without it:
///
/// 1. **A missed `keyUp` must not wedge the machine.** The OS can disable a tap by timeout and
///    drop events; if a `holding`/`fired` machine then waited forever for a `keyUp`, every Q
///    press would be swallowed until relaunch. So a fresh (non-repeat) press always begins a
///    new hold, whatever state the machine thought it was in.
/// 2. **Holding on after a quit must not cascade.** When the target app terminates, the next app
///    becomes frontmost while the key is still down. Auto-repeat presses in `fired` are swallowed
///    and never begin another hold, so one long hold quits exactly one app.
/// 3. **A press the machine did not see start is not a hold.** An auto-repeat `keyDown` while
///    `idle` (feature enabled mid-hold, tap re-armed) passes through untouched.
/// 4. **Cancelling must outlast the key.** After Esc the user is still holding Q and auto-repeat
///    continues; those repeats are swallowed (`cancelled`) until Q is released, or Esc would
///    "cancel" and then quit the app on the very next repeat.
enum QuitHold {

    // MARK: Keys and modifiers (raw values, identical to CGKeyCode / CGEventFlags)

    static let keyCodeQ = 12
    static let keyCodeEscape = 53

    static let maskShift: UInt64 = 0x0002_0000
    static let maskControl: UInt64 = 0x0004_0000
    static let maskAlternate: UInt64 = 0x0008_0000
    static let maskCommand: UInt64 = 0x0010_0000
    /// The four modifiers that change what a key *means*. Caps Lock, Fn and the numeric-pad bit
    /// do not, so they are ignored: ⌘Q with Caps Lock on is still ⌘Q.
    static let meaningfulMask: UInt64 = maskShift | maskControl | maskAlternate | maskCommand

    /// ⌘Q exactly: Q with Command and **no** other meaningful modifier. ⌘⇧Q is Log Out and
    /// ⌘⌥Q is a different command in many apps; neither is touched.
    static func isQuitChord(keyCode: Int, flags: UInt64) -> Bool {
        keyCode == keyCodeQ && (flags & meaningfulMask) == maskCommand
    }

    static func commandHeld(flags: UInt64) -> Bool { flags & maskCommand != 0 }

    // MARK: Apps the feature never touches

    /// ⌘Q does nothing in Finder and the Dock cannot be quit; intercepting would only add a HUD
    /// that promises a quit that never comes. `loginwindow` owns system dialogs.
    static let neverIntercepted: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.SecurityAgent",
    ]

    static func intercepts(bundleID: String?) -> Bool {
        guard let id = bundleID, !id.isEmpty else { return false }
        return !neverIntercepted.contains(id)
    }

    // MARK: The machine

    /// `cancelled` exists because Esc ends the hold while the user is STILL holding Q, and the
    /// keyboard keeps sending auto-repeat ⌘Q. Treating that as `idle` would pass the first repeat
    /// to the app and quit it — Esc would cancel nothing (property 4).
    enum State: Equatable { case idle, holding, fired, cancelled }

    enum Input: Equatable {
        /// A ⌘Q key-down. `isRepeat` is the keyboard auto-repeat flag.
        case quitDown(isRepeat: Bool)
        /// Any key-up of Q, whatever the modifiers are by then.
        case quitUp
        case escapeDown
        /// A modifier change after which Command is no longer held.
        case commandReleased
        /// The hold duration elapsed (the one-shot timer fired).
        case holdElapsed
    }

    enum Action: Equatable {
        /// Not ours; let the event through unchanged.
        case passThrough
        /// Consume the event; nothing else to do.
        case swallow
        /// Consume the event and start (or restart) the hold: show the HUD, arm the timer.
        case beginHold
        /// End the hold without quitting: hide the HUD, disarm the timer. `swallowEvent` says
        /// whether the triggering event is consumed (a Q key-up / Esc) or passed (a modifier change).
        case cancelHold(swallowEvent: Bool)
        /// The hold completed: quit the target app, hide the HUD.
        case quit
        /// A timer firing with nothing to do (it raced a cancel). Neither consumes nor changes anything.
        case ignore
    }

    struct Machine: Equatable {
        private(set) var state: State = .idle

        init() {}

        /// Forget everything. Called when the tap is torn down or the OS disables it — events
        /// were lost, so no earlier state can be trusted.
        mutating func reset() { state = .idle }

        mutating func handle(_ input: Input) -> Action {
            switch (state, input) {

            // A fresh press always starts a hold — from ANY state (property 1: self-healing).
            case (_, .quitDown(isRepeat: false)):
                state = .holding
                return .beginHold

            // Auto-repeat while idle: we never saw the press start (property 3).
            case (.idle, .quitDown(isRepeat: true)):
                return .passThrough
            // Auto-repeat while holding, after firing, or after a cancel: swallowed, never
            // re-begins and never reaches the app (properties 2 and 4).
            case (.holding, .quitDown(isRepeat: true)), (.fired, .quitDown(isRepeat: true)),
                 (.cancelled, .quitDown(isRepeat: true)):
                return .swallow

            case (.holding, .quitUp):
                state = .idle
                return .cancelHold(swallowEvent: true)
            case (.fired, .quitUp), (.cancelled, .quitUp):
                state = .idle
                return .swallow
            case (.idle, .quitUp):
                return .passThrough

            case (.holding, .escapeDown):
                state = .cancelled   // the key is still down — see property 4
                return .cancelHold(swallowEvent: true)
            case (_, .escapeDown):
                return .passThrough

            case (.holding, .commandReleased):
                state = .idle
                return .cancelHold(swallowEvent: false)
            case (.fired, .commandReleased), (.cancelled, .commandReleased):
                state = .idle
                return .passThrough
            case (.idle, .commandReleased):
                return .passThrough

            case (.holding, .holdElapsed):
                state = .fired
                return .quit
            case (_, .holdElapsed):
                return .ignore
            }
        }
    }
}
