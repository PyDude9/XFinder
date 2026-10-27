import SwiftUI
import AppKit

/// XF-T28 cluster E / XF-T30 W1 / XF-T32 W3 — one pane: its own tab strip (always visible), location bar (per
/// `fileBrowser.showLocationBar`), the related-items strip (Tilde "+ Add related items … 🔍 ⋯ +"), search/filter bar
/// (also while `model.filterFocusRequest == pane.id`), the view for `pane.viewMode`, Status Bar
/// (`fileBrowser.showStatusBar`) and the breadcrumb at the very bottom (`fileBrowser.showPathBar`, default on — Tilde).
/// With ≥ 2 panes the active one is marked per `fileBrowser.paneFocusStyle`: `"dim"` fades the others (opacity
/// only, nothing laid over them, so a click still lands), `"outline"` draws the accent line on the active one.
/// Handles the `.failed`/`.notPermitted` error state per contract.
struct PaneView: View {
    let pane: PaneState
    let model: BrowserWindowModel
    let isActive: Bool

    /// Same keys/defaults as `BrowserSettings` (contract §4: "via @AppStorage with the SAME defaults as
    /// BrowserSettings") — a View-menu toggle (`model.perform(.togglePathBar)` etc.) flips the UserDefaults key and
    /// every open window's `@AppStorage` picks it up without any direct window-to-window wiring.
    @AppStorage("fileBrowser.showLocationBar") private var showLocationBar = true
    @AppStorage("fileBrowser.showPathBar") private var showPathBar = true
    @AppStorage("fileBrowser.showStatusBar") private var showStatusBar = true
    /// XF-T30 W7 — the Preview pane (⇧⌘P), same default as `BrowserSettings.showPreview`.
    @AppStorage("fileBrowser.showPreview") private var showPreview = false
    /// XF-T32 W3 — same key/default as `BrowserSettings.paneFocusStyle`.
    @AppStorage("fileBrowser.paneFocusStyle") private var paneFocusStyle = "dim"

    var body: some View {
        chrome
            .opacity(isDimmed ? XFinderTokens.PaneChrome.inactivePaneOpacity : 1)
            .background(XFinderTokens.Fill.window)
            // No tap gesture here: an ancestor gesture makes AppKit delay every mouse-down to the file view until the
            // recognisers decide. `BrowserWindow.sendEvent` activates the pane instead — the file view under the click,
            // or the pane whose frame (reported below) contains it.
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                model.paneFramesInWindow[pane.id] = frame
            }
            .onDisappear { model.paneFramesInWindow[pane.id] = nil }
            .onChange(of: BrowserMetadata.shared.revision, initial: true) { _, _ in
                pane.metadataDidChange()
            }
    }

    private var hasSeveralPanes: Bool { model.tree.count >= 2 }

    /// `"dim"` (and any unknown value — the reader's default) fades every inactive pane; `"outline"` never dims.
    private var usesOutline: Bool { paneFocusStyle == "outline" }

    private var isDimmed: Bool { hasSeveralPanes && !isActive && !usesOutline }

    private var chrome: some View {
        VStack(spacing: 0) {
            accentLine

            PaneTabStripView(paneID: pane.id, model: model, isActive: isActive)
            Rectangle().fill(XFinderTokens.Fill.hairline).frame(height: 1)

            if showLocationBar {
                LocationBarView(pane: pane, model: model)
                    .padding(.horizontal, XFinderTokens.Space.tight)
                    .padding(.top, XFinderTokens.Space.tight)
            }

            RelatedItemsStrip(pane: pane, model: model, metadata: BrowserMetadata.shared)

            if pane.search != nil || !pane.filterText.isEmpty || model.filterFocusRequest == pane.id {
                SearchBarView(pane: pane, model: model)
                    .padding(.horizontal, XFinderTokens.Space.tight)
                    .padding(.top, 2)
            }

            Rectangle().fill(XFinderTokens.Fill.hairline).frame(height: 1)

            HStack(spacing: 0) {
                content
                if showPreview {
                    Rectangle().fill(XFinderTokens.Fill.hairline).frame(width: 1)
                    PreviewPaneView(pane: pane, model: model)
                }
            }

            if showStatusBar {
                Rectangle().fill(XFinderTokens.Fill.hairline).frame(height: 1)
                StatusBarView(pane: pane)
            }

            // Tilde keeps the breadcrumb as the last line of the pane, under everything else.
            if showPathBar {
                Rectangle().fill(XFinderTokens.Fill.hairline).frame(height: 1)
                PathBarView(pane: pane, model: model)
            }
        }

    }

    /// `"outline"` style only (XF-T32 §G: the dim style has no accent line). Skipped entirely with a single pane
    /// (nothing to distinguish it from). Always present with ≥ 2 panes (clear when inactive): inserting it on
    /// activation pushed the whole pane down by its height under the pointer, in the middle of the click that
    /// activated it. The style itself never changes on a click, so switching styles cannot cause that shift.
    @ViewBuilder
    private var accentLine: some View {
        if hasSeveralPanes && usesOutline {
            Rectangle()
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(height: XFinderTokens.Space.hairline)
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
}
