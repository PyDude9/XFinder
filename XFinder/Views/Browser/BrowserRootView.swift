import SwiftUI

/// XF-T28 cluster E — the file browser window's root chrome: toolbar, sidebar + pane grid, Shelf strip, and the
/// sheets/overlays everything else in the window funnels through (conflict, batch rename, recovery, command
/// palette, a one-line auto-hiding banner).
struct BrowserRootView: View {
    static let minimumSize = CGSize(width: 720, height: 460)
    private static let sidebarWidth: CGFloat = 200
    private static let bannerAutoHide: TimeInterval = 4

    let model: BrowserWindowModel

    @State private var showingWorkspaceSaveSheet = false
    @State private var showingOperationsPopover = false
    @State private var workspaceName = ""
    @State private var bannerWorkItem: DispatchWorkItem?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(XFinderTokens.Fill.hairline).frame(height: 1)

            HStack(spacing: 0) {
                BrowserSidebarView(model: model)
                    .frame(width: Self.sidebarWidth)
                Rectangle().fill(XFinderTokens.Fill.hairline).frame(width: 1)
                PaneGridView(model: model)
            }

            if model.shelfVisible {
                ShelfBarView(model: model)
            }
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .overlay(alignment: .top) {
            if let banner = model.banner {
                bannerView(banner)
            }
        }
        .overlay {
            if let mode = model.palette {
                CommandPaletteView(model: model, mode: mode)
            }
        }
        .sheet(isPresented: Binding(
            get: { FileOperationQueue.shared.pendingConflict != nil },
            set: { if !$0 { } }
        )) {
            if let prompt = FileOperationQueue.shared.pendingConflict {
                ConflictSheet(prompt: prompt, queue: FileOperationQueue.shared)
            }
        }
        .sheet(isPresented: Binding(
            get: { model.batchRenameSources != nil },
            set: { if !$0 { model.batchRenameSources = nil } }
        )) {
            if let sources = model.batchRenameSources {
                BrowserBatchRenameSheet(sources: sources, model: model)
            }
        }
        .sheet(isPresented: Binding(
            get: { !FileOperationQueue.shared.recovery.isEmpty },
            set: { _ in }
        )) {
            RecoveryReportSheet(queue: FileOperationQueue.shared)
        }
        .sheet(isPresented: $showingWorkspaceSaveSheet) {
            saveWorkspaceSheet
        }
        .onChange(of: model.banner) { _, newValue in
            scheduleBannerAutoHide(newValue)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: XFinderTokens.Space.inline) {
            HStack(spacing: 2) {
                Button { model.active.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!model.active.history.canGoBack)
                Button { model.active.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!model.active.history.canGoForward)
            }

            Picker("", selection: Binding(
                get: { model.active.viewMode },
                set: { model.active.viewMode = $0 }
            )) {
                Image(systemName: "list.bullet").tag(BrowserViewMode.list)
                Image(systemName: "square.grid.2x2").tag(BrowserViewMode.icons)
                Image(systemName: "rectangle.split.3x1").tag(BrowserViewMode.columns)
                Image(systemName: "rectangle.grid.1x2").tag(BrowserViewMode.gallery)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            presetMenu

            Spacer()

            Button {
                _ = model.perform(.toggleShelf)
            } label: {
                Image(systemName: model.shelfVisible ? "tray.full.fill" : "tray")
            }

            operationsButton

            workspaceMenu
        }
        .padding(.horizontal, XFinderTokens.Space.row)
        .padding(.vertical, XFinderTokens.Space.tight)
    }

    private var presetMenu: some View {
        Menu {
            Button(L10n.t("Một ngăn")) { _ = model.perform(.presetSingle) }
            Button(L10n.t("Cạnh nhau")) { _ = model.perform(.presetSideBySide) }
            Button(L10n.t("Chồng lên nhau")) { _ = model.perform(.presetStacked) }
            Button(L10n.t("Lưới 2×2")) { _ = model.perform(.presetGrid) }
            Divider()
            Button(L10n.t("Chia ngăn sang phải")) { _ = model.perform(.splitRight) }
                .disabled(!model.tree.canSplit)
            Button(L10n.t("Chia ngăn sang trái")) { _ = model.perform(.splitLeft) }
                .disabled(!model.tree.canSplit)
            Button(L10n.t("Chia ngăn xuống dưới")) { _ = model.perform(.splitDown) }
                .disabled(!model.tree.canSplit)
            Button(L10n.t("Chia ngăn lên trên")) { _ = model.perform(.splitUp) }
                .disabled(!model.tree.canSplit)
            Divider()
            Button(L10n.t("Chia đều các ngăn")) { _ = model.perform(.equalizePanes) }
        } label: {
            Image(systemName: "rectangle.3.group")
        }
    }

    private var operationsButton: some View {
        let activeCount = FileOperationQueue.shared.queue.jobs.filter { !$0.isFinished }.count
        return Button {
            showingOperationsPopover = true
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "arrow.left.arrow.right.circle")
                if activeCount > 0 {
                    Text("\(activeCount)")
                        .font(XFinderTokens.Font.caption)
                }
            }
        }
        .popover(isPresented: $showingOperationsPopover) {
            OperationsPanelView(queue: FileOperationQueue.shared)
        }
    }

    private var workspaceMenu: some View {
        Menu {
            Button(L10n.t("Lưu Workspace")) {
                workspaceName = ""
                showingWorkspaceSaveSheet = true
            }
            // "Mở Workspace" needs a list of saved workspaces, which only `BrowserWindowController` (Cluster C)
            // can read (workspaces.json); its stub does not yet expose that store, so the item is disabled rather
            // than wired to a no-op — a future Cluster-C method is the only thing this menu item is waiting on.
            Button(L10n.t("Mở Workspace")) {}
                .disabled(true)
        } label: {
            Image(systemName: "square.stack.3d.up")
        }
    }

    /// Builds the `WindowSnapshot` for the current window (`model.snapshot(frame:)`) and names it; persisting that
    /// snapshot into `workspaces.json` (`WorkspaceStore.save`, loaded/saved once per app by `BrowserWindowController`
    /// per ui-contract Cụm C) is a Cluster-C responsibility this stub does not yet expose a hook for — documented as
    /// a contract gap in the final report rather than reaching into another cluster's persistence file from here.
    private var saveWorkspaceSheet: some View {
        VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
            Text(L10n.t("Lưu Workspace"))
                .font(XFinderTokens.Font.sectionTitle)
            TextField(L10n.t("Tên Workspace"), text: $workspaceName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(L10n.t("Dừng")) { showingWorkspaceSaveSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.t("Lưu Workspace")) {
                    _ = model.snapshot(frame: nil)
                    showingWorkspaceSaveSheet = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(XFinderTokens.Space.section)
        .frame(width: 320)
    }

    // MARK: - Banner

    private func bannerView(_ text: String) -> some View {
        Text(L10n.t(text))
            .font(XFinderTokens.Font.rowValue)
            .padding(.horizontal, XFinderTokens.Space.row)
            .padding(.vertical, XFinderTokens.Space.tight)
            .background(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous).fill(XFinderTokens.Fill.surface))
            .overlay(RoundedRectangle(cornerRadius: XFinderTokens.Radius.control, style: .continuous).stroke(XFinderTokens.Fill.hairline))
            .shadow(radius: 6)
            .padding(.top, XFinderTokens.Space.row)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func scheduleBannerAutoHide(_ text: String?) {
        bannerWorkItem?.cancel()
        guard text != nil else { return }
        let work = DispatchWorkItem { [weak model] in
            model?.banner = nil
        }
        bannerWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.bannerAutoHide, execute: work)
    }
}
