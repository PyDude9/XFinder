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
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            HStack {
                Text(L10n.t("Dịch vùng chọn")).font(XFinderTokens.Font.row).bold()
                if let app = model.sourceApp {
                    Text("· \(app)").font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(TranslateSelectionRules.hotkeyLabel).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                Button { TranslateSelectionController.shared.dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundColor(.secondary).help(L10n.t("Đóng")).keyboardShortcut(.cancelAction)
            }
            if let k = model.messageKey {
                Text(L10n.t(k)).font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    Text(model.text).font(XFinderTokens.Font.row).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
                translationArea
            }
            Spacer(minLength: 0)
        }
        .padding(XFinderTokens.Space.inline + 4)
        .frame(width: 520, height: 300)
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

    @ViewBuilder private var translationArea: some View {
        if #available(macOS 15.0, *) {
            let request = model.requestPresentation
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                HStack {
                    Button(L10n.t("Dịch")) {
                        presentingRequest = request
                        model.nativePresented = true
                    }.buttonStyle(.borderedProminent).controlSize(.small)
                        .translationPresentation(isPresented: presentation(for: request), text: model.text) { translated in
                            guard request == model.requestPresentation, model.isActive else { return }
                            model.translated = translated
                        }
                        .id(request)
                    if model.translated != nil {
                        Button(L10n.t("Sao chép bản dịch")) { TranslateSelectionController.shared.copyTranslation() }.controlSize(.small)
                    }
                }
                if let t = model.translated {
                    ScrollView {
                        Text(t).font(XFinderTokens.Font.row).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 90)
                } else {
                    Text(L10n.t("Bản dịch của Apple chạy trên máy; lần đầu mỗi cặp ngôn ngữ macOS sẽ hỏi tải gói ngôn ngữ. Bấm \"Thay thế\" trong hộp dịch để nhận bản dịch về đây."))
                        .font(XFinderTokens.Font.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text(L10n.t("Dịch tại chỗ cần macOS 15 trở lên (Translation framework của Apple)."))
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
        }
    }
}
