import AppKit
import Carbon
import SwiftUI

/// Structured sense for displaying dictionary definitions with Part of Speech badges.
struct ParsedSense: Identifiable, Sendable, Equatable {
    var id: String { pos + ":" + meaning }
    var pos: String
    var meaning: String
}

/// N5a — the live half of "Dịch vùng chọn": a Carbon hotkey (⇧⌘G, the same mechanism as ⌘K), the Accessibility read
/// of the focused element's selection (the Voice module's helper), and a floating panel positioned near the selection
/// hosting an inline AI-translation and dictionary card. ONE reader of `translate.hotkeyEnabled`. Off ⇒ no hotkey, no panel.
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
    func translate(text: String?, sourceApp: String?, anchorRect: CGRect? = nil) {
        let verdict = TranslateSelectionRules.verdict(for: text)
        model.requestPresentation += 1
        model.isActive = true
        model.sourceApp = sourceApp
        model.isTranslating = false
        model.translationMeaning = ""
        model.translationError = nil
        model.savedToWordbook = false
        model.savedCard = nil
        model.localDefinition = nil
        model.localSyllables = nil
        model.localPhonetic = nil
        model.localSnippet = nil
        model.localSenses = []
        model.isSentence = false

        switch verdict {
        case .translate(let resolved):
            model.text = resolved
            model.messageKey = nil

            let words = resolved.split(separator: " ")
            model.isSentence = (words.count > 3 || resolved.count > 40)

            // Instant on-device local dictionary lookup (1-2 ms)
            if let rawDef = DictionaryLookup.definition(resolved) {
                model.localDefinition = rawDef
                let parsed = Self.parseLocalDictionary(rawDef)
                model.localSyllables = parsed.syllables
                model.localPhonetic = parsed.phonetic
                model.localSnippet = parsed.snippet
                model.localSenses = parsed.senses
            }

            // Check if term is already saved in wordbook
            let store = VocabularyStore.shared
            if !store.isLoaded { Task { await store.load() } }
            if let existing = store.library.cards.first(where: {
                $0.term.localizedCaseInsensitiveCompare(resolved) == .orderedSame
            }) {
                model.savedToWordbook = true
                model.savedCard = existing
            }

            startAITranslation(text: resolved)
        default:
            model.text = ""
            model.messageKey = TranslateSelectionRules.messageKey(for: verdict)
        }

        showPanel(at: anchorRect)
    }

    private func showPanel(at anchorRect: CGRect? = nil) {
        registerWorkspaceObserver()
        let cardSize = CGSize(width: 400, height: 250)
        if panel == nil {
            let p = SurfacePanel(kind: .interactive, size: cardSize)
            p.host(TranslateSelectionView(model: model))
            panel = p
        } else {
            panel?.setContentSize(NSSize(width: cardSize.width, height: cardSize.height))
        }

        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin: CGPoint
        if let anchorRect {
            origin = CGPoint(x: anchorRect.minX, y: anchorRect.minY - cardSize.height - 6)
            if origin.y < visible.minY { origin.y = anchorRect.maxY + 6 }
        } else {
            origin = CGPoint(x: pointer.x - cardSize.width / 2, y: pointer.y - cardSize.height - 12)
            if origin.y < visible.minY { origin.y = pointer.y + 12 }
        }
        let clamped = SurfaceGeometry.clamp(CGRect(origin: origin, size: cardSize), into: visible)
        panel?.setFrame(clamped, display: true)
        panel?.makeKeyAndOrderFront(nil)
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
        Task { if !store.isLoaded { await store.load() } }
        let blueprints = store.isLoaded ? store.library.blueprints : [:]
        assistant.analyze(module: .definition, overrides: blueprints)
        model.assistant = assistant
    }

    static func parseLocalDictionary(_ raw: String) -> (syllables: String?, phonetic: String?, snippet: String, senses: [ParsedSense]) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var syllables: String?
        var phonetic: String?
        var snippet = trimmed
        var senses: [ParsedSense] = []

        let pipeParts = trimmed.components(separatedBy: "|")
        if pipeParts.count >= 2 {
            let beforeFirstPipe = pipeParts[0].trimmingCharacters(in: .whitespaces)
            let wordsBefore = beforeFirstPipe.split(separator: " ").map(String.init)
            if wordsBefore.count >= 2 {
                syllables = wordsBefore.dropFirst().joined(separator: " ")
            }
            let ipaPart = pipeParts[1].trimmingCharacters(in: .whitespaces)
            if !ipaPart.isEmpty { phonetic = ipaPart }
            if pipeParts.count >= 3 {
                snippet = pipeParts.dropFirst(2).joined(separator: "|").trimmingCharacters(in: .whitespaces)
            }
        }

        let body = pipeParts.count >= 3 ? pipeParts.dropFirst(2).joined(separator: "|") : trimmed
        let posPatterns: [(regex: String, badge: String)] = [
            ("danh từ", "n."),
            ("ngoại động từ", "v."),
            ("nội động từ", "v."),
            ("động từ", "v."),
            ("tính từ", "adj."),
            ("phó từ|trạng từ", "adv."),
            ("giới từ", "prep."),
            ("liên từ", "conj."),
            ("thán từ", "interj."),
            ("\\bnoun\\b", "n."),
            ("\\btransitive verb\\b|\\bintransitive verb\\b|\\bverb\\b", "v."),
            ("\\badjective\\b", "adj."),
            ("\\badverb\\b", "adv.")
        ]

        var markers: [(badge: String, range: Range<String.Index>)] = []
        for pattern in posPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern.regex, options: .caseInsensitive) {
                let nsRange = NSRange(body.startIndex..<body.endIndex, in: body)
                let matches = regex.matches(in: body, options: [], range: nsRange)
                for m in matches {
                    if let r = Range(m.range, in: body) {
                        markers.append((pattern.badge, r))
                    }
                }
            }
        }

        markers.sort { $0.range.lowerBound < $1.range.lowerBound }
        var filteredMarkers: [(badge: String, range: Range<String.Index>)] = []
        for m in markers {
            if let last = filteredMarkers.last, m.range.lowerBound < last.range.upperBound {
                continue
            }
            filteredMarkers.append(m)
        }

        if filteredMarkers.isEmpty && !snippet.isEmpty {
            senses.append(ParsedSense(pos: "def.", meaning: snippet))
        } else {
            for i in 0..<filteredMarkers.count {
                let current = filteredMarkers[i]
                let nextStart = (i + 1 < filteredMarkers.count) ? filteredMarkers[i + 1].range.lowerBound : body.endIndex
                let sectionText = String(body[current.range.upperBound..<nextStart])

                var defs: [String] = []
                let rawItems = sectionText.components(separatedBy: CharacterSet(charactersIn: "0123456789"))
                for item in rawItems {
                    var cleaned = item
                    if let exampleIndex = cleaned.range(of: "▸") {
                        cleaned = String(cleaned[..<exampleIndex.lowerBound])
                    }
                    if let synIndex = cleaned.range(of: "từ đồng nghĩa") {
                        cleaned = String(cleaned[..<synIndex.lowerBound])
                    }
                    if let antIndex = cleaned.range(of: "từ trái nghĩa") {
                        cleaned = String(cleaned[..<antIndex.lowerBound])
                    }
                    cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                                     .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";,.")))
                    if !cleaned.isEmpty && cleaned.count > 2 && !defs.contains(cleaned) {
                        defs.append(cleaned)
                        if defs.count >= 3 { break }
                    }
                }
                let meaning = defs.joined(separator: "; ")
                if !meaning.isEmpty {
                    senses.append(ParsedSense(pos: current.badge, meaning: meaning))
                }
            }
        }

        return (syllables, phonetic, snippet, senses)
    }

    func speak(text: String, language: String = "en-US") {
        assistant.speak(text, language: language)
    }

    func saveToWordbook() {
        let store = VocabularyStore.shared
        var meaning = assistant.meaning
        if meaning.isEmpty {
            if !model.localSenses.isEmpty {
                meaning = model.localSenses.map { "\($0.pos) \($0.meaning)" }.joined(separator: "\n")
            } else if let snippet = model.localSnippet {
                meaning = snippet
            }
        }
        guard !meaning.isEmpty || !model.text.isEmpty else { return }

        var card = assistant.card(wordbook: VocabularyLibrary.defaultWordbookID)
        if card.meaning.isEmpty {
            card.meaning = meaning
        }
        if card.phoneticUS == nil || card.phoneticUS?.isEmpty == true {
            card.phoneticUS = model.localPhonetic
        }
        if card.syllables == nil || card.syllables?.isEmpty == true {
            card.syllables = model.localSyllables
        }

        Task {
            if !store.isLoaded { await store.load() }
            let saved = await store.saveCard(card)
            if let saved {
                model.savedToWordbook = true
                model.savedCard = saved
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
        var t = model.translationMeaning
        if t.isEmpty, !assistant.meaning.isEmpty { t = assistant.meaning }
        if t.isEmpty {
            t = model.localSenses.map { "\($0.pos) \($0.meaning)" }.joined(separator: "\n")
        }
        if t.isEmpty, let snip = model.localSnippet { t = snip }
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
    /// Instant on-device local dictionary result (1-2 ms)
    var localDefinition: String?
    var localSyllables: String?
    var localPhonetic: String?
    var localSnippet: String?
    var localSenses: [ParsedSense] = []
    var isSentence = false
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
