import SwiftUI

/// N5a — the floating selection card: shows the selected text, instant Google / AI / on-device dictionary translations,
/// with audio pronunciation, engine switching, and a one-tap save button.
struct TranslateSelectionView: View {
    var model: TranslateSelectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let k = model.messageKey {
                errorMessageRow(key: k)
            } else {
                headerRow
                phoneticAndEngineRow
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

    // MARK: Phonetics & Engine Row

    private var phoneticAndEngineRow: some View {
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

            // Engine Switcher
            HStack(spacing: 4) {
                ForEach(TranslationEngine.allCases) { eng in
                    Button {
                        TranslateSelectionController.shared.switchEngine(to: eng)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: eng.icon).font(.system(size: 10))
                            Text(eng.title).font(.system(size: 11, weight: model.engine == eng ? .bold : .regular))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            model.engine == eng ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .foregroundColor(model.engine == eng ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var resolvedPhonetic: String {
        if let us = model.assistant?.definition?.phoneticUS, !us.isEmpty { return us }
        if let uk = model.assistant?.definition?.phoneticUK, !uk.isEmpty { return uk }
        return model.localPhonetic ?? ""
    }

    // MARK: Content Section (Google / AI / Dictionary)

    @ViewBuilder private var contentSection: some View {
        switch model.engine {
        case .google:
            googleContent
        case .ai:
            aiContent
        case .dictionary:
            dictionaryContent
        }
    }

    // MARK: Google Translate Content

    @ViewBuilder private var googleContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.isGoogleLoading && model.googleTranslation.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("Đang dịch…")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else if !model.googleTranslation.isEmpty {
                Text(model.googleTranslation)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                // Optional dictionary senses underneath for single words
                if !model.localSenses.isEmpty && !model.isSentence {
                    ForEach(Array(model.localSenses.prefix(2))) { sense in
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
                        }
                    }
                }
            } else if let err = model.googleError {
                Text(err).font(XFinderTokens.Font.caption).foregroundColor(.orange)
            } else {
                Text(model.localSnippet ?? "").font(.system(size: 13)).foregroundColor(.secondary)
            }
        }
    }

    // MARK: AI Content

    @ViewBuilder private var aiContent: some View {
        let isBusy = (model.assistant?.busy ?? false) || model.isTranslating
        let meaning = model.assistant?.meaning ?? ""
        VStack(alignment: .leading, spacing: 6) {
            if !meaning.isEmpty {
                Text(meaning)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if let def = model.assistant?.definition, !def.synonyms.isEmpty {
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
            } else if isBusy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("Đang dịch…")).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else if let key = model.assistant?.messageKey {
                Text(L10n.t(key)).font(XFinderTokens.Font.caption).foregroundColor(.orange)
            } else {
                Text(model.localSnippet ?? "").font(.system(size: 13)).foregroundColor(.secondary)
            }
        }
    }

    // MARK: Dictionary Content

    @ViewBuilder private var dictionaryContent: some View {
        let senses = model.localSenses
        if !senses.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(senses.prefix(3))) { sense in
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
        } else if let snippet = model.localSnippet {
            Text(snippet).font(.system(size: 13)).foregroundColor(.primary)
        } else {
            Text(model.googleTranslation.isEmpty ? model.text : model.googleTranslation)
                .font(.system(size: 14)).foregroundColor(.secondary)
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
