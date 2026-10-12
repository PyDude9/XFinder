import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// N5a — the selection, Apple's translation popover over it (macOS 15+), and the translated text once the popover
/// handed it back. Nothing leaves the Mac: the Translation framework is on-device after its language pack download.
struct TranslateSelectionView: View {
    var model: TranslateSelectionModel
    @State private var presented = false

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
        .onChange(of: model.requestPresentation) { presented = !model.text.isEmpty }
    }

    @ViewBuilder private var translationArea: some View {
        if #available(macOS 15.0, *) {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
                HStack {
                    Button(L10n.t("Dịch")) { presented = true }.buttonStyle(.borderedProminent).controlSize(.small)
                        .translationPresentation(isPresented: $presented, text: model.text) { translated in
                            model.translated = translated
                        }
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
