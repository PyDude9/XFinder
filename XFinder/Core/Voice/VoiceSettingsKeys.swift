import Foundation

/// Every `UserDefaults` key the Voice feature reads or writes, in one place.
///
/// The reason this exists as a named constant list rather than string literals at each call
/// site: CLAUDE.md Part 3b records a whole class of bug where a settings key was *stored*
/// but never read by the engine that was supposed to honour it, so the switch looked live
/// and did nothing. Naming the keys here makes `grep VoiceSettingsKey.` show every reader
/// and writer at once, and `VoiceSettingsTests` asserts each one has a default.
public enum VoiceSettingsKey {
    // Already shipped before this pass — kept identical so existing users keep their setting.
    public static let enabled = "voice.enabled"
    public static let language = "voice.language"
    /// Legacy: the single trigger keycode. Superseded by `triggerKey`, but still read once
    /// so a user who chose Left Option keeps it (see `VoiceConfig.migratedTrigger`).
    public static let legacyKeyCode = "voice.keyCode"

    // Trigger & activation.
    public static let triggerKey = "voice.triggerKey"
    public static let activationMode = "voice.activationMode"

    // Dictation.
    public static let dictationMode = "voice.dictationMode"
    public static let customModes = "voice.customModes"
    public static let stripFillers = "voice.stripFillers"
    public static let autoPunctuation = "voice.autoPunctuation"
    public static let customInstruction = "voice.customInstruction"

    // Refiner / model tier.
    public static let refinerTier = "voice.refinerTier"
    public static let apiProvider = "voice.apiProvider"
    public static let apiBaseURL = "voice.apiBaseURL"
    public static let ollamaBaseURL = "voice.ollamaBaseURL"
    public static let ollamaModel = "voice.ollamaModel"

    // Context.
    public static let screenContext = "voice.screenContext"
    public static let selectionContext = "voice.selectionContext"

    // Insert & review.
    public static let diffReview = "voice.diffReview"
    public static let restoreClipboard = "voice.restoreClipboard"

    // HUD & feedback.
    public static let hudAnchor = "voice.hudAnchor"
    public static let showWaveform = "voice.showWaveform"
    public static let audioCues = "voice.audioCues"

    /// Per-provider model override: `voice.apiModel.<kind>`.
    public static func apiModel(for kind: APIProviderKind) -> String { "voice.apiModel.\(kind.rawValue)" }
}

/// Pure helpers for the settings layer. Foundation-only so the test package can assert them.
public enum VoiceConfig {

    /// Reject a value that cannot possibly be an API key before it is written to the
    /// Keychain. Deliberately permissive — vendors change key formats — but it catches the
    /// real failure mode, which is a user pasting a URL, a whole `export` line, or a
    /// sentence that merely contains the word "key".
    public static func looksLikeAPIKey(_ raw: String) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 16, key.count <= 512 else { return false }
        guard !key.contains(" ") && !key.contains("\n") && !key.contains("\t") else { return false }
        guard !key.lowercased().hasPrefix("http://"), !key.lowercased().hasPrefix("https://") else { return false }
        // At least one letter and one digit or dash is the shape of every key we support.
        let hasLetter = key.contains { $0.isLetter }
        let hasOther = key.contains { $0.isNumber || $0 == "-" || $0 == "_" }
        return hasLetter && hasOther
    }

    /// A base URL is only usable if it parses and carries a scheme. The custom-provider
    /// field is the one place a user can type a bad value, so it is checked before saving.
    public static func looksLikeBaseURL(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return false }
        return true
    }

    /// Migrate the pre-existing single keycode to a named trigger, once.
    ///
    /// The old page hardcoded Right Option (61) and stored the code. A user who never
    /// opened that page has no value at all, and a user who did chose Left Option (58).
    /// Returns `nil` when there is nothing to migrate, so the caller can leave the stored
    /// trigger alone rather than overwriting a deliberate choice.
    public static func migratedTrigger(legacyKeyCode: Int64?) -> VoiceTriggerKey? {
        guard let code = legacyKeyCode else { return nil }
        switch code {
        case 58: return .leftOption
        case 54: return .rightCommand
        case 63: return .fnGlobe
        case 61: return .rightOption
        default: return nil
        }
    }

    /// The model to use for a provider: the user's override if they set one, else the
    /// vendor default. Kept here so the settings page, the test button and the runtime
    /// all resolve the model the same way.
    public static func resolvedModel(for kind: APIProviderKind, override: String?) -> String {
        let value = override?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? kind.defaultModel : value
    }

    /// Whether a tier is usable right now. `raw` mode never needs a provider, so the
    /// caller passes the mode and gets "no provider needed" for free.
    public static func requiresProvider(mode: DictationMode) -> Bool { mode.usesLanguageModel }
}

/// One read of every setting the Voice feature honours.
///
/// Reading them together, once, at the moment a session starts is what makes a session
/// self-consistent: the trigger that started it, the mode it will use and the provider it
/// will call cannot change underneath it half-way through. It also gives the test package a
/// single place to assert that **every** key has a default that agrees with its reader — the
/// bug CLAUDE.md Part 0 §5 records, where an `@AppStorage` default silently flipped a feature
/// for everyone who never touched it.
public struct VoiceSettingsSnapshot: Equatable, Sendable {
    public var enabled: Bool
    public var language: String
    public var triggerKey: VoiceTriggerKey
    public var activationMode: VoiceActivationMode

    public var mode: DictationMode
    public var customInstruction: String
    public var stripFillers: Bool
    public var autoPunctuation: Bool

    public var tier: VoiceRefinerTier
    public var provider: APIProviderKind
    public var apiBaseURL: String
    public var apiModel: String
    public var ollamaBaseURL: String
    public var ollamaModel: String

    public var screenContext: Bool
    public var selectionContext: Bool

    public var diffReview: Bool
    public var restoreClipboard: Bool

    public var hudAnchor: VoiceHUDAnchor
    public var showWaveform: Bool
    public var audioCues: Bool

    /// The defaults, as one value. The settings page's `@AppStorage` initial values must
    /// match these exactly; `VoiceSettingsTests` asserts it.
    public static let defaults = VoiceSettingsSnapshot(
        enabled: true,
        language: "vi-VN",
        triggerKey: .rightOption,
        activationMode: .hold,
        mode: .cleanUp,
        customInstruction: "",
        stripFillers: true,
        autoPunctuation: true,
        tier: .appleOnDevice,
        provider: .openai,
        apiBaseURL: "",
        apiModel: "",
        ollamaBaseURL: "http://localhost:11434",
        ollamaModel: "",
        screenContext: false,
        selectionContext: false,
        diffReview: false,
        restoreClipboard: true,
        hudAnchor: .caret,
        showWaveform: true,
        audioCues: false
    )

    public static func read(from store: UserDefaults = .standard) -> VoiceSettingsSnapshot {
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            store.object(forKey: key) as? Bool ?? fallback
        }
        func string(_ key: String, _ fallback: String) -> String {
            store.string(forKey: key) ?? fallback
        }

        let legacy = store.object(forKey: VoiceSettingsKey.legacyKeyCode) as? Int64
        let storedTrigger = store.string(forKey: VoiceSettingsKey.triggerKey)
            .flatMap(VoiceTriggerKey.init(rawValue:))
        // A stored trigger wins. Only when there is none does the old keycode get a say —
        // which is what makes the migration a one-time event rather than an override.
        let trigger = storedTrigger
            ?? VoiceConfig.migratedTrigger(legacyKeyCode: legacy)
            ?? VoiceSettingsSnapshot.defaults.triggerKey

        // The provider is resolved *before* the model, because the model's key is namespaced
        // by vendor: reading `voice.apiModel.openai` while the user has chosen Groq would hand
        // the request a model name that vendor does not serve. `provider` is therefore the
        // stored one, and only the fallback comes from the static defaults.
        let provider = store.string(forKey: VoiceSettingsKey.apiProvider)
            .flatMap(APIProviderKind.init(rawValue:)) ?? VoiceSettingsSnapshot.defaults.provider

        return VoiceSettingsSnapshot(
            enabled: bool(VoiceSettingsKey.enabled, VoiceSettingsSnapshot.defaults.enabled),
            language: string(VoiceSettingsKey.language, VoiceSettingsSnapshot.defaults.language),
            triggerKey: trigger,
            activationMode: store.string(forKey: VoiceSettingsKey.activationMode)
                .flatMap(VoiceActivationMode.init(rawValue:)) ?? VoiceSettingsSnapshot.defaults.activationMode,
            mode: store.string(forKey: VoiceSettingsKey.dictationMode)
                .flatMap(DictationMode.init(rawValue:)) ?? VoiceSettingsSnapshot.defaults.mode,
            customInstruction: string(VoiceSettingsKey.customInstruction, VoiceSettingsSnapshot.defaults.customInstruction),
            stripFillers: bool(VoiceSettingsKey.stripFillers, VoiceSettingsSnapshot.defaults.stripFillers),
            autoPunctuation: bool(VoiceSettingsKey.autoPunctuation, VoiceSettingsSnapshot.defaults.autoPunctuation),
            tier: store.string(forKey: VoiceSettingsKey.refinerTier)
                .flatMap(VoiceRefinerTier.init(rawValue:)) ?? VoiceSettingsSnapshot.defaults.tier,
            provider: provider,
            apiBaseURL: string(VoiceSettingsKey.apiBaseURL, VoiceSettingsSnapshot.defaults.apiBaseURL),
            apiModel: string(VoiceSettingsKey.apiModel(for: provider), VoiceSettingsSnapshot.defaults.apiModel),
            ollamaBaseURL: string(VoiceSettingsKey.ollamaBaseURL, VoiceSettingsSnapshot.defaults.ollamaBaseURL),
            ollamaModel: string(VoiceSettingsKey.ollamaModel, VoiceSettingsSnapshot.defaults.ollamaModel),
            screenContext: bool(VoiceSettingsKey.screenContext, VoiceSettingsSnapshot.defaults.screenContext),
            selectionContext: bool(VoiceSettingsKey.selectionContext, VoiceSettingsSnapshot.defaults.selectionContext),
            diffReview: bool(VoiceSettingsKey.diffReview, VoiceSettingsSnapshot.defaults.diffReview),
            restoreClipboard: bool(VoiceSettingsKey.restoreClipboard, VoiceSettingsSnapshot.defaults.restoreClipboard),
            hudAnchor: store.string(forKey: VoiceSettingsKey.hudAnchor)
                .flatMap(VoiceHUDAnchor.init(rawValue:)) ?? VoiceSettingsSnapshot.defaults.hudAnchor,
            showWaveform: bool(VoiceSettingsKey.showWaveform, VoiceSettingsSnapshot.defaults.showWaveform),
            audioCues: bool(VoiceSettingsKey.audioCues, VoiceSettingsSnapshot.defaults.audioCues)
        )
    }

    /// Persist the trigger and activation mode, so the page's pickers and the engine agree.
    public func writeTrigger(to defaults: UserDefaults = .standard) {
        defaults.set(triggerKey.rawValue, forKey: VoiceSettingsKey.triggerKey)
        defaults.set(activationMode.rawValue, forKey: VoiceSettingsKey.activationMode)
    }

    /// The messages that will be sent for this snapshot's mode, given a transcription.
    public func messages(for text: String, context: RefineContext?) -> [RefineMessage] {
        RefinePrompt.messages(
            mode: mode,
            customInstruction: customInstruction.isEmpty ? nil : customInstruction,
            stripFillers: stripFillers,
            autoPunctuation: autoPunctuation,
            context: context,
            text: text,
            locale: language
        )
    }
}
