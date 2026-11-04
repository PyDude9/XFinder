import AppKit
import AVFoundation
import NaturalLanguage
import Observation

@MainActor @Observable
final class TranslateAssistant {
    var text = ""
    var context = ""
    var meaning = ""
    var source = "und"
    var target = "vi"
    var output = ""
    var definition: VocabularyDefinitionResult?
    var busy = false
    var messageKey: String?
    private(set) var provenance: String?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let speaker = AVSpeechSynthesizer()

    func invalidate() {
        generation += 1; work?.cancel(); work = nil; busy = false
        definition = nil; output = ""; provenance = nil; messageKey = nil
    }
    func receive(text: String, meaning: String) {
        invalidate(); self.text = String(text.prefix(5_000)); self.meaning = meaning; context = ""
        let recognizer = NLLanguageRecognizer(); recognizer.processString(text)
        let detected = recognizer.dominantLanguage?.rawValue.split(separator: "-").first.map(String.init) ?? "und"
        source = ["en", "vi", "zh", "ja", "ko"].contains(detected) ? detected : "und"
        target = source == "vi" ? "en" : "vi"
    }
    func analyze(module: TranslationBlueprintModule, overrides: [String: String]) {
        invalidate()
        let token = generation
        let input: String
        do { input = try module.userInput(text: text, context: context, sourceLanguage: source, targetLanguage: target, template: overrides[module.rawValue + ".user"]) }
        catch { messageKey = "Nội dung quá dài hoặc ngôn ngữ chưa được hỗ trợ."; return }
        let config = VoiceSettingsSnapshot.read()
        guard let refiner = VoiceRefinerFactory.make(tier: config.tier, provider: config.provider,
            apiBaseURL: config.apiBaseURL, apiModel: config.apiModel,
            ollamaBaseURL: config.ollamaBaseURL, ollamaModel: config.ollamaModel) else {
            messageKey = "Hãy cấu hình AI trong trang Giọng nói trước khi phân tích."; return
        }
        let system = overrides[module.rawValue] ?? module.systemInstruction
        guard system.utf8.count <= 50_000, !system.contains("\0") else { messageKey = "Prompt không hợp lệ."; return }
        busy = true
        work = Task {
            do {
                let response = try await refiner.refine(RefineRequest(text: input, messages: [
                    RefineMessage(role: .system, content: system), RefineMessage(role: .user, content: input)]))
                try Task.checkCancellation()
                let validated = try module.validatedJSON(response)
                guard generation == token else { return }
                if module == .definition {
                    let result = try VocabularyDefinitionResult.decode(response)
                    definition = result; meaning = result.meaning
                }
                output = String(decoding: validated, as: UTF8.self)
                provenance = "AI: " + (config.tier == .customAPI ? config.provider.rawValue : config.tier.rawValue)
                busy = false
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                busy = false
                messageKey = (error as? RefinerError)?.messageKey ?? "AI trả về dữ liệu không đúng cấu trúc. Chưa lưu kết quả."
            }
        }
    }
    func speak(_ value: String, language: String) {
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: String(value.prefix(5_000)))
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        speaker.speak(utterance)
    }
    func stop() { invalidate(); speaker.stopSpeaking(at: .immediate) }

    func card(wordbook: UUID) -> VocabularyCard {
        let result = definition
        return VocabularyCard(term: text.trimmingCharacters(in: .whitespacesAndNewlines), language: source,
            targetLanguage: target, meaning: meaning, context: context,
            syllables: result?.syllables, phoneticUS: result?.phoneticUS, phoneticUK: result?.phoneticUK,
            definitions: result?.definitions ?? [], synonyms: result?.synonyms ?? [], etymology: result?.etymology,
            cefr: result?.cefr, provenance: provenance, wordbookID: wordbook)
    }
}
