import SwiftUI

/// Dynamic Island Feedback page ("Phản hồi").
///
/// Layout: designed for the wide Dynamic Island tool body (584 × 140 pt content budget) while
/// staying usable in narrower widths. Reuses XFinder's notch tokens, `NotchPillButtonStyle`,
/// and `@FocusState` focus contract.
///
/// Privacy & honesty contract:
/// - Draft stays in memory only; survives tab switches (`onDisappear` never clears draft).
/// - Never reads or attaches logs, diagnostics, system info, or Clipboard automatically.
/// - Opening GitHub passes only the destination issues URL; browser failures preserve the draft.
struct NotchFeedbackPage: View {
    var model: NotchFeedbackModel = .shared
    @Environment(\.notchAccent) private var accent
    @FocusState private var inputFocused: Bool

    private typealias N = XFinderTokens.Notch

    private static let headerHeight: CGFloat = 22
    private static let sectionGap: CGFloat = 6
    private static let bodyHeight: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: Self.sectionGap) {
            headerRow
                .frame(height: Self.headerHeight, alignment: .center)

            HStack(spacing: 0) {
                composerColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, XFinderTokens.Space.row)

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1)
                    .padding(.vertical, 4)

                previewAndActionsColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, XFinderTokens.Space.row)
            }
            .frame(height: Self.bodyHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: inputFocused) { _, focused in
            if model.isInputFocused != focused {
                model.isInputFocused = focused
            }
        }
        .onChange(of: model.focusInputRequest) { _, _ in
            inputFocused = true
        }
        .onChange(of: model.isInputFocused) { _, focused in
            if !focused, inputFocused {
                inputFocused = false
            }
        }
    }

    // MARK: - Header Row (22 pt)

    private var headerRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "envelope.open")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(accent)

            Text(L10n.t("Phản hồi"))
                .font(XFinderTokens.Font.row)
                .lineLimit(1)

            HStack(spacing: 3) {
                ForEach(NotchFeedbackRules.Category.allCases) { item in
                    categoryChip(item)
                }
            }

            Spacer(minLength: XFinderTokens.Space.tight)

            Button(L10n.t("Chẩn đoán")) {
                _ = model.openDiagnostics()
            }
            .buttonStyle(NotchPillButtonStyle(primary: false))
            .help(L10n.t("Mở trang Chẩn đoán để tự xem báo cáo"))
            .accessibilityLabel(L10n.t("Mở trang Chẩn đoán"))
        }
    }

    private func categoryChip(_ item: NotchFeedbackRules.Category) -> some View {
        let selected = model.category == item
        let title = categoryLabel(item)
        return Button {
            model.selectCategory(item)
        } label: {
            Text(title)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(selected ? .white : .white.opacity(0.7))
                .padding(.horizontal, 7)
                .frame(height: 19)
                .background(
                    Capsule().fill(selected ? accent.opacity(0.85) : N.capsule)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Left Column: Draft Composer

    private var composerColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(
                L10n.t("Viết ý kiến hoặc mô tả lỗi…"),
                text: Binding(
                    get: { model.draft },
                    set: { model.updateDraft($0) }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(XFinderTokens.Font.caption)
            .foregroundColor(.white)
            .lineLimit(4...5)
            .focused($inputFocused)
            .padding(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                    .fill(N.capsule)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                    .strokeBorder(inputFocused ? accent.opacity(0.75) : N.cardStroke, lineWidth: 1)
            )
            .accessibilityLabel(L10n.t("Ô nhập nội dung phản hồi"))

            HStack(spacing: XFinderTokens.Space.tight) {
                Text(L10n.t("Không tự đọc nhật ký hay thông tin máy."))
                    .font(XFinderTokens.Font.caption)
                    .opacity(0.45)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(model.characterCount)/\(model.maxCharacters)")
                    .font(XFinderTokens.Font.caption.monospacedDigit())
                    .foregroundColor(model.characterCount > model.maxCharacters ? .orange : .white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Right Column: Preview + Copy / Open GitHub

    private var previewAndActionsColumn: some View {
        let preview = model.formattedPreview(categoryLabel: categoryLabel(model.category))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Text(L10n.t("Xem trước"))
                    .font(XFinderTokens.Font.caption)
                    .opacity(0.55)
                Spacer(minLength: 0)
                if let notice = statusNoticeText {
                    Text(notice)
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(statusIsError ? .orange : accent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            ScrollView(.vertical, showsIndicators: false) {
                Text(preview.isEmpty ? L10n.t("Bản xem trước để sao chép sẽ hiện tại đây.") : preview)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(preview.isEmpty ? .white.opacity(0.45) : .white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                    .fill(N.capsule)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                    .strokeBorder(N.cardStroke, lineWidth: 1)
            )
            .accessibilityLabel(L10n.t("Xem trước nội dung phản hồi"))

            HStack(spacing: XFinderTokens.Space.tight) {
                Button(L10n.t("Sao chép")) {
                    _ = model.copyPreview(categoryLabel: categoryLabel(model.category))
                }
                .buttonStyle(NotchPillButtonStyle(primary: true))
                .disabled(!model.canCopy)
                .help(copyHelpText)
                .accessibilityLabel(L10n.t("Sao chép nội dung phản hồi"))

                Button(L10n.t("Mở trang issue")) {
                    _ = model.openIssuesPage()
                }
                .buttonStyle(NotchPillButtonStyle(primary: false))
                .help(L10n.t("Mở trang tạo issue của XFinder trên GitHub (chỉ mở đích đến, không tự gửi)"))
                .accessibilityLabel(L10n.t("Mở trang tạo issue XFinder"))

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Localized Labels & Status

    private func categoryLabel(_ item: NotchFeedbackRules.Category) -> String {
        switch item {
        case .bug:
            return L10n.t("Báo lỗi")
        case .suggestion:
            return L10n.t("Đề xuất")
        case .other:
            return L10n.t("Khác")
        }
    }

    private var statusIsError: Bool {
        if case .tooLong = model.copyBlockReason { return true }
        switch model.status {
        case .copyFailed, .openBrowserFailed, .openDiagnosticsFailed:
            return true
        case .idle, .copied, .openedIssues, .openedDiagnostics:
            return false
        }
    }

    private var statusNoticeText: String? {
        if case .tooLong(_, let limit) = model.copyBlockReason {
            return "\(L10n.t("Vượt quá giới hạn "))\(limit)\(L10n.t(" ký tự."))"
        }
        switch model.status {
        case .idle:
            return nil
        case .copied:
            return L10n.t("Đã sao chép phản hồi.")
        case .copyFailed:
            return L10n.t("Không thể sao chép. Nội dung vẫn được giữ.")
        case .openedIssues:
            return L10n.t("Đã mở trang tạo issue.")
        case .openBrowserFailed:
            return L10n.t("Không mở được trình duyệt. Nội dung vẫn được giữ để sao chép.")
        case .openedDiagnostics:
            return L10n.t("Đã mở Chẩn đoán.")
        case .openDiagnosticsFailed:
            return L10n.t("Không mở được trang Chẩn đoán.")
        }
    }

    private var copyHelpText: String {
        guard let block = model.copyBlockReason else {
            return L10n.t("Sao chép nội dung phản hồi đã định dạng")
        }
        switch block {
        case .emptyText:
            return L10n.t("Nhập nội dung trước khi sao chép")
        case .tooLong(_, let limit):
            return "\(L10n.t("Vượt quá giới hạn "))\(limit)\(L10n.t(" ký tự."))"
        }
    }
}
