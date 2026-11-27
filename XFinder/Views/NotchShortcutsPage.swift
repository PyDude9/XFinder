import SwiftUI
import AppKit

/// Dynamic Island (Notch) page for listing and running the user's macOS Apple Shortcuts.
///
/// Design:
/// - Fits both narrow (382 pt) and wide (612 pt) Notch bodies using `XFinderTokens`.
/// - Loads shortcuts on appear (`store.onOpen()`) and explicit refresh (`store.refresh()`).
/// - Runs a shortcut ONLY when the user explicitly clicks that shortcut row.
/// - Cleans up in-flight requests on disappear (`store.onCloseOrTabSwitch()`) so stale replies
///   after tab switch or collapse never mutate UI state.
struct NotchShortcutsPage: View {
    var store: AppleShortcutsStore
    @Environment(\.notchAccent) private var accent

    private typealias N = XFinderTokens.Notch

    init(store: AppleShortcutsStore = AppleShortcutsStore(runner: AppleShortcutsProcessRunner())) {
        self.store = store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.tight) {
            headerRow
            runStatusBanner
            contentBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { store.onOpen() }
        .onDisappear { store.onCloseOrTabSwitch() }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(XFinderTokens.Font.sectionIcon)
                .foregroundStyle(accent)
            Text(L10n.t("Phím tắt"))
                .font(XFinderTokens.Font.row)
                .lineLimit(1)

            Spacer(minLength: XFinderTokens.Space.tight)

            if store.isRunning {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(L10n.t("Đang chạy"))
                        .font(XFinderTokens.Font.caption)
                        .opacity(0.75)
                }
            } else if store.isLoading && !store.shortcuts.isEmpty {
                ProgressView()
                    .controlSize(.mini)
            }

            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(XFinderTokens.Font.caption)
                    .foregroundStyle(Color.white.opacity(store.isLoading || store.isRunning ? 0.35 : 0.75))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(N.capsule))
            }
            .buttonStyle(.plain)
            .disabled(store.isLoading || store.isRunning)
            .help(L10n.t("Làm mới"))
            .accessibilityLabel(L10n.t("Làm mới"))
        }
        .frame(height: 22)
    }

    // MARK: - Run Status Banner

    @ViewBuilder
    private var runStatusBanner: some View {
        switch store.runState {
        case .idle:
            EmptyView()

        case .running(let shortcut):
            HStack(spacing: XFinderTokens.Space.tight) {
                ProgressView()
                    .controlSize(.mini)
                Text("\(L10n.t("Đang chạy "))\(shortcut.name)")
                    .font(XFinderTokens.Font.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Button(L10n.t("Hủy")) {
                    store.cancelRun()
                }
                .buttonStyle(NotchPillButtonStyle(primary: false))
                .accessibilityLabel(L10n.t("Hủy"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                    .fill(N.capsule)
            )

        case .succeeded(let shortcut):
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "checkmark.circle.fill")
                    .font(XFinderTokens.Font.caption)
                    .foregroundStyle(Color(nsColor: .systemGreen))
                Text("\(L10n.t("Đã chạy "))\(shortcut.name)")
                    .font(XFinderTokens.Font.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                dismissBannerButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                    .fill(N.capsule)
            )

        case .cancelled(let shortcut):
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "xmark.circle.fill")
                    .font(XFinderTokens.Font.caption)
                    .foregroundStyle(Color(nsColor: .systemOrange))
                Text("\(L10n.t("Đã hủy "))\(shortcut.name)\(L10n.t(" — tác vụ đã gửi có thể vẫn chạy nền."))")
                    .font(XFinderTokens.Font.caption)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                dismissBannerButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                    .fill(N.capsule)
            )

        case .failed(_, let error):
            HStack(spacing: XFinderTokens.Space.tight) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(XFinderTokens.Font.caption)
                    .foregroundStyle(Color(nsColor: .systemRed))
                Text(errorMessage(for: error))
                    .font(XFinderTokens.Font.caption)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if case .shortcutNotFound = error {
                    Button(L10n.t("Làm mới")) {
                        store.clearRunFeedback()
                        store.refresh()
                    }
                    .buttonStyle(NotchPillButtonStyle(primary: false))
                }
                dismissBannerButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                    .fill(N.capsule)
            )
        }
    }

    private var dismissBannerButton: some View {
        Button {
            store.clearRunFeedback()
        } label: {
            Image(systemName: "xmark")
                .font(XFinderTokens.Font.caption)
                .opacity(0.65)
        }
        .buttonStyle(.plain)
        .help(L10n.t("Đóng"))
        .accessibilityLabel(L10n.t("Đóng"))
    }

    // MARK: - Body States

    @ViewBuilder
    private var contentBody: some View {
        switch store.loadState {
        case .idle, .loading:
            if store.shortcuts.isEmpty {
                loadingState
            } else {
                shortcutList(truncated: false)
            }

        case .failed(let error):
            if store.shortcuts.isEmpty {
                errorState(error)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    inlineLoadError(error)
                    shortcutList(truncated: false)
                }
            }

        case .loaded(let truncated):
            if store.shortcuts.isEmpty {
                emptyState
            } else {
                shortcutList(truncated: truncated)
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: XFinderTokens.Space.tight) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.t("Đang tải phím tắt…"))
                .font(XFinderTokens.Font.caption)
                .opacity(0.65)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "square.stack.3d.up")
                .font(XFinderTokens.Font.pageIcon)
                .opacity(0.55)
            Text(L10n.t("Chưa có phím tắt nào trong Phím tắt Apple."))
                .font(XFinderTokens.Font.caption)
                .opacity(0.65)
                .multilineTextAlignment(.center)
            HStack(spacing: XFinderTokens.Space.tight) {
                Button(L10n.t("Mở ứng dụng Phím tắt")) {
                    openShortcutsApp()
                }
                .buttonStyle(NotchPillButtonStyle(primary: false))
                Button(L10n.t("Làm mới")) {
                    store.refresh()
                }
                .buttonStyle(NotchPillButtonStyle(primary: false))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ error: AppleShortcutsError) -> some View {
        VStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "exclamationmark.triangle")
                .font(XFinderTokens.Font.pageIcon)
                .foregroundStyle(Color(nsColor: .systemOrange))
                .opacity(0.85)
            Text(errorMessage(for: error))
                .font(XFinderTokens.Font.caption)
                .opacity(0.75)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button(L10n.t("Thử lại")) {
                store.refresh()
            }
            .buttonStyle(NotchPillButtonStyle(primary: false))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func inlineLoadError(_ error: AppleShortcutsError) -> some View {
        HStack(spacing: XFinderTokens.Space.tight) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(XFinderTokens.Font.caption)
                .foregroundStyle(Color(nsColor: .systemOrange))
            Text(errorMessage(for: error))
                .font(XFinderTokens.Font.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Button(L10n.t("Thử lại")) {
                store.refresh()
            }
            .buttonStyle(NotchPillButtonStyle(primary: false))
        }
    }

    private func shortcutList(truncated: Bool) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(store.shortcuts) { shortcut in
                    shortcutRow(shortcut)
                }
                if truncated {
                    Text(L10n.t("Danh sách quá dài — chỉ hiển thị phần đầu."))
                        .font(XFinderTokens.Font.caption)
                        .opacity(0.5)
                        .padding(.horizontal, 6)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func shortcutRow(_ shortcut: AppleShortcut) -> some View {
        let isThisRunning = store.runningShortcutID == shortcut.id
        return Button {
            store.run(shortcut)
        } label: {
            HStack(spacing: XFinderTokens.Space.tight) {
                if isThisRunning {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "play.fill")
                        .font(XFinderTokens.Font.caption)
                        .foregroundStyle(accent)
                        .frame(width: 14, height: 14)
                }
                Text(shortcut.name)
                    .font(XFinderTokens.Font.rowValue)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                    .fill(isThisRunning ? accent.opacity(0.22) : N.capsule)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XFinderTokens.Radius.badge)
                    .strokeBorder(N.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(store.isRunning)
        .opacity(store.isRunning && !isThisRunning ? 0.5 : 1)
        .accessibilityLabel("\(L10n.t("Chạy phím tắt "))\(shortcut.name)")
    }

    // MARK: - Helpers

    private func errorMessage(for error: AppleShortcutsError) -> String {
        switch error {
        case .cliUnavailable:
            return L10n.t("Không tìm thấy công cụ shortcuts của macOS.")
        case .timedOut:
            return L10n.t("Phím tắt phản hồi quá lâu và đã hết thời gian chờ.")
        case .shortcutNotFound(let name):
            return "\(L10n.t("Không tìm thấy phím tắt “"))\(name)\(L10n.t("” — có thể đã bị đổi tên hoặc xóa."))"
        case .commandFailed(let exitCode, let detail):
            if let detail, !detail.isEmpty {
                return "\(L10n.t("Không chạy được phím tắt: "))\(detail)"
            }
            return "\(L10n.t("Công cụ shortcuts báo lỗi (mã "))\(exitCode))."
        case .launchFailed(let detail):
            if let detail, !detail.isEmpty {
                return "\(L10n.t("Không khởi chạy được shortcuts: "))\(detail)"
            }
            return L10n.t("Không khởi chạy được công cụ shortcuts.")
        }
    }

    private func openShortcutsApp() {
        let appURL = URL(fileURLWithPath: "/System/Applications/Shortcuts.app")
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    }
}
