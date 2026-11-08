import AppKit
import SwiftUI
import Speech
import AVFoundation

public enum VoiceState: Equatable {
    case idle
    case listening(rms: Float)
    case processing
    case reviewing
    case error(String)
}

/// The dictation session: audio in, text out.
///
/// One session is a small state machine, and the shape of it is the whole feature:
///
/// ```
/// idle ──trigger──▶ listening ──release──▶ refining ──▶ (review) ──▶ insert ──▶ idle
///   ▲                  │                      │            │
///   └──── Esc ─────────┴──── Esc ─────────────┘            │
///   └───────────────── Space (insert raw now) ─────────────┘
/// ```
///
/// Three decisions in here are worth stating, because each is a place the obvious choice is
/// the wrong one:
///
/// 1. **A failed rewrite inserts the raw transcription.** The user's words already exist; the
///    model failing is not a reason to throw them away. The failure is surfaced, and the raw
///    text lands. The alternative — showing an error and inserting nothing — loses work.
/// 2. **`raw` mode never constructs a refiner at all.** That is what makes "just give me my
///    words" work on a machine with nothing configured, and it is why `VoiceRefinerFactory`
///    is asked with the mode in hand.
/// 3. **The HUD is torn down and re-shown between phases.** It has to be: the waveform must
///    stop when the microphone closes, and the panel's content changes from a live preview to
///    a "refining" state. Reusing one view and mutating it left a moving waveform on screen
///    while the microphone was already off, which reads as "still listening".
@MainActor
@Observable
public final class VoiceManager {
    public static let shared = VoiceManager()

    public var state: VoiceState = .idle {
        didSet { onStateChange?(state) }
    }
    public var onStateChange: ((VoiceState) -> Void)?

    // MARK: Compatibility accessors
    //
    // The settings page and the menubar controller predate the snapshot type. These keep the
    // old call sites working while routing every read through the same defaults keys.

    public var selectedLanguage: String {
        get { UserDefaults.standard.string(forKey: VoiceSettingsKey.language) ?? VoiceSettingsSnapshot.defaults.language }
        set { UserDefaults.standard.set(newValue, forKey: VoiceSettingsKey.language) }
    }

    public var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: VoiceSettingsKey.enabled) as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: VoiceSettingsKey.enabled)
            applySettings()
        }
    }

    /// Kept for the old page's binding; now a view onto the named trigger.
    public var targetKeyCode: Int64 {
        get { VoiceSettingsSnapshot.read().triggerKey.keyCode }
        set {
            if let key = VoiceConfig.migratedTrigger(legacyKeyCode: newValue) {
                var snapshot = VoiceSettingsSnapshot.read()
                snapshot.triggerKey = key
                snapshot.writeTrigger()
            }
            applySettings()
        }
    }

    private let audioCapture = AudioCapture.shared
    private let hotkeyManager = VoiceHotkeyManager.shared
    private let speechProvider = AppleSpeechProvider()
    private let typingSink = TypingSink.shared
    private let hud = VoiceHUD.shared
    private let diffPanel = VoiceDiffPanel.shared

    private var currentPartialText = ""
    private var isSessionActive = false
    /// The transcription captured when the trigger was released, held while the model works
    /// so Space can insert it verbatim without waiting.
    private var pendingTranscription: String?
    /// The rewritten text waiting on the review card.
    private var pendingRewritten: String?
    private var refineTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    public func setup() {
        hotkeyManager.onStart = { [weak self] in self?.handleStart() }
        hotkeyManager.onStop = { [weak self] in self?.handleStop() }
        hotkeyManager.onCancel = { [weak self] in self?.handleCancel() }
        hotkeyManager.onSkipRewrite = { [weak self] in self?.handleSkipRewrite() }
        hotkeyManager.onReviewAccept = { [weak self] in self?.handleReviewAccept() }
        hotkeyManager.onReviewReject = { [weak self] in self?.handleReviewReject() }

        audioCapture.onAudioBuffer = { [weak self] buffer in
            self?.speechProvider.appendAudioBuffer(buffer)
        }

        audioCapture.onRMSUpdate = { [weak self] _, normalized in
            Task { @MainActor in
                guard let self, self.isSessionActive else { return }
                self.state = .listening(rms: normalized)
                // The waveform advances here — once per captured audio buffer — and nowhere
                // else. There is no timer in this feature.
                self.hud.pushLevel(normalized)
            }
        }

        applySettings()
    }

    /// Re-arm the event tap and push the trigger settings into it. Called at launch, whenever
    /// the page changes a setting, and when the app becomes active again (which is how a user
    /// who has just granted Accessibility gets the feature without relaunching).
    public func applySettings() {
        let snapshot = VoiceSettingsSnapshot.read()
        hotkeyManager.triggerKey = snapshot.triggerKey
        hotkeyManager.activationMode = snapshot.activationMode
        typingSink.restoresClipboard = snapshot.restoreClipboard

        if snapshot.enabled && AXIsProcessTrusted() {
            hotkeyManager.start()
        } else {
            hotkeyManager.stop()
        }
    }

    public var isEventTapInstalled: Bool { hotkeyManager.isTapInstalled }

    // MARK: - Permissions
    //
    // XF-VOICE-PERMISSIONS: what a press does about Microphone and Speech Recognition is decided by
    // `VoicePermissionRules.decide` — a refused permission is never asked again, the two are never asked together by
    // the Voice page, and a press asks the undecided ones one at a time. The page's rows go through
    // `FeatureHub.request(_:)`, the one place XFinder asks macOS for a permission.

    /// A TCC status the rules understand. An unknown future value is treated as undecided: asking is then harmless (macOS
    /// answers without a dialog if it has an answer), while "refused" would block dictation for good.
    static func microphoneStatus() -> VoicePermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .notDetermined
        }
    }

    static func speechStatus() -> VoicePermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .notDetermined
        }
    }

    /// True while a press is waiting on a permission dialog: another press must not stack a second request.
    private var isAskingPermission = false

    /// Ask for each undecided permission in order; stop at the first refusal. The press that asked does not start a
    /// session — the trigger was released while the dialog was up — so success says "press again".
    private func askPermissions(_ kinds: [VoicePermissionKind]) async {
        defer { isAskingPermission = false }
        for kind in kinds {
            let granted: Bool
            switch kind {
            case .microphone:
                granted = await AVCaptureDevice.requestAccess(for: .audio)
            case .speechRecognition:
                granted = await withCheckedContinuation { continuation in
                    // `@Sendable`: formed here, on the main actor, the closure would inherit MainActor isolation and a
                    // Swift 6 executor check that traps if Speech runs it off the main thread (probe of that shape:
                    // SIGTRAP, exit 133; Speech's own queue not measured — `PermissionCallbackIsolationTests`).
                    SFSpeechRecognizer.requestAuthorization { @Sendable status in
                        continuation.resume(returning: status == .authorized)
                    }
                }
            }
            // The Voice page and the Features hub show these rows; let them re-read.
            FeatureHub.shared.refresh()
            guard granted else {
                showError(L10n.t(VoicePermissionRules.blockedMessageKey(kind, restricted: false)))
                return
            }
        }
        showTransientNotice(L10n.t(VoicePermissionRules.grantedNoticeKey))
    }

    // MARK: - Session

    private func handleStart() {
        let snapshot = VoiceSettingsSnapshot.read()
        guard snapshot.enabled, !isAskingPermission else { return }

        switch VoicePermissionRules.decide(microphone: Self.microphoneStatus(), speech: Self.speechStatus()) {
        case .start:
            break
        case .blocked(let kind, let restricted):
            // No request API here: macOS would answer "denied" without a dialog, every press.
            showError(L10n.t(VoicePermissionRules.blockedMessageKey(kind, restricted: restricted)))
            return
        case .ask(let kinds):
            // Set before the Task runs: a second press in between must already see it.
            isAskingPermission = true
            Task { await self.askPermissions(kinds) }
            return
        }

        isSessionActive = true
        currentPartialText = ""
        pendingTranscription = nil
        pendingRewritten = nil
        _ = typingSink.snapshot()

        state = .listening(rms: 0)
        hud.show(anchor: snapshot.hudAnchor, showWaveform: snapshot.showWaveform)
        if snapshot.audioCues { VoiceAudioCue.start() }

        Task {
            await speechProvider.start(
                language: snapshot.language,
                onPartial: { text in
                    Task { @MainActor in
                        guard self.isSessionActive else { return }
                        self.currentPartialText = text
                        self.hud.updatePartial(text)
                    }
                },
                onFinal: { text in
                    Task { @MainActor in
                        guard self.isSessionActive else { return }
                        self.currentPartialText = text
                        self.hud.updatePartial(text)
                    }
                },
                onError: { error in
                    Task { @MainActor in
                        guard self.isSessionActive else { return }
                        if error == .noSpeech || error == .silentStream {
                            self.showError(L10n.t("Không nghe thấy tiếng"))
                        } else {
                            self.showError(L10n.t("Lỗi nhận dạng giọng nói"))
                        }
                    }
                }
            )

            do {
                try self.audioCapture.start()
            } catch {
                self.showError(L10n.t("Không mở được Micro"))
            }
        }
    }

    private func handleStop() {
        guard isSessionActive else { return }
        isSessionActive = false
        state = .processing

        let snapshot = VoiceSettingsSnapshot.read()
        let metrics = audioCapture.stop()

        Task {
            let transcription = await speechProvider.stop()

            let text = (transcription?.isEmpty == false ? transcription : nil)
                ?? (currentPartialText.isEmpty ? nil : currentPartialText)

            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                _ = metrics
                hud.hide()
                showError(L10n.t("Không nghe thấy tiếng"))
                typingSink.rollback()
                return
            }

            pendingTranscription = text

            // XF-T29: `.voiceAIRefine` gates the AI refine modes — plain dictation (`raw`) stays free in every
            // tier. Free still gets the words inserted, raw, with a short notice instead of losing the session.
            if snapshot.mode.usesLanguageModel, !LicenseManager.shared.allows(.voiceAIRefine) {
                finish(inserting: text, snapshot: snapshot)
                showTransientNotice(L10n.t("Cần XFinder Pro để tút văn bản bằng AI — đã chèn nguyên văn."))
            } else if snapshot.mode.usesLanguageModel {
                await refine(text: text, snapshot: snapshot)
            } else {
                finish(inserting: text, snapshot: snapshot)
            }
        }
    }

    /// Ask the configured provider to rewrite, then insert — or hand off to the review card.
    private func refine(text: String, snapshot: VoiceSettingsSnapshot) async {
        hotkeyManager.setState(.refining)
        hud.enterRefining(mode: snapshot.mode)

        let context: RefineContext? = snapshot.screenContext || snapshot.selectionContext
            ? VoiceScreenContext.capture(includeApp: snapshot.screenContext, includeSelection: snapshot.selectionContext)
            : nil

        let messages = snapshot.messages(for: text, context: context)

        guard let refiner = VoiceRefinerFactory.make(
            tier: snapshot.tier,
            provider: snapshot.provider,
            apiBaseURL: snapshot.apiBaseURL,
            apiModel: snapshot.apiModel,
            ollamaBaseURL: snapshot.ollamaBaseURL,
            ollamaModel: snapshot.ollamaModel
        ) else {
            // No provider configured. The words still exist, so they land — with the failure
            // stated — rather than being dropped.
            fallBackToRaw(text, reason: L10n.t("Chưa cấu hình nhà cung cấp AI, đã chèn bản gốc"))
            return
        }

        let request = RefineRequest(text: text, messages: messages, contextSummary: context?.promptBlock)

        do {
            let refined = try await refiner.refine(request)
            if snapshot.diffReview, !VoiceTextDiff.isIdentical(from: text, to: refined) {
                pendingRewritten = refined
                hotkeyManager.setState(.reviewing)
                hud.hide()
                diffPanel.show(original: text, rewritten: refined, mode: snapshot.mode)
                state = .reviewing
            } else {
                finish(inserting: refined, snapshot: snapshot)
            }
        } catch is CancellationError {
            // Esc or Space already handled the session; nothing to do.
        } catch let error as RefinerError {
            if case .cancelled = error { return }
            // `messageKey` is a key, not display text: it has to go through `L10n.t` here or
            // the HUD would show the Vietnamese literal in an English UI.
            fallBackToRaw(text, reason: L10n.t(error.messageKey))
        } catch {
            fallBackToRaw(text, reason: L10n.t("Lỗi khi tút văn bản, đã chèn bản gốc"))
        }
    }

    private func fallBackToRaw(_ text: String, reason: String) {
        let snapshot = VoiceSettingsSnapshot.read()
        finish(inserting: text, snapshot: snapshot)
        // Stated after the text lands, so the message never displaces the user's words.
        showTransientNotice(reason)
    }

    /// Insert and return to idle.
    private func finish(inserting text: String, snapshot: VoiceSettingsSnapshot) {
        refineTask?.cancel()
        refineTask = nil
        pendingTranscription = nil
        pendingRewritten = nil
        diffPanel.hide()
        hud.hide()
        hotkeyManager.setState(.idle)

        typingSink.commit(text)
        if snapshot.audioCues { VoiceAudioCue.done() }
        state = .idle
    }

    // MARK: - Session keys

    /// Space while refining: the user does not want to wait. Insert what they said.
    private func handleSkipRewrite() {
        guard let text = pendingTranscription else { return }
        refineTask?.cancel()
        finish(inserting: text, snapshot: VoiceSettingsSnapshot.read())
    }

    private func handleReviewAccept() {
        guard let text = pendingRewritten else { return }
        finish(inserting: text, snapshot: VoiceSettingsSnapshot.read())
    }

    private func handleReviewReject() {
        // "Huỷ" means nothing is inserted — the card says so in as many words, so this is the
        // behaviour the user was promised rather than a surprise.
        pendingTranscription = nil
        pendingRewritten = nil
        diffPanel.hide()
        hud.hide()
        hotkeyManager.setState(.idle)
        typingSink.rollback()
        state = .idle
    }

    private func handleCancel() {
        refineTask?.cancel()
        refineTask = nil
        pendingTranscription = nil
        pendingRewritten = nil

        if isSessionActive {
            isSessionActive = false
            _ = audioCapture.stop()
            speechProvider.cancel()
        }
        diffPanel.hide()
        hud.hide()
        hotkeyManager.setState(.idle)
        typingSink.rollback()
        state = .idle
    }

    // MARK: - Errors

    private func showError(_ message: String) {
        state = .error(message)
        hud.showFailure(message)
        if VoiceSettingsSnapshot.read().audioCues { VoiceAudioCue.failed() }
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if case .error = self.state {
                self.hud.hide()
                self.state = .idle
            }
        }
    }

    /// A short notice that does not interrupt: the HUD shows it and fades on its own.
    private func showTransientNotice(_ message: String) {
        hud.showFailure(message)
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if case .idle = self.state { self.hud.hide() }
        }
    }
}
