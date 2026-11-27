import SwiftUI
import AppKit

/// Dynamic Island scratchpad page — a lightweight local draft editor that persists across
/// collapse/reopen and app restarts. Uses XFinder's notch tokens and `NotchPillButtonStyle`,
/// never reads the system clipboard on open, preserves unreadable disk content until a
/// successful reload, and flushes pending edits on disappear.
struct NotchScratchpadPage: View {
    var store: NotchScratchpadStore = .shared
    /// Bumped by `NotchSurfaceController` after making the notch panel key so keyboard focus
    /// lands directly in the editor.
    var focusRequest: Int = 0
    /// Reports whether the editor currently owns keyboard focus so the controller can keep the
    /// hub open (`NotchSurfaceMachine.Settings.composing`) while the user is typing.
    var onEditingChanged: @MainActor (Bool) -> Void = { _ in }
    /// Injected clipboard writer; defaults to writing plain UTF-8 text to `NSPasteboard.general`.
    var copyToPasteboard: @MainActor (String) -> Bool = NotchScratchpadPage.writeToGeneralPasteboard

    @Environment(\.notchAccent) private var accent
    @FocusState private var editorFocused: Bool
    @State private var copiedFeedback = false
    @State private var copiedResetTask: Task<Void, Never>?

    private typealias N = XFinderTokens.Notch

    private var textBinding: Binding<String> {
        Binding(
            get: { store.text },
            set: { store.updateText($0) }
        )
    }

    private var borderColor: Color {
        switch store.status {
        case .overLimit, .readFailed:
            return .orange.opacity(0.85)
        case .saveFailed:
            return .red.opacity(0.85)
        case .idle, .saved:
            return editorFocused ? accent.opacity(0.8) : N.cardStroke
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            headerRow
            statusBanner
            editorBox
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if !store.isReadBlocked {
                editorFocused = true
                onEditingChanged(true)
            } else {
                editorFocused = false
                onEditingChanged(false)
            }
        }
        .onChange(of: focusRequest) { _, _ in
            if !store.isReadBlocked {
                editorFocused = true
            }
        }
        .onChange(of: store.isReadBlocked) { _, blocked in
            if blocked {
                editorFocused = false
                onEditingChanged(false)
            }
        }
        .onChange(of: editorFocused) { _, focused in
            onEditingChanged(focused && !store.isReadBlocked)
        }
        .onDisappear {
            copiedResetTask?.cancel()
            copiedResetTask = nil
            copiedFeedback = false
            store.cancelClear()
            store.flush()
            onEditingChanged(false)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "note.text")
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.white.opacity(0.8))
            Text(L10n.t("Bản nháp"))
                .font(XFinderTokens.Font.row)
                .lineLimit(1)

            Spacer(minLength: XFinderTokens.Space.tight)

            Text("\(store.characterCount)/\(store.maxCharacters)")
                .font(XFinderTokens.Font.caption)
                .monospacedDigit()
                .foregroundColor(store.isOverLimit ? .orange : .white.opacity(0.55))

            if store.confirmingClear {
                Button(L10n.t("Hủy")) {
                    store.cancelClear()
                }
                .buttonStyle(NotchPillButtonStyle(primary: false))

                Button(L10n.t("Xóa bản nháp")) {
                    store.confirmClear()
                }
                .buttonStyle(NotchPillButtonStyle(primary: true))
            } else {
                Button(copiedFeedback ? L10n.t("Đã sao chép") : L10n.t("Sao chép")) {
                    performCopy()
                }
                .buttonStyle(NotchPillButtonStyle(primary: true))
                .disabled(!store.canCopy)
                .opacity(store.canCopy ? 1 : 0.45)

                Button(L10n.t("Xóa")) {
                    store.requestClear()
                }
                .buttonStyle(NotchPillButtonStyle(primary: false))
                .disabled(!store.canClear)
                .opacity(store.canClear ? 1 : 0.45)
                .help(L10n.t("Xóa bản nháp"))
            }
        }
    }

    // MARK: - Status banner

    @ViewBuilder
    private var statusBanner: some View {
        switch store.status {
        case .overLimit(_, let limit):
            Text("\(L10n.t("Vượt giới hạn "))\(limit)\(L10n.t(" ký tự — chưa lưu bản mới, bản đã lưu trước đó vẫn được giữ."))")
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.orange)
                .lineLimit(1)
                .truncationMode(.tail)
        case .readFailed:
            HStack(spacing: XFinderTokens.Space.tight) {
                Text(L10n.t("Không đọc được bản nháp — tệp trên đĩa vẫn được giữ nguyên."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Button(L10n.t("Thử lại")) {
                    store.reload()
                }
                .buttonStyle(NotchPillButtonStyle(primary: false))
                .fixedSize()
                .accessibilityLabel(L10n.t("Thử lại"))
            }
        case .saveFailed:
            HStack(spacing: XFinderTokens.Space.tight) {
                Text(L10n.t("Không thể lưu bản nháp — bản đã lưu trước đó vẫn được giữ."))
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Button(L10n.t("Thử lại")) {
                    _ = store.flush()
                }
                .buttonStyle(NotchPillButtonStyle(primary: false))
                .fixedSize()
                .accessibilityLabel(L10n.t("Thử lại"))
            }
        case .idle, .saved:
            EmptyView()
        }
    }

    // MARK: - Editor

    private var editorBox: some View {
        ZStack(alignment: .topLeading) {
            if store.isEmpty && !store.isReadBlocked {
                Text(L10n.t("Ghi nhanh tại đây…"))
                    .font(XFinderTokens.Font.rowValue)
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }

            TextEditor(text: textBinding)
                .font(XFinderTokens.Font.rowValue)
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .disabled(store.isReadBlocked)
                .opacity(store.isReadBlocked ? 0.45 : 1)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .accessibilityLabel(L10n.t("Ô nhập bản nháp"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .fill(N.capsule)
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func performCopy() {
        guard store.copy(using: copyToPasteboard) else { return }
        copiedFeedback = true
        copiedResetTask?.cancel()
        copiedResetTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            copiedFeedback = false
        }
    }

    private static func writeToGeneralPasteboard(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setString(text, forType: .string)
    }
}
