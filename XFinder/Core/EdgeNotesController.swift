import AppKit
import SwiftUI
import Combine

/// Screen-edge notes, three states (matches the reference screenshots):
///
/// 1. **Docked** — one slim coloured tab per note, stacked down the screen
///    edge, each showing its title rotated 90°.
/// 2. **Peek** — pointing at a tab slides that one note out far enough to read.
/// 3. **Open** — clicking a tab opens the full editor: title, body, formatting
///    row, colour swatches, archive / delete / close.
///
/// Plain `NSPanel`s + an `NSEvent` monitor — no event tap, no private API, and
/// no timer (a still pointer costs nothing).
@MainActor
@Observable
final class EdgeNotesController {
    static let shared = EdgeNotesController()

    /// Note currently peeking (hover) — nil when every tab is docked.
    var peekedNoteID: UUID?
    /// Note open in the editor — takes priority over peek.
    var openNoteID: UUID?

    private var panel: NSPanel?
    private var monitor: Any?
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    // Geometry — deliberately small (3/5 of the previous size). The docked
    // strip sits on top of the user's work all day, so it is a row of short
    // pills, not tall bars.
    let tabWidth: CGFloat = 9
    let tabHeight: CGFloat = 28
    let tabGap: CGFloat = 4
    private let peekWidth: CGFloat = 200
    private let editorWidth: CGFloat = 520
    private let editorHeight: CGFloat = 420

    private init() {
        // `@Observable` has no Combine publishers, so the note list tells us
        // directly when it changes instead of us subscribing to `$notes`.
        NoteStore.shared.onChange = { [weak self] in
            Task { @MainActor in self?.applySettings() }
        }
    }

    // MARK: - Settings (read at point of use)

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "notes.edgeEnabled") as? Bool ?? false
    }
    var side: String {
        UserDefaults.standard.string(forKey: "notes.edgeSide") ?? "Right"
    }
    private var hotspot: CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: "notes.edgeHotspot") as? Double ?? 12)
    }
    private var showFullscreen: Bool {
        UserDefaults.standard.object(forKey: "notes.fullscreen") as? Bool ?? false
    }
    private var hideOnLeave: Bool {
        UserDefaults.standard.object(forKey: "notes.hideOnLeave") as? Bool ?? true
    }

    var visibleNotes: [QuickNote] {
        NoteStore.shared.notes.filter { !$0.isArchived }
    }

    func applySettings() {
        guard isEnabled, !visibleNotes.isEmpty else {
            stop()
            return
        }
        ensurePanel()
        applyCollectionBehavior()
        layout(animated: false)
        startMonitor()
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        peekedNoteID = nil
        openNoteID = nil
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Panel

    private func ensurePanel() {
        if panel != nil { return }
        let host = NSHostingView(rootView: EdgeNotesRootView())
        let p = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: editorWidth, height: 600),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false          // each card draws its own shadow
        p.ignoresMouseEvents = false
        p.hidesOnDeactivate = false
        p.contentView = host
        applyCollectionBehavior(to: p)
        panel = p
        p.orderFrontRegardless()
    }

    private func applyCollectionBehavior(to panel: NSPanel? = nil) {
        let target = panel ?? self.panel
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces]
        if showFullscreen { behavior.insert(.stationary) }
        target?.collectionBehavior = behavior
    }

    /// TWO monitors, deliberately.
    ///
    /// `addGlobalMonitorForEvents` only sees events delivered to *other*
    /// applications — the moment XFinder itself (its Settings window, the
    /// clipboard shelf, or this very panel) is frontmost, it goes silent. That
    /// is what made the hover feel random: it worked over other apps and died
    /// over our own. The local monitor covers our own windows. Same fix as
    /// `DockPreviewController`.
    private func startMonitor() {
        if monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged]
            ) { [weak self] _ in
                Task { @MainActor in self?.pointerMoved() }
            }
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged]
            ) { [weak self] event in
                Task { @MainActor in self?.pointerMoved() }
                return event
            }
        }
    }

    // MARK: - Layout
    //
    // The panel is always tall enough for the whole tab stack; the SwiftUI
    // content inside decides what is drawn where. Resizing the *window* per
    // state caused flicker, so only its width changes.

    /// Width the panel needs for the current state.
    ///
    /// While peeking the panel must fit the pill column **and** the card
    /// floating beside it — the card no longer replaces the strip, so a width
    /// of just `peekWidth` would clip it.
    private var neededWidth: CGFloat {
        if openNoteID != nil { return editorWidth }
        if peekedNoteID != nil { return tabWidth + 6 + peekWidth + 12 }
        return tabWidth
    }

    func layout(animated: Bool) {
        guard let panel, let screen = NSScreen.main else { return }
        let count = max(visibleNotes.count, 1)
        let stackHeight = CGFloat(count) * tabHeight + CGFloat(count - 1) * tabGap
        // A little slack around the stack so shadows are not clipped; no more
        // room for a "+" button — that has moved to the menubar.
        let height = max(stackHeight + 24, openNoteID != nil ? editorHeight + 40 : 0)
        let w = neededWidth
        let y = screen.visibleFrame.midY - height / 2
        let x = side == "Left" ? screen.frame.minX : screen.frame.maxX - w

        let frame = NSRect(x: x, y: y, width: w, height: height)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                // A gentle custom curve: slow start, soft landing. The stock
                // `.easeOut` begins at full speed and reads as a snap.
                ctx.duration = 0.26
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.9, 0.26, 1)
                ctx.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: - Hover / click state

    private func pointerMoved() {
        guard isEnabled, !visibleNotes.isEmpty, let panel else {
            stop()
            return
        }
        // While the editor is open the pointer is free to roam.
        guard openNoteID == nil else { return }

        let mouse = NSEvent.mouseLocation

        // 1. The pill strip wins, always. The preview card now floats BESIDE
        //    the strip instead of covering it, so every pill stays reachable
        //    and sliding the pointer down the edge walks through the notes one
        //    after another — the behaviour the user asked for. This must be
        //    checked first, or the "hold" rule below would freeze the peek on
        //    whichever note was opened first.
        if edgeHotZone().contains(mouse) {
            if let id = noteID(at: mouse, in: panel) {
                setPeek(id)
            }
            return
        }

        // 2. Otherwise, hold the current peek while the pointer is over the
        //    panel — i.e. on the card itself, so it can be read and clicked.
        //    `noteID(at:)` maps Y to a fixed row index and the card spans
        //    several rows, so re-running the hit-test here would resolve to a
        //    different note and oscillate.
        if peekedNoteID != nil, panel.frame.insetBy(dx: -hotspot, dy: -hotspot).contains(mouse) {
            return
        }

        if peekedNoteID != nil, hideOnLeave { setPeek(nil) }
    }

    /// A strip along the docked edge, widened by the sensitivity setting.
    /// Covers ONLY the tab stack — the "+" button sits below it and must stay
    /// clickable without triggering a peek.
    private func edgeHotZone() -> NSRect {
        guard let screen = NSScreen.main, let panel else { return .zero }
        let f = panel.frame
        let count = max(visibleNotes.count, 1)
        let stackHeight = CGFloat(count) * tabHeight + CGFloat(count - 1) * tabGap
        let top = f.maxY - (f.height - stackHeight) / 2
        let x = side == "Left" ? screen.frame.minX : screen.frame.maxX - tabWidth - hotspot
        return NSRect(x: x, y: top - stackHeight, width: tabWidth + hotspot, height: stackHeight)
    }

    /// Which tab the pointer is over, top-to-bottom within the stack.
    /// Returns nil below the last tab — that region belongs to the "+" button,
    /// and treating it as a tab made hovering "+" pop open the last note.
    private func noteID(at point: CGPoint, in panel: NSPanel) -> UUID? {
        let notes = visibleNotes
        guard !notes.isEmpty else { return nil }
        let stackHeight = CGFloat(notes.count) * tabHeight + CGFloat(notes.count - 1) * tabGap
        let top = panel.frame.maxY - (panel.frame.height - stackHeight) / 2
        let offset = top - point.y
        guard offset >= 0, offset <= stackHeight else { return nil }
        let index = Int(offset / (tabHeight + tabGap))
        guard notes.indices.contains(index) else { return nil }
        return notes[index].id
    }

    func setPeek(_ id: UUID?) {
        guard peekedNoteID != id else { return }
        peekedNoteID = id
        layout(animated: true)
    }

    func open(_ id: UUID) {
        openNoteID = id
        peekedNoteID = nil
        layout(animated: true)
        // Give the panel key status so it accepts typing, but do NOT call
        // `NSApp.activate` — that raises every XFinder window, so opening a
        // note also threw the whole Settings window in the user's face.
        // `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded = false` is enough
        // for a borderless panel to receive keystrokes on its own.
        panel?.becomesKeyOnlyIfNeeded = false
        panel?.makeKeyAndOrderFront(nil)
    }

    func closeEditor() {
        openNoteID = nil
        layout(animated: true)
    }

    /// Creates a note and opens it for editing. Turns the edge panel on if it
    /// was off — otherwise "Ghi chú mới" from the menubar would create a note
    /// the user cannot see anywhere.
    func createNote() {
        if !isEnabled { UserDefaults.standard.set(true, forKey: "notes.edgeEnabled") }
        NoteStore.shared.create(title: nil, content: "", color: CodableColor(color: .yellow))
        applySettings()
        guard let newest = NoteStore.shared.notes.first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.open(newest.id)
        }
    }

    /// Shows the docked strip (and peeks the first note) so "Tất cả ghi chú"
    /// actually surfaces them.
    func revealAll() {
        if !isEnabled { UserDefaults.standard.set(true, forKey: "notes.edgeEnabled") }
        applySettings()
        guard let first = visibleNotes.first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.setPeek(first.id)
        }
    }
}

/// A borderless panel refuses key status by default, so the note editor could
/// not receive keystrokes. Overriding this is what lets the panel take typing
/// WITHOUT `NSApp.activate`, which would raise the Settings window too.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
