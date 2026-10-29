import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// N5a — the selection, Apple's translation popover over it (macOS 15+), and the translated text once the popover
/// handed it back. Nothing leaves the Mac: the Translation framework is on-device after its language pack download.
struct TranslateSelectionView: View {
    var model: TranslateSelectionModel
    @State private var presentingRequest: Int?
    private func presentation(for request: Int) -> Binding<Bool> {
        Binding(get: { request == model.requestPresentation && model.nativePresented },
                set: { if request == model.requestPresentation { model.nativePresented = $0 } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            HStack(spacing: 6) {
                Text(L10n.t("Dịch vùng chọn")).font(XFinderTokens.Font.row).bold()
                if let app = model.sourceApp {
                    Text("· \(app)").font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                Spacer(minLength: 4)
                Text(TranslateSelectionRules.hotkeyLabel).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                Button { TranslateSelectionController.shared.dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundColor(.secondary).help(L10n.t("Đóng")).keyboardShortcut(.cancelAction)
            }
            if let k = model.messageKey {
                Text(L10n.t(k)).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer(minLength: 0)
                    Button(L10n.t("Tra từ & lưu vào sổ")) {
                        let text = model.text, meaning = model.translated ?? ""
                        TranslateSelectionController.shared.dismiss()
                        VocabularyWorkspaceController.shared.show(text: text, meaning: meaning)
                    }.controlSize(.small)
                }
            } else {
                Text(model.text)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button(L10n.t("Tra từ & lưu vào sổ")) {
                        let text = model.text, meaning = model.translated ?? ""
                        TranslateSelectionController.shared.dismiss()
                        VocabularyWorkspaceController.shared.show(text: text, meaning: meaning)
                    }.controlSize(.small)
                    Spacer(minLength: 0)
                    translationAnchor
                }
            }
        }
        .padding(XFinderTokens.Space.inline + 4)
        .frame(width: 460, height: 105)
        .background(XFinderTokens.Fill.surface, in: RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile))
        .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile).stroke(XFinderTokens.Fill.hairline))
        .task(id: model.requestPresentation) {
            let request = model.requestPresentation
            await Task.yield()
            guard !Task.isCancelled, model.isActive, model.messageKey == nil, !model.text.isEmpty,
                  request == model.requestPresentation else { return }
            presentingRequest = request
            model.nativePresented = true
        }
        .onChange(of: model.nativePresented) { wasPresented, isPresented in
            guard wasPresented, !isPresented, let request = presentingRequest else { return }
            TranslateSelectionController.shared.nativePresentationDidEnd(request: request)
        }
    }

    @ViewBuilder private var translationAnchor: some View {
        if #available(macOS 15.0, *) {
            let request = model.requestPresentation
            Color.clear
                .frame(width: 1, height: 1)
                .translationPresentation(isPresented: presentation(for: request), text: model.text) { translated in
                    guard request == model.requestPresentation, model.isActive else { return }
                    model.translated = translated
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(translated, forType: .string)
                    ClipboardSounds.playCopy()
                }
                .id(request)
        } else {
            Text(L10n.t("Dịch tại chỗ cần macOS 15 trở lên (Translation framework của Apple)."))
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
        }
    }
}
