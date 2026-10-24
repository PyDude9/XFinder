import AppKit
import SwiftUI

/// XF-T28 cluster C — STUB (contract: docs/specs/XF-T28-ui-contract.md).
@MainActor final class BrowserWindowController: NSObject {
    static let shared = BrowserWindowController()
    func openWindow(path: String?) {}
    func restoreSessionAtLaunch() {}
    func saveSession() {}
    /// The feature was switched off: save the session, close every browser window, stop every watcher.
    func closeAllWindows() {}
    var windowCount: Int { 0 }
    func toggleQuickLook(for model: BrowserWindowModel) {}
    /// applicationShouldTerminate: false = stay open (the person chose to wait for running operations).
    func confirmQuit() -> Bool { true }
}

final class BrowserWindow: NSWindow {}
