import Foundation
import AppKit

/// PermissionManager: the Accessibility banner's state for `RootView` — nothing more.
///
/// 2026-10-18 audit (Q-PRUNE-4): the class also carried Screen Recording and Bluetooth status, a `CBCentralManager`
/// delegate and request/open helpers with ZERO callers; `FeatureHub.granted()` is where every permission is read
/// for the hub and the catalog. Dead members removed; this is now a small ObservableObject the banner observes.
/// It never prompts — `updateStatuses()` only reads `AXIsProcessTrusted()`.
@MainActor
public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()

    @Published public private(set) var isAccessibilityGranted: Bool = false
    @Published public var showAccessibilityBanner: Bool = false

    private init() {
        updateStatuses()
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        // Re-check when the user switches back to XFinder from System Settings.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notif in
            let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
            MainActor.assumeIsolated { PermissionManager.shared.updateStatuses() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { PermissionManager.shared.updateStatuses() }
        }
    }

    /// Refresh the Accessibility state without showing any system prompt.
    public func updateStatuses() {
        isAccessibilityGranted = AXIsProcessTrusted()
        showAccessibilityBanner = !isAccessibilityGranted
    }

    /// Opens System Settings > Privacy & Security > Accessibility.
    public func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
