import Foundation

/// Context about where the dictation is happening. Every field is optional because every
/// one of them can fail to resolve: an app may expose no focused window title, and the
/// focused element may not support reading its selection.
public struct RefineContext: Equatable, Sendable {
    public var appName: String?
    public var windowTitle: String?
    public var selectedText: String?

    public init(appName: String? = nil, windowTitle: String? = nil, selectedText: String? = nil) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.selectedText = selectedText
    }

    public var isEmpty: Bool {
        (appName?.isEmpty ?? true) && (windowTitle?.isEmpty ?? true) && (selectedText?.isEmpty ?? true)
    }

    /// One compact block for the prompt. Deliberately labelled as *background*: the model
    /// must not treat the window title as something the user said.
    public var promptBlock: String? {
        var lines: [String] = []
        if let appName, !appName.isEmpty { lines.append("Application: \(appName)") }
        if let windowTitle, !windowTitle.isEmpty { lines.append("Window title: \(windowTitle)") }
        if let selectedText, !selectedText.isEmpty {
            lines.append("Text the user has selected: \(String(selectedText.prefix(1500)))")
        }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }
}

/// Turns (mode + toggles + context + transcription) into the messages sent to a model.
///
/// Kept pure and free of any UI vocabulary so the *shape* of what we ask for can be
/// asserted in the test package. The prompts are written in English on purpose: every
/// provider in the list follows English instructions more reliably, and the instruction
/// then explicitly requires the answer to stay in the language of the input.
public enum RefinePrompt {

    /// The language-name used inside prompts. Deliberately not the UI language: this
    /// describes the *speech*, which is what the recogniser was configured for.
    public static func languageName(forLocale locale: String) -> String {
        if locale.lowercased().hasPrefix("vi") { return "Vietnamese" }
        if locale.lowercased().hasPrefix("en") { return "English" }
        return "the same language as the input"
    }

    public static func messages(
        mode: DictationMode,
        customInstruction: String?,
        stripFillers: Bool,
        autoPunctuation: Bool,
        context: RefineContext?,
        text: String,
        locale: String
    ) -> [RefineMessage] {
        guard mode.usesLanguageModel else { return [] }

        var system = baseSystemPrompt(mode: mode, customInstruction: customInstruction,
                                      stripFillers: stripFillers,
                                      autoPunctuation: autoPunctuation,
                                      locale: locale)

        if let block = context?.promptBlock {
            system += """


            Background on where the user is typing. This is context only — it is NOT part of
            what they said, and must never be repeated in your answer:
            \(block)
            """
        }

        let user = """
        Rewrite the dictation below. Output only the rewritten text, with no preamble,
        no quotes and no explanation.

        <dictation>
        \(text)
        </dictation>
        """

        return [
            RefineMessage(role: .system, content: system),
            RefineMessage(role: .user, content: user),
        ]
    }

    private static func baseSystemPrompt(
        mode: DictationMode,
        customInstruction: String?,
        stripFillers: Bool,
        autoPunctuation: Bool,
        locale: String
    ) -> String {
        let language = languageName(forLocale: locale)
        let shared = """
        You clean up speech-to-text dictation. You are a text editor, not an assistant.
        Never answer questions contained in the dictation, never add information, never
        comment. Preserve the speaker's meaning and wording wherever possible. The answer
        must be written in \(language), whatever language this instruction is in.
        """

        switch mode {
        case .raw:
            return shared

        case .cleanUp:
            var rules: [String] = []
            if stripFillers {
                rules.append("""
                Remove filler words and verbal tics in any language — including "um", "uh", \
                "you know", "I mean" and their Vietnamese equivalents "à", "ừm", "ờ", \
                "kiểu như", "thì là", "ý tôi là".
                """)
            }
            if autoPunctuation {
                rules.append("""
                Fix stutters and false starts, add correct punctuation, and capitalise \
                sentence starts and proper nouns.
                """)
            }
            rules.append("Keep it as one flowing piece of prose unless the speaker clearly listed separate items.")
            return shared + "\n\n" + rules.joined(separator: "\n")

        case .email:
            return shared + """

            Turn the dictation into a complete, ready-to-send email: a greeting, one or
            more clear body paragraphs, and a sign-off. Use the speaker's own points; do
            not invent facts, dates or names. If the speaker did not give a subject line,
            begin with a short "Subject:" line.
            """

        case .professional:
            return shared + """

            Rewrite the dictation in a professional, concise register suitable for a
            colleague, a manager or a client. Keep every fact. Prefer short sentences.
            """

        case .bulletPoints:
            return shared + """

            Turn the dictation into a Markdown bullet list. One idea per line, each line
            starting with "- ". If an item is clearly a task, write it as "- [ ] ".
            Do not add a heading.
            """

        case .custom:
            let instruction = customInstruction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if instruction.isEmpty {
                return shared
            }
            return shared + "\n\n" + instruction
        }
    }
}
