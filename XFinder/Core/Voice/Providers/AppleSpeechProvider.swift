import Foundation
import Speech
import AVFoundation

/// AppleSpeechProvider uses Apple's native SFSpeechRecognizer for real-time speech-to-text.
/// Supports vi-VN (default) and en-US with low latency streaming partial results.
public final class AppleSpeechProvider: @unchecked Sendable, SttProvider {
    public let id: String = "apple-speech"

    private var recognizers: [String: SFSpeechRecognizer] = [:]
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private let lock = NSLock()
    private var currentText: String = ""
    private var isTaskActive = false

    public init() {
        recognizers["vi-VN"] = SFSpeechRecognizer(locale: Locale(identifier: "vi-VN"))
        recognizers["en-US"] = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    public func isAvailable() async -> Bool {
        let auth = SFSpeechRecognizer.authorizationStatus()
        return auth == .authorized
    }

    public func warmup() async {
        // Pre-initialize recognition capabilities
        _ = recognizers["vi-VN"]?.isAvailable
        _ = recognizers["en-US"]?.isAvailable
    }

    public func start(
        language: String,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (SttError) -> Void
    ) async {
        cancel()

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            onError(.permissionDenied)
            return
        }

        let recognizer = recognizers[language] ?? recognizers["vi-VN"]
        guard let recognizer = recognizer, recognizer.isAvailable else {
            onError(.modelNotReady)
            return
        }

        let request = beginRequest()

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                let nsError = error as NSError
                // Domain=kAFAssistantErrorDomain Code=203 (Retry/no speech) or Code=216 (Request canceled)
                if nsError.code == 203 || nsError.code == 1110 {
                    onError(.noSpeech)
                } else if nsError.code != 216 {
                    onError(.systemError(error.localizedDescription))
                }
                return
            }

            if let result = result {
                let text = result.bestTranscription.formattedString
                self.recordPartialText(text)

                if result.isFinal {
                    onFinal(text)
                } else {
                    onPartial(text)
                }
            }
        }

        assignTask(task)
    }

    private func beginRequest() -> SFSpeechAudioBufferRecognitionRequest {
        lock.lock()
        defer { lock.unlock() }
        currentText = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.recognitionRequest = request
        self.isTaskActive = true
        return request
    }

    private func assignTask(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        defer { lock.unlock() }
        self.recognitionTask = task
    }

    private func recordPartialText(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        self.currentText = text
    }

    /// Feeds PCM buffer from AudioCapture into the speech recognition engine.
    public func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        recognitionRequest?.append(buffer)
    }

    public func stop() async -> String? {
        let initialText = finishAudio()

        // Allow up to 200ms for final result resolution if needed
        try? await Task.sleep(nanoseconds: 200_000_000)

        return completeTranscription(fallback: initialText)
    }

    private func finishAudio() -> String {
        lock.lock()
        defer { lock.unlock() }
        recognitionRequest?.endAudio()
        return currentText
    }

    private func completeTranscription(fallback: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        let finalText = currentText.isEmpty ? fallback : currentText
        isTaskActive = false
        return finalText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        currentText = ""
        isTaskActive = false
    }
}
