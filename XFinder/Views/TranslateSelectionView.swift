import SwiftUI

/// N5a — the floating selection card: shows the selected text and its translation inline,
/// with instant on-device dictionary lookup while AI translates, audio pronunciation, and a one-tap save button.
struct TranslateSelectionView: View {
    var model: TranslateSelectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let k = model.messageKey {
                errorMessageRow(key: k)
            } else {
                headerRow
                if !model.isSentence {
                    phoneticRow
                    sensesSection
                } else {
                    sentenceSection
                }
                Divider()
                footerRow
            }
        }
        .padding(14)
        .frame(width: 400)
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
                TranslateSelectionController.shared.saveToWordbook()
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

    // MARK: Sub-header (Phonetic & Audio Speaker)

    private var phoneticRow: some View {
        HStack(alignment: .center, spacing: 8) {
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

            Spacer(minLength: 0)
        }
    }

    private var resolvedPhonetic: String {
        if let us = model.assistant?.definition?.phoneticUS, !us.isEmpty { return us }
        if let uk = model.assistant?.definition?.phoneticUK, !uk.isEmpty { return uk }
        return model.localPhonetic ?? ""
    }

    // MARK: Senses Section (POS Badges + Meanings)

    @ViewBuilder private var sensesSection: some View {
        let senses = resolvedSenses
        if !senses.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(senses) { sense in
                    HStack(alignment: .top, spacing: 8) {
                        Text(sense.pos)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.purple)
                            .frame(width: 28, height: 20)
                            .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))

                        Text(sense.meaning)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
        } else if let assistant = model.assistant, !assistant.meaning.isEmpty {
            Text(assistant.meaning)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else if (model.assistant?.busy ?? false) || model.isTranslating {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L10n.t("Đang dịch…"))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var resolvedSenses: [ParsedSense] {
        if !model.localSenses.isEmpty {
            return Array(model.localSenses.prefix(3))
        }
        if let aiDefs = model.assistant?.definition?.definitions, !aiDefs.isEmpty {
            return aiDefs.prefix(3).map { def in
                let posBadge = formatPOSBadge(def.pos)
                let meaning = def.meaningVi.isEmpty ? def.meaningEn : def.meaningVi
                return ParsedSense(pos: posBadge, meaning: meaning)
            }
        }
        return []
    }

    private func formatPOSBadge(_ raw: String) -> String {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.contains("noun") || lower == "n" || lower == "n." { return "n." }
        if lower.contains("verb") || lower == "v" || lower == "v." { return "v." }
        if lower.contains("adj") || lower == "a" || lower == "a." { return "adj." }
        if lower.contains("adv") { return "adv." }
        if lower.contains("prep") { return "prep." }
        return raw.isEmpty ? "def." : String(raw.prefix(4))
    }

    // MARK: Sentence Section (For full sentences/phrases)

    @ViewBuilder private var sentenceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            let meaning = model.assistant?.meaning ?? model.translationMeaning
            if !meaning.isEmpty {
                Text(meaning)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else if (model.assistant?.busy ?? false) || model.isTranslating {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("Đang dịch…"))
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
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
                TranslateSelectionController.shared.openVoiceSettings()
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
