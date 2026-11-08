import AppKit
import ApplicationServices
import os

/// Smart Selection E4 — watches the frontmost app's text selection through Accessibility and asks
/// `SmartSelectionRules` when to show the badge and what it offers. ONE reader of `smartSelect.enabled`.
///
/// Cost when on: one `AXObserver` on the frontmost app (re-targeted on app activation), a global+local left-mouse-up
/// monitor pair, and a one-shot 300 ms work item while a selection is changing. Nothing polls; nothing runs when the
/// user is not selecting. Off ⇒ no observer, no monitor, no panel.
///
/// Never writes an attribute of another app (no `AXManualAccessibility`): the probe measured notifications arriving
/// from Chrome and Electron without it. Selected text is held in memory for the current selection only, never logged.
@MainActor
final class SelectionWatcher {
    static let shared = SelectionWatcher()
    private init() {}

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "smartSelect.enabled") as? Bool ?? false }
    /// Literal defaults on purpose: `FeatureKeyDefaultsTests` matches them against the page's `@AppStorage` defaults.
    var minLength: Int { UserDefaults.standard.object(forKey: "smartSelect.minLength") as? Int ?? 2 }
    var excluded: Set<String> { SmartSelectionRules.parseExcluded(UserDefaults.standard.string(forKey: "smartSelect.excludedApps") ?? "") }

    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var observedFocused: AXUIElement?
    private var activationToken: NSObjectProtocol?
    private var mouseUpGlobal: Any?
    private var mouseUpLocal: Any?
    private var settleWork: DispatchWorkItem?
    private var lifetimeWork: DispatchWorkItem?
    private var watch = SmartSelectionRules.Watch()
    /// The current selection, kept only until the next change. Never persisted.
    private var currentText = ""
    private var currentBounds: CGRect?
    var currentSelectionText: String { currentText }
    private(set) var isRunning = false
    /// Diagnostics: lengths, kinds and bundle ids only — never the selected text.
    private let log = Logger(subsystem: "com.xfinder.app", category: "SmartSelect")

    /// Called at launch, from the page's switch, and on `didBecomeActive` (a granted Accessibility re-arms it).
    func applySettings() {
        if isEnabled && WindowManager.isTrusted { start() } else { stop() }
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        if let front = NSWorkspace.shared.frontmostApplication { attach(to: front) }
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier ?? 0
            MainActor.assumeIsolated {   // queue: .main
                SelectionWatcher.shared.dismiss()
                if let app, pid != 0 { SelectionWatcher.shared.attach(to: app) }
            }
        }
        // Global + local pair (Part 3c rule). The local one only matters for completeness: XFinder's own windows are
        // excluded by the gate, but a click in them must still reach `.mouseUp` so a stale point is replaced.
        mouseUpGlobal = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            let p = NSEvent.mouseLocation
            runOnMainActor { SelectionWatcher.shared.handleMouseUp(p, at: ProcessInfo.processInfo.systemUptime) }
        }
        mouseUpLocal = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            let p = NSEvent.mouseLocation
            MainActor.assumeIsolated { SelectionWatcher.shared.handleMouseUp(p, at: ProcessInfo.processInfo.systemUptime) }
            return event
        }
    }

    func stop() {
        guard isRunning else { SmartSelectionBadge.shared.hideAll(); return }
        isRunning = false
        detach()
        if let t = activationToken { NSWorkspace.shared.notificationCenter.removeObserver(t) }
        activationToken = nil
        if let m = mouseUpGlobal { NSEvent.removeMonitor(m) }
        if let m = mouseUpLocal { NSEvent.removeMonitor(m) }
        mouseUpGlobal = nil; mouseUpLocal = nil
        settleWork?.cancel(); settleWork = nil
        lifetimeWork?.cancel(); lifetimeWork = nil
        watch = SmartSelectionRules.Watch()
        currentText = ""; currentBounds = nil
        SmartSelectionBadge.shared.hideAll()
    }

    // MARK: AX observer on the frontmost app

    private var attachRetry: DispatchWorkItem?

    private func attach(to app: NSRunningApplication, attempt: Int = 0) {
        let pid = app.processIdentifier
        guard pid != observedPID else { return }
        detach()
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        var obs: AXObserver?
        // Read on the callback's thread and hand only Sendable values (String, CGRect?) to the main actor — an
        // AXUIElement is a CF object, not Sendable. The source is on the main run loop, so this is main in practice;
        // `runOnMainActor` does not trust that.
        let callback: AXObserverCallback = { _, element, notification, _ in
            let name = notification as String
            let isSelection = name == (kAXSelectedTextChangedNotification as String)
            let read = isSelection ? SelectionWatcher.readSelection(element) : (text: "", bounds: nil)
            let text = read.text, bounds = read.bounds
            runOnMainActor { SelectionWatcher.shared.axNotification(name, text: text, bounds: bounds) }
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let o = obs else { return }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.5)   // short: this runs on the main thread; -25204 is retried
        if let bid = app.bundleIdentifier?.lowercased(),
           bid.contains("chrome") || bid.contains("edge") || bid.contains("brave") || bid.contains("electron") {
            AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        let sel = AXObserverAddNotification(o, appElement, kAXSelectedTextChangedNotification as CFString, nil)
        let foc = AXObserverAddNotification(o, appElement, kAXFocusedUIElementChangedNotification as CFString, nil)

        // Chromium and WebKit post selection changes on the focused element, not on AXApplication
        var focRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focRef) == .success,
           let f = focRef, CFGetTypeID(f) == AXUIElementGetTypeID() {
            let focused = f as! AXUIElement
            AXObserverAddNotification(o, focused, kAXSelectedTextChangedNotification as CFString, nil)
            observedFocused = focused
        }

        log.info("observing \(app.bundleIdentifier ?? "?", privacy: .public) selection=\(sel.rawValue) focus=\(foc.rawValue) attempt=\(attempt)")
        guard sel == .success else {
            // Not attached: do NOT remember the pid, or the app stays silent until the next app switch.
            if let delay = SmartSelectionRules.registrationRetryDelay(attempt: attempt, error: sel.rawValue) {
                let work = DispatchWorkItem { MainActor.assumeIsolated {
                    let w = SelectionWatcher.shared
                    guard w.isRunning, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                    w.attach(to: app, attempt: attempt + 1)
                } }
                attachRetry = work
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        observer = o
        observedPID = pid
    }

    private func detach() {
        attachRetry?.cancel(); attachRetry = nil
        if let o = observer {
            if let f = observedFocused {
                AXObserverRemoveNotification(o, f, kAXSelectedTextChangedNotification as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        }
        observedFocused = nil
        observer = nil
        observedPID = 0
    }

    private func axNotification(_ name: String, text: String, bounds: CGRect?) {
        guard isRunning else { return }
        if name == (kAXFocusedUIElementChangedNotification as String) {
            if let o = observer, observedPID != 0 {
                if let old = observedFocused {
                    AXObserverRemoveNotification(o, old, kAXSelectedTextChangedNotification as CFString)
                }
                observedFocused = nil
                let appElement = AXUIElementCreateApplication(observedPID)
                var focRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focRef) == .success,
                   let f = focRef, CFGetTypeID(f) == AXUIElementGetTypeID() {
                    let focused = f as! AXUIElement
                    AXObserverAddNotification(o, focused, kAXSelectedTextChangedNotification as CFString, nil)
                    observedFocused = focused
                }
            }
            dismiss()
            return
        }
        guard name == (kAXSelectedTextChangedNotification as String) else { return }
        currentText = text
        currentBounds = bounds
        feed(.selectionChanged(length: text.trimmingCharacters(in: .whitespacesAndNewlines).count,
                               at: ProcessInfo.processInfo.systemUptime))
    }

    /// The selected text and, when the app reports a real one, its screen rect (AX space). Falls back to WebKit's
    /// text-marker attributes when `AXSelectedText` is empty (Safari reported changes with an empty value in the probe).
    nonisolated static func readSelection(_ element: AXUIElement) -> (text: String, bounds: CGRect?) {
        AXUIElementSetMessagingTimeout(element, 0.5)   // a hung app must not freeze the thread that reads it

        var targetElement = element
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
           let f = focusedRef, CFGetTypeID(f) == AXUIElementGetTypeID() {
            targetElement = f as! AXUIElement
            AXUIElementSetMessagingTimeout(targetElement, 0.5)
        }

        var value: CFTypeRef?
        var text = ""
        if AXUIElementCopyAttributeValue(targetElement, kAXSelectedTextAttribute as CFString, &value) == .success, let s = value as? String {
            text = s
        }
        if text.isEmpty, targetElement !== element {
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success, let s = value as? String {
                text = s
            }
        }
        var markerRange: CFTypeRef?
        if text.isEmpty {
            var out: CFTypeRef?
            if AXUIElementCopyAttributeValue(targetElement, "AXSelectedTextMarkerRange" as CFString, &markerRange) == .success, let r = markerRange,
               AXUIElementCopyParameterizedAttributeValue(targetElement, "AXStringForTextMarkerRange" as CFString, r, &out) == .success,
               let s = out as? String {
                text = s
            }
        }
        if text.isEmpty, targetElement !== element {
            var out: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRange) == .success, let r = markerRange,
               AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, r, &out) == .success,
               let s = out as? String {
                text = s
            }
        }
        var bounds: CGRect?
        var rangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(targetElement, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
           let rv = rangeValue, CFGetTypeID(rv) == AXValueGetTypeID() {
            var b: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(targetElement, kAXBoundsForRangeParameterizedAttribute as CFString, rv, &b) == .success,
               let bv = b, CFGetTypeID(bv) == AXValueGetTypeID() {
                var rect = CGRect.zero
                if AXValueGetValue(bv as! AXValue, .cgRect, &rect) { bounds = rect }
            }
        }
        if bounds == nil, targetElement !== element {
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
               let rv = rangeValue, CFGetTypeID(rv) == AXValueGetTypeID() {
                var b: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rv, &b) == .success,
                   let bv = b, CFGetTypeID(bv) == AXValueGetTypeID() {
                    var rect = CGRect.zero
                    if AXValueGetValue(bv as! AXValue, .cgRect, &rect) { bounds = rect }
                }
            }
        }
        // Marker range bounds fallback for WebKit and Chromium (AXBoundsForTextMarkerRange)
        if bounds == nil {
            var mr = markerRange
            if mr == nil {
                var mrRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(targetElement, "AXSelectedTextMarkerRange" as CFString, &mrRef) == .success {
                    mr = mrRef
                } else if targetElement !== element, AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &mrRef) == .success {
                    mr = mrRef
                }
            }
            if let r = mr {
                var b: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(targetElement, "AXBoundsForTextMarkerRange" as CFString, r, &b) == .success,
                   let bv = b, CFGetTypeID(bv) == AXValueGetTypeID() {
                    var rect = CGRect.zero
                    if AXValueGetValue(bv as! AXValue, .cgRect, &rect) { bounds = rect }
                } else if targetElement !== element,
                          AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForTextMarkerRange" as CFString, r, &b) == .success,
                          let bv = b, CFGetTypeID(bv) == AXValueGetTypeID() {
                    var rect = CGRect.zero
                    if AXValueGetValue(bv as! AXValue, .cgRect, &rect) { bounds = rect }
                }
            }
        }
        return (String(text.prefix(SmartSelectionRules.maxLength + 1)), bounds)
    }

    // MARK: The machine

    func handleMouseUp(_ point: CGPoint, at uptime: TimeInterval) {
        guard isRunning else { return }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            let appElement = AXUIElementCreateApplication(front.processIdentifier)
            let read = SelectionWatcher.readSelection(appElement)
            let clean = read.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.count >= max(1, minLength) {
                currentText = clean
                currentBounds = read.bounds
                feed(.selectionChanged(length: clean.count, at: uptime))
            } else if clean.isEmpty && (watch.shown || watch.length > 0) {
                feed(.dismiss)
                return
            }
        }
        feed(.mouseUp(point, at: uptime))
    }

    func feed(_ event: SmartSelectionRules.Event) {
        guard isRunning else { return }
        for fx in SmartSelectionRules.reduce(&watch, event, minLength: minLength) {
            switch fx {
            case .hide:
                lifetimeWork?.cancel()
                SmartSelectionBadge.shared.hideBadge()
            case .armSettle(let at):
                settleWork?.cancel()
                let work = DispatchWorkItem { MainActor.assumeIsolated {
                    SelectionWatcher.shared.feed(.settle(at: ProcessInfo.processInfo.systemUptime)) } }
                settleWork = work
                let delay = max(0, at - ProcessInfo.processInfo.systemUptime)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.005, execute: work)
            case .show(let point):
                showBadge(mouseUp: point)
            }
        }
    }

    func dismiss() {
        feed(.dismiss)
    }

    private func showBadge(mouseUp: CGPoint) {
        guard !TranslateSelectionController.shared.model.isActive else { watch.shown = false; return }
        let front = NSWorkspace.shared.frontmostApplication
        guard SmartSelectionRules.shouldConsider(text: currentText, minLength: minLength,
                                                 frontBundleID: front?.bundleIdentifier, frontAppName: front?.localizedName,
                                                 ownBundleID: Bundle.main.bundleIdentifier ?? "com.xfinder.app",
                                                 excluded: excluded) else { watch.shown = false; return }
        let rates = CurrencyRateStore.shared
        if rates.isEnabled, CurrencyConversion.parse(currentText) != nil { rates.refreshIfNeeded() }
        let actions = SmartSelectionRules.actions(for: currentText, now: Date(), localZone: .current,
                                                  currency: rates.context(), define: DictionaryLookup.definition)
        guard !actions.isEmpty else { watch.shown = false; return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let anchor = SmartSelectionRules.anchor(axBounds: currentBounds, mouseUp: mouseUp, primaryScreenHeight: primaryHeight)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let frame = SmartSelectionRules.badgeFrame(anchor: anchor, visible: screen?.visibleFrame ?? .zero)
        let kinds = actions.map { a -> String in
            switch a {
            case .unit: "unit"; case .currency: "currency"; case .time: "time"; case .arithmetic: "arithmetic"
            case .calendar: "calendar"; case .define: "define"; case .translate: "translate"
            }
        }.joined(separator: ",")
        log.notice("badge shown kinds=\(kinds, privacy: .public) length=\(self.currentText.count) anchor=\(self.currentBounds == nil ? "mouse" : "ax", privacy: .public) app=\(front?.bundleIdentifier ?? "?", privacy: .public) frame=\(Int(frame.minX)),\(Int(frame.minY))")
        SmartSelectionBadge.shared.showBadge(frame: frame, text: currentText, actions: actions,
                                             sourceApp: front?.localizedName, sourceBundleID: front?.bundleIdentifier)
        lifetimeWork?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated {
            if !SmartSelectionBadge.shared.isPanelOpen { SelectionWatcher.shared.dismiss() } } }
        lifetimeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + SmartSelectionRules.badgeLifetime, execute: work)
    }
}
