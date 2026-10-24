import SwiftUI
import AppKit

/// XF-T28 cluster E — one pane: location bar, search/filter bar (only while active), the view for
/// `pane.viewMode`, and a status line. Handles the `.failed`/`.notPermitted` error state per contract.
struct PaneView: View {
    let pane: PaneState
    let model: BrowserWindowModel
    let isActive: Bool

    var body: some View {
        VStack(spacing: 0) {
            LocationBarView(pane: pane, model: model)
                .padding(.horizontal, XFinderTokens.Space.tight)
                .padding(.top, XFinderTokens.Space.tight)

            if pane.search != nil || !pane.filterText.isEmpty {
                SearchBarView(pane: pane, model: model)
                    .padding(.horizontal, XFinderTokens.Space.tight)
                    .padding(.top, 2)
            }

            Rectangle().fill(XFinderTokens.Fill.hairline).frame(height: 1).padding(.top, XFinderTokens.Space.tight)

            content

            Rectangle().fill(XFinderTokens.Fill.hairline).frame(height: 1)
            statusLine
        }
        .background(XFinderTokens.Fill.window)
        .contentShape(Rectangle())
        .onTapGesture {
            model.focus(pane.id)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch pane.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            errorView(error)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            viewModeContent
        }
    }

    @ViewBuilder
    private var viewModeContent: some View {
        switch pane.viewMode {
        case .list:
            FileListView(pane: pane, model: model)
        case .icons:
            FileIconView(pane: pane, model: model)
        case .columns:
            FileColumnView(pane: pane, model: model)
        case .gallery:
            FileGalleryView(pane: pane, model: model)
        }
    }

    private func errorView(_ error: DirectoryReadError) -> some View {
        VStack(spacing: XFinderTokens.Space.row) {
            Image(systemName: "exclamationmark.triangle")
                .font(XFinderTokens.Font.pageIcon)
                .foregroundColor(.secondary)
            Text(L10n.t(error.messageKey))
                .font(XFinderTokens.Font.row)
                .multilineTextAlignment(.center)
            if case .notPermitted = error {
                Button(L10n.t("Mở Cài đặt hệ thống")) {
                    openFullDiskAccessSettings()
                }
                .buttonStyle(.bordered)
            } else {
                Button(L10n.t("Thử lại")) {
                    pane.reload()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(XFinderTokens.Space.section)
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    private var statusLine: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            Text(itemCountLabel)
                .font(XFinderTokens.Font.caption)
                .foregroundColor(.secondary)
            if !pane.selection.isEmpty {
                Text("\(pane.selection.count)\(L10n.t(" mục được chọn"))")
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let free = DirectoryReader.freeSpace(of: pane.path) {
                Text("\(L10n.t("Còn trống: "))\(ByteCountFormatter.string(fromByteCount: free, countStyle: .file))")
                    .font(XFinderTokens.Font.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, XFinderTokens.Space.row)
        .padding(.vertical, 4)
    }

    private var itemCountLabel: String {
        "\(pane.entries.count)\(L10n.t(" mục"))"
    }
}
