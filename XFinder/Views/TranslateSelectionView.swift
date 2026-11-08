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
            if !model.showGoogle && !model.showDictionary && !model.showAI {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("Chưa bật dịch vụ dịch nào trong Cài đặt."))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                    Button(L10n.t("Mở Cài đặt")) {
                        TranslateSelectionController.shared.openTranslateSettings()
                    }
                    .controlSize(.small)
                }
            }

            // 1. Google Translate for sentence, or Dictionary + Web senses for words
            if model.isSentence {
                if model.showGoogle {
                    googleTranslationSection
                }
            } else {
                // Dictionary Senses (Parts of speech breakdown)
                if model.showDictionary {
                    if !model.localSenses.isEmpty {
                        dictionarySensesSection
                    } else if let snippet = model.localSnippet, model.localSenses.isEmpty {
                        Text(snippet)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }

                // Web / Google sense
                if model.showGoogle {
                    if model.isGoogleLoading && model.googleTranslation.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L10n.t("Đang dịch…")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    } else if !model.googleTranslation.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Text("web.")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(posColor(for: "web."))
                                .frame(width: 38, height: 20)
                                .background(posColor(for: "web.").opacity(0.12), in: RoundedRectangle(cornerRadius: 5))

                            Text(model.googleTranslation)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    } else if let err = model.googleError {
                        Text(err).font(XFinderTokens.Font.caption).foregroundColor(.orange)
                    }
                }
            }

            // 3. AI Analysis & Synonyms (shown if enabled or requested via ✨ button)
            if model.showAI || model.aiRequested {
                aiSection
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
                        .foregroundColor(posColor(for: sense.pos))
                        .frame(width: 28, height: 20)
                        .background(posColor(for: sense.pos).opacity(0.12), in: RoundedRectangle(cornerRadius: 5))

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

    private func posColor(for pos: String) -> Color {
        let clean = pos.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.contains("adj") { return Color.pink }
        if clean.contains("noun") || clean == "n." || clean == "n" { return Color.purple }
        if clean.contains("verb") || clean == "v." || clean == "v" { return Color.blue }
        if clean.contains("adv") { return Color.orange }
        if clean.contains("web") { return Color(red: 0.55, green: 0.25, blue: 0.95) }
        return Color.accentColor
    }

    // MARK: AI Details Section

    @ViewBuilder private var aiSection: some View {
        if let assistant = model.assistant {
            if assistant.busy || model.isTranslating {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("Đang dịch AI…")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            } else if !assistant.meaning.isEmpty {
                aiDetailsSection(assistant: assistant)
            } else if let k = assistant.messageKey {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(k)).font(XFinderTokens.Font.caption).foregroundColor(.orange)
                    if k.contains("Chọn thông minh") || k.contains("Cài đặt") || k.contains("cấu hình") {
                        Button(L10n.t("Mở Cài đặt")) {
                            TranslateSelectionController.shared.openTranslateSettings()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

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

    // MARK: Footer Row (Review count badge, copy button, wordbook, sparkles AI, settings)

    private var footerRow: some View {
        HStack(spacing: 8) {
            let repetition = model.savedCard?.review.repetition ?? 1
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                Text("\(repetition)")
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(Color(red: 0.45, green: 0.25, blue: 0.95))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(red: 0.45, green: 0.25, blue: 0.95).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

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
                guard !(model.assistant?.busy == true || model.isTranslating) else { return }
                TranslateSelectionController.shared.analyzeWithAI()
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundColor((model.showAI || model.aiRequested) && model.assistant?.meaning.isEmpty == false ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(model.assistant?.busy == true || model.isTranslating)
            .help(L10n.t("Dịch bằng AI"))

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
