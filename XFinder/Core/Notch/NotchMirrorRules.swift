import Foundation

/// Authorization status for video capture, kept pure Foundation so `Tests/XFinderLogicTests`
/// can exercise every permission and lifecycle transition without AVFoundation or hardware.
enum NotchMirrorPermissionStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// Observable state of the Dynamic Island Camera Mirror preview.
enum NotchMirrorState: Equatable, Sendable {
    case idle
    case requesting
    case starting
    case running
    case interrupted
    case denied
    case restricted
    case unavailable
    case deviceRemoved
    case failed
    case misconfigured

    /// Whether the live (or momentarily interrupted) preview surface should be shown.
    var isPreviewVisible: Bool {
        self == .running || self == .interrupted
    }

    /// Whether an async permission check or capture startup is currently in flight.
    var isBusy: Bool {
        self == .requesting || self == .starting
    }

    /// Whether the user can trigger an explicit Start / Retry action from this state.
    var canStart: Bool {
        switch self {
        case .idle, .denied, .unavailable, .deviceRemoved, .failed, .interrupted:
            return true
        case .requesting, .starting, .running, .restricted, .misconfigured:
            return false
        }
    }

    /// Whether an explicit Stop / Cancel action is meaningful in this state.
    var canStop: Bool {
        switch self {
        case .requesting, .starting, .running, .interrupted:
            return true
        case .idle, .denied, .restricted, .unavailable, .deviceRemoved, .failed, .misconfigured:
            return false
        }
    }

    /// Whether System Settings privacy shortcut should be offered.
    var showsOpenSettings: Bool {
        self == .denied
    }

    /// Vietnamese L10n key describing the current state.
    var statusMessageKey: String {
        switch self {
        case .idle:
            return "Xem nhanh hình ảnh được lật gương trước cuộc gọi. Camera chỉ bật khi bạn nhấn Bật camera."
        case .requesting:
            return "Đang xin quyền truy cập camera…"
        case .starting:
            return "Đang khởi động camera…"
        case .running:
            return "Chỉ xem trực tiếp trên máy, không ghi hình."
        case .interrupted:
            return "Camera đang bị tạm gián đoạn bởi hệ thống hoặc ứng dụng khác."
        case .denied:
            return "Quyền camera bị từ chối — mở Cài đặt hệ thống ▸ Quyền riêng tư ▸ Camera để bật lại."
        case .restricted:
            return "Quyền truy cập camera bị hạn chế trên máy này."
        case .unavailable:
            return "Không tìm thấy camera khả dụng. Kết nối camera rồi thử lại."
        case .deviceRemoved:
            return "Camera đang dùng đã bị ngắt kết nối. Kết nối lại rồi thử lại."
        case .failed:
            return "Không mở được camera. Đóng ứng dụng khác đang dùng camera rồi thử lại."
        case .misconfigured:
            return "Bản dựng chưa khai báo mô tả quyền camera."
        }
    }

    /// Vietnamese L10n key for the primary Start / Retry button, or nil when no start action applies.
    var primaryActionTitleKey: String? {
        switch self {
        case .idle:
            return "Bật camera"
        case .denied, .unavailable, .deviceRemoved, .failed, .interrupted:
            return "Thử lại"
        case .requesting, .starting, .running, .restricted, .misconfigured:
            return nil
        }
    }

    /// Vietnamese L10n key for the compact status badge over the preview, if any.
    var statusBadgeKey: String? {
        switch self {
        case .running:
            return "Trực tiếp"
        case .interrupted:
            return "Tạm gián đoạn"
        default:
            return nil
        }
    }
}

/// Result reported by the background capture worker when attempting to start the video session.
enum NotchMirrorStartOutcome: Equatable, Sendable {
    case started(deviceID: String, deviceName: String?)
    case unavailable
    case failed
    case cancelled
}

/// Side effect requested by `NotchMirrorStateMachine` for the controller to execute.
enum NotchMirrorEffect: Equatable, Sendable {
    case none
    case requestPermission(token: UInt64)
    case startCapture(token: UInt64)
    case stopCapture
}

/// Pure, deterministic state machine for the Dynamic Island Camera Mirror.
///
/// Guarantees:
/// - Never requests camera access on appearance; only when `start(...)` is called explicitly.
/// - Repeated Start clicks while requesting/starting/running are strict no-ops.
/// - Repeated Stop clicks while idle are strict no-ops.
/// - Leaving the page, closing the Island, or disabling the tab (`close()`) invalidates any
///   in-flight permission or startup token and releases the capture session.
/// - Late permission or startup completions from an older token or closed preview are ignored
///   (and a late hardware start triggers defensive `.stopCapture`).
struct NotchMirrorStateMachine: Equatable, Sendable {
    private(set) var state: NotchMirrorState = .idle
    private(set) var isPageActive: Bool = false
    private(set) var generation: UInt64 = 0
    private(set) var activeDeviceID: String? = nil
    private(set) var activeDeviceName: String? = nil

    /// Marks the Mirror page visible without prompting or starting the camera.
    mutating func activate() -> NotchMirrorEffect {
        isPageActive = true
        return .none
    }

    /// Explicit user request to start (or retry) the mirrored video preview.
    mutating func start(
        hasUsageDescription: Bool,
        permission: NotchMirrorPermissionStatus
    ) -> NotchMirrorEffect {
        // Ignore repeated clicks while already requesting, starting, or running.
        guard state != .requesting, state != .starting, state != .running else {
            return .none
        }

        isPageActive = true
        activeDeviceID = nil
        activeDeviceName = nil

        guard hasUsageDescription else {
            state = .misconfigured
            return .none
        }

        switch permission {
        case .restricted:
            state = .restricted
            return .none
        case .denied:
            state = .denied
            return .none
        case .notDetermined:
            generation &+= 1
            state = .requesting
            return .requestPermission(token: generation)
        case .authorized:
            generation &+= 1
            state = .starting
            return .startCapture(token: generation)
        }
    }

    /// Handles the asynchronous result of `AVCaptureDevice.requestAccess(for: .video)`.
    mutating func resolvePermission(
        token: UInt64,
        granted: Bool,
        statusAfterRequest: NotchMirrorPermissionStatus
    ) -> NotchMirrorEffect {
        guard isPageActive, token == generation, state == .requesting else {
            return .none
        }
        if granted && statusAfterRequest == .authorized {
            state = .starting
            return .startCapture(token: token)
        }
        if statusAfterRequest == .restricted {
            state = .restricted
            return .none
        }
        state = .denied
        return .none
    }

    /// Handles the asynchronous completion of starting the video-only `AVCaptureSession`.
    mutating func resolveStart(
        token: UInt64,
        outcome: NotchMirrorStartOutcome
    ) -> NotchMirrorEffect {
        guard isPageActive, token == generation, state == .starting else {
            if case .started = outcome {
                return .stopCapture
            }
            return .none
        }

        switch outcome {
        case .started(let deviceID, let deviceName):
            activeDeviceID = deviceID
            activeDeviceName = deviceName
            state = .running
            return .none
        case .unavailable:
            activeDeviceID = nil
            activeDeviceName = nil
            state = .unavailable
            return .none
        case .failed:
            activeDeviceID = nil
            activeDeviceName = nil
            state = .failed
            return .none
        case .cancelled:
            activeDeviceID = nil
            activeDeviceName = nil
            state = .idle
            return .none
        }
    }

    /// Explicit user stop/cancel while remaining on the Mirror page.
    mutating func stop() -> NotchMirrorEffect {
        guard state != .idle || activeDeviceID != nil else {
            return .none
        }
        let shouldStopHardware = state == .starting || state == .running || state == .interrupted || activeDeviceID != nil
        generation &+= 1
        activeDeviceID = nil
        activeDeviceName = nil
        state = .idle
        return shouldStopHardware ? .stopCapture : .none
    }

    /// Called when leaving the page, closing/collapsing the Island, disabling the tab, or backgrounding.
    mutating func close() -> NotchMirrorEffect {
        let shouldStopHardware = state == .starting || state == .running || state == .interrupted || activeDeviceID != nil
        isPageActive = false
        generation &+= 1
        activeDeviceID = nil
        activeDeviceName = nil
        state = .idle
        return shouldStopHardware ? .stopCapture : .none
    }

    /// Called on `AVCaptureSession.wasInterruptedNotification`.
    mutating func handleInterruptionBegan() -> NotchMirrorEffect {
        guard isPageActive, state == .running || state == .starting else {
            return .none
        }
        state = .interrupted
        return .none
    }

    /// Called on `AVCaptureSession.interruptionEndedNotification`.
    mutating func handleInterruptionEnded(isSessionRunning: Bool) -> NotchMirrorEffect {
        guard isPageActive, state == .interrupted else {
            return .none
        }
        if isSessionRunning {
            state = .running
            return .none
        }
        generation &+= 1
        activeDeviceID = nil
        activeDeviceName = nil
        state = .idle
        return .stopCapture
    }

    /// Called on `AVCaptureSession.runtimeErrorNotification`.
    mutating func handleRuntimeError() -> NotchMirrorEffect {
        guard isPageActive, state == .starting || state == .running || state == .interrupted else {
            return .none
        }
        generation &+= 1
        activeDeviceID = nil
        activeDeviceName = nil
        state = .failed
        return .stopCapture
    }

    /// Called on `AVCaptureDevice.wasDisconnectedNotification`.
    /// Only stops the preview if the disconnected device matches the active capture device
    /// (or if we are mid-startup before `activeDeviceID` is recorded).
    mutating func handleDeviceDisconnected(deviceID: String) -> NotchMirrorEffect {
        guard isPageActive, state == .starting || state == .running || state == .interrupted else {
            return .none
        }
        if let activeDeviceID, activeDeviceID != deviceID {
            return .none
        }
        generation &+= 1
        activeDeviceID = nil
        activeDeviceName = nil
        state = .deviceRemoved
        return .stopCapture
    }
}
