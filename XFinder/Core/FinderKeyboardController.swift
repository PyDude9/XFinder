import AppKit
import ApplicationServices

/// Bàn phím Finder — Windows-style file operations inside Finder.
///
/// **⌘X / ⌘V cut-and-paste.** Finder has no Cut, but it *does* have
/// "Move Item Here" (⌘⌥V). So: ⌘X in Finder marks the current selection and
/// copies it to the pasteboard the normal way (⌘C), then ⌘V is rewritten to
/// ⌘⌥V — a real Finder move, which means **⌘Z still undoes it**, because the
/// move was performed by Finder itself rather than by us behind its back.
///
/// **Delete → Trash** rewrites the Delete key to ⌘⌫ (Finder's own command).
/// **Return → Open** swaps Return (rename) and ⌘O (open).
///
/// Every rewrite is scoped to Finder *and* skipped while a text field has
/// focus, so renaming a file or typing in the search box behaves normally.
/// Needs Accessibility trust for the event tap.
@MainActor
@Observable
final class FinderKeyboardController {
    static let shared = FinderKeyboardController()

    private(set) var isActive = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Set by ⌘X, consumed by the next ⌘V.
    private let cutPending = Locked<Bool>(false)

    private init() {}

    // MARK: Settings (read at point of use)

    private var cutPasteEnabled: Bool {
        UserDefaults.standard.object(forKey: "finderKeyboard.cutPaste") as? Bool ?? false
    }
    private var deleteToTrash: Bool {
        UserDefaults.standard.object(forKey: "finderKeyboard.deleteToTrash") as? Bool ?? false
    }
    private var returnOpens: Bool {
        UserDefaults.standard.object(forKey: "finderKeyboard.returnOpens") as? Bool ?? false
    }

    private var anyEnabled: Bool { cutPasteEnabled || deleteToTrash || returnOpens }

    func applySettings() {
        refreshSnapshots()
        guard anyEnabled, WindowManager.isTrusted else {
            teardown()
            isActive = false
            return
        }
        setup()
        isActive = eventTap != nil
    }

    // MARK: Event tap

    private func setup() {
        guard eventTap == nil else { return }
        let mask = 1 << CGEventType.keyDown.rawValue
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let c = Unmanaged<FinderKeyboardController>.fromOpaque(refcon).takeUnretainedValue()
            return c.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    private func teardown() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if type == .tapDisabledByTimeout { DiagnosticsLog.record("eventTap", "timeout.finderKeyboard") }
            Task { @MainActor in
                if let tap = self.eventTap, CFMachPortIsValid(tap) {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        // Only rewrite keys while Finder is frontmost.
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            return Unmanaged.passUnretained(event)
        }
        // …and never while the user is typing (rename field, search box).
        guard !isEditingText() else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let cmd = flags.contains(.maskCommand)

        // ⌘X — mark a cut, then let Finder do a normal ⌘C.
        if cmd, keyCode == 7, cutPasteSnapshot.value { // X
            cutPending.value = true
            event.setIntegerValueField(.keyboardEventKeycode, value: 8) // → C
            return Unmanaged.passUnretained(event)
        }

        // ⌘V after a ⌘X — rewrite to Finder's own Move Item Here (⌘⌥V), so
        // the operation is Finder's and stays undoable with ⌘Z.
        if cmd, keyCode == 9, cutPasteSnapshot.value { // V
            if cutPending.value {
                cutPending.value = false
                event.flags = flags.union(.maskAlternate)
            }
            return Unmanaged.passUnretained(event)
        }

        // Delete → ⌘⌫ (Finder's Move to Trash).
        if keyCode == 51, !cmd, deleteSnapshot.value { // Delete
            event.flags = flags.union(.maskCommand)
            return Unmanaged.passUnretained(event)
        }

        // Return → ⌘O (Open) instead of rename.
        if keyCode == 36, !cmd, returnSnapshot.value { // Return
            event.setIntegerValueField(.keyboardEventKeycode, value: 31) // O
            event.flags = flags.union(.maskCommand)
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    /// True when the AX-focused element takes text — renaming a file, or the
    /// search field. Rewriting keys there would break normal typing.
    private nonisolated func isEditingText() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused
        else { return false }
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String
        else { return false }
        return role == kAXTextFieldRole as String || role == kAXTextAreaRole as String
    }

    // Settings mirrored for lock-free reads from the tap thread.
    private let cutPasteSnapshot = Locked<Bool>(false)
    private let deleteSnapshot = Locked<Bool>(false)
    private let returnSnapshot = Locked<Bool>(false)

    /// Called whenever a toggle changes so the tap thread sees fresh values.
    func refreshSnapshots() {
        cutPasteSnapshot.value = cutPasteEnabled
        deleteSnapshot.value = deleteToTrash
        returnSnapshot.value = returnOpens
    }
}
