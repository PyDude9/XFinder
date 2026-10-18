import AppKit
import Carbon
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
    let tabWidth: CGFloat = EdgeNotesLayout.tabWidth
    let tabHeight: CGFloat = EdgeNotesLayout.tabHeight
    let tabGap: CGFloat = EdgeNotesLayout.tabGap
    /// XF-T24: what the view needs to draw the peek where the hit test thinks it is (see EdgeNotesLayout).
    private(set) var stackTopInset: CGFloat = EdgeNotesLayout.slack
    private(set) var cardLift: CGFloat = 0
    private(set) var cardHeight: CGFloat = EdgeNotesLayout.minCardHeight
    /// Lines the cap cut off (0 = the whole note is shown).
    private(set) var cardHiddenLines = 0
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

    var isEnabled: Bool {
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

    /// Ghi chú ghim LUÔN nằm trên cùng dải mép màn hình (dễ truy cập), rồi mới
    /// tới các ghi chú khác theo thời gian sửa mới nhất.
    var visibleNotes: [QuickNote] {
        NoteStore.shared.notes
            .filter { !$0.isArchived }
            .sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned }
                return a.updatedAt > b.updatedAt
            }
    }

    func applySettings() {
        syncGlobalHotkey()
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
    /// The laid-out height of a note body in the card's font and width, and the font's line height.
    private func measureBody(_ text: String) -> (height: CGFloat, line: CGFloat) {
        let font = NSFont.systemFont(ofSize: 11)
        let width = EdgeNotesLayout.cardWidth - 2 * EdgeNotesLayout.cardPadding
        let line = NSLayoutManager().defaultLineHeight(for: font)
        let body = text.isEmpty ? " " : text
        let r = (body as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        return (ceil(r.height) + 2, line)
    }

    func layout(animated: Bool) {
        guard let panel, let screen = NSScreen.main else { return }
        let notes = visibleNotes
        let count = max(notes.count, 1)
        let onLeft = side == "Left"
        let frame: NSRect
        if openNoteID != nil {
            let height = max(EdgeNotesLayout.stackHeight(count: count) + 24, editorHeight + 40)
            let x = onLeft ? screen.frame.minX : screen.frame.maxX - editorWidth
            frame = NSRect(x: x, y: screen.visibleFrame.midY - height / 2, width: editorWidth, height: height)
        } else if let id = peekedNoteID, let index = notes.firstIndex(where: { $0.id == id }) {
            // XF-T24: the card is as tall as the note (up to a cap); the stack keeps its fixed rect.
            let m = measureBody(notes[index].content)
            let fit = EdgeNotesLayout.cardHeight(bodyHeight: m.height, visible: screen.visibleFrame)
            cardHeight = fit.height
            let shownBody = fit.height - EdgeNotesLayout.cardChrome - (fit.truncated ? m.line : 0)
            cardHiddenLines = fit.truncated ? max(1, Int(((m.height - shownBody) / m.line).rounded(.up))) : 0
            let peek = EdgeNotesLayout.peek(index: index, count: notes.count, cardHeight: fit.height,
                                            visible: screen.visibleFrame, screen: screen.frame, onLeft: onLeft)
            stackTopInset = peek.stackTopInset
            cardLift = peek.cardLift
            frame = peek.panel
        } else {
            let docked = EdgeNotesLayout.docked(count: count, visible: screen.visibleFrame, screen: screen.frame, onLeft: onLeft)
            stackTopInset = docked.stackTopInset
            cardLift = 0
            frame = docked.panel
        }
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
        guard let screen = NSScreen.main, panel != nil else { return .zero }
        // XF-T24: the stack's FIXED rect — the same one the view draws at, whatever the panel's height is while peeking.
        let stack = EdgeNotesLayout.stackRect(count: visibleNotes.count, visible: screen.visibleFrame, screen: screen.frame, onLeft: side == "Left")
        let x = side == "Left" ? screen.frame.minX : screen.frame.maxX - tabWidth - hotspot
        return NSRect(x: x, y: stack.minY, width: tabWidth + hotspot, height: stack.height)
    }

    /// Which tab the pointer is over, top-to-bottom within the stack.
    /// Returns nil below the last tab — that region belongs to the "+" button,
    /// and treating it as a tab made hovering "+" pop open the last note.
    private func noteID(at point: CGPoint, in panel: NSPanel) -> UUID? {
        let notes = visibleNotes
        guard !notes.isEmpty, let screen = NSScreen.main else { return nil }
        let stack = EdgeNotesLayout.stackRect(count: notes.count, visible: screen.visibleFrame, screen: screen.frame, onLeft: side == "Left")
        guard let index = EdgeNotesLayout.index(at: point.y, stack: stack, count: notes.count) else { return nil }
        return notes[index].id
    }

    // MARK: - XF-T24 global hotkey ⌃⌥N (Carbon, no permission) — opt-in, it takes a chord from every app

    /// The ONE reader of `notes.globalHotkey` (default off).
    static var globalHotkeyEnabled: Bool { UserDefaults.standard.object(forKey: "notes.globalHotkey") as? Bool ?? false }
    /// N, and ⌃⌥ — the chord ShortcutCatalog lists as `notes.summon`.
    static let summonKeyCode: UInt32 = 45
    /// 'XFnt' — this feature's own signature, so ⌘K's and ⇧⌘G's handlers ignore its events.
    private static let hotkeySignature: OSType = 0x58466E74
    private static let hotkeyID: UInt32 = 3
    private var hotKeyRef: EventHotKeyRef?
    private var carbonHandler: EventHandlerRef?
    /// false when the switch is on but RegisterEventHotKey refused (another app holds ⌃⌥N) — the page says so.
    private(set) var globalHotkeyRegistered = false

    private func syncGlobalHotkey() {
        if isEnabled && Self.globalHotkeyEnabled {
            installCarbonHandlerIfNeeded()
            guard hotKeyRef == nil else { return }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(Self.summonKeyCode, UInt32(controlKey | optionKey),
                                             EventHotKeyID(signature: Self.hotkeySignature, id: Self.hotkeyID),
                                             GetApplicationEventTarget(), 0, &ref)
            hotKeyRef = status == noErr ? ref : nil
            globalHotkeyRegistered = hotKeyRef != nil
        } else {
            if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
            hotKeyRef = nil
            globalHotkeyRegistered = false
        }
    }

    private func installCarbonHandlerIfNeeded() {
        guard carbonHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == EdgeNotesController.hotkeySignature, id.id == EdgeNotesController.hotkeyID
            else { return OSStatus(eventNotHandledErr) }
            let c = Unmanaged<EdgeNotesController>.fromOpaque(userData).takeUnretainedValue()
            c.summonFired()
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &carbonHandler)
    }

    private nonisolated func summonFired() {
        Task { @MainActor in self.summon() }
    }

    /// Open the edge editor on the first note of the strip (pinned first, then most recently edited); none ⇒ a new note.
    func summon() {
        guard isEnabled else { return }
        if openNoteID != nil { closeEditor(); return }          // the same chord closes it again
        guard let first = visibleNotes.first else { createNote(); return }
        applySettings()
        open(first.id)
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
