import AppKit
import Carbon
import SwiftUI

/// N5a — the live half of "Dịch vùng chọn": a Carbon hotkey (⇧⌘G, the same mechanism as ⌘K), the Accessibility read
/// of the focused element's selection (the Voice module's helper), and a floating panel at the Spotlight position
/// hosting an inline AI-translation card. ONE reader of `translate.hotkeyEnabled`. Off ⇒ no hotkey, no panel.
@MainActor
final class TranslateSelectionController {
    static let shared = TranslateSelectionController()

    private var hotKeyRef: EventHotKeyRef?
    private var carbonHandler: EventHandlerRef?
    private var panel: SurfacePanel?
    private var workspaceObserver: (any NSObjectProtocol)?
    let model = TranslateSelectionModel()

    /// Dedicated assistant; does not share state with VocabularyWorkspace.
    private let assistant = TranslateAssistant()

    private init() {}

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "translate.hotkeyEnabled") as? Bool ?? false }

    func applySettings() {
        if isEnabled { registerHotkey() } else { unregisterHotkey(); dismiss() }
    }

    // MARK: Hotkey (Carbon, like QuickSearchPanelController)

    /// 'XFtr' — this feature's own signature, so its handler ignores ⌘K's events and vice versa.
    private static let signature: OSType = 0x58467472
    private static let hotKeyID: UInt32 = 2

    private func registerHotkey() {
        installCarbonHandlerIfNeeded()
        guard hotKeyRef == nil else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(TranslateSelectionRules.keyCodeG, UInt32(cmdKey | shiftKey),
                                         EventHotKeyID(signature: Self.signature, id: Self.hotKeyID),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr { hotKeyRef = ref }
    }

    private func unregisterHotkey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installCarbonHandlerIfNeeded() {
        guard carbonHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == TranslateSelectionController.signature, id.id == TranslateSelectionController.hotKeyID
            else { return OSStatus(eventNotHandledErr) }
            let c = Unmanaged<TranslateSelectionController>.fromOpaque(userData).takeUnretainedValue()
            c.hotkeyFired()
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &carbonHandler)
    }

    private nonisolated func hotkeyFired() {
        Task { @MainActor in self.translateSelection() }
    }

    // MARK: The action

    /// Read the selection NOW (before any panel takes focus), decide, show.
    func translateSelection() {
        translate(text: VoiceScreenContext.selectedText(), sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName)
    }

    /// Smart Selection's panel hands over the text it already read (the badge works whether or not ⇧⌘G is on).
    func translate(text: String?, sourceApp: String?) {
        let verdict = TranslateSelectionRules.verdict(for: text)
        model.requestPresentation += 1
        model.isActive = true
        model.sourceApp = sourceApp
        model.isTranslating = false
        model.translationMeaning = ""
        model.translationError = nil
        model.savedToWordbook = false
        model.savedCard = nil

        switch verdict {
        case .translate(let resolved):
            model.text = resolved
            model.messageKey = nil
            startAITranslation(text: resolved)
        default:
            model.text = ""
            model.messageKey = TranslateSelectionRules.messageKey(for: verdict)
        }

        registerWorkspaceObserver()
        if panel == nil {
            let p = SurfacePanel(kind: .interactive, size: CGSize(width: 460, height: 200))
            p.host(TranslateSelectionView(model: model))
            panel = p
        } else {
            panel?.setContentSize(NSSize(width: 460, height: 200))
        }
        panel?.show(anchor: .spotlight)
        panel?.installClickOutside { [weak self] in
            guard let self else { return }
            self.dismiss()
        }
    }

    private func startAITranslation(text: String) {
        model.isTranslating = true
        model.translationError = nil
        model.translationMeaning = ""
        assistant.receive(text: text, meaning: "")
        let store = VocabularyStore.shared
        let blueprints = store.isLoaded ? store.library.blueprints : [:]
        assistant.analyze(module: .definition, overrides: blueprints)
        // Poll assistant state via observation — the view directly reads `assistant` via a wrapper
        // We bridge the assistant state into model properties so view stays simple.
        model.assistant = assistant
    }

    func saveToWordbook() {
        guard !assistant.meaning.isEmpty else { return }
        let card = assistant.card(wordbook: VocabularyLibrary.defaultWordbookID)
        Task {
            let saved = await VocabularyStore.shared.saveCard(card)
            if saved != nil {
                model.savedToWordbook = true
                model.savedCard = saved
                // Auto-dismiss after a brief moment
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if model.savedToWordbook { dismiss() }
            }
        }
    }

    func openWorkspace() {
        let text = model.text
        let meaning = model.translationMeaning
        dismiss()
        VocabularyWorkspaceController.shared.show(text: text, meaning: meaning)
    }

    func openVoiceSettings() {
        dismiss()
        AppState.shared.navigate(to: .voiceTyping)
        AppState.shared.bringMainWindowFront()
    }

    func dismiss() {
        unregisterWorkspaceObserver()
        assistant.invalidate()
        model.isActive = false
        model.isTranslating = false
        panel?.hide()
    }

    private func registerWorkspaceObserver() {
        guard workspaceObserver == nil else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self, self.model.isActive else { return }
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                self.dismiss()
            }
        }
    }

    private func unregisterWorkspaceObserver() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
    }

    // MARK: Legacy – kept for any remaining test references; no longer used by the view.
    func nativePresentationDidEnd(request: Int) {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, TranslateSelectionRules.shouldDismissHost(endedRequest: request,
                  currentRequest: self.model.requestPresentation,
                  hasTranslation: !self.model.translationMeaning.isEmpty, isActive: self.model.isActive) else { return }
            self.dismiss()
        }
    }

    func copyTranslation() {
        let t = model.translationMeaning
        guard !t.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents(); pb.setString(t, forType: .string)
        ClipboardSounds.playCopy()
    }
}

/// What the panel shows. Mutated by the controller; `requestPresentation` ticks when a new selection arrives.
@MainActor
@Observable
final class TranslateSelectionModel {
    var text = ""
    var sourceApp: String?
    var messageKey: String?
    /// AI translation state
    var isTranslating = false
    var translationMeaning = ""
    var translationError: String?
    var savedToWordbook = false
    var savedCard: VocabularyCard?
    /// Bridged assistant — view reads busy/messageKey/definition from it via withObservationTracking
    var assistant: TranslateAssistant?
    /// Ticks each time a new selection arrives so the view can reset state.
    var requestPresentation = 0
    var isActive = false
}
