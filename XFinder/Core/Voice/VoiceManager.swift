import AppKit
import SwiftUI
import Speech
import AVFoundation

public enum VoiceState: Equatable {
    case idle
    case listening(rms: Float)
    case processing
    case error(String)
}

/// Central coordinator for Voice to Typing system-wide functionality.
@MainActor
@Observable
public final class VoiceManager {
    public static let shared = VoiceManager()

    public var state: VoiceState = .idle {
        didSet {
            onStateChange?(state)
        }
    }
    public var onStateChange: ((VoiceState) -> Void)?

    public var selectedLanguage: String {
        get { UserDefaults.standard.string(forKey: "voice.language") ?? "vi-VN" }
        set { UserDefaults.standard.set(newValue, forKey: "voice.language") }
    }

    public var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "voice.enabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "voice.enabled")
            applySettings()
        }
    }

    public var targetKeyCode: Int64 {
        get { (UserDefaults.standard.object(forKey: "voice.keyCode") as? Int64) ?? 61 }
        set {
            UserDefaults.standard.set(newValue, forKey: "voice.keyCode")
            hotkeyManager.targetKeyCode = newValue
        }
    }

    private let audioCapture = AudioCapture.shared
    private let hotkeyManager = VoiceHotkeyManager.shared
    private let speechProvider = AppleSpeechProvider()
    private let typingSink = TypingSink.shared
    private let ghostOverlay = VoiceGhostOverlay.shared

    private var currentPartialText = ""
    private var isSessionActive = false

    private init() {}

    public func setup() {
        hotkeyManager.targetKeyCode = targetKeyCode
        hotkeyManager.onHoldStart = { [weak self] in
            self?.handleHoldStart()
        }
        hotkeyManager.onHoldEnd = { [weak self] in
            self?.handleHoldEnd()
        }
        hotkeyManager.onCancel = { [weak self] in
            self?.handleCancel()
        }

        audioCapture.onAudioBuffer = { [weak self] buffer in
            self?.speechProvider.appendAudioBuffer(buffer)
        }

        audioCapture.onRMSUpdate = { [weak self] db, normalized in
            Task { @MainActor in
                guard let self = self, self.isSessionActive else { return }
                self.state = .listening(rms: normalized)
                self.ghostOverlay.update(text: self.currentPartialText, rms: normalized)
            }
        }

        applySettings()
    }

    public func applySettings() {
        if isEnabled && AXIsProcessTrusted() {
            hotkeyManager.start()
        } else {
            hotkeyManager.stop()
        }
    }

    // MARK: - Permissions

    public func checkAndRequestPermissions() async -> Bool {
        // 1. Accessibility
        guard AXIsProcessTrusted() else {
            return false
        }

        // 2. Microphone
        var micAllowed = false
        if #available(macOS 14.0, *) {
            micAllowed = await AVAudioApplication.requestRecordPermission()
        } else {
            micAllowed = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        guard micAllowed else { return false }

        // 3. Speech Recognition
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        return speechStatus == .authorized
    }

    // MARK: - Voice Flow Handlers

    private func handleHoldStart() {
        guard isEnabled else { return }

        // Verify permissions
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            Task {
                let ok = await self.checkAndRequestPermissions()
                if !ok {
                    self.showError(L10n.t("Chưa cấp quyền Micro hoặc Nhận dạng giọng nói"))
                }
            }
            return
        }

        isSessionActive = true
        currentPartialText = ""
        _ = typingSink.snapshot()
        state = .listening(rms: 0.0)
        ghostOverlay.show()

        Task {
            await speechProvider.start(
                language: selectedLanguage,
                onPartial: { [weak self] text in
                    Task { @MainActor in
                        guard let self = self, self.isSessionActive else { return }
                        self.currentPartialText = text
                        self.ghostOverlay.update(text: text)
                    }
                },
                onFinal: { [weak self] text in
                    Task { @MainActor in
                        guard let self = self, self.isSessionActive else { return }
                        self.currentPartialText = text
                        self.ghostOverlay.update(text: text)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        guard let self = self, self.isSessionActive else { return }
                        if error == .noSpeech || error == .silentStream {
                            self.showError(L10n.t("Không nghe thấy tiếng"))
                        } else {
                            self.showError(L10n.t("Lỗi nhận dạng giọng nói"))
                        }
                    }
                }
            )

            do {
                try audioCapture.start()
            } catch {
                self.showError(L10n.t("Không mở được Micro"))
            }
        }
    }

    private func handleHoldEnd() {
        guard isSessionActive else { return }
        isSessionActive = false
        state = .processing

        let metrics = audioCapture.stop()

        Task {
            let finalTranscription = await speechProvider.stop()
            ghostOverlay.hide()

            if metrics.isSilent && (finalTranscription == nil || finalTranscription?.isEmpty == true) {
                showError(L10n.t("Không nghe thấy tiếng"))
                typingSink.rollback()
                return
            }

            if let text = finalTranscription, !text.isEmpty {
                typingSink.commit(text)
                state = .idle
            } else if !currentPartialText.isEmpty {
                typingSink.commit(currentPartialText)
                state = .idle
            } else {
                showError(L10n.t("Không nghe thấy tiếng"))
                typingSink.rollback()
            }
        }
    }

    private func handleCancel() {
        guard isSessionActive else { return }
        isSessionActive = false
        _ = audioCapture.stop()
        speechProvider.cancel()
        ghostOverlay.hide()
        typingSink.rollback()
        state = .idle
    }

    private func showError(_ message: String) {
        state = .error(message)
        ghostOverlay.hide()
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if case .error = self.state {
                self.state = .idle
            }
        }
    }
}
