import SwiftUI

/// N5a — the floating selection card: shows the selected text and its AI translation inline,
/// with instant on-device dictionary lookup while AI translates and a one-tap "Save to wordbook" button.
struct TranslateSelectionView: View {
    var model: TranslateSelectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            if let k = model.messageKey {
                errorMessageRow(key: k)
            } else {
                wordAndPhoneticRow
                contentSection
                Divider()
                actionRow
            }
        }
        .padding(14)
        .frame(width: 460)
        .background(XFinderTokens.Fill.surface, in: RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile))
        .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile).stroke(XFinderTokens.Fill.hairline))
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "translate")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Text(L10n.t("Dịch vùng chọn")).font(XFinderTokens.Font.row).bold()
            if let app = model.sourceApp {
                Text("· \(app)").font(XFinderTokens.Font.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
            Text(TranslateSelectionRules.hotkeyLabel)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
            Button { TranslateSelectionController.shared.dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain).foregroundColor(.secondary)
            .help(L10n.t("Đóng")).keyboardShortcut(.cancelAction)
        }
    }

    // MARK: Word row (the selected text + phonetic & syllables)

    private var wordAndPhoneticRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(model.text)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)

            let phonetic = resolvedPhonetic
            if !phonetic.isEmpty {
                Text("/\(phonetic)/")
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }

            if let syllables = resolvedSyllables, !syllables.isEmpty, syllables != model.text {
                Text("· \(syllables)")
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var resolvedPhonetic: String {
        if let us = model.assistant?.definition?.phoneticUS, !us.isEmpty { return us }
        if let uk = model.assistant?.definition?.phoneticUK, !uk.isEmpty { return uk }
        return model.localPhonetic ?? ""
    }

    private var resolvedSyllables: String? {
        if let syl = model.assistant?.definition?.syllables, !syl.isEmpty { return syl }
        return model.localSyllables
    }

    // MARK: Content Section — Instant Local Definition + AI Translation

    @ViewBuilder private var contentSection: some View {
        let hasAiMeaning = !(model.assistant?.meaning ?? "").isEmpty
        let isBusy = (model.assistant?.busy ?? false) || (model.isTranslating && !hasAiMeaning)
        let errorKey = model.assistant?.messageKey

        if hasAiMeaning, let assistant = model.assistant {
            // Full AI Translation Ready
            VStack(alignment: .leading, spacing: 6) {
                Text(assistant.meaning)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if let def = assistant.definition, !def.synonyms.isEmpty {
                    synonymsPills(Array(def.synonyms.prefix(4)))
                }

                if let snippet = model.localSnippet {
                    Text(snippet)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
            }
        } else if let snippet = model.localSnippet {
            // Instant Local Dictionary Definition (available in ~1 ms while AI works)
            VStack(alignment: .leading, spacing: 6) {
                Text(snippet)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .textSelection(.enabled)

                if isBusy {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L10n.t("Đang dịch…"))
                            .font(XFinderTokens.Font.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let err = errorKey {
                    aiErrorNotice(key: err)
                }
            }
        } else if isBusy {
            // Waiting for AI without local dictionary
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L10n.t("Đang dịch…"))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        } else if let err = errorKey {
            aiErrorState(key: err)
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L10n.t("Đang dịch…"))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func synonymsPills(_ synonyms: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(synonyms, id: \.self) { syn in
                Text(syn)
                    .font(XFinderTokens.Font.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundColor(.accentColor)
            }
        }
    }

    private func aiErrorNotice(key: String) -> some View {
        HStack(spacing: 4) {
            Text(L10n.t("Lỗi AI:"))
                .font(XFinderTokens.Font.caption).bold()
                .foregroundColor(.orange)
            Text(L10n.t(key))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private func aiErrorState(key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                Text(L10n.t("Lỗi AI:"))
                    .font(XFinderTokens.Font.caption).bold()
                    .foregroundColor(.orange)
                Text(L10n.t(key))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(L10n.t("Mở cài đặt Giọng nói")) {
                    TranslateSelectionController.shared.openVoiceSettings()
                }.controlSize(.small)
                Button(L10n.t("Mở tra từ")) {
                    TranslateSelectionController.shared.openWorkspace()
                }.controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Action Row

    private var actionRow: some View {
        HStack(spacing: 8) {
            if model.savedToWordbook {
                Label(L10n.t("Đã lưu vào sổ từ"), systemImage: "checkmark.circle.fill")
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.green)
            } else {
                Button {
                    TranslateSelectionController.shared.saveToWordbook()
                } label: {
                    Label(L10n.t("Lưu vào sổ từ"), systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(saveButtonDisabled)
            }
            Spacer(minLength: 0)
            Button(L10n.t("Mở tra từ")) {
                TranslateSelectionController.shared.openWorkspace()
            }.controlSize(.small)
        }
    }

    private var saveButtonDisabled: Bool {
        let hasMeaning = !(model.assistant?.meaning ?? "").isEmpty
        let hasLocal = (model.localSnippet != nil)
        return (!hasMeaning && !hasLocal) || model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Error state (no selection / too short / too long)

    private func errorMessageRow(key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t(key))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
