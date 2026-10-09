import Foundation
import Combine
import AppKit
import SwiftUI
import os

/// Thread-safe locked wrapper around a value using os_unfair_lock.
final class Locked<T>: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var _val: T

    init(_ val: T) {
        self._val = val
    }

    var value: T {
        get {
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
            return _val
        }
        set {
            os_unfair_lock_lock(&lock)
            _val = newValue
            os_unfair_lock_unlock(&lock)
        }
    }

    @discardableResult
    func mutate<R>(_ block: (inout T) -> R) -> R {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return block(&_val)
    }
}

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private(set) var window: NSWindow?

    func showWindow(destination: SidebarDestination? = nil) {
        if let destination {
            AppState.shared.selection = destination
        }

        if let win = window {
            if win.isMiniaturized { win.deminiaturize(nil) }
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            win.orderFrontRegardless()
            return
        }

        let rootView = RootView()
            .environment(ClipboardManager.shared)
            .environment(SystemMonitorManager.shared)
            .onAppear {
                PermissionManager.shared.requestAllIfNeeded()
            }

        let hosting = NSHostingController(rootView: rootView)
        let win = NSWindow(contentViewController: hosting)
        win.title = "XFinder"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.setContentSize(NSSize(width: 900, height: 600))
        win.minSize = NSSize(width: 760, height: 500)
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        self.window = win

        if win.isMiniaturized { win.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
    }

    func closeWindow() {
        window?.orderOut(nil)
    }

    // MARK: - NSWindowDelegate
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    var selection: SidebarDestination = .dashboard
    var caffeineActive = false

    private init() {
        // Debug affordance: `-startPage <rawValue>` opens straight to a page,
        // so a specific screen can be inspected without clicking through.
        if let raw = UserDefaults.standard.string(forKey: "startPage"),
           let dest = SidebarDestination(rawValue: raw) {
            selection = dest
        }
    }

    func navigate(to destination: SidebarDestination) {
        selection = destination
        bringMainWindowFront()
    }

    /// The app's real settings/browser window — NOT one of our floating panels.
    static func mainAppWindow() -> NSWindow? {
        MainWindowController.shared.window ?? NSApp.windows.first {
            !($0 is NSPanel) && $0.canBecomeMain && $0.contentView != nil
        }
    }

    func bringMainWindowFront() {
        MainWindowController.shared.showWindow(destination: selection)
    }
}
