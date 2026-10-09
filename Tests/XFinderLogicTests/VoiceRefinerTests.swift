import XCTest
import Foundation
@testable import XFinderLogicTests

/// Tests for the Voice-to-typing pure layer: the mode vocabulary, the settings snapshot and
/// its defaults, API-key validation, run-once trigger migration, the request builders and
/// response parsers for all four shapes, the word diff, and — the one that matters most for
/// this app — that **every string the model hands the UI** resolves to English in the real
/// shipped store.
///
/// That last test exists because of a failure this codebase has already had four times: a
/// string reaches the screen through `L10n.t(variable)`, so no literal sweep can see it, and
/// `L10n.t` silently falls back to the Vietnamese on a miss. Enumerating the vocabulary here
/// is the only gate that closes it.
final class VoiceRefinerTests: XCTestCase {

    // MARK: - DictationMode

    func testEveryDictationModeHasADistinctIdentityAndOnlyRawSkipsTheModel() {
        let modes = DictationMode.allCases
        XCTAssertEqual(Set(modes.map(\.rawValue)).count, modes.count, "raw values must be unique")
        XCTAssertEqual(Set(modes.map(\.labelKey)).count, modes.count, "labels must be unique")
        XCTAssertEqual(Set(modes.map(\.detailKey)).count, modes.count, "details must be unique")
        XCTAssertEqual(Set(modes.map(\.icon)).count, modes.count, "icons must be unique")

        // `raw` is the only path that works with no provider configured at all — that is what
        // makes "just give me my words" honest on a fresh install.
        let usingModel = modes.filter(\.usesLanguageModel)
        XCTAssertEqual(usingModel, [.cleanUp, .email, .professional, .bulletPoints, .custom])
        XCTAssertFalse(DictationMode.raw.usesLanguageModel)
    }

    func testBuiltInModesMatchTheDeclaredCases() {
        XCTAssertEqual(Set(DictationMode.builtIn), Set(DictationMode.allCases))
        XCTAssertEqual(DictationMode.builtIn.first, .raw)
        XCTAssertEqual(DictationMode.builtIn.last, .custom)
    }

    func testCustomModeRoundTripsThroughJSON() throws {
        let original = DictationMode.Custom(name: "Dịch sang tiếng Anh", instruction: "Translate to English.")
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([DictationMode.Custom].self, from: data)
        XCTAssertEqual(decoded, [original])
    }

    // MARK: - Trigger vocabulary

    func testTriggerKeyCodesAreTheHardwareCodesAndAreDistinct() {
        XCTAssertEqual(VoiceTriggerKey.rightOption.keyCode, 61)
        XCTAssertEqual(VoiceTriggerKey.leftOption.keyCode, 58)
        XCTAssertEqual(VoiceTriggerKey.rightCommand.keyCode, 54)
        XCTAssertEqual(VoiceTriggerKey.fnGlobe.keyCode, 63)

        let codes = VoiceTriggerKey.allCases.map(\.keyCode)
        XCTAssertEqual(Set(codes).count, codes.count, "two triggers must never share a keycode")

        // Only Fn is flagged as unreliable, because on some keyboards it is not delivered as a
        // normal keycode. Every other trigger gets no warning.
        XCTAssertNotNil(VoiceTriggerKey.fnGlobe.hintKey)
        for key in VoiceTriggerKey.allCases where key != .fnGlobe {
            XCTAssertNil(key.hintKey, "\(key) should not carry a caveat")
        }
    }

    // MARK: - Snapshot defaults vs the settings page

    /// The page's `@AppStorage` initial values and `VoiceSettingsSnapshot.defaults` are two
    /// declarations of the same thing. When they disagree, the feature silently behaves
    /// differently for every user who never touched the control (CLAUDE.md Part 0 §5). This
    /// reads the page's own source, so it fails if either side drifts.
    func testSnapshotDefaultsMatchThePageAppStorageInitialValues() throws {
        let url = L10nFixture.repoRoot().appendingPathComponent("XFinder/Views/Detail/VoiceDetailView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        let pattern = #"@AppStorage\(VoiceSettingsKey\.([A-Za-z]+)\)\s*private var [A-Za-z]+\s*=\s*([^\n]+)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let ns = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        XCTAssertGreaterThan(matches.count, 15, "the page's @AppStorage declarations were not found — the parse rotted")

        let d = VoiceSettingsSnapshot.defaults
        let expected: [String: String] = [
            "enabled": String(d.enabled),
            "language": d.language,
            "triggerKey": d.triggerKey.rawValue,
            "activationMode": d.activationMode.rawValue,
            "dictationMode": d.mode.rawValue,
            "customInstruction": d.customInstruction,
            "stripFillers": String(d.stripFillers),
            "autoPunctuation": String(d.autoPunctuation),
            "refinerTier": d.tier.rawValue,
            "apiProvider": d.provider.rawValue,
            "apiBaseURL": d.apiBaseURL,
            "ollamaBaseURL": d.ollamaBaseURL,
            "ollamaModel": d.ollamaModel,
            "screenContext": String(d.screenContext),
            "selectionContext": String(d.selectionContext),
            "diffReview": String(d.diffReview),
            "restoreClipboard": String(d.restoreClipboard),
            "hudAnchor": d.hudAnchor.rawValue,
            "showWaveform": String(d.showWaveform),
            "audioCues": String(d.audioCues),
        ]

        var seen: Set<String> = []
        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: source),
                  let valueRange = Range(match.range(at: 2), in: source) else { continue }
            let name = String(source[nameRange])
            let literal = Self.literalValue(from: String(source[valueRange]))
            seen.insert(name)

            guard let want = expected[name] else {
                XCTFail("@AppStorage(\(name)) is on the page but VoiceSettingsSnapshot has no such default")
                continue
            }
            XCTAssertEqual(literal, want,
                           "@AppStorage(\(name)) starts at \(literal) but the snapshot default is \(want)")
        }

        let missing = Set(expected.keys).subtracting(seen)
        XCTAssertTrue(missing.isEmpty, "the snapshot reads keys the page never declares: \(missing.sorted())")
    }

    /// Turn an `@AppStorage` initial value into the string the snapshot would hold: a quoted
    /// string loses its quotes, a `X.y.rawValue` expression keeps only `y`.
    private static func literalValue(from raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix(".rawValue") {
            let head = value.dropLast(".rawValue".count)
            return String(head.split(separator: ".").last ?? "")
        }
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    // MARK: - Reading the snapshot

    private func scratchDefaults() -> UserDefaults {
        let suite = "voice-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testSnapshotOnAnEmptyStoreIsExactlyTheDefaults() {
        let defaults = scratchDefaults()
        let snapshot = VoiceSettingsSnapshot.read(from: defaults)
        XCTAssertEqual(snapshot, VoiceSettingsSnapshot.defaults)
    }

    /// The model's key is namespaced by vendor, so the provider has to be resolved first.
    /// Reading `voice.apiModel.openai` while the user has chosen Groq would hand the request
    /// a model name that vendor does not serve.
    func testSnapshotReadsTheModelNamespacedToTheStoredProvider() {
        let defaults = scratchDefaults()
        defaults.set(APIProviderKind.groq.rawValue, forKey: VoiceSettingsKey.apiProvider)
        defaults.set("llama-3.3-70b-versatile", forKey: VoiceSettingsKey.apiModel(for: .groq))
        defaults.set("gpt-4o-mini", forKey: VoiceSettingsKey.apiModel(for: .openai))

        let snapshot = VoiceSettingsSnapshot.read(from: defaults)
        XCTAssertEqual(snapshot.provider, .groq)
        XCTAssertEqual(snapshot.apiModel, "llama-3.3-70b-versatile")
    }

    func testStoredTriggerWinsOverTheLegacyKeyCodeAndTheLegacyCodeMigratesOnce() {
        // A stored trigger is a deliberate choice and must never be overwritten by the
        // migration — including when the user deliberately picked the same key the legacy
        // code would have produced.
        let withBoth = scratchDefaults()
        withBoth.set(Int64(58), forKey: VoiceSettingsKey.legacyKeyCode)
        withBoth.set(VoiceTriggerKey.rightOption.rawValue, forKey: VoiceSettingsKey.triggerKey)
        XCTAssertEqual(VoiceSettingsSnapshot.read(from: withBoth).triggerKey, .rightOption)

        // Nothing stored: the legacy code decides, once.
        let legacyLeft = scratchDefaults()
        legacyLeft.set(Int64(58), forKey: VoiceSettingsKey.legacyKeyCode)
        XCTAssertEqual(VoiceSettingsSnapshot.read(from: legacyLeft).triggerKey, .leftOption)

        let legacyRight = scratchDefaults()
        legacyRight.set(Int64(61), forKey: VoiceSettingsKey.legacyKeyCode)
        XCTAssertEqual(VoiceSettingsSnapshot.read(from: legacyRight).triggerKey, .rightOption)
    }

    // MARK: - API key validation

    func testLooksLikeAPIKeyAcceptsRealisticKeysAndRejectsTheRealMistakes() {
        XCTAssertTrue(VoiceConfig.looksLikeAPIKey("sk-proj-abcdefghijklmnop1234"))
        XCTAssertTrue(VoiceConfig.looksLikeAPIKey("gsk_0123456789abcdefghij"))
        XCTAssertTrue(VoiceConfig.looksLikeAPIKey("  AIzaSyA-1234567890abcdef  "), "surrounding whitespace is trimmed")

        // The three things users actually paste by mistake.
        XCTAssertFalse(VoiceConfig.looksLikeAPIKey("https://platform.openai.com/api-keys"), "a URL is not a key")
        XCTAssertFalse(VoiceConfig.looksLikeAPIKey("export OPENAI_API_KEY=abcdefghijklmnop"), "a shell line is not a key")
        XCTAssertFalse(VoiceConfig.looksLikeAPIKey("my key is abcdefghijklmnop"), "a sentence is not a key")
        XCTAssertFalse(VoiceConfig.looksLikeAPIKey("short1"), "too short to be a key")
        XCTAssertFalse(VoiceConfig.looksLikeAPIKey(""), "empty")
        XCTAssertFalse(VoiceConfig.looksLikeAPIKey(String(repeating: "a", count: 513)), "absurdly long")
    }

    func testMigratedTriggerMapsTheFourKnownCodesAndNothingElse() {
        XCTAssertEqual(VoiceConfig.migratedTrigger(legacyKeyCode: 58), .leftOption)
        XCTAssertEqual(VoiceConfig.migratedTrigger(legacyKeyCode: 54), .rightCommand)
        XCTAssertEqual(VoiceConfig.migratedTrigger(legacyKeyCode: 63), .fnGlobe)
        XCTAssertEqual(VoiceConfig.migratedTrigger(legacyKeyCode: 61), .rightOption)
        XCTAssertNil(VoiceConfig.migratedTrigger(legacyKeyCode: 53), "Escape was never a trigger")
        XCTAssertNil(VoiceConfig.migratedTrigger(legacyKeyCode: nil))
    }

    func testResolvedModelPrefersTheUserOverrideAndFallsBackToTheVendorDefault() {
        XCTAssertEqual(VoiceConfig.resolvedModel(for: .openai, override: "gpt-4o"), "gpt-4o")
        XCTAssertEqual(VoiceConfig.resolvedModel(for: .openai, override: "   "), APIProviderKind.openai.defaultModel)
        XCTAssertEqual(VoiceConfig.resolvedModel(for: .groq, override: nil), APIProviderKind.groq.defaultModel)
    }

    // MARK: - Request building

    private var sampleMessages: [RefineMessage] {
        [RefineMessage(role: .system, content: "SYSTEM"),
         RefineMessage(role: .user, content: "USER")]
    }

    func testOpenAICompatibleRequest() throws {
        let request = try XCTUnwrap(RefinerRequestBuilder.request(
            kind: .openai, baseURL: "", model: "gpt-4o-mini", apiKey: "sk-abc", messages: sampleMessages))

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-abc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try Self.body(of: request)
        XCTAssertEqual(body["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual(body["stream"] as? Bool, false)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?["role"] as? String, "system")
    }

    func testAnthropicRequestSplitsTheSystemPromptOutOfTheMessages() throws {
        let request = try XCTUnwrap(RefinerRequestBuilder.request(
            kind: .anthropic, baseURL: "", model: "claude-3-5-haiku-latest", apiKey: "k", messages: sampleMessages))

        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "k")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

        let body = try Self.body(of: request)
        XCTAssertEqual(body["system"] as? String, "SYSTEM")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1, "Anthropic takes the system prompt as its own field")
        XCTAssertEqual(messages.first?["role"] as? String, "user")
    }

    func testGeminiRequestCarriesTheModelInThePathAndTheKeyInTheQuery() throws {
        let request = try XCTUnwrap(RefinerRequestBuilder.request(
            kind: .gemini, baseURL: "", model: "gemini-2.0-flash", apiKey: "k", messages: sampleMessages))

        XCTAssertEqual(request.url?.absoluteString,
                       "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=k")
        let body = try Self.body(of: request)
        XCTAssertNotNil(body["contents"])
        XCTAssertNotNil(body["systemInstruction"])
    }

    func testRequestBuilderRefusesAnUnusableConfiguration() {
        // A custom endpoint with no base URL has nowhere to go.
        XCTAssertNil(RefinerRequestBuilder.request(
            kind: .custom, baseURL: "", model: "m", apiKey: "k", messages: sampleMessages))
        // No model means no request.
        XCTAssertNil(RefinerRequestBuilder.request(
            kind: .openai, baseURL: "", model: "", apiKey: "k", messages: sampleMessages))
    }

    func testOllamaRequestTargetsItsOwnChatEndpoint() throws {
        let request = try XCTUnwrap(RefinerRequestBuilder.ollamaRequest(
            baseURL: "http://localhost:11434", model: "qwen2.5:7b", messages: sampleMessages))
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/chat")
        let body = try Self.body(of: request)
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertNotNil(body["options"])
    }

    // MARK: - Response parsing

    func testResponseParserHandlesEveryShape() throws {
        let openAI = Data(#"{"choices":[{"message":{"content":"  hello  "}}]}"#.utf8)
        XCTAssertEqual(RefinerResponseParser.text(kind: .openai, from: openAI), "hello")

        let anthropic = Data(#"{"content":[{"type":"text","text":"a"},{"type":"text","text":"b"}]}"#.utf8)
        XCTAssertEqual(RefinerResponseParser.text(kind: .anthropic, from: anthropic), "ab")

        let gemini = Data(#"{"candidates":[{"content":{"parts":[{"text":"x"},{"text":"y"}]}}]}"#.utf8)
        XCTAssertEqual(RefinerResponseParser.text(kind: .gemini, from: gemini), "xy")

        // An error delivered with HTTP 200 is still an error, not a rewrite.
        let errorWith200 = Data(#"{"error":{"message":"invalid api key"}}"#.utf8)
        XCTAssertNil(RefinerResponseParser.text(kind: .openai, from: errorWith200))
        XCTAssertEqual(RefinerResponseParser.errorMessage(from: errorWith200), "invalid api key")

        // Unrecognised shapes return nil rather than an empty string, so a provider change
        // surfaces as `.badResponse` instead of silently inserting nothing.
        XCTAssertNil(RefinerResponseParser.text(kind: .openai, from: Data(#"{"nope":1}"#.utf8)))
        XCTAssertNil(RefinerResponseParser.text(kind: .gemini, from: Data("not json".utf8)))
    }

    func testOllamaParsers() throws {
        let chat = Data(#"{"message":{"content":" rewritten "}}"#.utf8)
        XCTAssertEqual(RefinerResponseParser.ollamaText(from: chat), "rewritten")
        XCTAssertNil(RefinerResponseParser.ollamaText(from: Data(#"{"message":{"content":"   "}}"#.utf8)))

        let tags = Data(#"{"models":[{"name":"qwen2.5:7b"},{"name":"llama3.2"}]}"#.utf8)
        XCTAssertEqual(RefinerResponseParser.ollamaModelNames(from: tags), ["llama3.2", "qwen2.5:7b"])
        XCTAssertEqual(RefinerResponseParser.ollamaModelNames(from: Data("{}".utf8)), [])
    }

    private static func body(of request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Diff

    func testVoiceTextDiffGroupsRunsAndReportsChangedWords() {
        XCTAssertEqual(VoiceTextDiff.runs(from: "a b c", to: "a b c"),
                       [DiffRun(status: .same, text: "a b c")])
        XCTAssertEqual(VoiceTextDiff.runs(from: "", to: ""), [])
        XCTAssertTrue(VoiceTextDiff.isIdentical(from: "a  b", to: "a b"), "tokenising, not byte-comparing")
        XCTAssertEqual(VoiceTextDiff.changedTokenCount(from: "a b c", to: "a b c"), 0)

        let runs = VoiceTextDiff.runs(from: "i want to go", to: "I want to go home")
        XCTAssertEqual(runs.filter { $0.status == .same }.map(\.text).joined(separator: " "), "want to go")
        XCTAssertEqual(runs.filter { $0.status == .removed }.map(\.text).joined(separator: " "), "i")
        XCTAssertEqual(runs.filter { $0.status == .added }.map(\.text).joined(separator: " "), "I home")
        XCTAssertEqual(VoiceTextDiff.changedTokenCount(from: "i want to go", to: "I want to go home"), 3,
                       "one word replaced (i -> I) counts as two changes, plus the added word")
        XCTAssertFalse(VoiceTextDiff.isIdentical(from: "i want to go", to: "I want to go home"))
    }

    func testVoiceTextDiffCapsAbsurdInputRatherThanAllocatingForIt() {
        let huge = Array(repeating: "word", count: VoiceTextDiff.maxTokens + 50).joined(separator: " ")
        let runs = VoiceTextDiff.runs(from: huge, to: "short")
        XCTAssertEqual(runs.map(\.status), [.removed, .added], "past the cap it reports one removed and one added run")
    }

    // MARK: - Factory

    func testRawModeNeverNeedsAProvider() {
        XCTAssertNil(VoiceRefinerFactory.resolvedTier(mode: .raw, configured: .customAPI))
        XCTAssertEqual(VoiceRefinerFactory.resolvedTier(mode: .cleanUp, configured: .ollama), .ollama)
    }

    func testSubscriptionTierIsDeliberatelyNotBuildable() {
        // There is no public OAuth that grants API access to a ChatGPT Plus / Claude Pro
        // subscription, so the factory returns nil and the page says so instead of shipping a
        // login that cannot work.
        XCTAssertNil(VoiceRefinerFactory.make(
            tier: .subscription, provider: .openai, apiBaseURL: "", apiModel: "gpt-4o",
            ollamaBaseURL: "http://localhost:11434", ollamaModel: "qwen2.5:7b"))
    }

    func testAppleTierIsAlwaysBuildableBecauseItNeedsNoConfiguration() {
        XCTAssertNotNil(VoiceRefinerFactory.make(
            tier: .appleOnDevice, provider: .openai, apiBaseURL: "", apiModel: "",
            ollamaBaseURL: "", ollamaModel: ""))
    }

    // MARK: - The vocabulary gate

    /// Every string the model hands to `L10n.t(variable)` must resolve to English in the real
    /// shipped store, and must be a plain key — never one carrying an interpolation, which can
    /// never match an entry.
    func testEveryVoiceVocabularyKeyResolvesToEnglishInTheShippedStore() throws {
        let store = try L10nFixture.load()
        // Brand names are spelled the same in both languages on purpose, and the allowlist is
        // where that is recorded. Everything else must actually translate.
        let sameByDesign = try L10nFixture.allowlist()

        var keys: [String] = []
        for mode in DictationMode.allCases { keys += [mode.labelKey, mode.detailKey] }
        for trigger in VoiceTriggerKey.allCases {
            keys.append(trigger.labelKey)
            if let hint = trigger.hintKey { keys.append(hint) }
        }
        for activation in VoiceActivationMode.allCases { keys += [activation.labelKey, activation.detailKey] }
        for anchor in VoiceHUDAnchor.allCases { keys += [anchor.labelKey, anchor.detailKey] }
        for tier in VoiceRefinerTier.allCases { keys += [tier.labelKey, tier.detailKey] }
        for provider in APIProviderKind.allCases { keys.append(provider.labelKey) }

        let errors: [RefinerError] = [
            .notConfigured, .missingKey, .unavailable("why"), .http(401, "body"),
            .badResponse, .transport("why"), .cancelled,
        ]
        for error in errors { keys.append(error.messageKey) }

        // Guards against the "green over nothing" shape: an empty or shrunken vocabulary would
        // otherwise pass every assertion below without checking anything.
        XCTAssertGreaterThan(keys.count, 40, "the vocabulary list collapsed")

        for key in keys {
            XCTAssertFalse(L10nFixtures.interpolates(key),
                           "\(key) is passed to L10n.t as a whole but contains an interpolation, so it can never match")
            let english = store.entries[key]?.en ?? ""
            XCTAssertFalse(english.isEmpty, "no English for \(key)")
            if !sameByDesign.contains(key) {
                XCTAssertNotEqual(english, key,
                                  "\(key) translates to itself and is not on the sameByDesign allowlist")
            }
        }
    }

    /// The on-device reasons reach the UI through `L10n.t(variable)`, so no literal sweep can
    /// see them. `AppleOnDeviceRefiner.knownReasonKeys` exists purely to make them enumerable,
    /// and this asserts each one resolves against the real shipped store.
    func testAppleOnDeviceReasonKeysResolveToEnglish() throws {
        let keys = AppleOnDeviceRefiner.knownReasonKeys
        XCTAssertGreaterThanOrEqual(keys.count, 5, "the reason vocabulary collapsed")

        let store = try L10nFixture.load()
        for key in keys {
            XCTAssertFalse(L10nFixtures.interpolates(key),
                           "\(key) contains an interpolation, so it can never match a store entry")
            let english = store.entries[key]?.en ?? ""
            XCTAssertFalse(english.isEmpty, "no English for the on-device reason \(key)")
            XCTAssertNotEqual(english, key, "\(key) translates to itself")
        }
    }

    /// A picker label that is a bare locale tag would be untranslatable; the two options the
    /// page offers must both be real keys.
    func testThePageUsesKeyedLabelsForBothRecognitionLanguages() {
        XCTAssertFalse(L10nFixtures.interpolates("Tiếng Việt (vi-VN)"))
        XCTAssertFalse(L10nFixtures.interpolates("Tiếng Anh (en-US)"))
    }
}
