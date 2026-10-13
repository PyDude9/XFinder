import AppKit
import ApplicationServices
import os

/// F3 — quits a LISTED app when its last window closes. The ONE reader of `quitOnClose.enabled` and `quitOnClose.apps`.
///
/// Event-driven, zero cost at rest: one `AXObserver` per running listed app (none when the list is empty or the switch
/// is off), `kAXUIElementDestroyedNotification` on the app element and on each window, `kAXWindowCreatedNotification`
/// to register new windows. A destroyed window arms ONE one-shot re-count after `QuitOnCloseRules.grace`; the decision
/// is `QuitOnCloseRules.shouldQuit`. Quitting is `NSRunningApplication.terminate()` — the app's own Quit, which still
/// asks to save documents.
@MainActor
final class QuitOnCloseController {
    static let shared = QuitOnCloseController()
    private init() {}

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "quitOnClose.enabled") as? Bool ?? false }
    var apps: Set<String> { QuitOnCloseRules.parseApps(UserDefaults.standard.string(forKey: "quitOnClose.apps") ?? "") }

    private struct Watch {
        let observer: AXObserver
        let app: AXUIElement
        var pending: DispatchWorkItem?
    }
    private var watches: [pid_t: Watch] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private let log = Logger(subsystem: "com.xfinder.app", category: "QuitOnClose")
    private var ownBundleID: String { Bundle.main.bundleIdentifier ?? "com.xfinder.app" }

    /// Called at launch, from the page's switch and list, and on `didBecomeActive` (Accessibility granted later).
    func applySettings() {
        guard isEnabled, WindowManager.isTrusted, !apps.isEmpty else { stop(); return }
        if workspaceTokens.isEmpty {
            let nc = NSWorkspace.shared.notificationCenter
            workspaceTokens.append(nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated { if let pid { QuitOnCloseController.shared.attachIfWatched(pid) } }
            })
            workspaceTokens.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated { if let pid { QuitOnCloseController.shared.detach(pid) } }
            })
        }
        let watched = Set(NSWorkspace.shared.runningApplications.filter {
            QuitOnCloseRules.isWatched($0.bundleIdentifier, enabled: true, apps: apps, ownBundleID: ownBundleID)
        }.map(\.processIdentifier))
        for pid in watches.keys where !watched.contains(pid) { detach(pid) }
        for pid in watched where watches[pid] == nil { attach(pid) }
    }

    private func stop() {
        for pid in Array(watches.keys) { detach(pid) }
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens.removeAll()
    }

    private func attachIfWatched(_ pid: pid_t) {
        guard watches[pid] == nil, let app = NSRunningApplication(processIdentifier: pid),
              QuitOnCloseRules.isWatched(app.bundleIdentifier, enabled: isEnabled, apps: apps, ownBundleID: ownBundleID) else { return }
        attach(pid)
    }

    private func attach(_ pid: pid_t) {
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, _ in
            let name = notification as String
            var p: pid_t = 0
            AXUIElementGetPid(element, &p)
            let pid = p
            runOnMainActor { QuitOnCloseController.shared.handle(name, pid: pid) }
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.5)
        let a = AXObserverAddNotification(obs, appEl, kAXUIElementDestroyedNotification as CFString, nil)
        let b = AXObserverAddNotification(obs, appEl, kAXWindowCreatedNotification as CFString, nil)
        for w in windows(of: appEl) ?? [] { AXObserverAddNotification(obs, w, kAXUIElementDestroyedNotification as CFString, nil) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        watches[pid] = Watch(observer: obs, app: appEl, pending: nil)
        log.notice("watching pid=\(pid) app=\(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "?", privacy: .public) destroyed=\(a.rawValue) created=\(b.rawValue)")
    }

    private func detach(_ pid: pid_t) {
        guard let w = watches.removeValue(forKey: pid) else { return }
        w.pending?.cancel()
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(w.observer), .defaultMode)
    }

    private func windows(of app: AXUIElement) -> [AXUIElement]? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success else { return nil }
        return (v as? [AXUIElement]) ?? []
    }

    /// Only Sendable values cross from the AX callback (the Bluetooth lesson): a new window is found again by reading
    /// the app's window list here — re-registering an element that already has the notification is a harmless error.
    fileprivate func handle(_ notification: String, pid: pid_t) {
        guard var w = watches[pid] else { return }
        if notification == (kAXWindowCreatedNotification as String) {
            for win in windows(of: w.app) ?? [] { AXObserverAddNotification(w.observer, win, kAXUIElementDestroyedNotification as CFString, nil) }
            w.pending?.cancel(); w.pending = nil
            watches[pid] = w
            return
        }
        guard notification == (kAXUIElementDestroyedNotification as String) else { return }
        w.pending?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { QuitOnCloseController.shared.recount(pid) } }
        w.pending = work
        watches[pid] = w
        DispatchQueue.main.asyncAfter(deadline: .now() + QuitOnCloseRules.grace, execute: work)
    }

    private func recount(_ pid: pid_t) {
        guard let w = watches[pid] else { return }
        let app = NSRunningApplication(processIdentifier: pid)
        let count = windows(of: w.app)?.count
        let watched = QuitOnCloseRules.isWatched(app?.bundleIdentifier, enabled: isEnabled, apps: apps, ownBundleID: ownBundleID)
        let quit = QuitOnCloseRules.shouldQuit(windowCount: count, stillRunning: app != nil && app?.isTerminated == false, watched: watched)
        log.notice("recount pid=\(pid) app=\(app?.bundleIdentifier ?? "?", privacy: .public) windows=\(count.map(String.init) ?? "unreadable", privacy: .public) quit=\(quit)")
        if quit { app?.terminate() }
    }
}
