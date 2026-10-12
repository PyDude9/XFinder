import AppKit
import SwiftUI

/// The one panel class for every floating surface. Eight controllers used to hand-roll the same
/// `NSPanel` setup with small, meaningful deltas; this makes the deltas explicit (`Kind`) and
/// bakes in the cheap lifecycle: build ONCE (`prepare`), then `show`/`hide` by mutating a model.
/// Measured in QuitProtection: creating an `NSHostingController` inside the hot path cost
/// 0.15–0.65 s, which is why a surface must never be built on the way to the screen.
///
/// `canBecomeKey` is true for `.interactive` AND `.notch` (false only for `.passive`); a borderless
/// panel that needs typing must become key WITHOUT `NSApp.activate` (which would raise every
/// XFinder window) — call `makeKeyAndOrderFront(nil)` on the panel itself.
@MainActor
final class SurfacePanel: NSPanel {

    enum Kind {
        /// Takes clicks and typing; `.floating`; dismissed by clicking outside (see `installClickOutside`).
        case interactive
        /// Mouse-transparent, never key; `.statusBar` so it rides above everything (toasts, HUDs).
        case passive
        /// Like interactive but at `.statusBar` level so it sits over the menu bar (the Notch).
        case notch
    }

    let kind: Kind
    private var clickOutside: ClickOutsideDismisser?
    private var hideWork: DispatchWorkItem?

    init(kind: Kind, size: CGSize) {
        self.kind = kind
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = kind != .notch           // the notch draws its own shape; a shadow would reveal the rect
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        // Measured 2026-10-12 (CGWindowList at 10 ms + `sample`): with the default behaviour AppKit plays its own
        // order-front zoom on every surface — the window appears at 98.4 % (740×228 for a 752×232 hub), springs
        // to 100.3 % and settles, and that animation runs through `-[NSAnimation _runBlocking]`, which BLOCKS the
        // main thread (214 of 565 samples in one open). The SwiftUI spring that draws the surface growing out of
        // the notch could not render meanwhile, so every open stuttered. The surfaces animate themselves.
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        switch kind {
        case .interactive: level = .floating; ignoresMouseEvents = false
        case .passive:     level = .statusBar; ignoresMouseEvents = true
        case .notch:       level = .statusBar; ignoresMouseEvents = false
        }
    }

    override var canBecomeKey: Bool { kind != .passive }
    override var canBecomeMain: Bool { false }

    /// Host a SwiftUI root once. Call from the controller's `prepare()`, never per show.
    func host<V: View>(_ root: V) {
        let hc = NSHostingController(rootView: root)
        hc.view.frame = NSRect(origin: .zero, size: frame.size)
        contentViewController = hc
    }

    /// Place and show. Geometry comes from `SurfaceGeometry` so every surface agrees on screens
    /// and clamping; `screen` defaults to the one under the pointer.
    func show(anchor: SurfaceGeometry.Anchor, on screen: NSScreen? = nil) {
        hideWork?.cancel(); hideWork = nil
        let s = screen ?? WindowManager.screenUnderPointer()
        setFrame(SurfaceGeometry.frame(size: frame.size, anchor: anchor, screen: s.frame, visible: s.visibleFrame), display: false)
        if kind == .passive { orderFrontRegardless() } else { makeKeyAndOrderFront(nil) }
    }

    /// Hide after `seconds` with one cancellable work item (never a repeating timer).
    func hide(after seconds: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hide() } }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel(); hideWork = nil
        clickOutside?.invalidate(); clickOutside = nil
        orderOut(nil)
    }

    /// Click anywhere outside the panel closes it. Global AND local monitors, because a global
    /// monitor goes silent while any XFinder window is frontmost (CLAUDE.md Part 3c).
    func installClickOutside(_ onDismiss: @escaping @MainActor () -> Void) {
        clickOutside?.invalidate()
        clickOutside = ClickOutsideDismisser(panel: self, onDismiss: onDismiss)
    }
}

/// Run `body` on the main actor from an NSEvent GLOBAL-monitor handler. AppKit delivers those on the
/// main thread in practice, but it is not a documented contract, and `MainActor.assumeIsolated` traps
/// if it is ever wrong — on the first mouse move, system-wide. Every live-verified monitor in this app
/// hops with a `Task`; this keeps the synchronous path (no allocation per mouse move) when we are on
/// main and falls back to a `Task` otherwise. Local monitors run inside our own event dispatch and
/// may keep `assumeIsolated`.
nonisolated func runOnMainActor(_ body: @escaping @MainActor @Sendable () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated { body() }
    } else {
        Task { @MainActor in body() }
    }
}

/// Owns the global+local mouse-down monitor pair. Call `invalidate()` to remove both — there is no
/// `deinit` on purpose: a nonisolated deinit may not touch MainActor state under Swift 6, and
/// `SurfacePanel.hide()` is the single owner that always invalidates before dropping it.
@MainActor
final class ClickOutsideDismisser {
    private var global: Any?
    private var local: Any?

    init(panel: NSPanel, onDismiss: @escaping @MainActor () -> Void) {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak panel] _ in
            runOnMainActor {
                guard let panel, panel.isVisible, !panel.frame.contains(NSEvent.mouseLocation) else { return }
                onDismiss()
            }
        }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak panel] event in
            MainActor.assumeIsolated {
                if let panel, panel.isVisible, event.window !== panel { onDismiss() }
            }
            return event   // a local monitor must return the event or it swallows the click
        }
    }

    func invalidate() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil; local = nil
    }
}
