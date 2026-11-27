import AppKit
import Combine
import SwiftUI

/// Owns Dynamic Island Teleprompter local persistence, playback ticker, system lifecycle observers
/// (sleep/wake, display changes, Reduce Motion), and the separate floating reader window.
/// Zero permissions and zero network calls.
@MainActor
final class NotchTeleprompterController: ObservableObject {
    static let shared = NotchTeleprompterController()

    @Published private(set) var state: NotchTeleprompterState
    @Published private(set) var wordCount: Int = 0
    @Published private(set) var isEditingScript: Bool = false {
        didSet {
            if oldValue != isEditingScript {
                onEditingStateChanged?(isEditingScript)
            }
        }
    }

    /// Optional hook for `NotchSurfaceController` so typing in the Island editor keeps the panel key
    /// and prevents hover auto-collapse.
    var onEditingStateChanged: ((Bool) -> Void)?

    private let defaults: UserDefaults
    private var readerPanel: TeleprompterReaderPanel?
    private var readerDisplayID: UInt32?
    private var playbackTimer: Timer?
    private var lastTickTimestamp: CFAbsoluteTime?
    private var persistWork: DispatchWorkItem?
    private var observersInstalled = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var centerObservers: [NSObjectProtocol] = []
    private var readerKeyMonitor: Any?

    /// Measured scrollable distances (in points) reported by the inline reader and separate reader window.
    private var inlineScrollableDistance: Double = 0
    private var windowScrollableDistance: Double = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawScript = defaults.string(forKey: NotchTeleprompterStorageKeys.script) ?? ""
        let settings = NotchTeleprompterSettings.sanitized(
            speed: defaults.object(forKey: NotchTeleprompterStorageKeys.speed) as? Double,
            fontSize: defaults.object(forKey: NotchTeleprompterStorageKeys.fontSize) as? Double,
            progress: defaults.object(forKey: NotchTeleprompterStorageKeys.progress) as? Double,
            modeRaw: defaults.string(forKey: NotchTeleprompterStorageKeys.mode)
        )
        let initial = NotchTeleprompterState(
            script: rawScript,
            settings: settings,
            isTabEnabled: true,
            isIslandVisible: false,
            isReaderWindowVisible: false,
            isSleeping: false,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        self.state = initial
        self.wordCount = NotchTeleprompterScriptNormalization.wordCount(initial.script)
    }

    // MARK: - Island & Tab Lifecycle

    func onIslandAppear() {
        installObserversIfNeeded()
        apply(NotchTeleprompterEngine.setReduceMotion(state, enabled: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))
        apply(NotchTeleprompterEngine.setIslandVisible(state, visible: true))
    }

    func onIslandDisappear() {
        isEditingScript = false
        apply(NotchTeleprompterEngine.setIslandVisible(state, visible: false))
        persistNow()
        teardownObserversIfIdle()
    }

    func handleIslandClosed() {
        onIslandDisappear()
    }

    func handleTabDisabled() {
        isEditingScript = false
        closeReaderWindowInternal(persist: false)
        apply(NotchTeleprompterEngine.setTabEnabled(state, enabled: false))
        persistNow()
        teardownObserversIfIdle()
    }

    func handleTabEnabled() {
        apply(NotchTeleprompterEngine.setTabEnabled(state, enabled: true))
    }

    func setEditingFocus(_ focused: Bool) {
        isEditingScript = focused && state.isIslandVisible && state.mode == .editor
    }

    // MARK: - User Actions

    func setMode(_ mode: NotchTeleprompterMode) {
        if mode == .reader {
            isEditingScript = false
        }
        apply(NotchTeleprompterEngine.setMode(state, mode: mode))
        schedulePersist()
    }

    func updateScript(_ rawText: String) {
        let next = NotchTeleprompterEngine.updateScript(state, rawText: rawText)
        let scriptChanged = next.script != state.script
        apply(next)
        if scriptChanged {
            wordCount = NotchTeleprompterScriptNormalization.wordCount(next.script)
            schedulePersist()
        }
    }

    func play() {
        installObserversIfNeeded()
        apply(NotchTeleprompterEngine.play(state))
        if state.mode == .reader {
            isEditingScript = false
        }
    }

    func pause() {
        apply(NotchTeleprompterEngine.pause(state))
        persistNow()
    }

    func togglePlayPause() {
        if state.isPlaying {
            pause()
        } else {
            play()
        }
    }

    func restart() {
        apply(NotchTeleprompterEngine.restart(state))
        schedulePersist()
    }

    func setProgress(_ progress: Double) {
        apply(NotchTeleprompterEngine.setProgress(state, progress: progress))
        schedulePersist()
    }

    func decreaseSpeed() {
        apply(NotchTeleprompterEngine.adjustSpeed(state, delta: -NotchTeleprompterLimits.speedStep))
        schedulePersist()
    }

    func increaseSpeed() {
        apply(NotchTeleprompterEngine.adjustSpeed(state, delta: NotchTeleprompterLimits.speedStep))
        schedulePersist()
    }

    func decreaseFontSize() {
        apply(NotchTeleprompterEngine.adjustFontSize(state, delta: -NotchTeleprompterLimits.fontSizeStep))
        schedulePersist()
    }

    func increaseFontSize() {
        apply(NotchTeleprompterEngine.adjustFontSize(state, delta: NotchTeleprompterLimits.fontSizeStep))
        schedulePersist()
    }

    /// Updates the measured scrollable distance for either the Island inline reader or the separate reader window.
    func updateScrollableDistance(_ distance: Double, isReaderWindow: Bool) {
        let sanitized = distance.isFinite ? max(0, distance) : 0
        if isReaderWindow {
            windowScrollableDistance = sanitized
        } else {
            inlineScrollableDistance = sanitized
        }
    }

    // MARK: - Separate Reader Window

    func toggleReaderWindow(on screen: NSScreen? = nil) {
        if state.isReaderWindowVisible {
            closeReaderWindow()
        } else {
            openReaderWindow(on: screen)
        }
    }

    func openReaderWindow(on preferredScreen: NSScreen? = nil) {
        guard state.isTabEnabled else { return }
        guard let screen = resolveActiveScreen(preferred: preferredScreen) else {
            closeReaderWindow()
            return
        }
        installObserversIfNeeded()
        apply(NotchTeleprompterEngine.setReduceMotion(state, enabled: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))

        let panel = ensureReaderPanel()
        readerDisplayID = Self.displayID(for: screen)
        positionReaderPanel(panel, on: screen)
        panel.makeKeyAndOrderFront(nil)

        installReaderKeyMonitorIfNeeded()
        apply(NotchTeleprompterEngine.setReaderWindowVisible(state, visible: true))
    }

    func closeReaderWindow() {
        closeReaderWindowInternal(persist: true)
    }

    private func closeReaderWindowInternal(persist: Bool) {
        removeReaderKeyMonitor()
        readerDisplayID = nil
        if let panel = readerPanel, panel.isVisible {
            panel.orderOut(nil)
        }
        apply(NotchTeleprompterEngine.setReaderWindowVisible(state, visible: false))
        if persist {
            persistNow()
        }
        teardownObserversIfIdle()
    }

    private func ensureReaderPanel() -> TeleprompterReaderPanel {
        if let existing = readerPanel {
            return existing
        }
        let panel = TeleprompterReaderPanel(size: NotchTeleprompterLimits.defaultReaderSize)
        panel.onEscape = { [weak self] in
            self?.closeReaderWindow()
        }
        panel.onCloseRequested = { [weak self] in
            self?.closeReaderWindow()
        }
        let hosting = NSHostingController(rootView: NotchTeleprompterReaderWindowView(controller: self))
        hosting.view.frame = NSRect(origin: .zero, size: NotchTeleprompterLimits.defaultReaderSize)
        panel.contentViewController = hosting
        readerPanel = panel
        return panel
    }

    private func positionReaderPanel(_ panel: NSPanel, on screen: NSScreen) {
        let frame = NotchTeleprompterWindowLayout.readerWindowFrame(
            size: panel.frame.size,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            topInset: screen.safeAreaInsets.top
        )
        panel.setFrame(frame, display: true)
    }

    private func resolveActiveScreen(preferred: NSScreen?) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        if let preferred, let id = Self.displayID(for: preferred),
           let live = screens.first(where: { Self.displayID(for: $0) == id }) {
            return live
        }
        if let existingID = readerDisplayID,
           let live = screens.first(where: { Self.displayID(for: $0) == existingID }) {
            return live
        }
        let mouseLocation = NSEvent.mouseLocation
        if let pointerScreen = screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return pointerScreen
        }
        if let keyScreen = NSApp.keyWindow?.screen,
           let id = Self.displayID(for: keyScreen),
           let live = screens.first(where: { Self.displayID(for: $0) == id }) {
            return live
        }
        return NSScreen.main ?? screens.first
    }

    private static func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func installReaderKeyMonitorIfNeeded() {
        guard readerKeyMonitor == nil else { return }
        readerKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.state.isReaderWindowVisible,
                  let readerPanel = self.readerPanel, event.window === readerPanel else { return event }
            if event.keyCode == 53 { // Escape
                self.closeReaderWindow()
                return nil
            }
            return event
        }
    }

    private func removeReaderKeyMonitor() {
        if let monitor = readerKeyMonitor {
            NSEvent.removeMonitor(monitor)
            readerKeyMonitor = nil
        }
    }

    // MARK: - Playback Ticker (active ONLY while visible & playing)

    private func apply(_ next: NotchTeleprompterState) {
        if next != state {
            state = next
        }
        syncTicker()
    }

    private func syncTicker() {
        if state.needsTicker {
            guard playbackTimer == nil else { return }
            lastTickTimestamp = CFAbsoluteTimeGetCurrent()
            let interval: TimeInterval = state.reduceMotion ? 0.15 : (1.0 / 30.0)
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleTick()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            playbackTimer = timer
        } else {
            stopTicker()
        }
    }

    private func stopTicker() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        lastTickTimestamp = nil
    }

    private func handleTick() {
        guard state.needsTicker else {
            stopTicker()
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        let delta = lastTickTimestamp.map { now - $0 } ?? 0
        lastTickTimestamp = now

        let activeDistance = effectiveScrollableDistance()
        let result = NotchTeleprompterEngine.tick(
            state,
            deltaTime: delta,
            scrollableDistance: activeDistance
        )
        apply(result.state)
        if result.state.reachedEnd {
            persistNow()
        }
    }

    private func effectiveScrollableDistance() -> Double {
        if state.isReaderWindowVisible && windowScrollableDistance > 0 {
            return windowScrollableDistance
        }
        if state.isInlineReaderVisible && inlineScrollableDistance > 0 {
            return inlineScrollableDistance
        }
        // Fallback estimate before SwiftUI completes its first layout pass.
        let estimatedLines = max(1.0, Double(state.script.count) / 36.0)
        return max(0, estimatedLines * (state.fontSize * 1.4) - 80.0)
    }

    // MARK: - System Observers (Sleep, Display Changes, Reduce Motion, Terminate)

    private func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true
        let wsCenter = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(wsCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.apply(NotchTeleprompterEngine.handleSystemSleep(self.state))
                self.persistNow()
            }
        })

        workspaceObservers.append(wsCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.apply(NotchTeleprompterEngine.handleSystemWake(self.state))
            }
        })

        workspaceObservers.append(wsCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                self.apply(NotchTeleprompterEngine.setReduceMotion(self.state, enabled: reduceMotion))
                if self.playbackTimer != nil {
                    self.stopTicker()
                    self.syncTicker()
                }
            }
        })

        let nc = NotificationCenter.default
        centerObservers.append(nc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenParametersChanged()
            }
        })

        centerObservers.append(nc.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stopTicker()
                self.persistNow()
            }
        })
    }

    private func handleScreenParametersChanged() {
        guard state.isReaderWindowVisible, let panel = readerPanel else { return }
        guard let screen = resolveActiveScreen(preferred: nil) else {
            closeReaderWindow()
            return
        }
        readerDisplayID = Self.displayID(for: screen)
        positionReaderPanel(panel, on: screen)
    }

    private func teardownObserversIfIdle() {
        guard !state.isIslandVisible && !state.isReaderWindowVisible else { return }
        stopTicker()
        removeReaderKeyMonitor()
        guard observersInstalled else { return }
        observersInstalled = false
        let wsCenter = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers { wsCenter.removeObserver(token) }
        workspaceObservers.removeAll()
        let nc = NotificationCenter.default
        for token in centerObservers { nc.removeObserver(token) }
        centerObservers.removeAll()
    }

    // MARK: - Local Persistence

    private func schedulePersist() {
        persistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.persistNow()
            }
        }
        persistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func persistNow() {
        persistWork?.cancel()
        persistWork = nil
        defaults.set(state.script, forKey: NotchTeleprompterStorageKeys.script)
        defaults.set(state.speedPointsPerSecond, forKey: NotchTeleprompterStorageKeys.speed)
        defaults.set(state.fontSize, forKey: NotchTeleprompterStorageKeys.fontSize)
        defaults.set(state.progress, forKey: NotchTeleprompterStorageKeys.progress)
        defaults.set(state.mode.rawValue, forKey: NotchTeleprompterStorageKeys.mode)
    }
}

/// Borderless floating panel for the separate Teleprompter reader window below the top edge of the active display.
@MainActor
private final class TeleprompterReaderPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onCloseRequested: (() -> Void)?

    init(size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        animationBehavior = .none
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }

    override func close() {
        super.close()
        onCloseRequested?()
    }
}
