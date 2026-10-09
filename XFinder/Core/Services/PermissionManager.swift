import Foundation
import AppKit
import CoreBluetooth
import ScreenCaptureKit

/// PermissionManager: Single service for managing and auto-requesting permissions.
/// Automatically prompts on startup without requiring manual drag-and-drop.
@MainActor
public final class PermissionManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    public static let shared = PermissionManager()

    @Published public private(set) var isAccessibilityGranted: Bool = false
    @Published public private(set) var isScreenRecordingGranted: Bool = false
    @Published public private(set) var isBluetoothGranted: Bool = false
    @Published public var showAccessibilityBanner: Bool = false

    private var centralManager: CBCentralManager?

    override private init() {
        super.init()
        updateStatuses()
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        // Re-check when user switches back to XFinder from System Settings
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self else { return }
            let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == Bundle.main.bundleIdentifier {
                self.updateStatuses()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatuses()
        }
    }

    /// Refresh status of all permissions without showing system prompts.
    public func updateStatuses() {
        isAccessibilityGranted = AXIsProcessTrusted()
        if #available(macOS 10.15, *) {
            isScreenRecordingGranted = CGPreflightScreenCaptureAccess()
        } else {
            isScreenRecordingGranted = true
        }

        if let cm = centralManager {
            if #available(macOS 13.1, *) {
                isBluetoothGranted = (cm.state == .poweredOn || cm.authorization == .allowedAlways)
            } else {
                isBluetoothGranted = (cm.state == .poweredOn)
            }
        }

        showAccessibilityBanner = !isAccessibilityGranted
    }

    /// Request Accessibility permission via AXIsProcessTrustedWithOptions prompt.
    public func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        isAccessibilityGranted = trusted
        showAccessibilityBanner = !trusted
    }

    /// Opens System Settings > Privacy & Security > Accessibility.
    public func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Request Screen Recording permission via CGRequestScreenCaptureAccess.
    public func requestScreenRecording() {
        if #available(macOS 10.15, *) {
            if !CGPreflightScreenCaptureAccess() {
                _ = CGRequestScreenCaptureAccess()
            }
        }
    }

    /// Opens System Settings > Privacy & Security > Screen Recording.
    public func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Request Bluetooth permission by initializing CBCentralManager to trigger NSBluetoothAlwaysUsageDescription dialog.
    public func requestBluetooth() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil, options: [
                CBCentralManagerOptionShowPowerAlertKey: false
            ])
        }
    }

    // MARK: - CBCentralManagerDelegate

    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        let auth = central.authorization
        Task { @MainActor in
            if #available(macOS 13.1, *) {
                self.isBluetoothGranted = (state == .poweredOn || auth == .allowedAlways)
            } else {
                self.isBluetoothGranted = (state == .poweredOn)
            }
        }
    }
}
