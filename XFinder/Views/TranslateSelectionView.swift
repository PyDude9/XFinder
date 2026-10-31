import SwiftUI

/// N5a — the floating selection card: shows the selected text, instant Google Translate and dictionary definitions
/// stacked cleanly vertically, with audio pronunciation, on-demand AI analysis, and a one-tap save button.
struct TranslateSelectionView: View {
    var model: TranslateSelectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let k = model.messageKey {
                errorMessageRow(key: k)
            } else {
                headerRow
                phoneticsRow
                contentSection
                Divider()
                footerRow
            }
        }
        .padding(14)
        .frame(width: 410)
        .background(XFinderTokens.Fill.surface, in: RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile))
        .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile).stroke(XFinderTokens.Fill.hairline))
    }

    // MARK: Header Row (Word + Saved check + Heart button + Close)

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(model.text)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)

            Spacer(minLength: 4)

            if model.savedToWordbook {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.green)
                    .help(L10n.t("Đã lưu vào sổ từ"))
            }

            Button {
                TranslateSelectionController.shared.toggleSave()
            } label: {
                Image(systemName: model.savedToWordbook ? "heart.fill" : "heart")
                    .font(.system(size: 15))
                    .foregroundColor(model.savedToWordbook ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .help(model.savedToWordbook ? L10n.t("Đã lưu vào sổ từ") : L10n.t("Lưu vào sổ từ"))

            Button {
                TranslateSelectionController.shared.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.t("Đóng"))
            .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: Phonetics Row & On-demand AI Trigger

    private var phoneticsRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if !model.isSentence {
                Text("US")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundColor(.secondary)

                let phonetic = resolvedPhonetic
                if !phonetic.isEmpty {
                    Text("/\(phonetic)/")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Button {
                    TranslateSelectionController.shared.speak(text: model.text, language: "en-US")
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.t("Phát âm"))
            }

            Spacer(minLength: 4)

            // On-demand AI button: discreet, only shown if AI hasn't been run yet
            if (model.assistant?.meaning.isEmpty ?? true) && !(model.assistant?.busy ?? false) && !model.isTranslating {
                Button {
                    TranslateSelectionController.shared.analyzeWithAI()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles").font(.system(size: 10))
                        Text(L10n.t("Phân tích AI")).font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundColor(Color.purple)
                }
                .buttonStyle(.plain)
                .help(L10n.t("Phân tích AI"))
            }
        }
    }

    private var resolvedPhonetic: String {
        if let us = model.assistant?.definition?.phoneticUS, !us.isEmpty { return us }
        if let uk = model.assistant?.definition?.phoneticUK, !uk.isEmpty { return uk }
        return model.localPhonetic ?? ""
    }

    // MARK: Stacked Vertical Content (Google -> Dictionary -> AI)

    @ViewBuilder private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. Google Translate (Fast ~200ms default)
            googleTranslationSection

            // 2. Dictionary Senses (Parts of speech breakdown)
            if !model.localSenses.isEmpty && !model.isSentence {
                dictionarySensesSection
            } else if let snippet = model.localSnippet, !model.isSentence, model.localSenses.isEmpty {
                Text(snippet)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            // 3. AI Analysis & Synonyms (shown if triggered)
            if let assistant = model.assistant {
                if assistant.busy || model.isTranslating {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L10n.t("Đang dịch…")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                } else if !assistant.meaning.isEmpty {
                    aiDetailsSection(assistant: assistant)
                }
            }
        }
    }

    // MARK: Google Translation Section

    @ViewBuilder private var googleTranslationSection: some View {
        if model.isGoogleLoading && model.googleTranslation.isEmpty {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L10n.t("Đang dịch…")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        } else if !model.googleTranslation.isEmpty {
            Text(model.googleTranslation)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else if let err = model.googleError {
            Text(err).font(XFinderTokens.Font.caption).foregroundColor(.orange)
        }
    }

    // MARK: Dictionary Senses Section

    private var dictionarySensesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(model.localSenses.prefix(3))) { sense in
                HStack(alignment: .top, spacing: 8) {
                    Text(sense.pos)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.purple)
                        .frame(width: 28, height: 20)
                        .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))

                    Text(sense.meaning)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: AI Details Section

    private func aiDetailsSection(assistant: TranslateAssistant) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if assistant.meaning != model.googleTranslation && !assistant.meaning.isEmpty {
                Text(assistant.meaning)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if let def = assistant.definition, !def.synonyms.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(def.synonyms.prefix(4)), id: \.self) { syn in
                        Text(syn)
                            .font(.system(size: 11))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
    }

    // MARK: Footer Row (Review count badge, copy button, wordbook, settings)

    private var footerRow: some View {
        HStack(spacing: 8) {
            if let card = model.savedCard {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("\(card.review.repetition)")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.purple)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            } else if model.savedToWordbook {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("0")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.purple)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            Spacer(minLength: 0)

            Button {
                TranslateSelectionController.shared.copyTranslation()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.t("Sao chép bản dịch"))

            Button {
                TranslateSelectionController.shared.openWorkspace()
            } label: {
                Image(systemName: "book.pages")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.t("Sổ từ vựng"))

            Button {
                TranslateSelectionController.shared.openTranslateSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.t("Cài đặt…"))
        }
    }

    // MARK: Error state

    private func errorMessageRow(key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.t(key))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { TranslateSelectionController.shared.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            HStack {
                Spacer(minLength: 0)
                Button(L10n.t("Tra từ & lưu vào sổ")) {
                    let text = model.text
                    TranslateSelectionController.shared.dismiss()
                    VocabularyWorkspaceController.shared.show(text: text, meaning: "")
                }.controlSize(.small)
            }
        }
    }
}
