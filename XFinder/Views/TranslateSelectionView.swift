import SwiftUI

/// N5a — the floating selection card: shows the selected text and its AI translation inline,
/// with a one-tap "Save to wordbook" button. Replaces the old Apple translationPresentation popup.
struct TranslateSelectionView: View {
    var model: TranslateSelectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            if let k = model.messageKey {
                errorMessageRow(key: k)
            } else {
                wordRow
                translationBody
            }
        }
        .padding(14)
        .frame(width: 460)
        .background(XFinderTokens.Fill.surface, in: RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile))
        .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile).stroke(XFinderTokens.Fill.hairline))
        .onChange(of: model.requestPresentation) { _, _ in
            // State resets are driven by the controller; view is purely reactive.
        }
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

    // MARK: Word row (the selected text)

    private var wordRow: some View {
        Text(model.text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.primary)
            .lineLimit(2)
            .truncationMode(.tail)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Translation body — three states driven by assistant

    @ViewBuilder private var translationBody: some View {
        if let assistant = model.assistant {
            if assistant.busy || (model.isTranslating && assistant.messageKey == nil && assistant.meaning.isEmpty) {
                loadingState
            } else if let errKey = assistant.messageKey {
                aiErrorState(key: errKey)
            } else if !assistant.meaning.isEmpty {
                successState(assistant: assistant)
            } else {
                // Fallback while assistant hasn't produced output yet
                loadingState
            }
        } else if model.isTranslating {
            loadingState
        } else {
            // No assistant set yet (shouldn't happen in normal flow)
            loadingState
        }
    }

    private var loadingState: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(L10n.t("Đang dịch…"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
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

    private func successState(assistant: TranslateAssistant) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Meaning
            Text(assistant.meaning)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            // Phonetics (if word has them)
            if let def = assistant.definition,
               !(def.phoneticUS ?? "").isEmpty || !(def.phoneticUK ?? "").isEmpty {
                HStack(spacing: 8) {
                    if let us = def.phoneticUS, !us.isEmpty {
                        Text("/\(us)/")
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                    if let uk = def.phoneticUK, !uk.isEmpty {
                        Text("/\(uk)/")
                            .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    }
                }
            }

            // Synonyms pill row (first 4)
            if let def = assistant.definition, !def.synonyms.isEmpty {
                let shown = Array(def.synonyms.prefix(4))
                HStack(spacing: 4) {
                    ForEach(shown, id: \.self) { syn in
                        Text(syn)
                            .font(XFinderTokens.Font.caption)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundColor(.accentColor)
                    }
                }
            }

            Divider()

            // Action row
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
                }
                Spacer(minLength: 0)
                Button(L10n.t("Mở tra từ")) {
                    TranslateSelectionController.shared.openWorkspace()
                }.controlSize(.small)
            }
        }
        .padding(.top, 2)
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
