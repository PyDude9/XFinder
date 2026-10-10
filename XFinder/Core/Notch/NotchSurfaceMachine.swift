import Foundation

/// The pure state machine of the Notch surface. Job: *"the tray opens when I mean it to — a file
/// drag reaching the notch, a shake, a deliberate hover over files I am holding, a click — and gets
/// out of the way otherwise, without ever losing what I staged."*
///
/// Every rule lives here with no AppKit, so the ways this feature failed before are each pinned by
/// a test: opening on any drag, opening an empty tray on hover, never closing, and throwing away
/// the files the user just dropped.
enum NotchSurfaceMachine {

    enum Page: String, Equatable, Codable { case files }

    enum State: Equatable {
        /// Nothing drawn — except, when files are held on a notched screen, a count badge under the notch.
        case collapsed
        /// A compact strip under the notch: file count, a drag handle, click to open.
        case peek
        /// The full surface with a page.
        case expanded(Page)

        var isOpen: Bool { if case .collapsed = self { return false }; return true }
    }

    /// Where the open surface lives. A shake opens it where the hand already is (ShakePin), so an
    /// in-flight drag has the shortest way to go; every other trigger opens it at the notch.
    enum Anchor: Equatable { case notch, pointer }

    struct Settings: Equatable {
        var enabled = true
        var hoverToPeek = true
        var dragIntoNotchOpens = true
        var shakeOpens = true
        /// Pointer must rest in the notch zone this long before hover counts (accidental passes are shorter).
        var hoverDwell: TimeInterval = 0.25
        /// Pointer must be away this long before the surface collapses.
        var leaveGrace: TimeInterval = 0.8
    }

    enum Event: Equatable {
        /// Pointer is inside the notch hover zone (no button down). `since` = when it entered.
        case hoverInZone(since: Date)
        /// Pointer left both the zone and the open surface. `since` = when it left.
        case pointerAway(since: Date)
        /// Pointer is over the open surface — keeps it open.
        case pointerOnSurface
        /// A drag that carries FILES entered the notch drag zone.
        case fileDragInZone
        /// A shake gesture was detected during a file drag.
        case shake
        /// Deliberate open: a click on the badge / peek strip, or the Finder-extension URL.
        case activate
        /// Files were dropped onto the surface; `count` is the tray's new total.
        case dropped(count: Int)
        /// The tray's item count changed elsewhere (the Khay thả page, "Xóa hết", the extension).
        case itemsChanged(count: Int)
        /// A hub action started / ended (B2d). While one runs the surface does not collapse on its own,
        /// or its progress would vanish mid-job.
        case taskStarted
        case taskEnded
        /// The close button.
        case dismiss
        /// The feature was switched off.
        case disabled
    }

    struct Machine: Equatable {
        var state: State = .collapsed
        var anchor: Anchor = .notch
        var itemCount = 0
        var taskRunning = false

        /// Advance. `now` makes dwell/grace decisions deterministic.
        mutating func handle(_ e: Event, settings s: Settings, now: Date) {
            guard s.enabled else { collapse(); return }
            switch e {
            case .disabled, .dismiss:
                collapse()
            case .taskStarted:
                taskRunning = true
            case .taskEnded:
                taskRunning = false
            case .activate:
                if case .expanded = state { return }
                open(at: .notch)
            case .fileDragInZone:
                guard s.dragIntoNotchOpens else { return }
                // A tray already open at the pointer stays put: moving it under a live drag would
                // pull the target away from the hand.
                if case .expanded = state, anchor == .pointer { return }
                open(at: .notch)
            case .shake:
                guard s.shakeOpens else { return }
                if case .expanded = state { return }
                open(at: .pointer)
            case .dropped(let n):
                itemCount = n
                state = .expanded(.files)           // dropping is the START of the task — stay open
            case .itemsChanged(let n):
                itemCount = n
                if n == 0, state == .peek { collapse() }
            case .hoverInZone(let since):
                // Hover only reveals files already held — never an empty tray (CLAUDE.md Part 3c).
                guard s.hoverToPeek, itemCount > 0, state == .collapsed,
                      now.timeIntervalSince(since) >= s.hoverDwell else { return }
                state = .peek
                anchor = .notch
            case .pointerOnSurface:
                break                               // whatever is open stays open
            case .pointerAway(let since):
                guard state.isOpen, now.timeIntervalSince(since) >= s.leaveGrace else { return }
                if taskRunning { return }
                // The shaken-open tray holding files never auto-closes: the user dropped them to
                // act on them next, and a tray that vanished mid-task was a reported bug. At the
                // notch the files are not lost either — the collapsed badge keeps showing them.
                if case .expanded = state, anchor == .pointer, itemCount > 0 { return }
                collapse()
            }
        }

        private mutating func open(at a: Anchor) {
            state = .expanded(.files)
            anchor = a
        }

        private mutating func collapse() {
            state = .collapsed
            anchor = .notch
        }
    }
}
