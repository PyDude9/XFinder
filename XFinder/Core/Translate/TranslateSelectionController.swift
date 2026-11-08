import AppKit
import Carbon
import NaturalLanguage
import SwiftUI

/// Structured sense for displaying dictionary definitions with Part of Speech badges.
struct ParsedSense: Identifiable, Sendable, Equatable {
    var id: String { pos + ":" + meaning }
    var pos: String
    var meaning: String
}

/// Available translation engines: Google Free Translate, AI (DeepSeek/Custom), and on-device macOS Dictionary.
enum TranslationEngine: String, CaseIterable, Identifiable, Sendable {
    case google = "google"
    case ai = "ai"
    case dictionary = "dictionary"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: return L10n.t("Google Dịch")
        case .ai: return L10n.t("Dịch AI")
        case .dictionary: return L10n.t("Từ điển")
        }
    }

    var icon: String {
        switch self {
        case .google: return "globe.asia.australia.fill"
        case .ai: return "sparkles"
        case .dictionary: return "character.book.closed"
        }
    }
}

/// Google Translate through the UNOFFICIAL `clients5.google.com/translate_a/t` endpoint (no API key, ~200 ms).
/// Not a documented API: it can be blocked or changed at any time. Sends the selected text to Google; the
/// Settings copy says so and the engine can be switched off (`translate.showGoogle`).
enum GoogleTranslateService {
    static func translate(text: String) async throws -> (translated: String, source: String, target: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "auto", "vi") }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let isVietnamese = (recognizer.dominantLanguage == .vietnamese)
        let target = isVietnamese ? "en" : "vi"

        var components = URLComponents(string: "https://clients5.google.com/translate_a/t")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "dict-chrome-ex"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "q", value: trimmed)
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let json = try JSONSerialization.jsonObject(with: data)
        let parsed = parseGoogleResponse(json)
        return (parsed, isVietnamese ? "vi" : "en", target)
    }

    private static func parseGoogleResponse(_ json: Any) -> String {
        if let strings = json as? [String] {
            return strings.joined(separator: " ")
        }
        if let arrays = json as? [[Any]] {
            return arrays.compactMap { $0.first as? String }.joined(separator: " ")
        }
        if let string = json as? String {
            return string
        }
        return ""
    }
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
    private var googleTask: Task<Void, Never>?
    let model = TranslateSelectionModel()

    /// Dedicated assistant; does not share state with VocabularyWorkspace.
    private let assistant = TranslateAssistant()

    private init() {}

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "translate.hotkeyEnabled") as? Bool ?? false }

    var showGoogle: Bool {
        UserDefaults.standard.object(forKey: "translate.showGoogle") as? Bool ?? true
    }

    var showDictionary: Bool {
        UserDefaults.standard.object(forKey: "translate.showDictionary") as? Bool ?? true
    }

    var showAI: Bool {
        UserDefaults.standard.object(forKey: "translate.showAI") as? Bool ?? false
    }

    var preferredEngine: TranslationEngine {
        get {
            let raw = UserDefaults.standard.string(forKey: "translate.preferredEngine") ?? "google"
            return TranslationEngine(rawValue: raw) ?? .google
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "translate.preferredEngine")
        }
    }

    var isAutoAIEnabled: Bool {
        UserDefaults.standard.bool(forKey: "translate.autoAI")
    }

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
        var text = VoiceScreenContext.selectedText()
        if text == nil || text?.isEmpty == true {
            let captured = SelectionWatcher.shared.currentSelectionText
            if !captured.isEmpty {
                text = captured
            }
        }
        if text == nil || text?.isEmpty == true {
            text = readSelectionViaClipboard()
        }
        translate(text: text, sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName)
    }

    private func readSelectionViaClipboard() -> String? {
        let pb = NSPasteboard.general
        let oldChangeCount = pb.changeCount
        let backup = TypingSink.capturePasteboard()

        let src = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false) else { return nil }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        // Poll briefly for pasteboard update (up to 120ms)
        let start = DispatchTime.now()
        var resultText: String?
        while DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds < 120_000_000 {
            if pb.changeCount != oldChangeCount {
                if let str = pb.string(forType: .string) {
                    let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count >= 2 {
                        resultText = trimmed
                        break
                    }
                }
            }
            usleep(10_000)
        }

        // Nothing was copied (no selection, or the app ignored ⌘C): the user's clipboard is untouched,
        // so there is nothing to restore — writing it back would only add a duplicate history entry.
        let copiedCount = pb.changeCount
        guard copiedCount != oldChangeCount else { return resultText }
        // This runs on the main thread, so the clipboard monitor cannot have ingested the copy yet.
        OwnWriteMark.shared.recordTransient(copiedCount)
        // Restore after a short delay so the target app has finished its copy. Restore only if nobody
        // copied anything since (a newer count is the user's), and an empty backup means "was empty".
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard pb.changeCount == copiedCount else { return }
            if backup.isEmpty { pb.clearContents() } else { TypingSink.restorePasteboard(backup) }
            OwnWriteMark.shared.recordTransient(pb.changeCount)
        }
        return resultText
    }

    /// Smart Selection's panel hands over the text it already read (the badge works whether or not ⇧⌘G is on).
    func translate(text: String?, sourceApp: String?, anchorRect: CGRect? = nil) {
        // Guarantee only ONE popup exists: hide any Smart Selection badge or panel immediately.
        SmartSelectionBadge.shared.hideAll()
        SelectionWatcher.shared.dismiss()

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
        model.googleTranslation = ""
        model.googleError = nil
        model.isGoogleLoading = false
        model.aiRequested = false

        let sg = showGoogle
        let sd = showDictionary
        let sa = showAI
        model.showGoogle = sg
        model.showDictionary = sd
        model.showAI = sa

        switch verdict {
        case .translate(let resolved):
            model.text = resolved
            model.messageKey = nil

            let words = resolved.split(separator: " ")
            model.isSentence = (words.count > 3 || resolved.count > 40)

            // 1. Instant on-device local dictionary lookup (1-2 ms), only if showDictionary is true
            if sd, let rawDef = DictionaryLookup.definition(resolved) {
                model.localDefinition = rawDef
                let parsed = Self.parseLocalDictionary(rawDef)
                model.localSyllables = parsed.syllables
                model.localPhonetic = parsed.phonetic
                model.localSnippet = parsed.snippet
                model.localSenses = parsed.senses
            }

            // Always initialize assistant with the term
            assistant.receive(text: resolved, meaning: "")

            // Check if term is already saved in wordbook
            let store = VocabularyStore.shared
            Task {
                if !store.isLoaded { await store.load() }
                if let existing = store.library.cards.first(where: {
                    $0.term.localizedCaseInsensitiveCompare(resolved) == .orderedSame
                }) {
                    self.model.savedToWordbook = true
                    self.model.savedCard = existing
                }
            }

            // 2. Start Google Translation (fast ~200 ms), only if showGoogle is true
            if sg {
                fetchGoogleTranslation(text: resolved)
            }

            // 3. ONLY run AI translation if explicitly enabled in Settings to avoid unnecessary Keychain/API calls
            if sa {
                startAITranslation(text: resolved)
            }
        default:
            model.text = ""
            model.messageKey = TranslateSelectionRules.messageKey(for: verdict)
        }

        showPanel(at: anchorRect)
    }

    private func showPanel(at anchorRect: CGRect? = nil) {
        var cardHeight: CGFloat = 110
        if model.showGoogle { cardHeight += 40 }
        if model.showDictionary {
            if !model.localSenses.isEmpty {
                cardHeight += CGFloat(min(model.localSenses.count, 3) * 26 + 8)
            } else if model.localSnippet != nil {
                cardHeight += 36
            }
        }
        if model.showAI { cardHeight += 50 }
        if !model.showGoogle && !model.showDictionary && !model.showAI {
            cardHeight += 50
        }
        let clampedHeight = max(160, min(cardHeight, 370))
        let cardSize = CGSize(width: 410, height: clampedHeight)
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
        panel?.orderFrontRegardless()
        panel?.installClickOutside { [weak self] in
            guard let self else { return }
            self.dismiss()
        }
    }

    func switchEngine(to engine: TranslationEngine) {
        model.engine = engine
        preferredEngine = engine
        if engine == .google && model.googleTranslation.isEmpty && !model.isGoogleLoading {
            fetchGoogleTranslation(text: model.text)
        } else if engine == .ai && (model.assistant?.meaning.isEmpty ?? true) && !(model.assistant?.busy ?? false) {
            startAITranslation(text: model.text)
        }
    }

    func analyzeWithAI() {
        guard !model.text.isEmpty else { return }
        model.aiRequested = true
        startAITranslation(text: model.text)
        updatePanelSize()
    }

    func updatePanelSize() {
        guard let panel, panel.isVisible else { return }
        var cardHeight: CGFloat = 110
        if model.showGoogle { cardHeight += 40 }
        if model.showDictionary {
            if !model.localSenses.isEmpty {
                cardHeight += CGFloat(min(model.localSenses.count, 3) * 26 + 8)
            } else if model.localSnippet != nil {
                cardHeight += 36
            }
        }
        if model.showAI || model.aiRequested { cardHeight += 70 }
        if !model.showGoogle && !model.showDictionary && !model.showAI && !model.aiRequested {
            cardHeight += 50
        }
        let clampedHeight = max(160, min(cardHeight, 420))
        var currentFrame = panel.frame
        let diff = clampedHeight - currentFrame.height
        if abs(diff) > 1 {
            currentFrame.origin.y -= diff
            currentFrame.size.height = clampedHeight
            panel.setFrame(currentFrame, display: true, animate: true)
        }
    }

    func fetchGoogleTranslation(text: String) {
        googleTask?.cancel()
        model.isGoogleLoading = true
        model.googleError = nil
        model.googleTranslation = ""
        googleTask = Task { @MainActor in
            do {
                let res = try await GoogleTranslateService.translate(text: text)
                guard !Task.isCancelled else { return }
                self.model.googleTranslation = res.translated
                self.model.isGoogleLoading = false
                if self.model.translationMeaning.isEmpty {
                    self.model.translationMeaning = res.translated
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.model.isGoogleLoading = false
                self.model.googleError = error.localizedDescription
            }
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
        let mod: TranslationBlueprintModule = model.isSentence ? .silentTranslate : .definition
        assistant.analyze(module: mod, overrides: blueprints)
        model.assistant = assistant

        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.assistant.busy {
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            self.model.isTranslating = false
            if !self.assistant.meaning.isEmpty {
                self.model.translationMeaning = self.assistant.meaning
            }
            self.updatePanelSize()
        }
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

    func toggleSave() {
        let store = VocabularyStore.shared
        if model.savedToWordbook, let existing = model.savedCard {
            Task {
                if !store.isLoaded { await store.load() }
                if await store.removeCard(id: existing.id) {
                    self.model.savedToWordbook = false
                    self.model.savedCard = nil
                }
            }
        } else {
            saveToWordbook()
        }
    }

    func saveToWordbook() {
        let store = VocabularyStore.shared
        let term = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        var meaning = ""
        if !model.googleTranslation.isEmpty {
            meaning = model.googleTranslation
        } else if let aiMeaning = assistant.meaning as String?, !aiMeaning.isEmpty {
            meaning = aiMeaning
        } else if !model.localSenses.isEmpty {
            meaning = model.localSenses.map { "\($0.pos) \($0.meaning)" }.joined(separator: "\n")
        } else if let snippet = model.localSnippet {
            meaning = snippet
        }
        if meaning.isEmpty {
            meaning = term
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(term)
        let isVietnamese = (recognizer.dominantLanguage == .vietnamese)
        let sourceLang = isVietnamese ? "vi" : "en"
        let targetLang = isVietnamese ? "en" : "vi"

        var definitions: [VocabularyDefinition] = []
        if let aiDefs = assistant.definition?.definitions, !aiDefs.isEmpty {
            definitions = aiDefs
        } else if !model.localSenses.isEmpty {
            definitions = model.localSenses.map {
                VocabularyDefinition(pos: $0.pos, meaningVi: $0.meaning)
            }
        }

        let card = VocabularyCard(
            term: term,
            language: sourceLang,
            targetLanguage: targetLang,
            meaning: meaning,
            context: "",
            syllables: model.localSyllables ?? assistant.definition?.syllables,
            phoneticUS: model.localPhonetic ?? assistant.definition?.phoneticUS,
            phoneticUK: assistant.definition?.phoneticUK,
            definitions: definitions,
            synonyms: assistant.definition?.synonyms ?? [],
            etymology: assistant.definition?.etymology,
            cefr: assistant.definition?.cefr,
            provenance: "Google Translate",
            wordbookID: VocabularyLibrary.defaultWordbookID
        )

        Task {
            if !store.isLoaded { await store.load() }
            let saved = await store.saveCard(card)
            if let saved {
                self.model.savedToWordbook = true
                self.model.savedCard = saved
            }
        }
    }

    func openWorkspace() {
        let text = model.text
        let meaning = model.translationMeaning
        dismiss()
        VocabularyWorkspaceController.shared.show(text: text, meaning: meaning)
    }

    func openTranslateSettings() {
        dismiss()
        AppState.shared.navigate(to: .smartSelect)
        AppState.shared.bringMainWindowFront()
    }

    func openVoiceSettings() {
        dismiss()
        AppState.shared.navigate(to: .voiceTyping)
        AppState.shared.bringMainWindowFront()
    }

    func dismiss() {
        assistant.invalidate()
        googleTask?.cancel()
        model.isActive = false
        model.isTranslating = false
        panel?.hide()
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
        var t = ""
        if !model.googleTranslation.isEmpty {
            t = model.googleTranslation
        } else if !assistant.meaning.isEmpty {
            t = assistant.meaning
        } else if !model.localSenses.isEmpty {
            t = model.localSenses.map { "\($0.pos) \($0.meaning)" }.joined(separator: "\n")
        } else if let snip = model.localSnippet {
            t = snip
        }
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
    /// Selected engines / flags
    var showGoogle = true
    var showDictionary = true
    var showAI = false
    var engine: TranslationEngine = .google
    var googleTranslation = ""
    var isGoogleLoading = false
    var googleError: String?
    /// AI translation state
    var isTranslating = false
    var translationMeaning = ""
    var translationError: String?
    var aiRequested = false
    var savedToWordbook = false
    var savedCard: VocabularyCard?
    /// Bridged assistant — view reads busy/messageKey/definition from it via withObservationTracking
    var assistant: TranslateAssistant?
    /// Ticks each time a new selection arrives so the view can reset state.
    var requestPresentation = 0
    var isActive = false
}
