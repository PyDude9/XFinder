import SwiftUI

/// Dynamic Island local message composer & preview page ("Tin nhắn cục bộ").
///
/// Layout: fits the Dynamic Island tool body (`140 pt` content height) in both wide and narrow widths.
/// Reuses XFinder's notch tokens, `NotchPillButtonStyle`, and `@FocusState` focus contract.
///
/// Behavior guarantees:
/// - Purely local & ephemeral: never reads Clipboard, never sends network data, never persists to disk.
/// - Respects `@Environment(\.accessibilityReduceMotion)` with static rendering when enabled.
/// - Dispatches display/stop through `NotchMessageModel`'s coordinator callbacks (`LiveActivity`).
struct NotchMessagePage: View {
    var model: NotchMessageModel = .shared
    var onInputFocusChanged: (Bool) -> Void = { _ in }
    @Environment(\.notchAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var inputFocused: Bool

    private typealias N = XFinderTokens.Notch

    private static let headerHeight: CGFloat = 22
    private static let sectionGap: CGFloat = 6
    private static let bodyHeight: CGFloat = 112

    private var presentationAnimation: Animation? {
        NotchMessageRules.presentationMode(reduceMotion: reduceMotion) == .staticOnly
            ? nil
            : XFinderTokens.Notch.pageFade
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.sectionGap) {
            headerRow
                .frame(height: Self.headerHeight, alignment: .center)

            VStack(alignment: .leading, spacing: 6) {
                inputRow
                durationAndActionRow
                previewSection
                Spacer(minLength: 0)
            }
            .frame(height: Self.bodyHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(presentationAnimation, value: model.isShowing)
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
            Image(systemName: model.isShowing ? "bubble.left.and.exclamationmark.bubble.right.fill" : "text.bubble")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(model.isShowing ? accent : .white.opacity(0.75))

            Text(L10n.t("Tin nhắn cục bộ"))
                .font(XFinderTokens.Font.row)
                .lineLimit(1)

            statusBadge

            Spacer(minLength: XFinderTokens.Space.tight)

            if model.isShowing {
                Button(L10n.t("Dừng")) {
                    model.stopActiveNotice()
                }
                .buttonStyle(NotchPillButtonStyle(primary: false))
                .help(L10n.t("Dừng hiển thị tin nhắn trên Island"))
                .accessibilityLabel(L10n.t("Dừng tin nhắn trên Island"))
            }
        }
    }

    @ViewBuilder private var statusBadge: some View {
        if model.isShowing {
            Text(L10n.t("Đang hiện"))
                .font(XFinderTokens.Font.caption)
                .foregroundColor(accent)
                .lineLimit(1)
        } else {
            Text(L10n.t("Tạm thời"))
                .font(XFinderTokens.Font.caption)
                .opacity(0.55)
                .lineLimit(1)
        }
    }

    // MARK: - Input Row

    private var inputRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            TextField(
                L10n.t("Nhập tin nhắn ngắn để hiện trên Island…"),
                text: Bindable(model).draft
            )
            .textFieldStyle(.plain)
            .font(XFinderTokens.Font.caption)
            .foregroundColor(.white)
            .focused($inputFocused)
            .onSubmit {
                if model.canShow {
                    _ = model.showInIsland(reduceMotion: reduceMotion)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                    .fill(N.capsule)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge, style: .continuous)
                    .strokeBorder(inputFocused ? accent.opacity(0.75) : N.cardStroke, lineWidth: 1)
            )
            .accessibilityLabel(L10n.t("Ô nhập tin nhắn cục bộ"))

            Text("\(model.previewCharacterCount)/\(model.maxCharacters)")
                .font(XFinderTokens.Font.caption.monospacedDigit())
                .foregroundColor(model.previewCharacterCount > model.maxCharacters ? .orange : .white.opacity(0.5))
                .frame(minWidth: 40, alignment: .trailing)
                .lineLimit(1)
        }
    }

    // MARK: - Duration Presets & Show CTA

    private var durationAndActionRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Text(L10n.t("Thời gian"))
                .font(XFinderTokens.Font.caption)
                .opacity(0.6)
                .lineLimit(1)

            HStack(spacing: 4) {
                ForEach(NotchMessageRules.durationPresets, id: \.self) { seconds in
                    durationChip(seconds)
                }
            }

            Spacer(minLength: XFinderTokens.Space.tight)

            Button(L10n.t("Hiển thị trong Island")) {
                _ = model.showInIsland(reduceMotion: reduceMotion)
            }
            .buttonStyle(NotchPillButtonStyle(primary: true))
            .disabled(!model.canShow)
            .help(showHelpText)
            .accessibilityLabel(L10n.t("Hiển thị tin nhắn trong Island"))
        }
    }

    private func durationChip(_ seconds: TimeInterval) -> some View {
        let selected = model.durationSeconds == seconds
        let secsInt = Int(seconds)
        return Button {
            model.selectDuration(seconds)
        } label: {
            Text("\(secsInt)\(L10n.t("s"))")
                .font(XFinderTokens.Font.caption.monospacedDigit())
                .foregroundColor(selected ? .white : .white.opacity(0.7))
                .padding(.horizontal, 7)
                .frame(height: 19)
                .background(
                    Capsule().fill(selected ? accent.opacity(0.85) : N.capsule)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(secsInt)\(L10n.t(" giây"))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - In-Page Preview / Validation Banner

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: XFinderTokens.Space.tight) {
                Text(L10n.t("Xem trước"))
                    .font(XFinderTokens.Font.caption)
                    .opacity(0.55)
                Spacer(minLength: 0)
                if let err = validationBannerText {
                    Text(err)
                        .font(XFinderTokens.Font.caption)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                } else {
                    Text(L10n.t("Chỉ hiện trên máy, không lưu khi thoát XFinder."))
                        .font(XFinderTokens.Font.caption)
                        .opacity(0.45)
                        .lineLimit(1)
                }
            }

            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(model.canShow ? accent : .white.opacity(0.4))

                Text(previewBodyText)
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(model.normalizedPreviewText.isEmpty ? .white.opacity(0.45) : .white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if NotchMessageRules.isValidDuration(model.durationSeconds) {
                    Text("\(Int(model.durationSeconds))\(L10n.t("s"))")
                        .font(XFinderTokens.Font.caption.monospacedDigit())
                        .opacity(0.55)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Capsule().fill(N.capsule)
            )
            .overlay(
                Capsule().strokeBorder(model.isShowing ? accent.opacity(0.6) : N.cardStroke, lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.t("Xem trước tin nhắn trên Island"))
        }
    }

    private var previewBodyText: String {
        let normalized = model.normalizedPreviewText
        if normalized.isEmpty {
            return L10n.t("Nội dung xem trước sẽ hiện tại đây…")
        }
        return normalized
    }

    private var validationBannerText: String? {
        guard let reason = model.showBlockReason else { return nil }
        switch reason {
        case .emptyText:
            return nil
        case .tooLong(_, let limit):
            return "\(L10n.t("Vượt quá giới hạn "))\(limit)\(L10n.t(" ký tự."))"
        case .invalidDuration:
            return L10n.t("Thời gian hiển thị không hợp lệ.")
        }
    }

    private var showHelpText: String {
        guard let reason = model.showBlockReason else {
            return L10n.t("Hiển thị tin nhắn này trong Dynamic Island")
        }
        switch reason {
        case .emptyText:
            return L10n.t("Nhập nội dung trước khi hiển thị")
        case .tooLong(_, let limit):
            return "\(L10n.t("Vượt quá giới hạn "))\(limit)\(L10n.t(" ký tự."))"
        case .invalidDuration:
            return L10n.t("Thời gian hiển thị không hợp lệ.")
        }
    }
}
