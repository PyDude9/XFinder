import AppKit
@preconcurrency import AVFoundation
import Combine
import os

/// Owns one on-device, video-only camera preview session for the Dynamic Island Mirror module.
///
/// - Never attaches audio inputs or any `AVCaptureOutput` (no recording, no disk/network transfer).
/// - Requests camera permission only when `start()` is invoked explicitly by the user.
/// - Releases the capture session and removes notification observers on `stop()` / `close()`.
@MainActor
final class MirrorCaptureController: ObservableObject {
    @Published private(set) var state: NotchMirrorState = .idle
    @Published private(set) var activeDeviceName: String? = nil

    private var machine = NotchMirrorStateMachine()
    private let worker = MirrorCaptureWorker()
    private let observerTokens = OSAllocatedUnfairLock(uncheckedState: [NSObjectProtocol]())

    deinit {
        Self.removeObservers(observerTokens)
        worker.stop()
    }

    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        worker.makePreviewLayer()
    }

    /// Called by `NotchSurfaceController.syncExtraModulesLifecycle()` or view appearance.
    /// Does NOT prompt for camera access and does NOT auto-start the camera.
    func onAppear() {
        apply(machine.activate())
    }

    /// Explicit user action to start (or retry) the mirrored camera preview.
    func start() {
        let effect = machine.start(
            hasUsageDescription: Self.hasCameraUsageDescription,
            permission: Self.currentPermissionStatus()
        )
        apply(effect)
    }

    /// Explicit user action to stop the preview or cancel a pending start/permission request.
    func stop() {
        apply(machine.stop())
    }

    /// Called when leaving the Mirror page, collapsing/closing the Island, disabling the Mirror tab,
    /// or moving the app to the background. Invalidates any pending permission or startup result
    /// and immediately releases the capture session.
    func close() {
        detachObservers()
        apply(machine.close())
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    static var hasCameraUsageDescription: Bool {
        guard let usage = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String else {
            return false
        }
        return !usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func currentPermissionStatus() -> NotchMirrorPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    // MARK: - Effect execution

    private func apply(_ effect: NotchMirrorEffect) {
        syncPublishedState()

        switch effect {
        case .none:
            if !machine.state.isPreviewVisible && !machine.state.isBusy {
                detachObservers()
            }

        case .requestPermission(let token):
            Task { [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                let after = Self.currentPermissionStatus()
                guard let self else { return }
                let next = self.machine.resolvePermission(
                    token: token,
                    granted: granted,
                    statusAfterRequest: after
                )
                self.apply(next)
            }

        case .startCapture(let token):
            attachObserversIfNeeded()
            worker.start { [weak self] outcome in
                Task { @MainActor in
                    guard let self else { return }
                    let next = self.machine.resolveStart(token: token, outcome: outcome)
                    self.apply(next)
                }
            }

        case .stopCapture:
            detachObservers()
            worker.stop()
        }
    }

    private func syncPublishedState() {
        if state != machine.state {
            state = machine.state
        }
        if activeDeviceName != machine.activeDeviceName {
            activeDeviceName = machine.activeDeviceName
        }
    }

    // MARK: - Hardware & session notifications (active only while capture is active)

    private func attachObserversIfNeeded() {
        guard observerTokens.withLockUnchecked({ $0.isEmpty }) else { return }
        let center = NotificationCenter.default
        let session = worker.sessionObject

        let interrupted = center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.apply(self.machine.handleInterruptionBegan())
            }
        }

        let interruptionEnded = center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let running = self.worker.isSessionRunning
                self.apply(self.machine.handleInterruptionEnded(isSessionRunning: running))
            }
        }

        let runtimeError = center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.apply(self.machine.handleRuntimeError())
            }
        }

        let disconnected = center.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let disconnectedID = (notification.object as? AVCaptureDevice)?.uniqueID ?? ""
            Task { @MainActor in
                guard let self else { return }
                self.apply(self.machine.handleDeviceDisconnected(deviceID: disconnectedID))
            }
        }

        observerTokens.withLockUnchecked { $0 = [interrupted, interruptionEnded, runtimeError, disconnected] }
    }

    private func detachObservers() {
        Self.removeObservers(observerTokens)
    }

    private nonisolated static func removeObservers(_ storage: OSAllocatedUnfairLock<[NSObjectProtocol]>) {
        let tokens = storage.withLockUnchecked { current in
            let previous = current
            current = []
            return previous
        }
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

/// Serializes blocking `AVCaptureSession` operations off the main thread.
///
/// The unfair lock guards only the lightweight `generation` counter and session reference lookup —
/// never held across `startRunning()` / `stopRunning()` — so `stop()` on the main thread is
/// guaranteed non-blocking while still fencing any queued or in-flight `start()`.
private final class MirrorCaptureWorker: Sendable {
    private struct Storage {
        let session = AVCaptureSession()
        var generation: UInt64 = 0
    }

    private let storage = OSAllocatedUnfairLock(initialState: Storage())
    private let queue = DispatchQueue(label: "com.xfinder.mirror.capture", qos: .userInitiated)

    var sessionObject: AVCaptureSession {
        storage.withLock { $0.session }
    }

    var isSessionRunning: Bool {
        storage.withLock { $0.session.isRunning }
    }

    @MainActor
    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: sessionObject)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    func start(completion: @escaping @Sendable (NotchMirrorStartOutcome) -> Void) {
        let (session, generation) = storage.withLock { value -> (AVCaptureSession, UInt64) in
            value.generation &+= 1
            return (value.session, value.generation)
        }

        queue.async { [self] in
            guard isCurrent(generation) else {
                completion(.cancelled)
                return
            }

            // Video-only input, zero outputs, strictly on-device preview.
            guard let camera = Self.selectVideoDevice() else {
                Self.teardown(session)
                completion(.unavailable)
                return
            }

            let input: AVCaptureDeviceInput
            do {
                input = try AVCaptureDeviceInput(device: camera)
            } catch {
                Self.teardown(session)
                completion(.unavailable)
                return
            }

            session.beginConfiguration()
            for existing in session.inputs { session.removeInput(existing) }
            for output in session.outputs { session.removeOutput(output) }
            if session.canSetSessionPreset(.medium) {
                session.sessionPreset = .medium
            }
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                Self.teardown(session)
                completion(.unavailable)
                return
            }
            session.addInput(input)
            session.commitConfiguration()

            guard isCurrent(generation) else {
                Self.teardown(session)
                completion(.cancelled)
                return
            }

            session.startRunning()

            guard isCurrent(generation) else {
                Self.teardown(session)
                completion(.cancelled)
                return
            }

            if session.isRunning {
                completion(.started(deviceID: camera.uniqueID, deviceName: camera.localizedName))
            } else {
                Self.teardown(session)
                completion(.failed)
            }
        }
    }

    func stop() {
        let session = storage.withLock { value -> AVCaptureSession in
            value.generation &+= 1
            return value.session
        }
        queue.async {
            Self.teardown(session)
        }
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        storage.withLock { $0.generation == generation }
    }

    private static func selectVideoDevice() -> AVCaptureDevice? {
        if let preferred = AVCaptureDevice.default(for: .video) {
            return preferred
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.first
    }

    private static func teardown(_ session: AVCaptureSession) {
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        session.commitConfiguration()
    }
}
