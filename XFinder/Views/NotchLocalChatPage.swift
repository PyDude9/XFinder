import SwiftUI

/// Dynamic Island on-device chat page ("Chat trên máy").
///
/// Layout: designed for the wide Dynamic Island tool body (584 × 140 pt content budget) while
/// staying responsive in narrower widths. Reuses XFinder's notch tokens, `NotchPillButtonStyle`,
/// and `@FocusState` focus contract (`NotchTodosPage`).
///
/// Lifecycle contract:
/// - Checks availability on `.onAppear` without ever invoking the language model.
/// - Preserves in-memory conversation history across tab switches (`onDisappear` never resets).
/// - "Cuộc trò chuyện mới" cancels any in-flight reply and clears both UI messages and session context.
struct NotchLocalChatPage: View {
    var model: NotchLocalChatModel = .shared
    var onInputFocusChanged: (Bool) -> Void = { _ in }
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

            Group {
                if let unavailable = model.availability.unavailableReason {
                    unavailableView(unavailable)
                } else {
                    chatBodyView
                }
            }
            .frame(height: Self.bodyHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            model.checkAvailability()
        }
        .onChange(of: inputFocused) { _, focused in
            if model.isInputFocused != focused {
                model.isInputFocused = focused
                onInputFocusChanged(focused)
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
            Image(systemName: "apple.intelligence")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(model.availability.isAvailable ? accent : .white.opacity(0.65))

            Text(L10n.t("Chat trên máy"))
                .font(XFinderTokens.Font.row)
                .lineLimit(1)

            statusBadge

            Spacer(minLength: XFinderTokens.Space.tight)

            if model.availability.isAvailable {
                Button(L10n.t("Cuộc trò chuyện mới")) {
                    model.resetConversation()
                }
                .buttonStyle(NotchPillButtonStyle(primary: false))
                .disabled(!model.hasConversation && !model.isGenerating && model.lastError == nil && !model.isContextWindowFull)
                .help(L10n.t("Xóa lịch sử và bắt đầu ngữ cảnh mới"))
                .accessibilityLabel(L10n.t("Cuộc trò chuyện mới"))
            }
        }
    }

    @ViewBuilder private var statusBadge: some View {
        if model.isGenerating {
            Text(L10n.t("Đang trả lời…"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(accent)
                .lineLimit(1)
        } else if model.availability.unavailableReason != nil {
            Text(L10n.t("Không khả dụng"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.orange)
                .lineLimit(1)
        } else if model.isContextWindowFull {
            Text(L10n.t("Đầy ngữ cảnh"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.orange)
                .lineLimit(1)
        } else {
            Text(L10n.t("Ngoại tuyến"))
                .font(XFinderTokens.Font.caption)
                .opacity(0.55)
                .lineLimit(1)
        }
    }

    // MARK: - Unavailable View

    private func unavailableView(_ reason: NotchLocalChatRules.UnavailableReason) -> some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.orange)
                Text(unavailableTitle(for: reason))
                    .font(XFinderTokens.Font.row)
                    .lineLimit(1)
            }

            Text(unavailableMessage(for: reason))
                .font(XFinderTokens.Font.caption)
                .opacity(0.7)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: XFinderTokens.Space.tight) {
                Button(L10n.t("Thử lại")) {
                    model.retryAvailability()
                }
                .buttonStyle(NotchPillButtonStyle(primary: true))
                .accessibilityLabel(L10n.t("Kiểm tra lại khả dụng Chat trên máy"))

                Text(L10n.t("Chạy hoàn toàn trên máy, không dùng mạng."))
                    .font(XFinderTokens.Font.caption)
                    .opacity(0.45)
                    .lineLimit(1)
            }
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chat Body (History + Notice + Input Bar)

    private var chatBodyView: some View {
        VStack(alignment: .leading, spacing: 5) {
            historySection
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let notice = inlineNoticeText {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(notice)
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
            }

            inputBar
                .frame(height: 24)
        }
    }

    private var historySection: some View {
        Group {
            if model.messages.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Hỏi nhanh bằng mô hình trên máy."))
                        .font(XFinderTokens.Font.rowValue)
                        .opacity(0.85)
                    Text(L10n.t("Không dùng mạng, không đọc Clipboard hay thiết lập Giọng nói. Lịch sử chỉ lưu trong bộ nhớ phiên chạy này."))
                        .font(XFinderTokens.Font.caption)
                        .opacity(0.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(model.messages) { msg in
                                messageRow(msg)
                                    .id(msg.id)
                            }
                            if model.isGenerating {
                                HStack(spacing: 4) {
                                    Text(L10n.t("Mô hình"))
                                        .font(XFinderTokens.Font.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(accent)
                                    Text(L10n.t("Đang tạo câu trả lời…"))
                                        .font(XFinderTokens.Font.caption)
                                        .opacity(0.6)
                                }
                                .id("generating-indicator")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: model.messages.count) { _, _ in
                        if let lastID = model.messages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                    .onChange(of: model.isGenerating) { _, generating in
                        if generating {
                            proxy.scrollTo("generating-indicator", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func messageRow(_ message: NotchLocalChatRules.Message) -> some View {
        let isUser = message.role == .user
        let roleLabel = isUser ? L10n.t("Bạn") : L10n.t("Mô hình")
        return HStack(alignment: .top, spacing: 6) {
            Text(roleLabel)
                .font(XFinderTokens.Font.caption)
                .fontWeight(.semibold)
                .foregroundColor(isUser ? .white.opacity(0.65) : accent)
                .frame(width: 48, alignment: .leading)
                .lineLimit(1)

            Text(message.text)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.white.opacity(isUser ? 0.9 : 0.8))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var inputBar: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            TextField(
                L10n.t("Nhập câu hỏi cho mô hình trên máy…"),
                text: Bindable(model).draft
            )
            .textFieldStyle(.plain)
            .font(XFinderTokens.Font.caption)
            .foregroundColor(.white)
            .focused($inputFocused)
            .disabled(!model.availability.isAvailable || model.isGenerating)
            .onSubmit {
                if model.canSend {
                    model.sendPrompt()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                    .fill(N.capsule)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                    .strokeBorder(inputFocused ? accent.opacity(0.75) : N.cardStroke, lineWidth: 1)
            )
            .accessibilityLabel(L10n.t("Ô nhập câu hỏi Chat trên máy"))

            if model.trimmedDraftLength > model.maxPromptCharacters * 3 / 4 {
                Text("\(model.trimmedDraftLength)/\(model.maxPromptCharacters)")
                    .font(XFinderTokens.Font.caption.monospacedDigit())
                    .foregroundColor(model.trimmedDraftLength > model.maxPromptCharacters ? .orange : .white.opacity(0.5))
                    .lineLimit(1)
            }

            if model.isGenerating {
                Button(L10n.t("Dừng")) {
                    model.stopGeneration()
                }
                .buttonStyle(NotchPillButtonStyle(primary: false))
                .keyboardShortcut(.cancelAction)
                .help(L10n.t("Dừng câu trả lời đang tạo"))
                .accessibilityLabel(L10n.t("Dừng câu trả lời"))
            } else {
                Button(L10n.t("Gửi")) {
                    model.sendPrompt()
                }
                .buttonStyle(NotchPillButtonStyle(primary: true))
                .disabled(!model.canSend)
                .help(sendButtonHelpText)
                .accessibilityLabel(L10n.t("Gửi câu hỏi"))
            }
        }
    }

    // MARK: - Localized Reasons (Every literal directly wrapped in L10n.t)

    private func unavailableTitle(for reason: NotchLocalChatRules.UnavailableReason) -> String {
        switch reason {
        case .unsupportedOS:
            return L10n.t("Cần macOS 26 trở lên")
        case .deviceNotEligible:
            return L10n.t("Thiết bị chưa hỗ trợ")
        case .appleIntelligenceNotEnabled:
            return L10n.t("Apple Intelligence đang tắt")
        case .modelNotReady:
            return L10n.t("Mô hình chưa sẵn sàng")
        case .sdkUnavailable, .unknown:
            return L10n.t("Không khả dụng trên máy này")
        }
    }

    private func unavailableMessage(for reason: NotchLocalChatRules.UnavailableReason) -> String {
        switch reason {
        case .unsupportedOS:
            return L10n.t("Máy này chạy macOS cũ hơn 26, chưa có Apple Intelligence.")
        case .deviceNotEligible:
            return L10n.t("Máy này không nằm trong danh sách hỗ trợ Apple Intelligence.")
        case .appleIntelligenceNotEnabled:
            return L10n.t("Apple Intelligence chưa được bật trong Cài đặt hệ thống.")
        case .modelNotReady:
            return L10n.t("Mô hình trên máy chưa tải xong. Thử lại sau ít phút.")
        case .sdkUnavailable:
            return L10n.t("Bản SDK này không có FoundationModels.")
        case .unknown:
            return L10n.t("Apple Intelligence không khả dụng trên máy này.")
        }
    }

    private var inlineNoticeText: String? {
        if let err = model.lastError {
            switch err {
            case .refused:
                return L10n.t("Mô hình đã từ chối yêu cầu này.")
            case .guardrailViolation:
                return L10n.t("Yêu cầu không phù hợp với giới hạn an toàn của mô hình.")
            case .contextWindowExceeded:
                return L10n.t("Cửa sổ ngữ cảnh đã đầy. Hãy bắt đầu cuộc trò chuyện mới.")
            case .assetsUnavailable:
                return L10n.t("Mô hình trên máy chưa tải xong. Thử lại sau ít phút.")
            case .concurrentRequest:
                return L10n.t("Đang xử lý câu hỏi trước đó. Hãy đợi hoàn tất hoặc bấm Dừng.")
            case .emptyResponse:
                return L10n.t("Mô hình không trả về nội dung.")
            case .unavailable(let reason):
                return unavailableMessage(for: reason)
            case .cancelled:
                return nil
            case .generationFailed:
                return L10n.t("Không thể tạo câu trả lời trên máy. Hãy thử lại.")
            }
        }

        if let block = model.sendBlockReason {
            switch block {
            case .promptTooLong(_, let limit):
                return "\(L10n.t("Vượt quá giới hạn "))\(limit)\(L10n.t(" ký tự."))"
            case .contextLimitReached:
                return L10n.t("Đã đạt giới hạn ngữ cảnh. Hãy bắt đầu cuộc trò chuyện mới.")
            case .availabilityUnchecked, .unavailable, .generating, .emptyPrompt:
                return nil
            }
        }

        return nil
    }

    private var sendButtonHelpText: String {
        guard let block = model.sendBlockReason else {
            return L10n.t("Gửi câu hỏi cho mô hình trên máy")
        }
        switch block {
        case .emptyPrompt:
            return L10n.t("Nhập câu hỏi trước khi gửi")
        case .generating:
            return L10n.t("Đang chờ câu trả lời hiện tại")
        case .promptTooLong(_, let limit):
            return "\(L10n.t("Vượt quá giới hạn "))\(limit)\(L10n.t(" ký tự."))"
        case .contextLimitReached:
            return L10n.t("Đã đạt giới hạn ngữ cảnh. Hãy bắt đầu cuộc trò chuyện mới.")
        case .availabilityUnchecked, .unavailable:
            return L10n.t("Mô hình trên máy hiện không khả dụng")
        }
    }
}
