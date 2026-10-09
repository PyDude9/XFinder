import Foundation

/// Builds the refiner for the currently configured tier.
///
/// Deliberately a factory over plain values rather than a singleton holding its own state:
/// the settings page, the "test connection" button and the runtime all need the same
/// resolution, and the only way to guarantee they agree is for them to call one function.
/// A refiner is cheap to construct — it is a URLSession configuration and some strings — so
/// building a fresh one per use removes any question of stale configuration.
public enum VoiceRefinerFactory {

    public static func make(
        tier: VoiceRefinerTier,
        provider: APIProviderKind,
        apiBaseURL: String,
        apiModel: String,
        ollamaBaseURL: String,
        ollamaModel: String
    ) -> TranscriptRefiner? {
        switch tier {
        case .appleOnDevice:
            return AppleOnDeviceRefiner()

        case .ollama:
            guard !ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return OllamaRefiner(baseURL: ollamaBaseURL, model: ollamaModel)

        case .customAPI:
            guard let key = VoiceKeychain.apiKey(for: provider), !key.isEmpty else { return nil }
            let model = VoiceConfig.resolvedModel(for: provider, override: apiModel)
            let base = provider == .custom ? apiBaseURL : provider.defaultBaseURL
            guard !model.isEmpty, !base.isEmpty else { return nil }
            return HTTPRefiner(kind: provider, baseURL: base, model: model, apiKey: key)

        case .subscription:
            // Not implemented, on purpose. See the settings page and docs/VOICE.md: there is
            // no public OAuth that grants API access for a ChatGPT Plus / Claude Pro
            // subscription, and "log in with your account" would mean replaying the web
            // app's private endpoints with the user's session cookie. That is against both
            // providers' terms, breaks on any front-end change, and is exactly the class of
            // undocumented private surface this app refuses to build on. Returning nil here
            // is what makes the UI say "not available" instead of shipping a fake login.
            return nil
        }
    }

    /// Resolve the tier that should actually be used for a given dictation mode.
    ///
    /// `raw` never needs a provider, so it is answered without touching the configuration —
    /// which is what makes "just give me my words" work on a machine with nothing set up.
    public static func resolvedTier(
        mode: DictationMode,
        configured: VoiceRefinerTier
    ) -> VoiceRefinerTier? {
        guard mode.usesLanguageModel else { return nil }
        return configured
    }
}
