import SwiftUI

/// D1 #9 — "Sửa & dọn text": a clip's full text in an editor, then one button to copy the edited result
/// (the monitor records it as a new clip, the original stays). Deliberately NOT a paste-into-app button:
/// the job the user described is "sửa rồi copy lại"; paste-back stays the notch's job.
@MainActor
@Observable
final class NotchTextEditorModel {
    var text = ""
    var sourceType: ContentType = .text
    var onCopy: (String) -> Void = { _ in }
    var onClose: () -> Void = {}
}

struct NotchTextEditorView: View {
    var model: NotchTextEditorModel
    @FocusState private var focused: Bool

    private var stats: (words: Int, characters: Int, lines: Int) { ClipboardTransform.stats(model.text) }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            HStack {
                Text(L10n.t("Sửa văn bản")).font(XFinderTokens.Font.sectionTitle)
                Spacer()
                Text("\(stats.words)\(L10n.t(" từ · "))\(stats.characters)\(L10n.t(" ký tự · "))\(stats.lines)\(L10n.t(" dòng"))")
                    .font(XFinderTokens.Font.caption).foregroundColor(.secondary).monospacedDigit()
            }
            TextEditor(text: Bindable(model).text)
                .font(model.sourceType == .code ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .focused($focused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control).strokeBorder(XFinderTokens.Fill.hairline))
            HStack {
                Button(L10n.t("Đóng")) { model.onClose() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.t("Sao chép")) { model.onCopy(model.text) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.text.isEmpty)
            }
        }
        .padding(XFinderTokens.Space.page)
        .frame(width: 560, height: 380)
        .onAppear { focused = true }
    }
}
